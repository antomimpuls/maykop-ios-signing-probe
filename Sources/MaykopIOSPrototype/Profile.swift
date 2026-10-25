import Foundation

enum VPNProfile {
    static func make(configuration: ServerConfiguration, password: String) throws -> Data {
        let c = try configuration.validated()
        guard !password.isEmpty else { throw PrototypeError.missingPassword }
        if c.isRelay { return try makeRelay(configuration: c, password: password) }
        // EAP-only IKEv2: server authenticated by its public CA certificate.
        // No client certificate, Network Extension, MDM, root CA or proxy payload.
        let ike: [String: Any] = ["RemoteAddress": c.address,
            "RemoteIdentifier": c.remoteID, "AuthenticationMethod": "None",
            "ExtendedAuthEnabled": 1, "AuthName": c.username, "AuthPassword": password,
            "DeadPeerDetectionRate": "Medium", "DisableMOBIKE": 0,
            "EnablePFS": 0, "IncludeAllNetworks": 0,
            "LocalIdentifier": c.localID,
            "IKESecurityAssociationParameters": ["EncryptionAlgorithm": "AES-256",
                "IntegrityAlgorithm": "SHA2-256", "DiffieHellmanGroup": 14, "LifeTimeInMinutes": 1440],
            "ChildSecurityAssociationParameters": ["EncryptionAlgorithm": "AES-256",
                "IntegrityAlgorithm": "SHA2-256", "DiffieHellmanGroup": 14, "LifeTimeInMinutes": 60]]
        let vpn: [String: Any] = ["PayloadType": "com.apple.vpn.managed", "PayloadVersion": 1,
            "PayloadIdentifier": "org.maykopvpn.ikev2-lab.vpn", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "MAYKOP iOS Test", "UserDefinedName": "MAYKOP iOS Test",
            "VPNType": "IKEv2", "IKEv2": ike, "IPv4": ["OverridePrimary": 1]]
        let profile: [String: Any] = ["PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "org.maykopvpn.ikev2-lab", "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "MAYKOP iOS Test", "PayloadRemovalDisallowed": false,
            "PayloadDescription": "Тестовый системный IKEv2. Установка вручную владельцем.",
            "PayloadContent": [vpn]]
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return data
    }

    private static func makeRelay(configuration c: ServerConfiguration, password: String) throws -> Data {
        guard let port = c.relayPort else { throw PrototypeError.invalidRelayConfiguration }
        let credential = Data("\(c.username):\(password)".utf8).base64EncodedString()
        var relay: [String: Any] = [
            "PayloadType": "com.apple.relay.managed", "PayloadVersion": 1,
            "PayloadIdentifier": "org.maykopvpn.https-relay.relay",
            "PayloadUUID": UUID().uuidString.uppercased(),
            "PayloadDisplayName": "MAYKOP HTTPS Test",
            "Relays": [[
                "HTTP2RelayURL": "https://\(c.address):\(port)/.well-known/masque/udp/{target_host}/{target_port}/",
                "AdditionalHTTPHeaderFields": ["Proxy-Authorization": "Basic \(credential)"]
            ]],
            "UIToggleEnabled": true
        ]
        if let domains = c.relayMatchDomains { relay["MatchDomains"] = domains }
        let profile: [String: Any] = [
            "PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "org.maykopvpn.https-relay",
            "PayloadUUID": UUID().uuidString.uppercased(),
            "PayloadDisplayName": "MAYKOP HTTPS Test", "PayloadOrganization": "Maykop VPN",
            "PayloadDescription": "Тест защищённого HTTPS-подключения MAYKOP. Профиль можно удалить в настройках iPhone.",
            "PayloadRemovalDisallowed": false, "PayloadContent": [relay]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return data
    }
}
