public enum TextNorm {
    private static let yo: Character = "ё"
    private static let ye: Character = "е"

    /// Lowercase letters only, with ё folded to е so dictionary lookup matches either spelling.
    public static func lookupLetters(_ raw: String) -> String {
        var out = String()
        out.reserveCapacity(raw.count)
        for character in raw.lowercased() {
            if character == yo {
                out.append(ye)
            } else if character.isLetter {
                out.append(character)
            }
        }
        return out
    }
}
