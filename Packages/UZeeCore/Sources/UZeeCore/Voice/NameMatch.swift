import Foundation

/// Finds the person a misheard name most likely meant, so a near miss isn't added to People as someone new
/// (owner, 2026-10-16).
public enum NameMatch {
    /// The one item whose name is close to `spoken`; nil when none is, or when several are.
    public static func closest<Item>(to spoken: String, among items: [Item], name: (Item) -> String) -> Item? {
        let matches = items.filter { isClose(spoken, name($0)) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Up to one edit apart for names of four letters or fewer, up to two for longer ones; compares name keys.
    public static func isClose(_ spoken: String, _ known: String) -> Bool {
        let a = NameKey.make(spoken), b = NameKey.make(known)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return distance(a, b) <= (max(a.count, b.count) <= 4 ? 1 : 2)
    }

    /// Levenshtein distance: insertions, deletions and substitutions, one character each.
    public static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// Words for the speech recogniser to listen out for, people first; categories are dropped first when there are
/// too many (owner, 2026-10-16).
public enum VoiceHints {
    public static func make(people: [String], accounts: [String], extra: [String], categories: [String], cap: Int = 100) -> [String] {
        var seen = Set<String>()
        let unique = (people + accounts + extra + categories).filter { word in
            let key = NameKey.make(word)
            return !key.isEmpty && seen.insert(key).inserted
        }
        return Array(unique.prefix(max(cap, 0)))
    }
}
