import ApplicationServices
import Foundation

enum SelectionReader {
    static func current() -> (text: String, element: AXUIElement)? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focused
        else { return nil }
        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &value) == .success,
              let text = value as? String,
              !text.isEmpty,
              text.count <= 2000
        else { return nil }
        return (text, element)
    }

    static func replace(_ element: AXUIElement, with text: String) -> Bool {
        AXUIElementSetAttributeValue(element, "AXSelectedText" as CFString, text as CFString) == .success
    }
}
