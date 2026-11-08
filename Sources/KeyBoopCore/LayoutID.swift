public enum LayoutID: String, Codable, Sendable, CaseIterable {
    case en
    case ru

    public var opposite: LayoutID {
        switch self {
        case .en: .ru
        case .ru: .en
        }
    }
}

public enum KeyCode {
    public static let space: UInt16 = 0x31
    public static let `return`: UInt16 = 0x24
    public static let keypadEnter: UInt16 = 0x4C
    public static let tab: UInt16 = 0x30
    public static let delete: UInt16 = 0x33
    public static let forwardDelete: UInt16 = 0x75
    public static let escape: UInt16 = 0x35
    public static let shift: UInt16 = 0x38
    public static let rightShift: UInt16 = 0x3C
}

public struct Stroke: Equatable, Sendable {
    public var keyCode: UInt16
    public var shift: Bool
    public var capsLock: Bool

    public init(keyCode: UInt16, shift: Bool = false, capsLock: Bool = false) {
        self.keyCode = keyCode
        self.shift = shift
        self.capsLock = capsLock
    }
}

public struct Glyph: Equatable, Sendable {
    public var character: Character
    public var isLetter: Bool
    public var isDigit: Bool

    public init(character: Character) {
        self.character = character
        self.isLetter = character.isLetter
        self.isDigit = character.isNumber && character.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }
}
