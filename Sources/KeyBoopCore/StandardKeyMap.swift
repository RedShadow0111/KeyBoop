public protocol LayoutDecoding: Sendable {
    func glyph(for stroke: Stroke, layout: LayoutID) -> Glyph?
}

/// Reference ЙЦУКЕН / ABC map used in tests and when a system layout has no Unicode data.
/// Punctuation matches the macOS “Russian – PC” layout (`RussianWin`); letter keys match both
/// Apple Russian layouts. Live typing prefers `SystemLayoutDecoder`.
public struct StandardKeyMap: LayoutDecoding, Sendable {
    public static let shared = StandardKeyMap()

    struct Row {
        var code: UInt16
        var enPlain: Character
        var enShift: Character
        var ruPlain: Character
        var ruShift: Character
    }

    let rows: [Row]
    let byCode: [UInt16: Row]

    init() {
        let rows = Self.makeRows()
        self.rows = rows
        self.byCode = Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })
    }

    public func glyph(for stroke: Stroke, layout: LayoutID) -> Glyph? {
        guard let row = byCode[stroke.keyCode] else { return nil }
        let plain = layout == .en ? row.enPlain : row.ruPlain
        let shifted = layout == .en ? row.enShift : row.ruShift
        let character: Character
        if plain.isLetter {
            let upper = stroke.shift != stroke.capsLock
            character = upper ? shifted : plain
        } else {
            character = stroke.shift ? shifted : plain
        }
        return Glyph(character: character)
    }

    /// Physical keys that produce `word` while `layout` is active.
    public func strokes(for word: String, layout: LayoutID) -> [Stroke]? {
        var strokes: [Stroke] = []
        strokes.reserveCapacity(word.count)
        for character in word {
            guard let stroke = stroke(for: character, layout: layout) else { return nil }
            strokes.append(stroke)
        }
        return strokes
    }

    public func stroke(for character: Character, layout: LayoutID) -> Stroke? {
        for row in rows {
            let plain = layout == .en ? row.enPlain : row.ruPlain
            let shifted = layout == .en ? row.enShift : row.ruShift
            if character == plain {
                return Stroke(keyCode: row.code, shift: false)
            }
            if character == shifted {
                return Stroke(keyCode: row.code, shift: true)
            }
        }
        return nil
    }

    static func row(_ code: UInt16, _ en: String, _ ru: String) -> Row {
        let e = Array(en)
        let r = Array(ru)
        precondition(e.count == 2 && r.count == 2)
        return Row(code: code, enPlain: e[0], enShift: e[1], ruPlain: r[0], ruShift: r[1])
    }

    static func makeRows() -> [Row] {
        [
            row(0x00, "aA", "фФ"),
            row(0x01, "sS", "ыЫ"),
            row(0x02, "dD", "вВ"),
            row(0x03, "fF", "аА"),
            row(0x04, "hH", "рР"),
            row(0x05, "gG", "пП"),
            row(0x06, "zZ", "яЯ"),
            row(0x07, "xX", "чЧ"),
            row(0x08, "cC", "сС"),
            row(0x09, "vV", "мМ"),
            row(0x0B, "bB", "иИ"),
            row(0x0C, "qQ", "йЙ"),
            row(0x0D, "wW", "цЦ"),
            row(0x0E, "eE", "уУ"),
            row(0x0F, "rR", "кК"),
            row(0x10, "yY", "нН"),
            row(0x11, "tT", "еЕ"),
            row(0x12, "1!", "1!"),
            row(0x13, "2@", "2\""),
            row(0x14, "3#", "3№"),
            row(0x15, "4$", "4;"),
            row(0x16, "6^", "6:"),
            row(0x17, "5%", "5%"),
            row(0x18, "=+", "=+"),
            row(0x19, "9(", "9("),
            row(0x1A, "7&", "7?"),
            row(0x1B, "-_", "-_"),
            row(0x1C, "8*", "8*"),
            row(0x1D, "0)", "0)"),
            row(0x1E, "]}", "ъЪ"),
            row(0x1F, "oO", "щЩ"),
            row(0x20, "uU", "гГ"),
            row(0x21, "[{", "хХ"),
            row(0x22, "iI", "шШ"),
            row(0x23, "pP", "зЗ"),
            row(0x25, "lL", "дД"),
            row(0x26, "jJ", "оО"),
            row(0x27, "'\"", "эЭ"),
            row(0x28, "kK", "лЛ"),
            row(0x29, ";:", "жЖ"),
            row(0x2A, "\\|", "\\/"),
            row(0x2B, ",<", "бБ"),
            row(0x2C, "/?", ".,"),
            row(0x2D, "nN", "тТ"),
            row(0x2E, "mM", "ьЬ"),
            row(0x2F, ".>", "юЮ"),
            row(0x32, "`~", "]["),
        ]
    }
}
