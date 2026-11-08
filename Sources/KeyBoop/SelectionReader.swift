import ApplicationServices
import Foundation

enum SelectionReader {
    static func current() -> (text: String, element: AXUIElement)? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        if let text = selectedText(of: element) {
            return (text, element)
        }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &children) == .success,
              let kids = children as? [AXUIElement]
        else { return nil }
        for child in kids.prefix(16) {
            if let text = selectedText(of: child) {
                return (text, child)
            }
        }
        return nil
    }

    static func replace(_ element: AXUIElement, with text: String, replacing previous: String) -> Bool {
        guard AXUIElementSetAttributeValue(element, "AXSelectedText" as CFString, text as CFString) == .success else {
            return false
        }
        if let current = selectedText(of: element), current == previous, previous != text {
            return false
        }
        return true
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSelectedText" as CFString, &value) == .success,
           let text = value as? String,
           acceptable(text)
        {
            return text
        }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextRange" as CFString, &range) == .success,
              let range
        else { return nil }
        var ranged: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForRange" as CFString,
            range,
            &ranged
        ) == .success,
            let text = ranged as? String,
            acceptable(text)
        else { return nil }
        return text
    }

    private static func acceptable(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 2000
    }
}
