import Foundation

/// Finds payments in an imported statement that repeat every month (OWN-024): the same payee, a similar amount,
/// around the same day, in at least two months in a row. Each one is offered as a bill, subscription or income
/// for the calendar, with a reminder.
public enum RecurringFinder {
    public struct Payment: Hashable, Sendable {
        public var date: LocalDate
        public var payee: String
        /// Positive; `isMoneyIn` gives the direction.
        public var amount: Money
        public var isMoneyIn: Bool
        public var categoryID: UUID?
        public var accountID: UUID?

        public init(date: LocalDate, payee: String, amount: Money, isMoneyIn: Bool, categoryID: UUID? = nil, accountID: UUID? = nil) {
            self.accountID = accountID
            self.date = date
            self.payee = payee
            self.amount = amount
            self.isMoneyIn = isMoneyIn
            self.categoryID = categoryID
        }
    }

    public struct Found: Hashable, Sendable, Identifiable {
        /// Payee key plus direction, stable across rebuilds.
        public var id: String
        public var name: String
        public var type: RecurringType
        /// The latest amount.
        public var amount: Money
        /// True when the amounts differed (a utility bill, say).
        public var varies: Bool
        public var day: Int
        public var months: Int
        public var firstDate: LocalDate
        public var lastDate: LocalDate
        /// The next time it should come, on or after `today`.
        public var nextDate: LocalDate
        public var isMoneyIn: Bool
        public var categoryID: UUID?
        /// The account the latest payment came from.
        public var accountID: UUID?
    }

    /// Payments a day apart at most this much (around the month end too) still count as "the same day".
    static let dayTolerance = 5
    /// Largest ÷ smallest amount, in percent, that still counts as "a similar amount".
    static let amountTolerancePercent: Int64 = 150

    /// Monthly repeats in `payments`, biggest first. Payees in `existingNames` (bills you already have) are skipped.
    public static func find(_ payments: [Payment], existingNames: [String] = [], today: LocalDate) -> [Found] {
        let existing = Set(existingNames.map(key).filter { !$0.isEmpty })
        let groups = Dictionary(grouping: payments.filter { $0.amount.minorUnits > 0 }) { payment in
            "\(payment.isMoneyIn ? "in" : "out"):\(key(payment.payee))"
        }
        var found: [Found] = []
        for (id, group) in groups {
            let payeeKey = key(group.first?.payee ?? "")
            guard !payeeKey.isEmpty, !existing.contains(payeeKey),
                  let currency = group.first?.amount.currency, group.allSatisfy({ $0.amount.currency == currency }) else { continue }
            // The same payment seen twice (already in UZee and in this statement, a day or two apart) counts once.
            var sorted: [Payment] = []
            for payment in group.sorted(by: { $0.date < $1.date }) {
                if let kept = sorted.last, kept.amount == payment.amount, kept.date.days(to: payment.date) <= 3 { continue }
                sorted.append(payment)
            }
            // A known subscription (Netflix, Spotify…) seen once recently is still worth offering.
            if sorted.count == 1, let only = sorted.first, !only.isMoneyIn,
               isKnownSubscription(only.payee), only.date.days(to: today) <= 45 {
                let next = RecurrenceRule.nextMonthly(day: only.date.day, onOrAfter: max(today, only.date.addingDays(1)))
                found.append(Found(id: id, name: displayName(only.payee), type: .subscription, amount: only.amount, varies: false,
                                   day: only.date.day, months: 1, firstDate: only.date, lastDate: only.date, nextDate: next,
                                   isMoneyIn: false, categoryID: only.categoryID, accountID: only.accountID))
                continue
            }
            // One payment per month: two in the same month isn't a monthly bill.
            let months = sorted.map { $0.date.year * 12 + $0.date.month }
            guard Set(months).count == months.count, months.count >= 2 else { continue }
            // Every month in a row, allowing one missed month.
            let gaps = zip(months, months.dropFirst()).map { $1 - $0 }
            guard gaps.allSatisfy({ $0 >= 1 && $0 <= 2 }), gaps.filter({ $0 == 2 }).count <= 1, gaps.contains(1) else { continue }
            // Around the same day of the month.
            let days = sorted.map(\.date.day)
            let reference = sorted.last!.date.day
            guard days.allSatisfy({ dayDistance($0, reference) <= dayTolerance }) else { continue }
            // A similar amount.
            let amounts = sorted.map(\.amount.minorUnits)
            guard let low = amounts.min(), let high = amounts.max(), low > 0,
                  high.multipliedReportingOverflow(by: 100).partialValue <= low.multipliedReportingOverflow(by: amountTolerancePercent).partialValue
            else { continue }
            let last = sorted.last!
            let day = typicalDay(days)
            let next = RecurrenceRule.nextMonthly(day: day, onOrAfter: max(today, last.date.addingDays(1)))
            found.append(Found(id: id, name: displayName(last.payee), type: suggestedType(last.payee, isMoneyIn: last.isMoneyIn),
                               amount: last.amount, varies: low != high, day: day, months: months.count,
                               firstDate: sorted.first!.date, lastDate: last.date, nextDate: next,
                               isMoneyIn: last.isMoneyIn, categoryID: last.categoryID, accountID: last.accountID))
        }
        return found.sorted {
            $0.amount.minorUnits != $1.amount.minorUnits ? $0.amount.minorUnits > $1.amount.minorUnits : $0.name < $1.name
        }
    }

