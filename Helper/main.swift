import Foundation
import IOKit
import Darwin

protocol SleepGate {
    func read() -> Bool?
    func set(_ disabled: Bool) -> Bool
}
final class SystemGate: SleepGate {
    func read() -> Bool? { rootProperty("SleepDisabled") }
    func set(_ disabled: Bool) -> Bool { run(["-a", "disablesleep", disabled ? "1" : "0"]) && read() == disabled }
    private func run(_ arguments: [String]) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let end = Monotonic.now + 3
        while p.isRunning && Monotonic.now < end { usleep(20_000) }
        if p.isRunning { p.terminate(); usleep(100_000); if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
protocol RecoveryStore {
    func load() throws -> Bool?
    func save(_ prior: Bool) throws
    func clear() throws
}
final class Journal: RecoveryStore {
    private let directory = URL(fileURLWithPath: "/Library/Application Support/AwakeLiteLocal", isDirectory: true)
    private var file: URL { directory.appendingPathComponent("sleep-recovery.json") }
    private func secureDirectory() throws {
        var st = stat()
        if lstat(directory.path, &st) != 0 {
            guard errno == ENOENT else { throw failure() }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            guard lstat(directory.path, &st) == 0 else { throw failure() }
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == 0, st.st_mode & 0o022 == 0 else { throw failure() }
    }
    private func failure() -> NSError { NSError(domain: "AwakeRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "恢复记录目录不可用或权限不安全"]) }
    func load() throws -> Bool? {
        try secureDirectory()
        var st = stat()
        guard lstat(file.path, &st) == 0 else { if errno == ENOENT { return nil }; throw failure() }
        guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == 0, st.st_nlink == 1, st.st_mode & 0o077 == 0 else { throw failure() }
        let value = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
        return value.prior
    }
    struct Record: Codable { let prior: Bool }
    func save(_ prior: Bool) throws {
        try secureDirectory()
        try JSONEncoder().encode(Record(prior: prior)).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        // The journal must exist and be readable before changing system policy.
        guard try load() == prior else { throw failure() }
    }
    func clear() throws { try secureDirectory(); if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
}

final class SleepEngine {
    struct Lease { var expires: TimeInterval; var display: Bool; var lowBattery: Bool }
    let gate: SleepGate
    let journal: RecoveryStore
    var leases: [UUID: Lease] = [:]
    var original: Bool?
    var lastFailure: String?
    var rejected: [UUID: StopReason] = [:]
    private var rejectedPower: [UUID: PowerReading] = [:]
    private let logger: EventLog?
    private var lastPower = PowerReading(onBattery: false, percent: nil, source: .unknown)
    private var lastSnapshotAt: TimeInterval = -.infinity
    private var recoveryBlocked = false
    init(gate: SleepGate, journal: RecoveryStore, logger: EventLog? = nil) { self.gate = gate; self.journal = journal; self.logger = logger }
    private func emit(_ event: String, reason: String? = nil, power: PowerReading? = nil, fields: [String: Any] = [:]) {
        var details: [String: Any] = ["leaseCount": leases.count, "sleepDisabled": gate.read().map { $0 as Any } ?? NSNull(), "originalSleepDisabled": original.map { $0 as Any } ?? NSNull()]
        details.merge(fields) { _, new in new }
        logger?.record(event, reason: reason, power: power ?? lastPower, fields: details)
    }
    private func reject(_ id: UUID, reason: StopReason, message: String, power: PowerReading) -> (Bool, String) {
        rejected[id] = reason; rejectedPower[id] = power
        emit("renew_rejected", reason: reason.rawValue, power: power, fields: ["leaseID": id.uuidString, "message": message])
        return (false, message)
    }
    func recover() -> Bool {
        do { original = try journal.load(); emit("recovery_checked", reason: original == nil ? "no_recovery_needed" : "recovery_pending"); let ok = restore(); recoveryBlocked = !ok; return ok }
        catch { recoveryBlocked = true; lastFailure = error.localizedDescription; emit("recovery_failed", reason: StopReason.recoveryFailure.rawValue, fields: ["error": error.localizedDescription]); return false }
    }
    func renew(id: UUID, display: Bool, lowBattery: Bool, now: TimeInterval, power: PowerReading, hot: Bool) -> (Bool, String) {
        lastPower = power
        if recoveryBlocked && !recover() { return reject(id, reason: .recoveryFailure, message: lastFailure ?? "恢复记录尚未就绪", power: power) }
        if let reason = rejected[id] { return (false, message(for: reason)) }
        if SleepPolicy.batteryShouldStop(onBattery: power.onBattery, percent: power.percent, enabled: lowBattery) {
            _ = stopAll(reason: .lowBattery, power: power)
            return reject(id, reason: .lowBattery, message: "电量低于 10%，已停止合盖控制", power: power)
        }
        if hot {
            _ = stopAll(reason: .thermal, power: power)
            return reject(id, reason: .thermal, message: "温度过高，已停止合盖控制", power: power)
        }
        if leases.isEmpty {
            // Finish a pending restore before admitting new work.
            if original != nil && !restore() { return reject(id, reason: .recoveryFailure, message: lastFailure ?? "系统睡眠设置尚未恢复", power: power) }
            guard let prior = gate.read() else { return reject(id, reason: .helperFailure, message: "无法读取系统睡眠状态", power: power) }
            if prior { return reject(id, reason: .settingsChanged, message: "系统已被其他设置禁止睡眠，请先结束已有的合盖控制。", power: power) }
            if !prior {
                do { try journal.save(prior); original = prior } catch { return reject(id, reason: .recoveryFailure, message: error.localizedDescription, power: power) }
                guard gate.set(true) else { _ = restore(); return reject(id, reason: .helperFailure, message: "系统拒绝合盖控制，未能启用", power: power) }
            }
        } else if gate.read() != true {
            _ = stopAll(reason: .settingsChanged, power: power); return reject(id, reason: .settingsChanged, message: "系统睡眠设置已被其他程序更改，合盖控制已停止", power: power)
        }
        let isNew = leases[id] == nil
        leases[id] = Lease(expires: now + 20, display: display, lowBattery: lowBattery)
        if isNew { emit("lease_started", power: power, fields: ["leaseID": id.uuidString, "keepDisplay": display, "lowBatteryProtection": lowBattery]) }
        lastFailure = nil
        return (true, display ? "合盖控制已生效 · 内屏保留开启" : "合盖控制已生效")
    }
    func release(id: UUID, reason: StopReason = .manual) -> Bool {
        if leases.removeValue(forKey: id) != nil { emit("lease_released", reason: reason.rawValue, fields: ["leaseID": id.uuidString]) }
        rejected.removeValue(forKey: id); rejectedPower.removeValue(forKey: id)
        return leases.isEmpty ? restore() : true
    }
    func releaseReply(id: UUID) -> (Bool, String) {
        let ok = release(id: id)
        guard ok else { return (false, lastFailure ?? "系统休眠设置仍在恢复") }
        switch gate.read() {
        case true?: return (true, "已释放本应用控制；系统仍禁止睡眠，请检查其他设置")
        case false?: return (true, "已释放合盖控制，全局睡眠开关已恢复")
        case nil: return (true, "已释放本应用控制，暂时无法确认系统休眠设置")
        }
    }
    func stopAll(reason: StopReason? = nil, power: PowerReading? = nil) -> Bool {
        if !leases.isEmpty {
            emit("protective_stop", reason: reason?.rawValue ?? "released", power: power, fields: ["leaseIDs": leases.keys.map { $0.uuidString }])
            if let reason { for id in leases.keys { rejected[id] = reason; rejectedPower[id] = power ?? lastPower } }
        }
        leases.removeAll(); return restore()
    }
    func message(for reason: StopReason) -> String {
        switch reason {
        case .lowBattery: return "电量低于 10%，已停止合盖控制"
        case .thermal: return "温度过高，已停止合盖控制"
        case .leaseExpired: return "合盖连接心跳超时，已恢复睡眠设置"
        case .settingsChanged: return "系统睡眠设置已被其他程序更改，合盖控制已停止"
        default: return lastFailure ?? "合盖服务已停止，请重新开启"
        }
    }
    func reply(id: UUID, ok: Bool, message: String, power: PowerReading, thermal: Int) -> String {
        let sample = rejectedPower[id] ?? power
        return HelperReply(code: ok ? "active" : rejected[id]?.rawValue ?? StopReason.helperFailure.rawValue, message: message,
            batteryPercent: sample.percent, powerSource: sample.source.rawValue, leaseID: id.uuidString,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown", thermal: thermal).encoded()
    }
    func restore() -> Bool {
        guard let original else { return true }
        guard let current = gate.read() else { lastFailure = "无法读取系统状态，保留恢复记录并等待重试"; emit("restore_failed", reason: "state_unreadable"); return false }
        if SleepPolicy.shouldRestore(original: original, current: current) && !gate.set(original) {
            lastFailure = "系统恢复失败，将自动重试"; emit("restore_failed", reason: "system_write_failed"); return false
        }
        do { try journal.clear(); emit("sleep_setting_restored", reason: "verified"); self.original = nil; return true }
        catch { lastFailure = error.localizedDescription; emit("restore_failed", reason: "journal_clear_failed", fields: ["error": error.localizedDescription]); return false }
    }
    func tick(now: TimeInterval, power: PowerReading, hot: Bool) {
        if power != lastPower || now - lastSnapshotAt >= 60 { lastPower = power; lastSnapshotAt = now; emit("snapshot", power: power) }
        for (id, lease) in leases where lease.expires <= now {
            rejected[id] = .leaseExpired; rejectedPower[id] = power
            emit("lease_expired", reason: StopReason.leaseExpired.rawValue, power: power, fields: ["leaseID": id.uuidString])
        }
        leases = leases.filter { $0.value.expires > now }
        let batteryStop = leases.values.contains { SleepPolicy.batteryShouldStop(onBattery: power.onBattery, percent: power.percent, enabled: $0.lowBattery) }
        if batteryStop { _ = stopAll(reason: .lowBattery, power: power) }
        else if hot { _ = stopAll(reason: .thermal, power: power) }
        if leases.isEmpty { _ = restore() }
        else if gate.read() != true { _ = stopAll(reason: .settingsChanged, power: power); lastFailure = "系统设置被其他程序更改" }
    }
}

final class ClientSession: NSObject, LidServiceProtocol {
    let id = UUID()
    let engine: SleepEngine
    let queue: DispatchQueue
    init(engine: SleepEngine, queue: DispatchQueue) { self.engine = engine; self.queue = queue }
    func renew(keepDisplay: Bool, stopOnLowBattery: Bool, withReply reply: @escaping (Bool, String) -> Void) {
        queue.async {
            let power = PowerReading.read(), thermal = ProcessInfo.processInfo.thermalState.rawValue
            let r = self.engine.renew(id: self.id, display: keepDisplay, lowBattery: stopOnLowBattery, now: Monotonic.now, power: power, hot: thermal >= 2)
            reply(r.0, self.engine.reply(id: self.id, ok: r.0, message: r.1, power: power, thermal: thermal))
        }
    }
    func releaseLease(withReply reply: @escaping (Bool, String) -> Void) {
        queue.async { let result = self.engine.releaseReply(id: self.id); reply(result.0, result.1) }
    }
    func status(withReply reply: @escaping (Bool, String) -> Void) {
        queue.async { reply(self.engine.leases[self.id] != nil, self.engine.lastFailure ?? "辅助服务已就绪") }
    }
}
final class Service: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "org.awakelite.app.power")
    let engine = SleepEngine(gate: SystemGate(), journal: Journal(), logger: EventLog(url: EventLog.helperURL, component: "helper"))
    var timer: DispatchSourceTimer?
    func start() {
        queue.sync { _ = engine.recover() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.engine.tick(now: Monotonic.now, power: .read(), hot: ProcessInfo.processInfo.thermalState.rawValue >= 2)
        }
        t.resume(); timer = t
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        let session = ClientSession(engine: engine, queue: queue)
        c.exportedInterface = NSXPCInterface(with: LidServiceProtocol.self); c.exportedObject = session
        c.invalidationHandler = { [queue, engine] in queue.async { _ = engine.release(id: session.id, reason: .clientDisconnected) } }
        c.interruptionHandler = { [queue, engine] in queue.async { _ = engine.release(id: session.id, reason: .clientDisconnected) } }
        c.resume(); return true
    }
}

final class FakeGate: SleepGate {
    var value: Bool? = false; var writes: [Bool] = []; var fail = false
    func read() -> Bool? { value }
    func set(_ v: Bool) -> Bool { if fail { return false }; writes.append(v); value = v; return true }
}
final class MemoryJournal: RecoveryStore {
    var value: Bool?; var fail = false; var failRead = false
    func load() throws -> Bool? { if failRead { throw NSError(domain: "JournalRead", code: 1) }; return value }
    func save(_ prior: Bool) throws { if fail { throw NSError(domain: "test", code: 1) }; value = prior }
    func clear() throws { value = nil }
}
func selfTest() {
    var checks = 0
    func check(_ ok: @autoclosure () -> Bool, _ name: String) { guard ok() else { fputs("FAIL: \(name)\n", stderr); exit(1) }; checks += 1 }
    let power = PowerReading(onBattery: false, percent: 100)
    let g = FakeGate(), j = MemoryJournal()
    let engine = SleepEngine(gate: g, journal: j), a = UUID(), b = UUID()
    check(engine.renew(id: a, display: false, lowBattery: true, now: 0, power: power, hot: false).0, "engage")
    check(g.value == true && j.value == false, "journal before system change")
    check(engine.renew(id: b, display: true, lowBattery: true, now: 1, power: power, hot: false).0, "second lease")
    check(engine.release(id: a) && g.value == true, "one holder stays")
    check(engine.release(id: b) && g.value == false && j.value == nil, "last holder restores")
    _ = engine.renew(id: a, display: true, lowBattery: true, now: 10, power: power, hot: false)
    engine.tick(now: 31, power: power, hot: false)
    check(g.value == false && engine.leases.isEmpty, "lease expiry restores")
    _ = engine.renew(id: a, display: true, lowBattery: true, now: 40, power: power, hot: false)
    engine.tick(now: 41, power: PowerReading(onBattery: true, percent: 9), hot: false)
    check(g.value == false, "low battery restores")
    _ = engine.release(id: a)
    _ = engine.renew(id: a, display: true, lowBattery: false, now: 50, power: power, hot: false)
    engine.tick(now: 51, power: power, hot: true)
    check(g.value == false, "thermal protection")
    _ = engine.release(id: a)
    g.value = true
    _ = engine.renew(id: a, display: true, lowBattery: true, now: 60, power: power, hot: false)
    _ = engine.release(id: a)
    check(g.value == true, "preserves preexisting disabled sleep")
    g.value = false; j.fail = true
    check(!engine.renew(id: a, display: true, lowBattery: true, now: 70, power: power, hot: false).0 && g.value == false, "journal failure prevents modification")
    _ = engine.release(id: a)
    j.fail = false; g.value = true; j.value = false
    check(engine.recover() && g.value == false, "crash journal recovery")
    _ = engine.renew(id: a, display: true, lowBattery: true, now: 80, power: power, hot: false)
    g.fail = true
    check(!engine.release(id: a) && j.value == false, "failed restore retains journal")
    g.fail = false
    check(engine.restore() && j.value == nil && g.value == false, "restore retry")
    check(!SleepPolicy.batteryShouldStop(onBattery: false, percent: 1, enabled: true), "AC power allowed")
    check(!SleepPolicy.batteryShouldStop(onBattery: true, percent: 10, enabled: true), "ten percent boundary")
    check(SleepPolicy.expired(now: 60, deadline: 60) && !SleepPolicy.expired(now: 999, deadline: nil), "timer deadline")
    for percent in 0...100 {
        for onBattery in [false, true] {
            for enabled in [false, true] {
                let gate = FakeGate(), journal = MemoryJournal(), id = UUID()
                let subject = SleepEngine(gate: gate, journal: journal)
                let sample = PowerReading(onBattery: onBattery, percent: percent)
                let shouldStop = onBattery && enabled && percent < 10
                let result = subject.renew(id: id, display: false, lowBattery: enabled, now: 0, power: sample, hot: false)
                check(result.0 == !shouldStop && gate.value == !shouldStop, "helper threshold admission \(percent)/\(onBattery)/\(enabled)")
                _ = subject.release(id: id)
            }
        }
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AwakeHelperTests-\(UUID().uuidString)")
    let logger = EventLog(url: folder.appendingPathComponent("events.jsonl"), component: "test-helper")
    let gate = FakeGate(), journal = MemoryJournal(), id = UUID()
    let subject = SleepEngine(gate: gate, journal: journal, logger: logger)
    check(subject.renew(id: id, display: false, lowBattery: true, now: 0, power: PowerReading(onBattery: true, percent: 20), hot: false).0, "twenty percent helper starts")
    subject.tick(now: 1, power: PowerReading(onBattery: true, percent: 10), hot: false)
    check(gate.value == true, "ten percent helper remains active")
    subject.tick(now: 2, power: PowerReading(onBattery: true, percent: 9), hot: false)
    check(gate.value == false && subject.rejected[id] == .lowBattery && journal.value == nil, "nine percent watchdog restores verified system setting")
    let after = subject.renew(id: id, display: false, lowBattery: true, now: 3, power: PowerReading(onBattery: false, percent: 20), hot: false)
    check(!after.0 && gate.value == false, "protection remains latched until explicit release")
    let payload = subject.reply(id: id, ok: false, message: after.1, power: PowerReading(onBattery: false, percent: 20), thermal: 0)
    let response = HelperReply.decode(payload)
    check(response?.code == "low_battery" && response?.batteryPercent == 9 && response?.powerSource == "battery", "reply preserves original stop sample after power source changes")
    let records = (try! String(contentsOf: logger.url, encoding: .utf8)).split(separator: "\n").map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
    let stop = records.first { $0["event"] as? String == "protective_stop" }
    check(stop?["reason"] as? String == "low_battery" && stop?["batteryPercent"] as? Int == 9, "root stop reason and battery durably logged")
    check(records.contains { $0["event"] as? String == "sleep_setting_restored" }, "verified restore logged")
    _ = subject.release(id: id)
    check(subject.renew(id: id, display: false, lowBattery: true, now: 4, power: PowerReading(onBattery: false, percent: 9), hot: false).0, "explicit new AC session admitted")
    _ = subject.release(id: id)
    let brokenGate = FakeGate(), brokenJournal = MemoryJournal()
    brokenGate.value = true; brokenJournal.value = false; brokenJournal.failRead = true
    let blocked = SleepEngine(gate: brokenGate, journal: brokenJournal)
    check(!blocked.recover(), "corrupt/unreadable recovery journal blocks startup")
    check(!blocked.renew(id: UUID(), display: false, lowBattery: true, now: 0, power: power, hot: false).0 && brokenGate.writes.isEmpty, "failed recovery cannot be silently treated as someone else's setting")
    let preexistingGate = FakeGate(), preexistingJournal = MemoryJournal()
    preexistingGate.value = true
    let preexisting = SleepEngine(gate: preexistingGate, journal: preexistingJournal), preexistingID = UUID()
    _ = preexisting.renew(id: preexistingID, display: false, lowBattery: true, now: 0, power: power, hot: false)
    let preservedReply = preexisting.releaseReply(id: preexistingID)
    check(preservedReply.0 && preexisting.leases.isEmpty && preexistingGate.value == true && preexistingGate.writes.isEmpty,
          "release succeeds without overriding external disabled-sleep policy")
    check(preservedReply.1.contains("系统仍禁止睡眠"), "release reports remaining external system policy")
    preexistingGate.value = false
    _ = preexisting.renew(id: preexistingID, display: false, lowBattery: true, now: 1, power: power, hot: false)
    let normalReply = preexisting.releaseReply(id: preexistingID)
    check(normalReply.0 && preexistingGate.value == false && normalReply.1.contains("全局睡眠开关已恢复"), "owned control restores and reports verified system state")
    print("PASS: \(checks) lifecycle and policy checks; no system settings changed")
}
if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
guard getuid() == 0, let requirement = Identity.requirement(identifier: appID) else { fputs("Root and a valid team signature are required.\n", stderr); exit(1) }
let service = Service(); service.start()
let listener = NSXPCListener(machServiceName: serviceID)
listener.setConnectionCodeSigningRequirement(requirement)
listener.delegate = service; listener.resume()
RunLoop.current.run()
