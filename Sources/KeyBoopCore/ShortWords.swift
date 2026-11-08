public enum ShortWords {
    public static let russian = [
        "я",
        "ты", "мы", "он", "вы", "да", "но", "не", "ну", "то", "по", "за", "из", "от", "на", "же", "ли", "бы", "уж",
    ]
    public static let english = [
        "a", "i",
        "we", "to", "of", "in", "on", "no", "it", "is", "be", "do", "go", "up", "my", "me", "he", "ok",
    ]

    public static func allows(_ letters: String, layout: LayoutID, disabled: Set<String>) -> Bool {
        guard !disabled.contains(letters) else { return false }
        switch layout {
        case .ru: return russian.contains(letters)
        case .en: return english.contains(letters)
        }
    }

    public struct Pair: Equatable, Sendable {
        public var word: String
        public var other: String
        public var layout: LayoutID
    }

    public static func pairs(using decoder: any LayoutDecoding = StandardKeyMap.shared) -> [Pair] {
        russian.map { word in
            Pair(word: word, other: companion(word, from: .ru, using: decoder), layout: .ru)
        } + english.map { word in
            Pair(word: word, other: companion(word, from: .en, using: decoder), layout: .en)
        }
    }

    public static func companion(_ word: String, from layout: LayoutID, using decoder: any LayoutDecoding) -> String {
        var text = ""
        for character in word {
            guard let stroke = decoder.stroke(for: character, layout: layout),
                  let glyph = decoder.glyph(for: stroke, layout: layout.opposite)
            else {
                text.append(character)
                continue
            }
            text.append(glyph.character)
        }
        return text
    }
}
