import Foundation
import Security

struct ServerConfiguration: Codable {
    var address = ""
    var remoteID = ""
    var localID = ""
    var username = ""
    var expectedExitAddress: String?
    var connectionKind: String?
    var relayPort: Int?
    var relayMatchDomains: [String]?

    var isRelay: Bool { connectionKind?.lowercased() == "relay" }
    var hasLimitedRelayDomains: Bool { isRelay && !(relayMatchDomains ?? []).isEmpty }

    func validated() throws -> ServerConfiguration {
        var c = ServerConfiguration(address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteID: remoteID.trimmingCharacters(in: .whitespacesAndNewlines),
            localID: localID.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedExitAddress: expectedExitAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
            connectionKind: connectionKind?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            relayPort: relayPort,
            relayMatchDomains: relayMatchDomains?.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard !c.address.isEmpty, !c.username.isEmpty else { throw PrototypeError.invalidConfiguration }
        if c.connectionKind?.isEmpty == true || c.connectionKind == "ikev2" { c.connectionKind = nil }
        guard c.connectionKind == nil || c.connectionKind == "relay" else { throw PrototypeError.invalidConfiguration }
        if c.isRelay {
            c.address = c.address.lowercased()
            if c.address.hasSuffix(".") { c.address.removeLast() }
            c.relayMatchDomains = c.relayMatchDomains?.map { value in
                value.hasSuffix(".") ? String(value.dropLast()) : value
            }
            guard let port = c.relayPort, (1...65535).contains(port), isValidHostname(c.address),
                  !c.username.contains(":"), validHTTPSURL(host: c.address, port: port) else {
                throw PrototypeError.invalidRelayConfiguration
            }
            if c.relayMatchDomains?.isEmpty == true { c.relayMatchDomains = nil }
            if let domains = c.relayMatchDomains, !domains.allSatisfy(isValidHostname) {
                throw PrototypeError.invalidRelayConfiguration
            }
        } else {
            guard !c.remoteID.isEmpty, !c.address.contains(":"), !c.address.contains("/"),
                  !c.address.contains(where: { $0.isWhitespace }) else { throw PrototypeError.invalidConfiguration }
        }
        if c.localID.isEmpty { c.localID = c.username }
        if c.expectedExitAddress?.isEmpty == true { c.expectedExitAddress = nil }
        return c
    }

    private func isValidHostname(_ value: String) -> Bool {
        let hostname = value.hasSuffix(".") ? String(value.dropLast()) : value
        guard !hostname.isEmpty, hostname.count <= 253 else { return false }
        return hostname.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            let label = String(part)
            return label.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$"#,
                options: .regularExpression) != nil
        }
    }

    private func validHTTPSURL(host: String, port: Int) -> Bool {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = "/.well-known/masque/udp/{target_host}/{target_port}/"
        return components.url != nil
    }
}

enum PrototypeError: LocalizedError {
    case invalidConfiguration, invalidRelayConfiguration, missingPassword, secureStorage, invalidImport
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Укажите адрес сервера без https:// и порта, удалённый ID и логин."
        case .invalidRelayConfiguration: return "Проверьте имя HTTPS-сервера, порт, области теста и логин без двоеточия."
        case .missingPassword: return "Введите пароль подключения."
        case .secureStorage: return "Не удалось сохранить пароль в защищённом хранилище."
        case .invalidImport: return "Файл настройки не прошёл проверку."
        }
    }
}

enum PasswordStore {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "MaykopTest.IKEv2", kSecAttrAccount as String: "server"] }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func write(_ password: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw PrototypeError.secureStorage }
        } else if status != errSecSuccess { throw PrototypeError.secureStorage }
    }
}

struct USBConfiguration: Decodable {
    let configuration: ServerConfiguration
    let password: String
}
