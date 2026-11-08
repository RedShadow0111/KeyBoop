public struct Observation: Equatable, Sendable {
    public var currentRaw: String
    public var alternateRaw: String
    public var currentLayout: LayoutID
    public var previousLayout: LayoutID?
    public var blockedByContext: Bool

    public init(
        currentRaw: String,
        alternateRaw: String,
        currentLayout: LayoutID,
        previousLayout: LayoutID? = nil,
        blockedByContext: Bool = false
    ) {
        self.currentRaw = currentRaw
        self.alternateRaw = alternateRaw
        self.currentLayout = currentLayout
        self.previousLayout = previousLayout
        self.blockedByContext = blockedByContext
    }
}

public enum Decision: Equatable, Sendable {
    case keep
    case replace(LayoutID)
}

public struct Detector: Sendable {
    private let knowledge: Knowledge
    private let exceptions: ExceptionList
    public var disabledShortWords: Set<String> = []

    public init(knowledge: Knowledge, exceptions: ExceptionList) {
        self.knowledge = knowledge
        self.exceptions = exceptions
    }

    public func isDictionaryPrefix(_ letters: String, _ layout: LayoutID) -> Bool {
        knowledge.isDictionaryPrefix(letters, layout)
    }

    public func isLongerDictionaryPrefix(_ letters: String, _ layout: LayoutID) -> Bool {
        knowledge.isLongerDictionaryPrefix(letters, layout)
    }

    public func containsWord(_ letters: String, _ layout: LayoutID) -> Bool {
        knowledge.contains(letters, layout)
    }

    public func impossible(_ letters: String, _ layout: LayoutID) -> Bool {
        knowledge.isImpossible(letters, layout)
    }

    public func decide(_ observation: Observation) -> Decision {
        if observation.blockedByContext { return .keep }
        let currentLetters = TextNorm.lookupLetters(observation.currentRaw)
        let alternateLetters = TextNorm.lookupLetters(observation.alternateRaw)
        if currentLetters.isEmpty { return .keep }
        let alternateLayout = observation.currentLayout.opposite
        let short = Self.shortPair(
            currentLetters: currentLetters,
            alternateLetters: alternateLetters,
            currentLayout: observation.currentLayout,
            alternateLayout: alternateLayout,
            disabled: disabledShortWords
        )
        if currentLetters.count < 3 && !short { return .keep }
        let alternateInDictionary = knowledge.contains(alternateLetters, alternateLayout)
        let dotIsLetter = alternateInDictionary
            || (alternateLetters.count >= 5 && knowledge.isPlausible(alternateLetters, alternateLayout))
        if StopRules.blocked(
            raw: observation.currentRaw,
            letters: currentLetters,
            allowDot: dotIsLetter,
            allowInnerCapitals: alternateInDictionary
        ) { return .keep }
        if exceptions.contains(currentLetters) || exceptions.contains(alternateLetters) { return .keep }
        if short {
            return .replace(alternateLayout)
        }

        if knowledge.contains(currentLetters, observation.currentLayout) { return .keep }

        let currentScore = knowledge.score(currentLetters, observation.currentLayout)
        var alternateScore = knowledge.score(alternateLetters, alternateLayout)
        if observation.previousLayout == alternateLayout {
            alternateScore += 0.2
        }
        let margin = alternateScore - currentScore

        if alternateInDictionary {
            if knowledge.isImpossible(currentLetters, observation.currentLayout) {
                return .replace(alternateLayout)
            }
            if !knowledge.isPlausible(currentLetters, observation.currentLayout), margin >= 1 {
                return .replace(alternateLayout)
            }
            if margin >= 1 {
                return .replace(alternateLayout)
            }
            return .keep
        }

        if currentLetters.count >= 5, knowledge.isPlausible(alternateLetters, alternateLayout) {
            if knowledge.isImpossible(currentLetters, observation.currentLayout) {
                return .replace(alternateLayout)
            }
            if !knowledge.isPlausible(currentLetters, observation.currentLayout), margin >= 0.35 {
                return .replace(alternateLayout)
            }
        }
        return .keep
    }

    static func shortPair(
        currentLetters: String,
        alternateLetters: String,
        currentLayout: LayoutID,
        alternateLayout: LayoutID,
        disabled: Set<String>
    ) -> Bool {
        guard alternateLetters.count <= 2, currentLetters.count <= 2 else { return false }
        guard ShortWords.allows(alternateLetters, layout: alternateLayout, disabled: disabled) else { return false }
        return !ShortWords.allows(currentLetters, layout: currentLayout, disabled: disabled)
    }
}

enum StopRules {
    static func blocked(raw: String, letters: String, allowDot: Bool, allowInnerCapitals: Bool = false) -> Bool {
        if raw.contains(where: \.isNumber) { return true }
        if raw.contains(".") && !allowDot { return true }
        if raw.contains("@") || raw.contains("/") || raw.contains("\\") { return true }
        if !allowInnerCapitals && camelCase(raw) { return true }
        return mixedScripts(letters)
    }

    static func camelCase(_ raw: String) -> Bool {
        var seenLower = false
        for character in raw where character.isLetter {
            if character.isLowercase {
                seenLower = true
            } else if character.isUppercase && seenLower {
                return true
            }
        }
        return false
    }

    static func mixedScripts(_ letters: String) -> Bool {
        var latin = false
        var cyrillic = false
        for character in letters {
            let value = character.unicodeScalars.first?.value ?? 0
            if value <= 127 {
                latin = true
            } else {
                cyrillic = true
            }
            if latin && cyrillic { return true }
        }
        return false
    }
}
