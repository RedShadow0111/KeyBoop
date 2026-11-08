import Foundation

public struct ReplacePlan: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case auto
        case url
        case manualWord
        case manualPhrase
        case undo
    }

    public var deleteCount: Int
    public var insert: String
    public var layout: LayoutID
    public var reason: Reason

    public init(deleteCount: Int, insert: String, layout: LayoutID, reason: Reason) {
        self.deleteCount = deleteCount
        self.insert = insert
        self.layout = layout
        self.reason = reason
    }
}

public enum Input: Equatable, Sendable {
    case key(Stroke, command: Bool, option: Bool, control: Bool)
    case shift(down: Bool)
    case backspace
    case drop
    case noop
    case systemLayout(LayoutID)
}

public final class Engine: @unchecked Sendable {
    private let lock = NSLock()
    private let decoder: any LayoutDecoding
    private let detector: Detector
    private let exceptions: ExceptionList

    public var gesturesEnabled = true
    public private(set) var systemLayout: LayoutID

    private var open: [Stroke] = []
    private var openLayout: LayoutID
    private var tokens: [Token] = []
    private var contextBlock = false
    private var lastAuto: LastAuto?
    private var cleanShiftUps: [Date] = []
    private var shiftHeld = false
    private var shiftDirty = false
    private var pendingGestureTarget: LayoutID?

    public init(decoder: any LayoutDecoding, knowledge: Knowledge, exceptions: ExceptionList, layout: LayoutID) {
        self.decoder = decoder
        self.detector = Detector(knowledge: knowledge, exceptions: exceptions)
        self.exceptions = exceptions
        self.systemLayout = layout
        self.openLayout = layout
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        clearBuffer()
    }

    public func handle(_ input: Input, now: Date = Date()) -> ReplacePlan? {
        lock.lock()
        defer { lock.unlock() }
        switch input {
        case .noop:
            return nil
        case .systemLayout(let layout):
            if layout != systemLayout {
                clearBuffer()
                systemLayout = layout
                openLayout = layout
            }
            return nil
        case .drop:
            if shiftHeld { shiftDirty = true }
            clearBuffer()
            return nil
        case .backspace:
            if shiftHeld { shiftDirty = true }
            applyBackspace()
            return nil
        case .shift(let down):
            return shiftGesture(down: down, now: now)
        case .key(let stroke, let command, let option, let control):
            if command || option || control {
                if shiftHeld { shiftDirty = true }
                clearBuffer()
                return nil
            }
            if shiftHeld { shiftDirty = true }
            return strokeIn(stroke, now: now)
        }
    }

    private func clearBuffer() {
        open.removeAll(keepingCapacity: true)
        tokens.removeAll(keepingCapacity: true)
        contextBlock = false
        lastAuto = nil
        pendingGestureTarget = nil
        cleanShiftUps.removeAll()
    }

    private func strokeIn(_ stroke: Stroke, now: Date) -> ReplacePlan? {
        if isWordCharacter(stroke) || isDigit(stroke) || isURLContinuation(stroke) {
            if open.isEmpty { openLayout = systemLayout }
            open.append(stroke)
            return urlReplacement(now: now)
        }
        if stroke.keyCode == KeyCode.space || isPunctuation(stroke) {
            return closeWord(with: stroke, now: now)
        }
        clearBuffer()
        return nil
    }

    private func urlReplacement(now: Date) -> ReplacePlan? {
        let current = render(open, openLayout)
        let alternate = render(open, openLayout.opposite)
        guard Self.isURL(alternate), !Self.isURL(current) else { return nil }
        if exceptions.contains(current) || exceptions.contains(alternate) { return nil }
        return commit(
            strokes: open,
            trailing: [],
            from: openLayout,
            to: openLayout.opposite,
            reason: .url,
            now: now
        )
    }

