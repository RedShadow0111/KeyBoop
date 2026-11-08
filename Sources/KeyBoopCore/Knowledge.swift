import Foundation

public enum KnowledgeError: Error, CustomStringConvertible {
    case missingDictionaries

    public var description: String {
        "Не найдены файлы словарей en.txt и ru.txt."
    }
}

public final class Knowledge: @unchecked Sendable {
    private let en: Set<String>
    private let ru: Set<String>
    private let enSorted: [String]
    private let ruSorted: [String]
    private let model: TrigramModel

    public init(english: Set<String>, russian: Set<String>) {
        self.en = english
        self.ru = russian
        self.enSorted = english.sorted()
        self.ruSorted = russian.sorted()
        self.model = TrigramModel(english: english, russian: russian)
    }

    public static func loadBundled() throws -> Knowledge {
        guard let directory = bundledDirectory() else {
            throw KnowledgeError.missingDictionaries
        }
        return try load(from: directory)
    }

    public static func load(from directory: URL) throws -> Knowledge {
        func read(_ name: String, letters: (Character) -> Bool) throws -> [String] {
            let url = directory.appendingPathComponent(name)
            let text = try String(contentsOf: url, encoding: .utf8)
            var words: [String] = []
            words.reserveCapacity(4096)
            for lineSub in text.split(whereSeparator: { $0.isNewline }) {
                let line = lineSub.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let key = TextNorm.lookupLetters(line)
                guard key.count == line.count, key.allSatisfy(letters) else { continue }
                words.append(key)
            }
            return words
        }
        let english = try read("en.txt") { character in
            guard let value = character.unicodeScalars.first?.value else { return false }
            return value >= 97 && value <= 122
        }
        let russian = try read("ru.txt") { character in
            guard let value = character.unicodeScalars.first?.value else { return false }
            return value >= 0x0430 && value <= 0x044F
        }
        let extraEN = (try? read("extra_en.txt") { character in
            guard let value = character.unicodeScalars.first?.value else { return false }
            return value >= 97 && value <= 122
        }) ?? []
        let extraRU = (try? read("extra_ru.txt") { character in
            guard let value = character.unicodeScalars.first?.value else { return false }
            return value >= 0x0430 && value <= 0x044F
        }) ?? []
        return Knowledge(english: Set(english + extraEN), russian: Set(russian + extraRU))
    }

    public func contains(_ letters: String, _ layout: LayoutID) -> Bool {
        switch layout {
        case .en: en.contains(letters)
        case .ru: ru.contains(letters)
        }
    }

