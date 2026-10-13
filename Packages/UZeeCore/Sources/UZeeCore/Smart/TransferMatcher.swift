import Foundation

/// Money moved between your own accounts shows on both statements: "Funds transfer to NayaPay" out of HBL and
/// "Incoming fund transfer from … HBL" into NayaPay. Imported one statement at a time, they became spending in one
/// account and income in the other, so October's spending was mostly "Other" (BUG-022). This pairs them so they
/// can be saved as one transfer that is neither spending nor income.
public enum TransferMatcher {
    public struct Entry: Equatable, Sendable {
        public var id: UUID
        public var accountID: UUID
        public var date: LocalDate
        /// Signed: below zero left the account, above zero came in.
        public var amount: Money
        /// Payee and statement text.
        public var text: String

        public init(id: UUID, accountID: UUID, date: LocalDate, amount: Money, text: String) {
            self.id = id
            self.accountID = accountID
            self.date = date
            self.amount = amount
            self.text = text
        }
    }

    public struct Pair: Equatable, Sendable {
        public var out: Entry
        public var into: Entry
        /// Both sides name you or the other account. False when only one does: shown, but left unticked.
        public var isSure: Bool
    }

    /// Days apart the two sides may be. On the owner's statements 34 of 42 landed the same day and none more than 2 apart.
    public static let maxDays = 2

    /// What banks and wallets print for each other: "MEZ" for Meezan, "HABB" for HBL, "TMFB" for Easypaisa.
    static let bankAliases: [String: [String]] = [
        "meezan": ["meezan", "mez", "mebl"],
        "hbl": ["hbl", "habb"],
        "nayapay": ["nayapay", "naya"],
        "easypaisa": ["easypaisa", "tmfb", "telenor"],
        "sadapay": ["sadapay", "sada"],
        "jazzcash": ["jazzcash", "jazz", "mobilink"],
        "mcb": ["mcb", "muco"],
        "ubl": ["ubl", "unil"],
        "alfalah": ["alfalah", "alfh"],
        "wise": ["wise", "transferwise"],
    ]

    /// Words every transfer row has, so they never count as your name.
    static let commonWords: Set<String> = [
        "transfer", "transfers", "trf", "ibft", "raast", "p2p", "funds", "fund", "incoming", "outgoing", "inward",
        "outward", "from", "to", "the", "and", "for", "via", "sent", "send", "received", "receive", "money", "payment",
        "paid", "pay", "account", "acc", "acct", "a/c", "bank", "ltd", "limited", "mobile", "wallet", "app", "online",
        "top", "up", "topup", "load", "deposit", "own", "self", "ref", "reference", "txn", "transaction", "id", "no",
        "pk", "pak", "pakistan", "cash", "in", "out", "by", "of", "on", "at", "mr", "mrs", "ms", "fee", "charges",
        "debit", "credit", "card", "instant", "branch", "number", "iban", "title", "pkr", "usd", "rs",
    ]

    /// Every outgoing entry paired with an incoming one in another account: the same amount and currency, at most
    /// `maxDays` apart, no ATM withdrawal, and at least one side naming you or the other account. Each entry is used
    /// once; sure pairs and close dates win.
    public static func pairs(_ entries: [Entry], accountNames: [UUID: String], ownerWords: [String]) -> [Pair] {
        let owner = ownerWords.map(NameKey.make).filter { $0.count >= 3 }
        var options: [(score: Int, gap: Int, pair: Pair)] = []
        for (out, into) in candidates(entries) {
            let gap = abs(out.date.days(to: into.date))
            let outProof = namesOwner(out.text, owner) || namesAccount(out.text, accountNames[into.accountID])
            let inProof = namesOwner(into.text, owner) || namesAccount(into.text, accountNames[out.accountID])
            guard outProof || inProof else { continue }
            let sure = outProof && inProof
            options.append((sure ? 0 : 1, gap, Pair(out: out, into: into, isSure: sure)))
        }
        var used = Set<UUID>()
        var result: [Pair] = []
        for option in options.sorted(by: { ($0.score, $0.gap, $0.pair.out.date) < ($1.score, $1.gap, $1.pair.out.date) }) {
            guard !used.contains(option.pair.out.id), !used.contains(option.pair.into.id) else { continue }
            used.insert(option.pair.out.id)
            used.insert(option.pair.into.id)
            result.append(option.pair)
        }
        return result.sorted { $0.out.date < $1.out.date }
    }