    private func closeWord(with boundary: Stroke, now: Date) -> ReplacePlan? {
        let boundaryText = piece(boundary, systemLayout) + piece(boundary, systemLayout.opposite)
        let separator = boundaryText.contains("/") || boundaryText.contains("\\") || boundaryText.contains("@")
        var plan: ReplacePlan?
        if !open.isEmpty {
            let from = openLayout
            if !separator && !contextBlock {
                let observation = Observation(
                    currentRaw: render(open, from),
                    alternateRaw: render(open, from.opposite),
                    currentLayout: from,
                    previousLayout: tokens.last?.display,
                    blockedByContext: false
                )
                if case .replace(let target) = detector.decide(observation) {
                    plan = commit(strokes: open, trailing: [boundary], from: from, to: target, reason: .auto, now: now)
                }
            }
            if plan == nil {
                tokens.append(Token(strokes: open, display: openLayout, trailing: [boundary]))
                open.removeAll(keepingCapacity: true)
                trim()
            }
        } else if !tokens.isEmpty {
            tokens[tokens.count - 1].trailing.append(boundary)
        }
        if boundary.keyCode == KeyCode.space {
            contextBlock = false
        } else if separator {
            contextBlock = true
        }
        return plan
    }

    private func commit(
        strokes: [Stroke],
        trailing: [Stroke],
        from: LayoutID,
        to: LayoutID,
        reason: ReplacePlan.Reason,
        now: Date
    ) -> ReplacePlan? {
        let old = render(strokes, from) + render(trailing, from)
        let new = render(strokes, to) + render(trailing, to)
        guard old != new else {
            tokens.append(Token(strokes: strokes, display: from, trailing: trailing))
            open.removeAll(keepingCapacity: true)
            trim()
            return nil
        }
        tokens.append(Token(strokes: strokes, display: to, trailing: trailing))
        open.removeAll(keepingCapacity: true)
        if reason == .auto || reason == .url {
            lastAuto = LastAuto(
                at: now,
                index: tokens.count - 1,
                originalLayout: from,
                originalLetters: TextNorm.lookupLetters(render(strokes, from))
            )
        }
        systemLayout = to
        openLayout = to
        trim()
        return ReplacePlan(deleteCount: old.count, insert: new, layout: to, reason: reason)
    }

    private func shiftGesture(down: Bool, now: Date) -> ReplacePlan? {
        if down {
            shiftHeld = true
            shiftDirty = false
            return nil
        }
        let dirty = shiftDirty
        shiftHeld = false
        shiftDirty = false
        if dirty || !gesturesEnabled { return nil }
        cleanShiftUps.removeAll { now.timeIntervalSince($0) > 0.7 }
        cleanShiftUps.append(now)
        if cleanShiftUps.count >= 3 {
            cleanShiftUps.removeAll()
            let target = pendingGestureTarget ?? systemLayout.opposite
            return convertPhrase(to: target)
        }
        if cleanShiftUps.count == 2 {
            return convertLastWord(now: now)
        }
        return nil
    }

    private func convertLastWord(now: Date) -> ReplacePlan? {
        if !open.isEmpty {
            let target = openLayout.opposite
            pendingGestureTarget = target
            lastAuto = nil
            return retargetOpen(to: target, reason: .manualWord)
        }
        guard let index = tokens.indices.last, !tokens[index].strokes.isEmpty else { return nil }
        let target = tokens[index].display.opposite
        pendingGestureTarget = target
        var reason: ReplacePlan.Reason = .manualWord
        if let auto = lastAuto,
           auto.index == index,
           now.timeIntervalSince(auto.at) <= 3,
           target == auto.originalLayout
        {
            reason = .undo
            exceptions.insert(auto.originalLetters)
            lastAuto = nil
        } else {
            lastAuto = nil
        }
        return retargetToken(at: index, to: target, reason: reason)
    }

    private func convertPhrase(to target: LayoutID) -> ReplacePlan? {
        let old = screen()
        guard !old.isEmpty else { return nil }
        for index in tokens.indices {
            tokens[index].display = target
        }
        if !open.isEmpty {
            openLayout = target
        }
        let new = screen()
        systemLayout = target
        openLayout = open.isEmpty ? target : openLayout
        lastAuto = nil
        pendingGestureTarget = nil
        guard old != new else { return nil }
        return ReplacePlan(deleteCount: old.count, insert: new, layout: target, reason: .manualPhrase)
    }