    /// True when some dictionary word of this language begins with `letters`, including the word itself.
    public func isDictionaryPrefix(_ letters: String, _ layout: LayoutID) -> Bool {
        guard !letters.isEmpty else { return false }
        let words = layout == .en ? enSorted : ruSorted
        var low = 0
        var high = words.count
        while low < high {
            let mid = (low + high) / 2
            if words[mid] < letters {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < words.count else { return false }
        return words[low].hasPrefix(letters)
    }

    /// A longer dictionary word begins with `letters`. The word itself does not count.
    public func isLongerDictionaryPrefix(_ letters: String, _ layout: LayoutID) -> Bool {
        guard !letters.isEmpty else { return false }
        let words = layout == .en ? enSorted : ruSorted
        var low = 0
        var high = words.count
        while low < high {
            let mid = (low + high) / 2
            if words[mid] < letters {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var index = low
        if index < words.count, words[index] == letters {
            index += 1
        }
        guard index < words.count else { return false }
        return words[index].count > letters.count && words[index].hasPrefix(letters)
    }

    public func score(_ letters: String, _ layout: LayoutID) -> Float {
        model.assess(letters, layout: layout).average
    }

    public func isImpossible(_ letters: String, _ layout: LayoutID) -> Bool {
        let score = model.assess(letters, layout: layout)
        if !score.inAlphabet { return true }
        if score.count >= 4 && !score.hasVowel { return true }
        if score.count >= 3 && score.seenFraction < 0.5 { return true }
        if score.count >= 5 && score.average < model.cutoff(layout) - 2 { return true }
        return false
    }

    public func isPlausible(_ letters: String, _ layout: LayoutID) -> Bool {
        let score = model.assess(letters, layout: layout)
        if !score.inAlphabet || score.count < 3 || !score.hasVowel { return false }
        if score.seenFraction < 0.34 { return false }
        return score.average >= model.cutoff(layout) - 1
    }

    public static func bundledDirectory() -> URL? {
        let packaged = [
            Bundle.main.resourceURL?.appendingPathComponent("Dictionaries"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Dictionaries"),
        ]
        for candidate in packaged.compactMap({ $0 }) where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("en.txt").path) {
            return candidate
        }
        if let url = Bundle.module.url(forResource: "en", withExtension: "txt", subdirectory: "Dictionaries") {
            return url.deletingLastPathComponent()
        }
        return nil
    }
}

final class TrigramModel: @unchecked Sendable {
    struct Assessment {
        var average: Float
        var seenFraction: Float
        var inAlphabet: Bool
        var hasVowel: Bool
        var count: Int
    }

    private let enLog: [Float]
    private let ruLog: [Float]
    private let enSeen: [Bool]
    private let ruSeen: [Bool]
    private let enCutoff: Float
    private let ruCutoff: Float

    init(english: Set<String>, russian: Set<String>) {
        let en = Self.train(words: english, alphabet: 26, index: Self.enIndex)
        let ru = Self.train(words: russian, alphabet: 32, index: Self.ruIndex)
        self.enLog = en.logs
        self.ruLog = ru.logs
        self.enSeen = en.seen
        self.ruSeen = ru.seen
        self.enCutoff = Self.cutoff(words: english, alphabet: 26, logs: en.logs, index: Self.enIndex, vowel: Self.enVowel)
        self.ruCutoff = Self.cutoff(words: russian, alphabet: 32, logs: ru.logs, index: Self.ruIndex, vowel: Self.ruVowel)
    }

    func cutoff(_ layout: LayoutID) -> Float {
        layout == .en ? enCutoff : ruCutoff
    }

    func assess(_ letters: String, layout: LayoutID) -> Assessment {
        let alphabet = layout == .en ? 26 : 32
        let indexFn = layout == .en ? Self.enIndex : Self.ruIndex
        let vowelFn = layout == .en ? Self.enVowel : Self.ruVowel
        let logs = layout == .en ? enLog : ruLog
        let seen = layout == .en ? enSeen : ruSeen
        var indexes: [Int] = []
        indexes.reserveCapacity(letters.count)
        var inAlphabet = true
        var hasVowel = false
        for character in letters {
            guard let index = indexFn(character) else {
                inAlphabet = false
                continue
            }
            if vowelFn(character) { hasVowel = true }
            indexes.append(index)
        }
        let count = indexes.count
        guard count >= 3 else {
            return Assessment(average: -20, seenFraction: 0, inAlphabet: inAlphabet, hasVowel: hasVowel, count: count)
        }
        var sum: Float = 0
        var seenCount = 0
        let trigrams = count - 2
        for offset in 0..<trigrams {
            let slot = indexes[offset] * alphabet * alphabet + indexes[offset + 1] * alphabet + indexes[offset + 2]
            sum += logs[slot]
            if seen[slot] { seenCount += 1 }
        }
        return Assessment(
            average: sum / Float(trigrams),
            seenFraction: Float(seenCount) / Float(trigrams),
            inAlphabet: inAlphabet,
            hasVowel: hasVowel,
            count: count
        )
    }

    private static func train(
        words: Set<String>,
        alphabet: Int,
        index: (Character) -> Int?
    ) -> (logs: [Float], seen: [Bool]) {
        let size = alphabet * alphabet * alphabet
        var counts = [Int](repeating: 0, count: size)
        var total = 0
        for word in words {
            var indexes: [Int] = []
            indexes.reserveCapacity(word.count)
            var valid = true
            for character in word {
                guard let value = index(character) else {
                    valid = false
                    break
                }
                indexes.append(value)
            }
            guard valid, indexes.count >= 3 else { continue }
            for offset in 0..<(indexes.count - 2) {
                let slot = indexes[offset] * alphabet * alphabet + indexes[offset + 1] * alphabet + indexes[offset + 2]
                counts[slot] += 1
                total += 1
            }
        }
        let smooth = 0.5
        let denominator = Float(total) + Float(smooth) * Float(size)
        var logs = [Float](repeating: 0, count: size)
        var seen = [Bool](repeating: false, count: size)
        for slot in 0..<size {
            seen[slot] = counts[slot] > 0
            logs[slot] = log((Float(counts[slot]) + Float(smooth)) / denominator)
        }
        return (logs, seen)
    }

    private static func cutoff(
        words: Set<String>,
        alphabet: Int,
        logs: [Float],
        index: (Character) -> Int?,
        vowel: (Character) -> Bool
    ) -> Float {
        var scores: [Float] = []
        scores.reserveCapacity(words.count)
        for word in words.sorted() where word.count >= 5 {
            var indexes: [Int] = []
            var ok = true
            var hasVowel = false
            for character in word {
                guard let value = index(character) else {
                    ok = false
                    break
                }
                if vowel(character) { hasVowel = true }
                indexes.append(value)
            }
            guard ok, hasVowel, indexes.count >= 5 else { continue }
            var sum: Float = 0
            let trigrams = indexes.count - 2
            for offset in 0..<trigrams {
                let slot = indexes[offset] * alphabet * alphabet + indexes[offset + 1] * alphabet + indexes[offset + 2]
                sum += logs[slot]
            }
            scores.append(sum / Float(trigrams))
        }
        guard !scores.isEmpty else { return -8 }
        scores.sort()
        let position = Int(Double(scores.count - 1) * 0.15)
        return scores[position]
    }

    private static func enIndex(_ character: Character) -> Int? {
        guard let value = character.unicodeScalars.first?.value, value >= 97, value <= 122 else { return nil }
        return Int(value - 97)
    }

    private static func ruIndex(_ character: Character) -> Int? {
        guard let value = character.unicodeScalars.first?.value, value >= 0x0430, value <= 0x044F else { return nil }
        return Int(value - 0x0430)
    }

    private static func enVowel(_ character: Character) -> Bool {
        "aeiouy".contains(character)
    }

    private static func ruVowel(_ character: Character) -> Bool {
        "аеиоуыэюя".contains(character)
    }
}
