import ApplicationServices
import Carbon
@preconcurrency import CoreGraphics
import Foundation
import KeyBoopCore

@MainActor
final class EventMonitor {
    let engine: Engine
    let replayer = Replayer()
    weak var model: AppModel?

    private var port: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    init(engine: Engine) {
        self.engine = engine
    }

    func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<EventMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return MainActor.assumeIsolated {
                monitor.handle(type: type, event: event)
            }
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        port = nil
        runLoopSource = nil
        isRunning = false
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Replayer.marker {
            return Unmanaged.passUnretained(event)
        }
        if replayer.isReplaying {
            replayer.abort()
            engine.reset()
            return Unmanaged.passUnretained(event)
        }

        let input = Self.parse(type, event)
        DispatchQueue.main.async { [weak self] in
            self?.deliver(input)
        }
        return Unmanaged.passUnretained(event)
    }

    private func deliver(_ input: Input) {
        guard let model else { return }
        syncSystemLayout()
        if !model.shouldProcess || IsSecureEventInputEnabled() || model.isFrontmostExcluded {
            engine.reset()
            model.noteBlocked(secure: IsSecureEventInputEnabled())
            return
        }
        model.noteReady()
        var selection: String?
        var element: AXUIElement?
        if case .shift(down: false) = input, let found = SelectionReader.current() {
            selection = found.text
            element = found.element
        }
        if let plan = engine.handle(input, selection: selection) {
            if plan.reason == .selection, let element {
                SystemLayouts.select(plan.layout)
                if !SelectionReader.replace(element, with: plan.insert) {
                    replayer.play(plan) { _ in }
                }
            } else {
                replayer.play(plan) { layout in
                    SystemLayouts.select(layout)
                }
            }
        }
    }

    private func syncSystemLayout() {
        guard !replayer.recentlySwitched, let actual = SystemLayouts.current(), actual != engine.systemLayout else { return }
        _ = engine.handle(.systemLayout(actual))
    }

    static func parse(_ type: CGEventType, _ event: CGEvent) -> Input {
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            return .drop
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if type == .flagsChanged {
            if code == KeyCode.shift || code == KeyCode.rightShift {
                return .shift(down: flags.contains(.maskShift))
            }
            return .noop
        }
        guard type == .keyDown else { return .noop }

        if code == KeyCode.delete { return .backspace }
        if code == KeyCode.escape
            || code == KeyCode.return
            || code == KeyCode.keypadEnter
            || code == KeyCode.tab
            || code == KeyCode.forwardDelete
            || (0x7B...0x7E).contains(code)
            || code == 0x73
            || code == 0x77
            || code == 0x74
            || code == 0x79
        {
            return .drop
        }

        let stroke = Stroke(
            keyCode: code,
            shift: flags.contains(.maskShift),
            capsLock: flags.contains(.maskAlphaShift)
        )
        return .key(
            stroke,
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl)
        )
    }
}
