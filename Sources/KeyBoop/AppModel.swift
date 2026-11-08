import AppKit
import ApplicationServices
import Foundation
import KeyBoopCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let defaultExcluded = ["com.apple.Terminal", "com.googlecode.iterm2"]

    @Published var enabled: Bool {
        didSet { persist(); engineIfNeeded?.reset() }
    }
    @Published var paused = false {
        didSet { refreshStatus() }
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
        exceptionCount = exceptions.count
    }

    func attach(engine: Engine) {
        self.engine = engine
        engine.gesturesEnabled = gesturesEnabled
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
        listenGranted = CGPreflightListenEventAccess()
        accessGranted = AXIsProcessTrusted()
        refreshStatus()
    }

    func requestListen() {
        CGRequestListenEventAccess()
    }

    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
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
        exceptionCount = 0
    }

    func exceptionsChanged(_ words: Set<String>) {
        exceptionCount = words.count
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

    private func open(urls: [String]) {
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}

enum ExceptionStore {
    static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KeyBoop/exceptions.json", isDirectory: false)
    }

    static func load() -> Set<String> {
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        struct File: Codable { var words: [String] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return Set(file.words)
    }

    static func save(_ words: Set<String>) {
        let url = fileURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        struct File: Codable { var words: [String] }
        let payload = File(words: words.sorted())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
