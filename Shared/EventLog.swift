import Foundation
import OSLog
import Darwin

// One writer per process; root and the GUI deliberately use separate private files.
final class EventLog {
    static var appURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AwakeLite/events.jsonl") }
    static let helperURL = URL(fileURLWithPath: "/Library/Application Support/AwakeLiteLocal/events.jsonl")
    let url: URL
    private let component: String
    private let lock = NSLock()
    private let systemLog: Logger
    private let limit: UInt64
    private(set) var lastError: String?
    init(url: URL, component: String, limit: UInt64 = 2 * 1024 * 1024) {
        self.url = url; self.component = component; self.limit = limit
        systemLog = Logger(subsystem: appID, category: component)
    }
    @discardableResult func record(_ event: String, reason: String? = nil, power: PowerReading = .read(), fields: [String: Any] = [:]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var row = fields
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; f.timeZone = .current
        row["timestamp"] = f.string(from: Date())
        row["event"] = event; row["reason"] = reason ?? NSNull()
        row["component"] = component; row["pid"] = ProcessInfo.processInfo.processIdentifier
        row["build"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        row["batteryPercent"] = power.percent.map { $0 as Any } ?? NSNull()
        row["powerSource"] = power.source.rawValue
        row["onBattery"] = power.onBattery
        row["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
        systemLog.notice("event=\(event, privacy: .public) reason=\(reason ?? "none", privacy: .public) battery=\(power.percent ?? -1) source=\(power.source.rawValue, privacy: .public)")
        do {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            }
            var st = stat()
            guard lstat(directory.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid(), st.st_mode & 0o022 == 0 else { throw failure("日志目录权限不安全") }
            if lstat(url.path, &st) == 0 {
                guard (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { throw failure("日志文件不是受管理的普通文件") }
                if UInt64(st.st_size) >= limit {
                    let fm = FileManager.default
                    for index in stride(from: 3, through: 1, by: -1) {
                        let dst = URL(fileURLWithPath: url.path + ".\(index)")
                        let src = index == 1 ? url : URL(fileURLWithPath: url.path + ".\(index - 1)")
                        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                        if fm.fileExists(atPath: src.path) { try fm.moveItem(at: src, to: dst) }
                    }
                }
            }
            let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw failure("无法打开日志文件，errno=\(errno)") }
            defer { close(fd) }
            guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else { throw failure("日志文件权限不安全") }
            guard fchmod(fd, 0o600) == 0 else { throw failure("无法保护日志文件") }
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); data.append(0x0a)
            try data.withUnsafeBytes { buffer in
                var done = 0
                while done < buffer.count {
                    let n = write(fd, buffer.baseAddress!.advanced(by: done), buffer.count - done)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw failure("日志写入失败") }; done += n
                }
            }
            if event != "snapshot" { guard fsync(fd) == 0 else { throw failure("日志同步失败") } }
            lastError = nil; return true
        } catch {
            lastError = error.localizedDescription
            systemLog.error("Persistent log failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "AwakeLog", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

enum StopReason: String, Codable {
    case manual, lowBattery = "low_battery", timerExpired = "timer_expired", thermal = "thermal_protection"
    case helperTimeout = "helper_timeout", helperFailure = "helper_failure", settingsChanged = "system_settings_changed"
    case leaseExpired = "lease_expired", clientDisconnected = "client_disconnected", userExit = "app_exit"
    case helperRemoved = "helper_removed", assertionFailure = "assertion_failure", recoveryFailure = "recovery_failure"
}

struct HelperReply: Codable {
    var code: String
    var message: String
    var batteryPercent: Int?
    var powerSource: String
    var leaseID: String
    var build: String
    var thermal: Int
    func encoded() -> String { (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? message }
    static func decode(_ string: String) -> HelperReply? { try? JSONDecoder().decode(Self.self, from: Data(string.utf8)) }
}
