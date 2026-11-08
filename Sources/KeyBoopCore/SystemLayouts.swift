import Carbon
import Foundation

public enum SystemLayouts {
    public static func current() -> LayoutID? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let layout = identify(source)
        {
            return layout
        }
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            return identify(source)
        }
        return nil
    }

    @discardableResult
    public static func select(_ layout: LayoutID) -> Bool {
        guard let source = bestSource(for: layout) else { return false }
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), identify(current) == layout,
           sameSource(current, source)
        {
            return true
        }
        return TISSelectInputSource(source) == noErr
    }

    static func bestSource(for layout: LayoutID) -> TISInputSource? {
        let matches = keyboardSources().filter { identify($0) == layout && layoutData($0) != nil }
        if let selected = matches.first(where: { boolProperty($0, kTISPropertyInputSourceIsSelected) }) {
            return selected
        }
        return matches.first
    }

    static func keyboardSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.filter { source in
            stringProperty(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String)
                && boolProperty(source, kTISPropertyInputSourceIsEnabled)
        }
    }

    static func identify(_ source: TISInputSource) -> LayoutID? {
        let languages = languageList(source)
        let identifier = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        if languages.first == "ru" || identifier.contains("Russian") { return .ru }
        if languages.contains("ru"), !languages.contains("en") { return .ru }
        if languages.first == "en" || languages.contains("en") { return .en }
        return nil
    }

    static func layoutData(_ source: TISInputSource) -> Data? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        return data as Data
    }

    private static func sameSource(_ lhs: TISInputSource, _ rhs: TISInputSource) -> Bool {
        stringProperty(lhs, kTISPropertyInputSourceID) == stringProperty(rhs, kTISPropertyInputSourceID)
    }

    private static func languageList(_ source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

public final class SystemLayoutDecoder: LayoutDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var layouts: [LayoutID: Data] = [:]
    private let fallback = StandardKeyMap.shared

    public init() {}

    public func refresh() {
        var found: [LayoutID: Data] = [:]
        for layout in LayoutID.allCases {
            if let source = SystemLayouts.bestSource(for: layout), let data = SystemLayouts.layoutData(source) {
                found[layout] = data
            }
        }
        lock.lock()
        layouts = found
        lock.unlock()
    }

    public func hasData(for layout: LayoutID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return layouts[layout] != nil
    }

    public func glyph(for stroke: Stroke, layout: LayoutID) -> Glyph? {
        lock.lock()
        let data = layouts[layout]
        lock.unlock()
        if let data, let glyph = Self.translate(data, stroke) {
            return glyph
        }
        return fallback.glyph(for: stroke, layout: layout)
    }

    static func translate(_ data: Data, _ stroke: Stroke) -> Glyph? {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return nil }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKey: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            var modifiers: UInt32 = 0
            if stroke.shift { modifiers |= UInt32(shiftKey >> 8) }
            if stroke.capsLock { modifiers |= UInt32(alphaLock >> 8) }
            let status = UCKeyTranslate(
                layout,
                stroke.keyCode,
                UInt16(kUCKeyActionDisplay),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKey,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length)
            guard let character = text.first, text.count == 1 else { return nil }
            return Glyph(character: character)
        }
    }
}
