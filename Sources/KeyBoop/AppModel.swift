import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import KeyBoopCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let defaultExcluded = ["com.apple.Terminal", "com.googlecode.iterm2"]

    @Published var enabled: Bool {
        didSet { persist(); engineIfNeeded?.reset() }
    }
    @Published var paused = false {
        didSet {
            if paused { engine?.reset() }
            refreshStatus()
        }
    }
    @Published var gesturesEnabled: Bool {
        didSet {
            persist()
            engine?.gesturesEnabled = gesturesEnabled
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }
    @Published var excluded: [String] {
        didSet { persist() }
    }
    @Published var status = "Запуск"
    @Published var exceptionCount = 0
    @Published var listenGranted = false
    @Published var accessGranted = false
    @Published var loginMessage = ""
    @Published var permissionNote = ""
    @Published var showRelaunch = false
    @Published var exceptionWords: [String] = []
    @Published var disabledShortWords: Set<String> {
        didSet {
            persist()
            engine?.disabledShortWords = disabledShortWords
        }
    }
    @Published var updateVersion: String?
    @Published var updateMessage = ""
    private var updateAssetURL: URL?

    let exceptions: ExceptionList
    private(set) var engine: Engine?
    private var engineIfNeeded: Engine? { enabled ? nil : engine }
    private let defaults = UserDefaults.standard
    private var applyingLogin = false

    private(set) var frontmostBundleID: String?
    private(set) var lastOtherBundleID: String?
    private(set) var lastOtherName: String?

    var isFrontmostExcluded: Bool {
        guard let frontmostBundleID else { return false }
        return excluded.contains(frontmostBundleID)
    }

    var shouldProcess: Bool {
        enabled && !paused && listenGranted && accessGranted
    }

    init(exceptions: ExceptionList) {
        self.exceptions = exceptions
        let storedExcluded = defaults.stringArray(forKey: "excludedBundles")
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        gesturesEnabled = defaults.object(forKey: "gesturesEnabled") as? Bool ?? true
        excluded = storedExcluded ?? Self.defaultExcluded
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        disabledShortWords = Set(defaults.stringArray(forKey: "disabledShortWords") ?? [])
        exceptionCount = exceptions.count
        exceptionWords = exceptions.recent
    }

    func attach(engine: Engine) {
        self.engine = engine
        engine.gesturesEnabled = gesturesEnabled
        engine.disabledShortWords = disabledShortWords
        if !enabled { engine.reset() }
    }

    func noteFrontmost(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        if let id = app?.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            lastOtherBundleID = id
            lastOtherName = app?.localizedName ?? id
        }
        refreshStatus()
    }

    func noteBlocked(secure: Bool) {
        if secure {
            status = "Пауза: защищённый ввод"
        } else if isFrontmostExcluded {
            status = "Пауза: приложение в исключениях"
        } else if !listenGranted || !accessGranted {
            status = "Нет доступа к клавиатуре"
        } else if paused {
            status = "На паузе"
        } else if !enabled {
            status = "Выключено"
        }
    }

    func noteReady() {
        status = "Работает"
    }

    func refreshPermissions() {
        let hidGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        listenGranted = hidGranted || CGPreflightListenEventAccess()
        accessGranted = AXIsProcessTrusted()
        if listenGranted {
            showRelaunch = false
            permissionNote = ""
        }
        refreshStatus()
    }

    func noteListenNeedsRelaunch() {
        showRelaunch = true
        permissionNote = "Переключатель включён. Нажмите «Перезапустить», чтобы мониторинг ввода заработал."
    }

    func requestListen() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            permissionNote = "Запрос мониторинга ввода работает в собранном KeyBoop.app"
            return
        }
        CGRequestListenEventAccess()
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissions()
        guard !listenGranted else {
            PermissionGuide.shared.dismiss()
            return
        }
        showRelaunch = true
        permissionNote = "KeyBoop уже в списке. Включите его переключатель, затем нажмите «Перезапустить». Файл выбирать не нужно."
        openListenSettings()
        PermissionGuide.shared.show(
            title: "Мониторинг ввода",
            steps: [
                "KeyBoop уже в списке, файл выбирать не нужно.",
                "Включите переключатель рядом с KeyBoop.",
                "Нажмите «Перезапустить» в окне KeyBoop.",
            ],
            retryTitle: "Перезапустить",
            granted: { [weak self] in self?.listenGranted == true },
            retry: { [weak self] in self?.relaunch() }
        )
    }

    func relaunch() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            permissionNote = "Перезапуск работает у собранного KeyBoop.app"
            return
        }
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        open \(Self.quote(path))
        """
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-c", script]
        if (try? shell.run()) != nil {
            NSApp.terminate(nil)
        }
    }

    func requestAccess() {
        permissionNote = ""
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
        guard !accessGranted else {
            PermissionGuide.shared.dismiss()
            return
        }
        openAccessSettings()
        PermissionGuide.shared.show(
            title: "Универсальный доступ",
            steps: [
                "Найдите KeyBoop в списке.",
                "Включите переключатель.",
                "Если статус не сменился, нажмите «Перезапустить».",
            ],
            retryTitle: "Спросить снова",
            granted: { [weak self] in self?.accessGranted == true },
            retry: { [weak self] in self?.requestAccess() }
        )
    }

    func resetListenGrant() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "ListenEvent", "com.keyboop.app"]
        if (try? task.run()) != nil {
            task.waitUntilExit()
        }
        CGRequestListenEventAccess()
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissions()
    }

    func openListenSettings() {
        open(urls: [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ])
    }

    func openAccessSettings() {
        open(urls: [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    func addLastOtherApp() {
        guard let lastOtherBundleID, !excluded.contains(lastOtherBundleID) else { return }
        excluded.append(lastOtherBundleID)
    }

    func removeExcluded(_ id: String) {
        excluded.removeAll { $0 == id }
    }

    func resetExceptions() {
        exceptions.removeAll()
        noteExceptions()
    }

    func removeException(_ word: String) {
        exceptions.remove(word)
        noteExceptions()
    }

    func setShortWord(_ word: String, enabled: Bool) {
        if enabled {
            disabledShortWords.remove(word)
        } else {
            disabledShortWords.insert(word)
        }
    }

    func noteExceptions() {
        exceptionWords = exceptions.recent
        exceptionCount = exceptions.count
    }

    func exceptionsChanged(_ words: Set<String>) {
        exceptionCount = words.count
        exceptionWords = exceptions.recent
        _ = words
    }

    func checkForUpdate(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: "lastUpdateCheck")
        if !force, now - last < 86_400, updateVersion == nil, last > 0 { return }
        if force {
            defaults.set(now, forKey: "lastUpdateCheck")
            updateMessage = "Проверяю GitHub…"
        } else if last == 0 || now - last >= 86_400 {
            defaults.set(now, forKey: "lastUpdateCheck")
        }
        Task { await fetchUpdate(report: force) }
    }

    func installUpdate() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            updateMessage = "Обновление ставится в собранное KeyBoop.app"
            return
        }
        guard let version = updateVersion else { return }
        updateMessage = "Скачивание \(version)…"
        Task { await downloadAndReplace() }
    }

    private func refreshStatus() {
        if !listenGranted || !accessGranted {
            status = "Нет доступа к клавиатуре"
        } else if !enabled {
            status = "Выключено"
        } else if paused {
            status = "На паузе"
        } else if isFrontmostExcluded {
            status = "Пауза: приложение в исключениях"
        } else {
            status = "Работает"
        }
    }

    private func persist() {
        defaults.set(enabled, forKey: "enabled")
        defaults.set(gesturesEnabled, forKey: "gesturesEnabled")
        defaults.set(excluded, forKey: "excludedBundles")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(Array(disabledShortWords), forKey: "disabledShortWords")
    }

    private func applyLoginItem() {
        guard !applyingLogin else { return }
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            loginMessage = "Автозапуск включается у собранного KeyBoop.app"
            return
        }
        applyingLogin = true
        defer { applyingLogin = false }
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            loginMessage = ""
        } catch {
            loginMessage = "Не удалось изменить автозапуск"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func fetchUpdate(report: Bool) async {
        let local = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        guard let url = URL(string: "https://api.github.com/repos/RedShadow0111/KeyBoop/releases?per_page=10") else { return }
        var request = URLRequest(url: url)
        request.setValue("KeyBoop", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                if report { updateMessage = "GitHub ответил \(http.statusCode)" }
                return
            }
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let match = releases.compactMap { release -> (String, URL)? in
                let remote = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Self.isNewer(remote, than: local),
                      let asset = release.assets.first(where: { $0.name == "KeyBoop-macos.zip" }),
                      let assetURL = URL(string: asset.browser_download_url)
                else { return nil }
                return (remote, assetURL)
            }.first
            if let match {
                updateVersion = match.0
                updateAssetURL = match.1
                updateMessage = "Доступна версия \(match.0)"
            } else {
                updateVersion = nil
                updateAssetURL = nil
                if report {
                    updateMessage = releases.isEmpty
                        ? "На GitHub пока нет релизов. Сейчас версия \(local)."
                        : "Версия \(local) — последняя"
                }
            }
        } catch {
            if report { updateMessage = "Не удалось проверить обновление" }
        }
    }

    private func downloadAndReplace() async {
        guard let url = updateAssetURL else { return }
        let destination = Bundle.main.bundleURL
        do {
            var request = URLRequest(url: url)
            request.setValue("KeyBoop", forHTTPHeaderField: "User-Agent")
            let (file, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateMessage = "Не удалось скачать обновление"
                return
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeyBoop-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let zip = folder.appendingPathComponent("KeyBoop-macos.zip")
            try FileManager.default.moveItem(at: file, to: zip)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-q", zip.path, "-d", folder.path]
            try unzip.run()
            unzip.waitUntilExit()
            let staged = folder.appendingPathComponent("KeyBoop.app")
            guard FileManager.default.fileExists(atPath: staged.path) else {
                updateMessage = "В архиве нет KeyBoop.app"
                return
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf \(Self.quote(destination.path))
            ditto \(Self.quote(staged.path)) \(Self.quote(destination.path))
            open \(Self.quote(destination.path))
            """
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/bash")
            shell.arguments = ["-c", script]
            try shell.run()
            NSApp.terminate(nil)
        } catch {
            updateMessage = "Не удалось установить обновление"
        }
    }

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let left = remote.split(separator: ".").map { Int($0) ?? 0 }
        let right = local.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private func open(urls: [String]) {
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

private struct GitHubRelease: Decodable {
    var tag_name: String
    var assets: [Asset]
    struct Asset: Decodable {
        var name: String
        var browser_download_url: String
    }
}

enum ExceptionStore {
    static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyBoop/exceptions.json", isDirectory: false)
    }

    static func load() -> [String] {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        struct File: Codable {
            var words: [String]
            var order: [String]?
        }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.order ?? file.words
    }

    static func save(_ words: [String]) {
        let url = fileURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct File: Codable {
            var words: [String]
            var order: [String]
        }
        let payload = File(words: words, order: words)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
