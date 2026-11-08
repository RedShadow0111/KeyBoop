@preconcurrency import CoreGraphics
import Foundation
import KeyBoopCore

final class Replayer {
    static let marker: Int64 = 0x4B427031
    private(set) var isReplaying = false
    private var abortFlag = false
    private var switchedAt: Date?

    var recentlySwitched: Bool {
        guard let switchedAt else { return false }
        return Date().timeIntervalSince(switchedAt) < 0.4
    }

    func abort() {
        abortFlag = true
    }

    func play(_ plan: ReplacePlan, switchLayout: (LayoutID) -> Void) {
        guard plan.deleteCount > 0, plan.deleteCount <= 500, plan.insert.count <= 500 else { return }
        isReplaying = true
        abortFlag = false
        defer { isReplaying = false }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        source.localEventsSuppressionInterval = 0
        source.userData = Self.marker

        for _ in 0..<plan.deleteCount {
            if abortFlag { return }
            postKey(source, keyCode: KeyCode.delete, down: true)
            postKey(source, keyCode: KeyCode.delete, down: false)
        }
        if abortFlag { return }
        switchLayout(plan.layout)
        switchedAt = Date()
        for character in plan.insert {
            if abortFlag { return }
            postCharacter(source, character)
        }
    }

    private func postKey(_ source: CGEventSource, keyCode: UInt16, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgSessionEventTap)
    }

    private func postCharacter(_ source: CGEventSource, _ character: Character) {
        var units = Array(String(character).utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        down.post(tap: .cgSessionEventTap)
        guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        up.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        up.post(tap: .cgSessionEventTap)
    }
}
