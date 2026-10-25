import NetworkExtension
import SwiftUI

@main
struct MaykopSigningProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}

private struct ProbeView: View {
    @StateObject private var probe = ProbeController()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("MAYKOP VPN")
                        .font(.title.bold())
                    Text("Проверка установки на iPhone")
                }
                Section("Результат") {
                    Text(probe.message)
                    Button("Проверить VPN-разрешение") {
                        probe.start()
                    }
                    .disabled(probe.busy)
                    Button("Остановить проверку") {
                        probe.stop()
                    }
                }
                Section {
                    Text("Это одно приложение со встроенным тестовым VPN-расширением. Проверка автоматически завершится через минуту.")
                    Text("Проверка не направляет интернет-трафик через VPN и не подтверждает работу Maykop-сервера. Её цель — проверить разрешение iOS на запуск нашего VPN-расширения.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Maykop Test")
        }
    }
}

@MainActor
private final class ProbeController: ObservableObject {
    @Published var message = "Проверка ещё не запускалась."
    @Published var busy = false
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?
    private var verified = false

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.statusChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        busy = true
        verified = false
        message = "Подготовка проверки…"
        Task {
            do {
                let extensionID = try installedExtensionID()
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                let selected = managers.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionID
                } ?? NETunnelProviderManager()
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = extensionID
                configuration.serverAddress = "Maykop signing test"
                configuration.includeAllNetworks = false
                configuration.disconnectOnSleep = true
                selected.protocolConfiguration = configuration
                selected.localizedDescription = "Maykop signing test"
                selected.isEnabled = true
                try await selected.saveToPreferences()
                try await selected.loadFromPreferences()
                manager = selected
                try selected.connection.startVPNTunnel()
                message = "Ожидается запуск встроенного VPN-расширения…"
                statusChanged()
            } catch {
                report(error)
            }
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        busy = false
        if !verified { message = "Проверка остановлена." }
    }

    private func statusChanged() {
        guard let manager else { return }
        switch manager.connection.status {
        case .connected:
            guard !verified, let session = manager.connection as? NETunnelProviderSession else { return }
            do {
                try session.sendProviderMessage(Data("maykop-signing-probe-v1".utf8)) { [weak self] data in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.busy = false
                        if data == Data("maykop-packet-tunnel-running-v1".utf8) {
                            self.verified = true
                            self.message = "Успех: встроенное VPN-расширение запущено и ответило. Это подтверждает разрешение iOS; работу настоящего VPN проверяем следующим этапом."
                        } else {
                            self.message = "VPN-сессия создана, но проверочный ответ расширения не получен. Успех не подтверждён."
                        }
                    }
                }
            } catch {
                report(error)
            }
        case .disconnected, .invalid:
            busy = false
            if !verified {
                message = "VPN-расширение не подтвердило запуск. Требуется проверить подпись приложения и расширения."
            }
        default:
            break
        }
    }

    private func installedExtensionID() throws -> String {
        guard let plugins = Bundle.main.builtInPlugInsURL else {
            throw NSError(domain: "MaykopProbe", code: 1)
        }
        let extensions = try FileManager.default.contentsOfDirectory(
            at: plugins,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "appex" }
        guard extensions.count == 1,
              let identifier = Bundle(url: extensions[0])?.bundleIdentifier else {
            throw NSError(domain: "MaykopProbe", code: 2)
        }
        return identifier
    }

    private func report(_ error: Error) {
        busy = false
        let failure = error as NSError
        // Keep profile data, device IDs and credentials out of diagnostics.
        message = "Проверка не выполнена. Ошибка: \(failure.domain), код \(failure.code)."
    }
}
