import Foundation

public final class ExceptionList: @unchecked Sendable {
    private let lock = NSLock()
    private var words: Set<String>
    private var order: [String]
    public var onChange: (@Sendable (Set<String>) -> Void)?

    public convenience init(_ words: Set<String> = []) {
        self.init(ordered: Array(words))
    }

    public init(ordered: [String]) {
        var unique: [String] = []
        var seen = Set<String>()
        for word in ordered {
            let key = TextNorm.lookupLetters(word)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            unique.append(key)
        }
        self.words = seen
        self.order = unique
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
        if inserted {
            order.append(key)
        }
        let snapshot = words
        lock.unlock()
        if inserted {
            onChange?(snapshot)
        }
    }

    public func remove(_ word: String) {
        let key = TextNorm.lookupLetters(word)
        guard !key.isEmpty else { return }
        lock.lock()
        let removed = words.remove(key) != nil
        if removed {
            order.removeAll { $0 == key }
        }
        let snapshot = words
        lock.unlock()
        if removed {
            onChange?(snapshot)
        }
    }

    public func removeAll() {
        lock.lock()
        words.removeAll()
        order.removeAll()
        lock.unlock()
        onChange?([])
    }

    public var recent: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(order.suffix(50).reversed())
    }

    public var ordered: [String] {
        lock.lock()
        defer { lock.unlock() }
        return order
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
