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

    public init(knowledge: Knowledge, exceptions: ExceptionList) {
        self.knowledge = knowledge
        self.exceptions = exceptions
    }

    public func decide(_ observation: Observation) -> Decision {
        if observation.blockedByContext { return .keep }
        let currentLetters = TextNorm.lookupLetters(observation.currentRaw)
        let alternateLetters = TextNorm.lookupLetters(observation.alternateRaw)
        if currentLetters.count < 3 { return .keep }
        let alternateLayout = observation.currentLayout.opposite
        let alternateInDictionary = knowledge.contains(alternateLetters, alternateLayout)
        let dotIsLetter = alternateInDictionary
            || (alternateLetters.count >= 5 && knowledge.isPlausible(alternateLetters, alternateLayout))
        if StopRules.blocked(raw: observation.currentRaw, letters: currentLetters, allowDot: dotIsLetter) { return .keep }
        if exceptions.contains(currentLetters) || exceptions.contains(alternateLetters) { return .keep }

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
            if margin >= 2.5 {
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
}

enum StopRules {
    static func blocked(raw: String, letters: String, allowDot: Bool) -> Bool {
        if raw.contains(where: \.isNumber) { return true }
        if raw.contains(".") && !allowDot { return true }
        if raw.contains("@") || raw.contains("/") || raw.contains("\\") { return true }
        if camelCase(raw) { return true }
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