    /// Your name, learned from the rows: a name you send money to yourself under shows on both sides of the
    /// transfer ("to A KHAN" out of one account, "from A KHAN" into the other), while someone else's name shows on
    /// one side only. Words seen on both sides of at least two candidate pairs, most frequent first.
    public static func likelyOwnerWords(_ entries: [Entry], accountNames: [UUID: String]) -> [String] {
        let bankWords = Set(bankAliases.values.flatMap { $0 } + accountNames.values.flatMap { words(NameKey.make($0)) })
        var counts: [String: Int] = [:]
        for (out, into) in candidates(entries) {
            let outWords = Set(words(NameKey.make(out.text)))
            let inWords = words(NameKey.make(into.text))
            var seen = Set<String>()
            for word in inWords where word.count >= 3 && !commonWords.contains(word) && !bankWords.contains(word)
                && word.allSatisfy(\.isLetter) && outWords.contains(where: { sameWord($0, word) }) && seen.insert(word).inserted {
                counts[word, default: 0] += 1
            }
        }
        return counts.filter { $0.value >= 2 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Same amount and currency, opposite directions, different accounts, close dates, neither an ATM withdrawal.
    static func candidates(_ entries: [Entry]) -> [(Entry, Entry)] {
        let usable = entries.filter { !$0.amount.isZero && !isATM($0.text) }
        let outs = usable.filter { $0.amount.isNegative }
        let ins = usable.filter { !$0.amount.isNegative }
        var result: [(Entry, Entry)] = []
        for out in outs {
            for into in ins where into.accountID != out.accountID && into.amount.currency == out.amount.currency
                && into.amount.minorUnits == -out.amount.minorUnits && abs(out.date.days(to: into.date)) <= maxDays {
                result.append((out, into))
            }
        }
        return result
    }

    static func isATM(_ text: String) -> Bool {
        words(NameKey.make(text)).contains("atm")
    }

    /// "Raast P2P to A KHAN": your name, allowing one letter's difference and cut-off words. With two or more
    /// name words known, two must match, so a shared first name alone isn't enough.
    static func namesOwner(_ text: String, _ owner: [String]) -> Bool {
        guard !owner.isEmpty else { return false }
        let found = words(NameKey.make(text))
        let hits = owner.filter { name in found.contains { sameWord($0, name) } }.count
        return hits >= min(2, owner.count)
    }

    /// "Funds transfer to NAYAPAY 03xx" in the HBL row: the other account's bank or wallet, by any of its aliases.
    static func namesAccount(_ text: String, _ accountName: String?) -> Bool {
        guard let accountName else { return false }
        let found = Set(words(NameKey.make(text)))
        let nameWords = words(NameKey.make(accountName))
        for (bank, aliases) in bankAliases where nameWords.contains(bank) || nameWords.contains(where: { aliases.contains($0) }) {
            if aliases.contains(where: { found.contains($0) }) { return true }
        }
        // An account named after something else ("Salary account"): its first distinctive word.
        if let first = nameWords.first(where: { $0.count >= 4 && !commonWords.contains($0) }) { return found.contains(first) }
        return false
    }

    /// Lowercased letters-and-digits words: "A/C#123-KHAN" → ["a", "c", "123", "khan"].
    static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// "khan" = "khan"; "mohammad" ≈ "muhammad" (one letter off, five or more letters); "muhamm" ≈ "muhammad" (cut off at four or more).
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        if short.count >= 4, long.hasPrefix(short) { return true }
        guard short.count >= 5, long.count - short.count <= 1 else { return false }
        return editDistance(Array(a), Array(b)) <= 1
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