    /// The payee without reference numbers or punctuation, first three words: "NETFLIX.COM 8812" → "netflix com".
    static func key(_ payee: String) -> String {
        let folded = payee.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let words = folded.split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 }
        return words.prefix(3).joined(separator: " ")
    }

    /// Distance between two days of the month, counting across the month end (30th and 2nd are 3 apart).
    static func dayDistance(_ a: Int, _ b: Int) -> Int {
        let straight = abs(a - b)
        return min(straight, 31 - straight)
    }

    /// The day most payments came on (the latest one on a tie).
    static func typicalDay(_ days: [Int]) -> Int {
        let counts = Dictionary(days.map { ($0, 1) }, uniquingKeysWith: +)
        let best = counts.values.max() ?? 1
        return days.last { counts[$0] == best } ?? days.last ?? 1
    }

    /// "NETFLIX.COM 8812" → "Netflix.com".
    public static func displayName(_ payee: String) -> String {
        let words = payee.split(whereSeparator: \.isWhitespace).filter { word in !word.contains { $0.isNumber } }
        let text = (words.isEmpty ? payee.split(whereSeparator: \.isWhitespace) : words).prefix(4).joined(separator: " ")
        let isShouting = text == text.uppercased()
        return isShouting ? text.lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") : text
    }

    static let subscriptionWords = ["netflix", "spotify", "youtube", "apple", "icloud", "google", "prime", "amazon", "openai",
                                    "chatgpt", "adobe", "microsoft", "disney", "canva", "dropbox", "notion", "github", "shahid",
                                    "anghami", "linkedin", "duolingo", "patreon", "claude", "anthropic", "hbo", "hulu"]
    static let utilityWords = ["electric", "lesco", "iesco", "mepco", "fesco", "gepco", "pesco", "hesco", "sngpl", "ssgc", "gas",
                               "water", "ptcl", "internet", "broadband", "nayatel", "stormfiber", "fiber", "wifi",
                               "zong", "telenor", "ufone"]

    /// Services that only ever bill monthly, so one sighting is enough to offer them (not shops like Amazon or Apple).
    static let knownSubscriptions = ["netflix", "spotify", "youtube premium", "icloud", "openai", "chatgpt", "adobe", "disney",
                                     "canva", "dropbox", "notion", "github", "shahid", "anghami", "linkedin", "duolingo", "patreon",
                                     "anthropic", "hbo", "hulu", "google one", "apple music", "apple tv", "amazon prime",
                                     "prime video", "tamasha", "starzplay"]

    static func words(_ payee: String) -> String {
        " " + payee.lowercased().split { !$0.isLetter }.joined(separator: " ") + " "
    }

    static func isKnownSubscription(_ payee: String) -> Bool {
        let text = words(payee)
        return knownSubscriptions.contains { text.contains(" \($0)") }
    }

    public static func suggestedType(_ payee: String, isMoneyIn: Bool) -> RecurringType {
        // Words from their start, so "parent" isn't rent.
        let text = words(payee)
        func has(_ list: [String]) -> Bool { list.contains { text.contains(" \($0)") } }
        if isMoneyIn { return has(["salary", "payroll", "wages"]) ? .salary : .income }
        if has(["rent"]) { return .rent }
        if has(["insurance", "takaful", "jubilee", "efu", "adamjee"]) { return .insurance }
        if has(subscriptionWords) { return .subscription }
        if has(utilityWords) { return .utility }
        if has(["gym", "club", "membership"]) { return .membership }
        return .bill
    }
}
