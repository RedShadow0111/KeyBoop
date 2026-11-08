import AppKit
import Darwin
import KeyBoopBrand
import KeyBoopCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let monitor: EventMonitor
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    override init() {
        let exceptions = ExceptionList(ordered: ExceptionStore.load())
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
        exceptions.onChange = { [weak model] words in
            let ordered = exceptions.ordered
            let recent = exceptions.recent
            ExceptionStore.save(ordered)
            Task { @MainActor in
                model?.exceptionWords = recent
                model?.exceptionCount = words.count
            }
        }
        self.model = model
        self.monitor = EventMonitor(engine: engine)
        super.init()
        monitor.model = model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
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
        model.checkForUpdate()
        if !model.listenGranted || !model.accessGranted {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        PermissionGuide.shared.dismiss()
        monitor.stop()
    }

    private func tick() {
        model.refreshPermissions()
        model.noteExceptions()
        if model.listenGranted, !monitor.isRunning {
            if !monitor.start() {
                model.noteListenNeedsRelaunch()
            }
        }
    }

    private func observeActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.model.noteFrontmost(app)
            }
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let mark = BrandMark.image(side: 18, template: true)
        item.button?.image = mark
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPanelView(
            model: model,
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        ))
        self.popover = popover
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.refreshPermissions()
        model.noteExceptions()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func showSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: host)
            window.title = "Настройки KeyBoop"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 680, height: 360))
            window.minSize = NSSize(width: 640, height: 320)
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
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
}

@MainActor
final class AppKeeper {
    static let shared = AppKeeper()
    var delegate: AppDelegate?
}

@MainActor
enum SingleInstance {
    private static var descriptor: Int32 = -1

    static func claim() -> Bool {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeyBoop", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("instance.lock").path
        descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return true }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            descriptor = -1
            return false
        }
        return true
    }
}

@main
enum KeyBoopMain {
    static func main() {
        MainActor.assumeIsolated {
            guard SingleInstance.claim() else {
                let pid = ProcessInfo.processInfo.processIdentifier
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.keyboop.app")
                    .first { $0.processIdentifier != pid }?
                    .activate()
                exit(0)
            }
            let delegate = AppDelegate()
            AppKeeper.shared.delegate = delegate
            let app = NSApplication.shared
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
