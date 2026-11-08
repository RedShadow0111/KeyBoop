import Foundation
import KeyBoopCore

struct Failed: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failed(message) }
}

@main
enum KeyBoopSelfTestMain {
    static func main() {
        do {
            try EngineChecks().runAll()
            print("KeyBoop checks passed")
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}

final class EngineChecks {
    private let map = StandardKeyMap.shared
    private static let knowledge = try! Knowledge.loadBundled()
    private var space: Stroke { Stroke(keyCode: KeyCode.space) }

    func runAll() throws {
        try wrongEnglishBecomesRussianOnSpace()
        try wrongRussianBecomesEnglishOnSpace()
        try githubTypedInRussianBecomesGithub()
        try mixedCaseDictionaryWordKeepsItsCapitals()
        try capitalizationIsPreserved()
        try realWordsStay()
        try shortTokensAndIdentifiersStay()
        try returnDoesNotRewrite()
        try urlFixesBeforeSpace()
        try wwwFixesBeforeSpace()
        try pathIsNotConverted()
        try undoRemembersTheWord()
        try doubleShiftConvertsTheLastWord()
        try tripleShiftConvertsThePhrase()
        try backspaceKeepsTheWordInSync()
        try commonWordsAreCorrected()
        try heldOutRecallAndFalsePositives()
        try systemLetterKeysMatchTheReferenceMap()
        try unfinishedWordSwitchesBeforeSpace()
        try ghostAndMacStayWhileTyping()
        try shortWordsSwitchBeforeSpace()
        try selectionDoubleShiftFlipsTheHighlight()
        try bufferStaysBounded()
    }

    func wrongEnglishBecomesRussianOnSpace() throws {
        let engine = makeEngine(layout: .en)
        let text = screen(engine, meant: "привет", meantLayout: .ru, boundary: space)
        try expect(text == "привет ", "screen \(text)")
        try expect(engine.systemLayout == .ru, "layout")
    }

    func wrongRussianBecomesEnglishOnSpace() throws {
        let engine = makeEngine(layout: .ru)
        let text = screen(engine, meant: "hello", meantLayout: .en, boundary: space)
        try expect(text == "hello ", "screen \(text)")
        try expect(engine.systemLayout == .en, "layout")
    }

    func githubTypedInRussianBecomesGithub() throws {
        let engine = makeEngine(layout: .ru)
        let text = screen(engine, meant: "github", meantLayout: .en, boundary: space)
        try expect(text == "github ", "github \(text)")
        try expect(engine.systemLayout == .en, "github layout")
        let own = makeEngine(layout: .en)
        try expect(feed(own, meant: "github", meantLayout: .en, boundary: space) == nil, "github stays")
    }

    func mixedCaseDictionaryWordKeepsItsCapitals() throws {
        let engine = makeEngine(layout: .ru)
        let text = screen(engine, meant: "GitHub", meantLayout: .en, boundary: space)
        try expect(text == "GitHub ", "GitHub \(text)")
        try expect(engine.systemLayout == .en, "GitHub layout")
        let own = makeEngine(layout: .en)
        try expect(feed(own, meant: "GitHub", meantLayout: .en, boundary: space) == nil, "GitHub stays")
        let identifier = makeEngine(layout: .en)
        try expect(feed(identifier, meant: "myValue", meantLayout: .en, boundary: space) == nil, "myValue")
    }

    func capitalizationIsPreserved() throws {
        let engine = makeEngine(layout: .en)
        let text = screen(engine, meant: "Привет", meantLayout: .ru, boundary: space)
        try expect(text == "Привет ", "screen \(text)")
        try expect(engine.systemLayout == .ru, "layout")
    }

    func realWordsStay() throws {
        let english = makeEngine(layout: .en)
        try expect(feed(english, meant: "hello", meantLayout: .en, boundary: space) == nil, "hello")
        try expect(feed(english, meant: "git", meantLayout: .en, boundary: space) == nil, "git")
        try expect(feed(english, meant: "mac", meantLayout: .en, boundary: space) == nil, "mac")
        let russian = makeEngine(layout: .ru)
        try expect(feed(russian, meant: "привет", meantLayout: .ru, boundary: space) == nil, "привет")
    }

    func shortTokensAndIdentifiersStay() throws {
        let engine = makeEngine(layout: .en)
        try expect(feed(engine, meant: "ok", meantLayout: .en, boundary: space) == nil, "ok")
        try expect(feed(engine, meant: "http", meantLayout: .en, boundary: space) == nil, "http")
        try expect(feed(engine, meant: "npm", meantLayout: .en, boundary: space) == nil, "npm")
        try expect(feed(engine, produced: "fooBar", boundary: space) == nil, "fooBar")
        try expect(feed(engine, produced: "asdfgh", boundary: space) == nil, "asdfgh \(String(describing: feed(engine, produced: "asdfgh", boundary: space)))")
    }

    func returnDoesNotRewrite() throws {
        let engine = makeEngine(layout: .en)
        let strokes = try need(map.strokes(for: "привет", layout: .ru))
        for stroke in strokes {
            _ = engine.handle(.key(stroke, command: false, option: false, control: false))
        }
        try expect(engine.handle(.drop) == nil, "return")
    }

    func urlFixesBeforeSpace() throws {
        let engine = makeEngine(layout: .ru)
        let strokes = try need(map.strokes(for: "https://", layout: .en))
        var plan: ReplacePlan?
        for stroke in strokes {
            if let next = engine.handle(.key(stroke, command: false, option: false, control: false)) {
                plan = next
            }
        }
        try expect(plan?.insert == "https://", "url insert \(plan?.insert ?? "nil") screen-keys")
        try expect(plan?.layout == .en, "url layout")
        try expect(plan?.reason == .url, "url reason \(String(describing: plan?.reason))")
        try expect(plan?.deleteCount == "реезыЖ..".count, "url delete \(plan?.deleteCount ?? -1)")
    }

    func wwwFixesBeforeSpace() throws {
        let engine = makeEngine(layout: .ru)
        let strokes = try need(map.strokes(for: "www.", layout: .en))
        var plan: ReplacePlan?
        for stroke in strokes {
            if let next = engine.handle(.key(stroke, command: false, option: false, control: false)) {
                plan = next
            }
        }
        try expect(plan?.insert == "www.", "www \(plan?.insert ?? "nil")")
        try expect(plan?.reason == .url, "www reason")
    }

    func pathIsNotConverted() throws {
        let engine = makeEngine(layout: .en)
        let slash = try need(map.stroke(for: "/", layout: .en))
        try expect(engine.handle(.key(slash, command: false, option: false, control: false)) == nil, "slash")
        try expect(feed(engine, meant: "привет", meantLayout: .ru, boundary: space) == nil, "path word")
    }

    func undoRemembersTheWord() throws {
        let exceptions = ExceptionList()
        let engine = makeEngine(layout: .en, exceptions: exceptions)
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let strokes = try need(map.strokes(for: "привет", layout: .ru))
        var plan: ReplacePlan?
        for stroke in strokes {
            plan = engine.handle(.key(stroke, command: false, option: false, control: false), now: now) ?? plan
        }
        try expect(plan?.reason == .auto, "auto \(String(describing: plan))")
        try expect(plan?.insert == "привет", "early \(plan?.insert ?? "nil")")
        now = now.addingTimeInterval(0.2)
        _ = engine.handle(.shift(down: true), now: now)
        _ = engine.handle(.shift(down: false), now: now)
        now = now.addingTimeInterval(0.2)
        _ = engine.handle(.shift(down: true), now: now)
        let undo = engine.handle(.shift(down: false), now: now)
        try expect(undo?.reason == .undo, "undo \(String(describing: undo))")
        try expect(undo?.insert == "ghbdtn", "undo text \(undo?.insert ?? "nil")")
        try expect(exceptions.contains("ghbdtn"), "exception")
        var again: ReplacePlan?
        for stroke in strokes {
            again = engine.handle(.key(stroke, command: false, option: false, control: false), now: now.addingTimeInterval(1)) ?? again
        }
        try expect(again == nil, "second time \(String(describing: again))")
    }

    func doubleShiftConvertsTheLastWord() throws {
        let engine = makeEngine(layout: .en)
        try expect(feed(engine, meant: "hello", meantLayout: .en, boundary: space) == nil, "hello stays")
        var now = Date(timeIntervalSince1970: 1_700_000_100)
        _ = engine.handle(.shift(down: true), now: now)
        _ = engine.handle(.shift(down: false), now: now)
        now = now.addingTimeInterval(0.25)
        _ = engine.handle(.shift(down: true), now: now)
        let plan = engine.handle(.shift(down: false), now: now)
        try expect(plan?.reason == .manualWord, "manual \(String(describing: plan))")
        try expect(plan?.layout == .ru, "layout")
        try expect(plan?.insert == "руддщ ", "text \(plan?.insert ?? "nil")")
    }

    func tripleShiftConvertsThePhrase() throws {
        let engine = makeEngine(layout: .en)
        try expect(feed(engine, meant: "hello", meantLayout: .en, boundary: space) == nil, "hello")
        try expect(feed(engine, meant: "world", meantLayout: .en, boundary: space) == nil, "world")
        var now = Date(timeIntervalSince1970: 1_700_000_200)
        var last: ReplacePlan?
        for _ in 0..<3 {
            now = now.addingTimeInterval(0.2)
            _ = engine.handle(.shift(down: true), now: now)
            last = engine.handle(.shift(down: false), now: now) ?? last
        }
        try expect(last?.reason == .manualPhrase, "phrase \(String(describing: last))")
        try expect(last?.insert == "руддщ цщкдв ", "phrase text \(last?.insert ?? "nil")")
        try expect(last?.layout == .ru, "phrase layout")
    }

    func backspaceKeepsTheWordInSync() throws {
        let engine = makeEngine(layout: .en)
        let strokes = try need(map.strokes(for: "hello", layout: .en))
        for stroke in strokes {
            try expect(engine.handle(.key(stroke, command: false, option: false, control: false)) == nil, "letter")
        }
        _ = engine.handle(.backspace)
        try expect(engine.handle(.key(strokes[strokes.count - 1], command: false, option: false, control: false)) == nil, "retype")
        try expect(engine.handle(.key(space, command: false, option: false, control: false)) == nil, "hello stays")
    }

    func commonWordsAreCorrected() throws {
        let russian = ["привет", "спасибо", "хорошо", "сегодня", "работа", "можно", "сейчас", "человек", "время", "слово", "текст"]
        let english = ["hello", "world", "thanks", "please", "computer", "keyboard", "switch", "layout", "because", "something", "another"]
        var hits = 0
        var total = 0
        var misses: [String] = []
        let engineRU = makeEngine(layout: .en)
        for word in russian {
            total += 1
            let text = screen(engineRU, meant: word, meantLayout: .ru, boundary: space)
            if text == word + " " { hits += 1 } else { misses.append("\(word)->\(text)") }
            engineRU.reset()
            _ = engineRU.handle(.systemLayout(.en))
        }
        let engineEN = makeEngine(layout: .ru)
        for word in english {
            total += 1
            let text = screen(engineEN, meant: word, meantLayout: .en, boundary: space)
            if text == word + " " { hits += 1 } else { misses.append("\(word)->\(text)") }
            engineEN.reset()
            _ = engineEN.handle(.systemLayout(.ru))
        }
        try expect(Double(hits) / Double(total) >= 0.96, "\(hits)/\(total) \(misses.joined(separator: ", "))")
    }

    func heldOutRecallAndFalsePositives() throws {
        let directory = try need(Knowledge.bundledDirectory())
        let russian = try lines(directory.appendingPathComponent("ru.txt")).filter { $0.count >= 5 }
        let english = try lines(directory.appendingPathComponent("en.txt")).filter { $0.count >= 5 }
        let heldRU = Array(russian.dropFirst(8000).prefix(200))
        let heldEN = Array(english.dropFirst(8000).prefix(200))
        let knowledge = Knowledge(
            english: bundledSet(directory, "en.txt", "extra_en.txt", held: Set(heldEN)),
            russian: bundledSet(directory, "ru.txt", "extra_ru.txt", held: Set(heldRU))
        )
        let detector = Detector(knowledge: knowledge, exceptions: ExceptionList())

        var ruRecall = 0
        var ruSeen = 0
        var inDict = 0
        var notImpossible = 0
        var altImplausible = 0
        var lowMargin = 0
        for word in heldRU {
            guard let strokes = map.strokes(for: word, layout: .ru) else { continue }
            let wrong = render(strokes, .en)
            let wrongLetters = TextNorm.lookupLetters(wrong)
            ruSeen += 1
            let decided = detector.decide(Observation(currentRaw: wrong, alternateRaw: word, currentLayout: .en)) == .replace(.ru)
            if decided {
                ruRecall += 1
            } else if knowledge.contains(wrongLetters, .en) {
                inDict += 1
            } else if !knowledge.isImpossible(wrongLetters, .en) {
                notImpossible += 1
            } else if !knowledge.isPlausible(word, .ru) {
                altImplausible += 1
            } else {
                lowMargin += 1
            }
            let correct = detector.decide(Observation(currentRaw: word, alternateRaw: wrong, currentLayout: .ru))
            try expect(correct == .keep, "ru false positive \(word)")
        }

        var enRecall = 0
        var enSeen = 0
        for word in heldEN {
            guard let strokes = map.strokes(for: word, layout: .en) else { continue }
            let wrong = render(strokes, .ru)
            enSeen += 1
            if detector.decide(Observation(currentRaw: wrong, alternateRaw: word, currentLayout: .ru)) == .replace(.en) {
                enRecall += 1
            }
            let correct = detector.decide(Observation(currentRaw: word, alternateRaw: wrong, currentLayout: .en))
            try expect(correct == .keep, "en false positive \(word)")
        }

        let ruRate = Double(ruRecall) / Double(max(ruSeen, 1))
        let enRate = Double(enRecall) / Double(max(enSeen, 1))
        try expect(ruRate >= 0.90, "ru recall \(ruRecall)/\(ruSeen) inDict \(inDict) notImpossible \(notImpossible) altImplausible \(altImplausible) margin \(lowMargin)")
        try expect(enRate >= 0.90, "en recall \(enRecall)/\(enSeen)")
    }

    func systemLetterKeysMatchTheReferenceMap() throws {
        let system = SystemLayoutDecoder()
        system.refresh()
        guard system.hasData(for: .ru), system.hasData(for: .en) else { return }
        for code: UInt16 in [0x00, 0x0C, 0x0D, 0x11, 0x1F] {
            let stroke = Stroke(keyCode: code)
            for layout in LayoutID.allCases {
                let live = system.glyph(for: stroke, layout: layout)
                let reference = map.glyph(for: stroke, layout: layout)
                if live?.isLetter == true || reference?.isLetter == true {
                    try expect(live?.character == reference?.character, "\(layout) \(code) \(String(describing: live)) vs \(String(describing: reference))")
                }
            }
        }
    }

    func unfinishedWordSwitchesBeforeSpace() throws {
        let engine = makeEngine(layout: .en)
        let strokes = try need(map.strokes(for: "привет", layout: .ru))
        var plan: ReplacePlan?
        for stroke in strokes.prefix(3) {
            plan = engine.handle(.key(stroke, command: false, option: false, control: false)) ?? plan
        }
        try expect(plan == nil, "ghb is an English word \(String(describing: plan))")
        for stroke in strokes.dropFirst(3) {
            plan = engine.handle(.key(stroke, command: false, option: false, control: false)) ?? plan
        }
        try expect(plan?.insert == "привет", "привет \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .ru, "layout \(String(describing: plan?.layout))")
        let ghost = makeEngine(layout: .en)
        try expect(feed(ghost, meant: "ghost", meantLayout: .en, boundary: nil) == nil, "ghost")
        let partial = makeEngine(layout: .en)
        let gho = try need(map.strokes(for: "gho", layout: .en))
        for stroke in gho {
            try expect(partial.handle(.key(stroke, command: false, option: false, control: false)) == nil, "gho")
        }
    }

    func ghostAndMacStayWhileTyping() throws {
        let engine = makeEngine(layout: .en)
        try expect(feed(engine, meant: "mac", meantLayout: .en, boundary: nil) == nil, "mac")
        try expect(feed(engine, meant: "mac", meantLayout: .en, boundary: space) == nil, "mac space")
    }

    func shortWordsSwitchBeforeSpace() throws {
        let engine = makeEngine(layout: .en)
        let keys = try need(map.strokes(for: "но", layout: .ru))
        var plan: ReplacePlan?
        for stroke in keys {
            plan = engine.handle(.key(stroke, command: false, option: false, control: false)) ?? plan
        }
        try expect(plan?.insert == "но", "но \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .ru, "но layout")
        let spaced = makeEngine(layout: .en)
        let text = screen(spaced, meant: "не", meantLayout: .ru, boundary: space)
        try expect(text == "не ", "не \(text)")
        let own = makeEngine(layout: .en)
        try expect(feed(own, meant: "ok", meantLayout: .en, boundary: space) == nil, "ok")
        let russian = makeEngine(layout: .ru)
        try expect(feed(russian, meant: "мы", meantLayout: .ru, boundary: space) == nil, "мы stays")
        let english = makeEngine(layout: .en)
        try expect(feed(english, meant: "to", meantLayout: .en, boundary: space) == nil, "to stays")
        try expect(feed(english, meant: "a", meantLayout: .en, boundary: space) == nil, "a stays")
        let ty = makeEngine(layout: .en)
        let tyText = screen(ty, meant: "ты", meantLayout: .ru, boundary: space)
        try expect(tyText == "ты ", "ты \(tyText)")
        let my = makeEngine(layout: .en)
        let myText = screen(my, meant: "мы", meantLayout: .ru, boundary: space)
        try expect(myText == "мы ", "мы \(myText)")
        let ya = makeEngine(layout: .en)
        let yaText = screen(ya, meant: "я", meantLayout: .ru, boundary: space)
        try expect(yaText == "я ", "я \(yaText)")
        let article = makeEngine(layout: .ru)
        try expect(screen(article, meant: "a", meantLayout: .en, boundary: space) == "a ", "a from ru")
        let longer = makeEngine(layout: .en)
        try expect(feed(longer, meant: "nsa", meantLayout: .en, boundary: space) == nil, "nsa")
        let disabled = makeEngine(layout: .en)
        disabled.disabledShortWords = ["но"]
        var blocked: ReplacePlan?
        for stroke in keys {
            blocked = disabled.handle(.key(stroke, command: false, option: false, control: false)) ?? blocked
        }
        try expect(blocked == nil, "disabled но \(String(describing: blocked))")
    }

    func selectionDoubleShiftFlipsTheHighlight() throws {
        let flipped = SelectionFlip.flip("ghbdtn, мир", using: map)
        try expect(flipped.text == "привет, vbh", "flip \(flipped.text)")
        try expect(flipped.layout == .ru, "flip layout")
        let engine = makeEngine(layout: .en)
        try expect(feed(engine, meant: "hello", meantLayout: .en, boundary: space) == nil, "hello")
        var now = Date(timeIntervalSince1970: 1_700_000_300)
        _ = engine.handle(.shift(down: true), now: now)
        _ = engine.handle(.shift(down: false), now: now)
        now = now.addingTimeInterval(0.2)
        _ = engine.handle(.shift(down: true), now: now, selection: "ghbdtn, мир")
        let plan = engine.handle(.shift(down: false), now: now, selection: "ghbdtn, мир")
        try expect(plan?.reason == .selection, "selection \(String(describing: plan))")
        try expect(plan?.insert == "привет, vbh", "selection text \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .ru, "selection layout")
        try expect(engine.storedWordCount == 0, "buffer \(engine.storedWordCount)")
        let plain = makeEngine(layout: .en)
        try expect(feed(plain, meant: "hello", meantLayout: .en, boundary: space) == nil, "hello again")
        now = Date(timeIntervalSince1970: 1_700_000_400)
        _ = plain.handle(.shift(down: true), now: now)
        _ = plain.handle(.shift(down: false), now: now)
        now = now.addingTimeInterval(0.2)
        _ = plain.handle(.shift(down: true), now: now)
        let word = plain.handle(.shift(down: false), now: now)
        try expect(word?.reason == .manualWord, "last word \(String(describing: word))")
        try expect(word?.insert == "руддщ ", "last word text \(word?.insert ?? "nil")")
    }

    func bufferStaysBounded() throws {
        let engine = makeEngine(layout: .en)
        for _ in 0..<10_000 {
            _ = feed(engine, meant: "mac", meantLayout: .en, boundary: space)
        }
        try expect(engine.storedWordCount <= 40, "tokens \(engine.storedWordCount)")
    }

    private func makeEngine(layout: LayoutID, exceptions: ExceptionList = ExceptionList()) -> Engine {
        Engine(decoder: map, knowledge: Self.knowledge, exceptions: exceptions, layout: layout)
    }

    @discardableResult
    private func feed(
        _ engine: Engine,
        meant word: String,
        meantLayout: LayoutID,
        boundary: Stroke?,
        now: Date = Date()
    ) -> ReplacePlan? {
        let strokes = map.strokes(for: word, layout: meantLayout)!
        return send(engine, strokes: strokes, boundary: boundary, now: now)
    }

    @discardableResult
    private func feed(
        _ engine: Engine,
        produced word: String,
        boundary: Stroke?,
        now: Date = Date()
    ) -> ReplacePlan? {
        let strokes = map.strokes(for: word, layout: engine.systemLayout)!
        return send(engine, strokes: strokes, boundary: boundary, now: now)
    }

    private func send(_ engine: Engine, strokes: [Stroke], boundary: Stroke?, now: Date) -> ReplacePlan? {
        var plan: ReplacePlan?
        for stroke in strokes {
            if let next = engine.handle(.key(stroke, command: false, option: false, control: false), now: now) {
                plan = next
            }
        }
        if let boundary, let next = engine.handle(.key(boundary, command: false, option: false, control: false), now: now) {
            plan = next
        }
        return plan
    }

    private func screen(
        _ engine: Engine,
        meant word: String,
        meantLayout: LayoutID,
        boundary: Stroke?
    ) -> String {
        let strokes = map.strokes(for: word, layout: meantLayout) ?? []
        let keys = boundary.map { strokes + [$0] } ?? strokes
        var text = ""
        for stroke in keys {
            let before = engine.systemLayout
            text += render([stroke], before)
            if let plan = engine.handle(.key(stroke, command: false, option: false, control: false)) {
                let drop = min(plan.deleteCount, text.count)
                text.removeLast(drop)
                text += plan.insert
            }
        }
        return text
    }

    private func render(_ strokes: [Stroke], _ layout: LayoutID) -> String {
        strokes.map { stroke in
            if stroke.keyCode == KeyCode.space { return " " }
            return map.glyph(for: stroke, layout: layout).map { String($0.character) } ?? ""
        }.joined()
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private func bundledSet(_ directory: URL, _ name: String, _ extra: String, held: Set<String>) -> Set<String> {
        let main = (try? lines(directory.appendingPathComponent(name))) ?? []
        let additions = (try? lines(directory.appendingPathComponent(extra))) ?? []
        return Set(main + additions).subtracting(held)
    }

    private func need<T>(_ value: T?) throws -> T {
        guard let value else { throw Failed("missing value") }
        return value
    }
}
