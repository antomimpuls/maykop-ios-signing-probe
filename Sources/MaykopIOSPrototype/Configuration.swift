import Foundation
import Security

struct ServerConfiguration: Codable {
    var address = ""
    var remoteID = ""
    var localID = ""
    var username = ""

    func validated() throws -> ServerConfiguration {
        var c = ServerConfiguration(address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            remoteID: remoteID.trimmingCharacters(in: .whitespacesAndNewlines),
            localID: localID.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !c.address.isEmpty, !c.remoteID.isEmpty, !c.username.isEmpty,
              !c.address.contains(":"), !c.address.contains("/"),
              !c.address.contains(where: { $0.isWhitespace }) else { throw PrototypeError.invalidConfiguration }
        if c.localID.isEmpty { c.localID = c.username }
        return c
    }
}

enum PrototypeError: LocalizedError {
    case invalidConfiguration, missingPassword, secureStorage, invalidImport
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Укажите адрес сервера без https:// и порта, удалённый ID и логин."
        case .missingPassword: return "Введите пароль IKEv2."
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
