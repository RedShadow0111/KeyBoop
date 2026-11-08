import AppKit
import KeyBoopCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let monitor: EventMonitor
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?

    override init() {
        let exceptions = ExceptionList(ExceptionStore.load())
        let model = AppModel(exceptions: exceptions)
        let knowledge: Knowledge
        do {
            knowledge = try Knowledge.loadBundled()
        } catch {
            fatalError("KeyBoop не нашёл словари: \(error)")
        }
        let decoder = SystemLayoutDecoder()
        decoder.refresh()
        let layout = SystemLayouts.current() ?? .en
        let engine = Engine(decoder: decoder, knowledge: knowledge, exceptions: exceptions, layout: layout)
        model.attach(engine: engine)
        exceptions.onChange = { words in
            ExceptionStore.save(words)
        }
        self.model = model
        self.monitor = EventMonitor(engine: engine)
        super.init()
        monitor.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        model.refreshPermissions()
        model.noteFrontmost(NSWorkspace.shared.frontmostApplication)
        if model.shouldProcess {
            _ = monitor.start()
        }
        observeActivation()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        if !model.listenGranted || !model.accessGranted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func tick() {
        model.refreshPermissions()
        model.exceptionCount = model.exceptions.count
        if model.listenGranted {
            if !monitor.isRunning {
                _ = monitor.start()
            }
        }
        rebuildMenu()
    }

    private func observeActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        model.noteFrontmost(app)
        rebuildMenu()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyBoop") {
            image.isTemplate = true
            item.button?.image = image
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: model.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Включено", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.state = model.enabled ? .on : .off
        enabled.target = self
        menu.addItem(enabled)

        let paused = NSMenuItem(title: "Пауза", action: #selector(togglePaused), keyEquivalent: "")
        paused.state = model.paused ? .on : .off
        paused.target = self
        menu.addItem(paused)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let permissions = NSMenuItem(title: "Разрешения…", action: #selector(showOnboarding), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    @objc private func toggleEnabled() {
        model.enabled.toggle()
        rebuildMenu()
    }

    @objc private func togglePaused() {
        model.paused.toggle()
        if model.paused { monitor.engine.reset() }
        rebuildMenu()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "KeyBoop"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView(model: model, onClose: { [weak self] in
                self?.onboardingWindow?.close()
            }))
            let window = NSWindow(contentViewController: host)
            window.title = "KeyBoop"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class AppKeeper {
    static let shared = AppKeeper()
    var delegate: AppDelegate?
}

@main
enum KeyBoopMain {
    static func main() {
        MainActor.assumeIsolated {
            let delegate = AppDelegate()
            AppKeeper.shared.delegate = delegate
            let app = NSApplication.shared
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