    private func retargetOpen(to target: LayoutID, reason: ReplacePlan.Reason) -> ReplacePlan? {
        let old = render(open, openLayout)
        let new = render(open, target)
        openLayout = target
        systemLayout = target
        guard old != new else { return nil }
        return ReplacePlan(deleteCount: old.count, insert: new, layout: target, reason: reason)
    }

    private func retargetToken(at index: Int, to target: LayoutID, reason: ReplacePlan.Reason) -> ReplacePlan? {
        let old = render(tokens[index])
        tokens[index].display = target
        let new = render(tokens[index])
        systemLayout = target
        guard old != new else { return nil }
        return ReplacePlan(deleteCount: old.count, insert: new, layout: target, reason: reason)
    }

    private func applyBackspace() {
        if !open.isEmpty {
            open.removeLast()
            return
        }
        guard var token = tokens.popLast() else { return }
        if !token.trailing.isEmpty {
            token.trailing.removeLast()
            if token.strokes.isEmpty && token.trailing.isEmpty { return }
            if !token.trailing.isEmpty {
                tokens.append(token)
                return
            }
            open = token.strokes
            openLayout = token.display
            systemLayout = token.display
            return
        }
        guard !token.strokes.isEmpty else { return }
        token.strokes.removeLast()
        guard !token.strokes.isEmpty else { return }
        open = token.strokes
        openLayout = token.display
        systemLayout = token.display
    }

    private func trim() {
        while tokens.count > 40 {
            tokens.removeFirst()
            if var auto = lastAuto {
                if auto.index == 0 {
                    lastAuto = nil
                } else {
                    auto.index -= 1
                    lastAuto = auto
                }
            }
        }
    }

    private func screen() -> String {
        tokens.map(render).joined() + (open.isEmpty ? "" : render(open, openLayout))
    }

    private func render(_ token: Token) -> String {
        render(token.strokes, token.display) + render(token.trailing, token.display)
    }

    private func render(_ strokes: [Stroke], _ layout: LayoutID) -> String {
        var text = ""
        for stroke in strokes {
            text.append(piece(stroke, layout))
        }
        return text
    }

    private func piece(_ stroke: Stroke, _ layout: LayoutID) -> String {
        if stroke.keyCode == KeyCode.space { return " " }
        guard let glyph = decoder.glyph(for: stroke, layout: layout) else { return "" }
        return String(glyph.character)
    }

    private func isWordCharacter(_ stroke: Stroke) -> Bool {
        for layout in LayoutID.allCases {
            if decoder.glyph(for: stroke, layout: layout)?.isLetter == true { return true }
        }
        return false
    }

    private func isDigit(_ stroke: Stroke) -> Bool {
        for layout in LayoutID.allCases {
            if decoder.glyph(for: stroke, layout: layout)?.isDigit == true { return true }
        }
        return false
    }

    private func isURLContinuation(_ stroke: Stroke) -> Bool {
        guard isPunctuation(stroke) else { return false }
        let layout = open.isEmpty ? systemLayout : openLayout
        let alternate = render(open + [stroke], layout.opposite)
        return Self.extendsURL(alternate)
    }

    static func extendsURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        for pattern in ["https://", "http://", "ftp://", "www."] {
            if lower.hasPrefix(pattern) || pattern.hasPrefix(lower) { return true }
        }
        return false
    }

    private func isPunctuation(_ stroke: Stroke) -> Bool {
        var sawGlyph = false
        for layout in LayoutID.allCases {
            guard let glyph = decoder.glyph(for: stroke, layout: layout) else { continue }
            sawGlyph = true
            if glyph.isLetter || glyph.isDigit { return false }
        }
        return sawGlyph
    }

    static func isURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("https://")
            || lower.hasPrefix("http://")
            || lower.hasPrefix("ftp://")
            || lower.hasPrefix("www.")
    }
}

private struct Token: Equatable {
    var strokes: [Stroke]
    var display: LayoutID
    var trailing: [Stroke]
}

private struct LastAuto {
    var at: Date
    var index: Int
    var originalLayout: LayoutID
    var originalLetters: String
}
