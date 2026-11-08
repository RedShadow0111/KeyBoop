import Foundation

public final class ExceptionList: @unchecked Sendable {
    private let lock = NSLock()
    private var words: Set<String>
    public var onChange: (@Sendable (Set<String>) -> Void)?

    public init(_ words: Set<String> = []) {
        self.words = Set(words.map { TextNorm.lookupLetters($0) }.filter { !$0.isEmpty })
    }

    public func contains(_ word: String) -> Bool {
        let key = TextNorm.lookupLetters(word)
        guard !key.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return words.contains(key)
    }

    public func insert(_ word: String) {
        let key = TextNorm.lookupLetters(word)
        guard !key.isEmpty else { return }
        lock.lock()
        let inserted = words.insert(key).inserted
        let snapshot = words
        lock.unlock()
        if inserted {
            onChange?(snapshot)
        }
    }

    public func removeAll() {
        lock.lock()
        words.removeAll()
        lock.unlock()
        onChange?([])
    }

    public var all: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return words
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return words.count
    }
}
