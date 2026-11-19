import AppKit
import ServiceManagement

@MainActor final class LidControl {
    private let service = SMAppService.daemon(plistName: serviceID + ".plist")
    private var connection: NSXPCConnection?
    var enabled: Bool { service.status == .enabled }

    func prepare() throws {
        guard Identity.requirement(identifier: serviceID) != nil else {
            throw NSError(domain: "AwakeLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "合盖控制需要用 Apple 开发团队签名后构建。"])
        }
        if service.status == .notRegistered || service.status == .notFound { try service.register() }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func renew(display: Bool, lowBattery: Bool, completion: @escaping (Bool, String) -> Void) {
        if connection == nil {
            guard let requirement = Identity.requirement(identifier: serviceID) else {
                completion(false, "辅助服务缺少开发团队签名。"); return
            }
            let client = NSXPCConnection(machServiceName: serviceID, options: .privileged)
            client.remoteObjectInterface = NSXPCInterface(with: LidServiceProtocol.self)
            client.setCodeSigningRequirement(requirement)
            client.resume()
            connection = client
        }
        let proxy = connection?.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async { completion(false, "合盖服务连接失败：\(error.localizedDescription)") }
        } as? LidServiceProtocol
        guard let proxy else { completion(false, "合盖服务无法连接。"); return }
        proxy.renew(keepDisplay: display, stopOnLowBattery: lowBattery) { ok, payload in
            DispatchQueue.main.async { completion(ok, HelperReply.decode(payload)?.message ?? payload) }
        }
    }

    func release() {
        // The daemon releases this client's lease on invalidation and retries restoration if needed.
        connection?.invalidate()
        connection = nil
    }
}
