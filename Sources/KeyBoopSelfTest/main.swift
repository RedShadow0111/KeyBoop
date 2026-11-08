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
    }

    func wrongEnglishBecomesRussianOnSpace() throws {
        let engine = makeEngine(layout: .en)
        let plan = feed(engine, meant: "привет", meantLayout: .ru, boundary: space)
        try expect(plan?.insert == "привет ", "insert \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .ru, "layout")
        try expect(plan?.reason == .auto, "reason \(String(describing: plan?.reason))")
        try expect(plan?.deleteCount == "ghbdtn ".count, "delete \(plan?.deleteCount ?? -1)")
    }

    func wrongRussianBecomesEnglishOnSpace() throws {
        let engine = makeEngine(layout: .ru)
        let plan = feed(engine, meant: "hello", meantLayout: .en, boundary: space)
        try expect(plan?.insert == "hello ", "insert \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .en, "layout")
        try expect(plan?.reason == .auto, "reason")
        try expect(plan?.deleteCount == "руддщ ".count, "delete")
    }

    func capitalizationIsPreserved() throws {
        let engine = makeEngine(layout: .en)
        let plan = feed(engine, meant: "Привет", meantLayout: .ru, boundary: space)
        try expect(plan?.insert == "Привет ", "insert \(plan?.insert ?? "nil")")
        try expect(plan?.layout == .ru, "layout")
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
            try expect(engine.handle(.key(stroke, command: false, option: false, control: false)) == nil, "letter")
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
        let plan = feed(engine, meant: "привет", meantLayout: .ru, boundary: space, now: now)
        try expect(plan?.reason == .auto, "auto")
        now = now.addingTimeInterval(0.2)
        _ = engine.handle(.shift(down: true), now: now)
        _ = engine.handle(.shift(down: false), now: now)
        now = now.addingTimeInterval(0.2)
        _ = engine.handle(.shift(down: true), now: now)
        let undo = engine.handle(.shift(down: false), now: now)
        try expect(undo?.reason == .undo, "undo \(String(describing: undo))")
        try expect(undo?.insert == "ghbdtn ", "undo text \(undo?.insert ?? "nil")")
        try expect(exceptions.contains("ghbdtn"), "exception")
        let again = feed(engine, meant: "привет", meantLayout: .ru, boundary: space, now: now.addingTimeInterval(1))
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
        let strokes = try need(map.strokes(for: "привет", layout: .ru))
        for stroke in strokes {
            try expect(engine.handle(.key(stroke, command: false, option: false, control: false)) == nil, "letter")
        }
        _ = engine.handle(.backspace)
        try expect(engine.handle(.key(strokes[strokes.count - 1], command: false, option: false, control: false)) == nil, "retype")
        let plan = engine.handle(.key(space, command: false, option: false, control: false))
        try expect(plan?.insert == "привет ", "backspace sync \(plan?.insert ?? "nil")")
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
            let plan = feed(engineRU, meant: word, meantLayout: .ru, boundary: space)
            if plan?.insert == word + " " { hits += 1 } else { misses.append("\(word)->\(plan?.insert ?? "nil")") }
            engineRU.reset()
            _ = engineRU.handle(.systemLayout(.en))
        }
        let engineEN = makeEngine(layout: .ru)
        for word in english {
            total += 1
            let plan = feed(engineEN, meant: word, meantLayout: .en, boundary: space)
            if plan?.insert == word + " " { hits += 1 } else { misses.append("\(word)->\(plan?.insert ?? "nil")") }
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
