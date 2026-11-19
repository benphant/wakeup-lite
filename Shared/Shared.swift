import Foundation
import IOKit
import IOKit.ps
import Security

let serviceID = "org.awakelite.app.LidHelper"
let appID = "org.awakelite.app"

@objc protocol LidServiceProtocol {
    func renew(keepDisplay: Bool, stopOnLowBattery: Bool, withReply reply: @escaping (Bool, String) -> Void)
    func releaseLease(withReply reply: @escaping (Bool, String) -> Void)
    func status(withReply reply: @escaping (Bool, String) -> Void)
}

enum Monotonic {
    static var now: TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

enum SleepPolicy {
    static let durations = [0, 15, 30, 60, 120, 240, 480]
    static func batteryShouldStop(onBattery: Bool, percent: Int?, enabled: Bool) -> Bool {
        enabled && onBattery && percent.map { (0..<10).contains($0) } == true
    }
    static func expired(now: TimeInterval, deadline: TimeInterval?) -> Bool {
        deadline.map { now >= $0 } ?? false
    }
    static func shouldRestore(original: Bool?, current: Bool?) -> Bool {
        original == false && current == true
    }
}

enum PowerSource: String, Codable { case battery, ac, unknown, noBattery = "no_battery" }
struct PowerReading: Equatable {
    let onBattery: Bool
    let percent: Int?
    let source: PowerSource
    init(onBattery: Bool, percent: Int?, source: PowerSource? = nil) {
        self.onBattery = onBattery
        self.percent = percent.flatMap { (0...100).contains($0) ? $0 : nil }
        self.source = source ?? (onBattery ? .battery : .ac)
    }
    static func normalized(current: Int?, maximum: Int?) -> Int? {
        guard let c = current, let m = maximum, m > 0, c >= 0, c <= m else { return nil }
        let (numerator, overflow) = c.multipliedReportingOverflow(by: 100)
        return overflow ? nil : numerator / m
    }
    static func read() -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerReading(onBattery: false, percent: nil, source: .unknown)
        }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            let kind: PowerSource = state == kIOPSBatteryPowerValue ? .battery : state == kIOPSACPowerValue ? .ac : .unknown
            return PowerReading(onBattery: kind == .battery, percent: normalized(current: d[kIOPSCurrentCapacityKey] as? Int, maximum: d[kIOPSMaxCapacityKey] as? Int), source: kind)
        }
        return PowerReading(onBattery: false, percent: nil, source: .noBattery)
    }
}

enum Identity {
    static func requirement(identifier: String) -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any], let team = d[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }
}

func rootProperty(_ key: String) -> Bool? {
    let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }
    return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
}
