import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var stopWork: DispatchWorkItem?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.1")
        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.252"])
        // Only a reserved benchmark destination is included. No default route or DNS.
        ipv4.includedRoutes = [
            NEIPv4Route(destinationAddress: "198.18.0.2", subnetMask: "255.255.255.255"),
        ]
        settings.ipv4Settings = ipv4
        settings.mtu = 1280
        setTunnelNetworkSettings(settings) { [weak self] error in
            if error == nil, let self {
                let work = DispatchWorkItem { [weak self] in self?.cancelTunnelWithError(nil) }
                self.stopWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
            }
            completionHandler(error)
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let answer = messageData == Data("maykop-signing-probe-v1".utf8)
            ? Data("maykop-packet-tunnel-running-v1".utf8)
            : nil
        completionHandler?(answer)
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopWork?.cancel()
        stopWork = nil
        completionHandler()
    }
}
