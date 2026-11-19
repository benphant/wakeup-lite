import Foundation
import Combine
import CoreGraphics
import IOKit.ps
import IOKit.pwr_mgt

// Only public power-management APIs. No global pmset changes or privileged helper.
final class PowerHold {
    private var system: IOPMAssertionID = 0
    private var display: IOPMAssertionID = 0
    var active: Bool { system != 0 }
    func start(displayOn: Bool) throws {
        do {
            if system == 0 { system = try create(kIOPMAssertionTypePreventUserIdleSystemSleep, "醒着Lite · 系统保持清醒") }
            try setDisplay(displayOn)
        } catch { stop(); throw error }
    }
    func setDisplay(_ on: Bool) throws {
        if on && display == 0 { display = try create(kIOPMAssertionTypePreventUserIdleDisplaySleep, "醒着Lite · 屏幕常亮") }
        if !on && display != 0 { IOPMAssertionRelease(display); display = 0 }
    }
    private func create(_ type: String, _ reason: String) throws -> IOPMAssertionID {
        var value: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &value)
        guard result == kIOReturnSuccess else { throw NSError(domain: "IOKit", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "无法申请电源保护（\(result)）"]) }
        return value
    }
    func stop() {
        if display != 0 { IOPMAssertionRelease(display); display = 0 }
        if system != 0 { IOPMAssertionRelease(system); system = 0 }
    }
    deinit { stop() }
}
struct Battery {
    let onBattery: Bool
    let percent: Int?
    static func read() -> Battery {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return Battery(onBattery: false, percent: nil) }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String:Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int, maxValue = d[kIOPSMaxCapacityKey] as? Int
            var percent: Int?
            if let c = current, let m = maxValue, c >= 0, c <= m, m > 0, c <= Int.max / 100 { percent = c * 100 / m }
            return Battery(onBattery: d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue, percent: percent)
        }
        return Battery(onBattery: false, percent: nil)
    }
    func shouldStop(enabled: Bool) -> Bool { enabled && onBattery && percent.map { (0..<10).contains($0) } == true }
}
@MainActor final class LiteModel: ObservableObject {
    @Published private(set) var awake = false
    @Published private(set) var connecting = false
    @Published private(set) var status = "尚未开始"
    @Published var displayOn = false { didSet { refreshDisplay(); renew() } }
    @Published var lowBattery = true { didSet { poll(); renew() } }
    let power = PowerHold()
    private let lid: LidControl?
    private var timer: Timer?
    private let battery: () -> Battery
    private var generation = 0
    private var lastRequest = -Double.infinity
    private var lastReply = -Double.infinity
    private var requestedAt = -Double.infinity
    private var requestPending = false
    private var activity: NSObjectProtocol?
    var canPrepareService: Bool { lid?.enabled == false }

    init(runTimer: Bool = true, battery: @escaping () -> Battery = Battery.read) {
        self.battery = battery
        lid = runTimer ? LidControl() : nil
        if runTimer {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }

    func prepareService() {
        do {
            try lid?.prepare()
            status = canPrepareService ? "请在系统设置中允许合盖辅助服务" : "合盖辅助服务已就绪"
        } catch { status = error.localizedDescription }
    }

    func toggle() {
        if awake || connecting { stop("本次已结束"); return }
        if battery().shouldStop(enabled: lowBattery) { status = "电池低于 10%，请接通电源"; return }
        if let lid {
            guard lid.enabled else { status = "请先设置合盖辅助服务"; return }
            connecting = true
            requestedAt = Monotonic.now
            status = "正在连接合盖辅助服务"
            renew()
        } else {
            begin()
        }
    }

    private func begin() {
        do {
            try power.start(displayOn: lid == nil && displayOn)
            if lid != nil { activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "维持合盖防休眠连接") }
            awake = true; connecting = false
            status = lid == nil ? "已开启防休眠" : "合盖清醒已开启"
            refreshDisplay()
        } catch { stop(error.localizedDescription) }
    }

    private func refreshDisplay() {
        guard awake else { return }
        let closed = rootProperty("AppleClamshellState") == true
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let knownDisplays = CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success
        let online = displays.prefix(knownDisplays ? Int(count) : 0)
        let builtInOnline = online.contains { CGDisplayIsBuiltin($0) != 0 }
        let onlyBuiltIn = builtInOnline && online.count == 1
        do { try power.setDisplay(displayOn && (lid == nil || (closed && onlyBuiltIn))) }
        catch { stop(error.localizedDescription); return }
        if lid != nil {
            if displayOn && closed && !onlyBuiltIn {
                status = builtInOnline ? "有外接屏幕时，无法单独控制内建屏幕" : "合盖清醒已开启，内建屏幕当前不可用"
            } else {
                status = "合盖清醒已开启"
            }
        }
    }

    private func renew() {
        guard let lid, awake || connecting, !requestPending else { return }
        let request = generation
        lastRequest = Monotonic.now
        requestPending = true
        lid.renew(display: displayOn, lowBattery: lowBattery) { [weak self] ok, message in
            guard let self, self.generation == request else { return }
            self.requestPending = false
            guard ok else { self.stop(message); return }
            self.lastReply = Monotonic.now
            if self.connecting { self.begin() }
        }
    }

    func poll() {
        guard awake || connecting else { return }
        if battery().shouldStop(enabled: lowBattery) { stop("电池低于 10%，已停止"); return }
        guard lid != nil else { return }
        if Monotonic.now - (connecting ? requestedAt : lastReply) > 12 {
            stop("合盖服务未响应，已停止"); return
        }
        refreshDisplay()
        if Monotonic.now - lastRequest >= 4 { renew() }
    }

    func stop(_ reason: String = "已结束") {
        generation += 1
        requestPending = false
        lid?.release()
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        power.stop()
        awake = false; connecting = false; status = reason
    }
}
