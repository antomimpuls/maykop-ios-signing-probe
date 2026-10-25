import SwiftUI
import UniformTypeIdentifiers

@main
struct MaykopTestApp: App {
    var body: some Scene { WindowGroup { MainView() } }
}

@MainActor
final class TestModel: ObservableObject {
    @Published var configuration = ServerConfiguration()
    @Published var password = ""
    @Published var message = "Подключение проверяется в настройках iPhone."
    @Published var probe = "Проверка трафика ещё не запускалась."
    @Published var checking = false
    @Published var exportedURL: URL?

    init() {
        if let data = UserDefaults.standard.data(forKey: "serverConfiguration"),
           let saved = try? JSONDecoder().decode(ServerConfiguration.self, from: data) { configuration = saved }
        password = PasswordStore.read()
        importUSBConfiguration()
    }

    func save() {
        do {
            let c = try configuration.validated()
            guard !password.isEmpty else { throw PrototypeError.missingPassword }
            try PasswordStore.write(password)
            UserDefaults.standard.set(try JSONEncoder().encode(c), forKey: "serverConfiguration")
            configuration = c
            message = "Настройки сохранены в приложении. Уже установленный системный VPN-профиль не изменён; для новых настроек подготовьте и установите новый профиль."
        } catch { message = error.localizedDescription }
    }

    func importUSBConfiguration() {
        let file = URL.documentsDirectory.appending(path: "maykop-test-config.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 99999 < 16384 else { throw PrototypeError.invalidImport }
            let imported = try JSONDecoder().decode(USBConfiguration.self, from: Data(contentsOf: file))
            let c = try imported.configuration.validated()
            guard !imported.password.isEmpty else { throw PrototypeError.missingPassword }
            try PasswordStore.write(imported.password)
            UserDefaults.standard.set(try JSONEncoder().encode(c), forKey: "serverConfiguration")
            try FileManager.default.removeItem(at: file)
            configuration = c
            password = imported.password
            message = "Настройки получены по USB, файл импорта удалён. Уже установленный системный VPN-профиль не изменён; для новых настроек подготовьте и установите новый профиль."
        } catch { message = error.localizedDescription }
    }

    func exportProfile() {
        do {
            let data = try VPNProfile.make(configuration: configuration, password: password)
            let file = URL.temporaryDirectory.appending(path: "MAYKOP-Test.mobileconfig")
            try data.write(to: file, options: [.atomic, .completeFileProtection])
            exportedURL = file
            message = "Профиль содержит пароль. Передавайте его только на свой iPhone. Установка требует подтверждения в настройках."
        } catch { message = error.localizedDescription }
    }

    func clearExport() {
        if let file = exportedURL { try? FileManager.default.removeItem(at: file) }
        exportedURL = nil
    }

    func openSettings() {
        guard let url = URL(string: "App-Prefs:root=General&path=VPN") else { return }
        UIApplication.shared.open(url, options: [:]) { success in
            Task { @MainActor in
                self.message = success ? "В настройках выберите MAYKOP iOS Test и включите VPN." :
                    "Откройте Настройки → Основные → VPN и управление устройством → VPN."
            }
        }
    }

    func checkTraffic() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.ipify.org?format=json")!)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 15
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let ip = object["ip"], ip.count < 64 else { throw URLError(.badServerResponse) }
            let expected = configuration.address.trimmingCharacters(in: .whitespacesAndNewlines)
            probe = ip == expected ? "Интернет работает. Выходной IP совпал с сервером. Это проверка маршрута, а не системного статуса VPN." :
                "Интернет работает. Выходной IP не совпал с указанным адресом сервера. VPN этим не подтверждён."
        } catch { probe = "Тестовый HTTPS-запрос не прошёл. Это не определяет причину и не подтверждает статус VPN." }
    }

    func checkWhenConfigured() async {
        guard (try? configuration.validated()) != nil else { return }
        await checkTraffic()
    }
}

struct MainView: View {
    @StateObject private var model = TestModel()
    @State private var showShare = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                Section("Системный VPN") {
                    Text("MAYKOP VPN").font(.title2.bold())
                    Text("Тест IKEv2").foregroundStyle(.secondary)
                    Text("VPN включается в настройках iPhone. Приложение не читает системный статус.")
                    Button("Открыть VPN в настройках") { model.openSettings() }
                    Button(model.checking ? "Проверяем…" : "Проверить трафик") { Task { await model.checkTraffic() } }
                        .disabled(model.checking)
                    Text(model.probe).font(.footnote)
                }
                Section("Сервер · IKEv2 с логином и паролем") {
                    TextField("Адрес сервера", text: $model.configuration.address)
                    TextField("Удалённый ID сертификата", text: $model.configuration.remoteID)
                    TextField("Локальный ID (по умолчанию — логин)", text: $model.configuration.localID)
                    TextField("Логин", text: $model.configuration.username)
                    SecureField("Пароль IKEv2", text: $model.password)
                    Button("Сохранить") { model.save() }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                Section("Профиль VPN") {
                    Text("Если профиль MAYKOP iOS Test уже установлен по USB, повторная установка не нужна.")
                    Text("Изменения, сохранённые в приложении, не меняют установленный системный VPN-профиль. Чтобы применить новые настройки, подготовьте и установите новый профиль.").font(.footnote)
                    Button("Подготовить файл профиля") { model.exportProfile() }
                    if model.exportedURL != nil {
                        Button("Передать профиль…") { showShare = true }
                        Button("Удалить временный файл", role: .destructive) { model.clearExport() }
                    }
                    Text("После загрузки: Настройки → Профиль загружен → Установить. Передача через «Поделиться» сама профиль не устанавливает.").font(.footnote)
                }
                Section("Подпись приложения · 7 дней") {
                    Text("Подключите iPhone к Windows. В Sideloadly выберите этот же IPA и тот же Apple Account, затем Start. Можно включить автоматическое обновление при доступном компьютере.")
                    Text("Срок профиля VPN не связан с подписью оболочки. Для работы нужны доступный сервер и действующие настройки.").font(.footnote)
                }
                Section { Text(model.message).font(.footnote) }
            }
            .navigationTitle("MAYKOP VPN Test")
            .task { await model.checkWhenConfigured() }
            .sheet(isPresented: $showShare) {
                if let url = model.exportedURL { ShareSheet(url: url) }
            }
            .onChange(of: phase) { _, newPhase in
                if newPhase == .active {
                    model.importUSBConfiguration()
                    Task { await model.checkWhenConfigured() }
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
