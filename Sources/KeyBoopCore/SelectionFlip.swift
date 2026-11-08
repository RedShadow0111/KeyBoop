public enum SelectionFlip {
    public static func flip(_ text: String, using decoder: any LayoutDecoding) -> (text: String, layout: LayoutID) {
        var output = ""
        output.reserveCapacity(text.count)
        var latin = 0
        var cyrillic = 0
        for character in text {
            let flipped = flipCharacter(character, using: decoder)
            output.append(flipped)
            guard flipped.isLetter else { continue }
            if isCyrillic(flipped) {
                cyrillic += 1
            } else {
                latin += 1
            }
        }
        return (output, cyrillic >= latin ? .ru : .en)
    }

    private static func flipCharacter(_ character: Character, using decoder: any LayoutDecoding) -> Character {
        guard character.isLetter else { return character }
        if let stroke = decoder.stroke(for: character, layout: .en),
           decoder.glyph(for: stroke, layout: .en)?.character == character,
           let glyph = decoder.glyph(for: stroke, layout: .ru)
        {
            return glyph.character
        }
        if let stroke = decoder.stroke(for: character, layout: .ru),
           decoder.glyph(for: stroke, layout: .ru)?.character == character,
           let glyph = decoder.glyph(for: stroke, layout: .en)
        {
            return glyph.character
        }
        return character
    }

    private static func isCyrillic(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0x0400...0x04FF).contains(value)
    }
}
