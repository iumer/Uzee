import Foundation

/// "Recurring mobile bill of Rs 1,900 on the 20th of every month", "Add 5,779 as yearly fees of golden debit card":
/// a bill, subscription or income that repeats (owner, 2026-10-15). Voice had saved the first as a one-off expense
/// and the second as monthly.
public enum RecurringPhrase {
    public struct Request: Equatable, Sendable {
        public var name: String
        public var amount: SpokenAmount
        public var unit: RecurrenceUnit
        public var interval: Int
        /// The next time it's due.
        public var next: LocalDate
        /// Said with a day ("on the 20th"); otherwise `next` is one period from today.
        public var daySaid: Bool
        public var type: RecurringType
        public var category: String?
        public var account: String?
    }

    /// How often, from the words said; nil when the sentence doesn't say it repeats.
    static func frequency(_ t: String) -> (unit: RecurrenceUnit, interval: Int)? {
        let table: [([String], RecurrenceUnit, Int)] = [
            ([" every 6 months ", " every six months ", " half yearly ", " half-yearly ", " twice a year ", " biannual"], .month, 6),
            ([" every 3 months ", " every three months ", " quarterly ", " every quarter "], .month, 3),
            ([" every 2 months ", " every two months ", " every other month "], .month, 2),
            ([" every 2 weeks ", " every two weeks ", " fortnightly ", " biweekly ", " every other week "], .week, 2),
            ([" yearly ", " annual ", " annually ", " every year ", " each year ", " per year ", " a year ", " per annum "], .year, 1),
            ([" weekly ", " every week ", " each week ", " per week ", " a week "], .week, 1),
            ([" monthly ", " every month ", " each month ", " per month ", " a month ", " of every month ", " of each month "], .month, 1)
        ]
        for (words, unit, interval) in table where words.contains(where: { t.contains($0) }) { return (unit, interval) }
        if [" recurring ", " recurrent ", " repeating ", " repeats ", " subscription "].contains(where: { t.contains($0) }) { return (.month, 1) }
        return nil
    }

    public static func request(_ sentence: String, vocabulary: VoiceVocabulary, today: LocalDate) -> Request? {
        // "rupees5779" → "rupees 5779"
        let spaced = sentence.replacingOccurrences(of: #"([A-Za-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        let t = " " + VoiceRuleParser.normalise(spaced) + " "
        guard !VoiceRuleParser.isQuestion(t, original: sentence), !t.hasPrefix(" remind me"),
              let (unit, interval) = frequency(t) else { return nil }
        // "Spent 2,000 on groceries this month" isn't a repeat: "a month"/"this month" alone needs a bill-like word.
        let strong = [" recurring ", " recurrent ", " repeating ", " repeats ", " every ", " each ", " monthly ", " yearly ",
                      " weekly ", " annual", " quarterly ", " subscription ", " per month ", " per year ", " fortnightly "]
        guard strong.contains(where: { t.contains($0) }) else { return nil }
        guard let amount = AmountPhrase.find(in: spaced.replacingOccurrences(of: #"\b\d{1,2}(st|nd|rd|th)\b"#, with: " ",
                                                                              options: .regularExpression)) else { return nil }
        let day = dayOfMonth(t)
        let next: LocalDate
        if let day, unit == .month || unit == .year {
            var month = today.firstOfMonth
            if day < today.day { month = month.addingMonths(1) }
            next = LocalDate(year: month.year, month: month.month, day: min(day, month.daysInMonth))
        } else if let date = ReminderPhrase.date(spaced, today: today), date >= today, !t.contains(" next month ") || day != nil {
            next = date
        } else {
            next = RecurrenceRule(unit: unit, interval: interval, anchor: today).date(at: 1) ?? today
        }
        let isIncome = [" salary ", " income ", " rent from ", " i get ", " i receive ", " receive ", " payout ", " earn"]
            .contains { t.contains($0) }
        let type: RecurringType
        if isIncome { type = t.contains(" salary ") ? .salary : .income }
        else if t.contains(" subscription ") || CategorySuggester.systemKey(inText: [t]).map({ ["streaming", "software"].contains($0) }) == true {
            type = .subscription
        } else if t.contains(" rent ") { type = .rent }
        else if t.contains(" insurance ") { type = .insurance }
        else if [" installment ", " instalment ", " emi "].contains(where: { t.contains($0) }) { type = .installment }
        else if [" kameti ", " committee "].contains(where: { t.contains($0) }) { type = .kameti }
        else { type = .bill }
        let accounts = VoiceRuleParser.findAccounts(t, vocabulary: vocabulary)
        let category = VoiceRuleParser.guessCategory(t, said: VoiceRuleParser.longestMatch(vocabulary.categories, in: t, allowPlural: true),
                                                     action: isIncome ? .income : .expense, vocabulary: vocabulary)
        return Request(name: name(spaced, accounts: accounts.map(\.name)), amount: amount, unit: unit, interval: interval, next: next,
                       daySaid: day != nil, type: type, category: category, account: accounts.first?.name)
    }

    /// "on the 20th", "20th of every month", "on 5".
    static func dayOfMonth(_ t: String) -> Int? {
        let words = t.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() {
            let digits = word.prefix { $0.isNumber }
            guard let day = Int(digits), (1...31).contains(day) else { continue }
            let suffix = String(word.dropFirst(digits.count))
            if ["st", "nd", "rd", "th"].contains(suffix) { return day }
            if suffix.isEmpty, index > 0, ["on", "the"].contains(words[index - 1]),
               index + 1 >= words.count || ["of", "every", "each"].contains(words[index + 1]) { return day }
        }
        return nil
    }

    /// What it's for, from the words left after taking out amounts, how often and filler:
    /// "Recurring mobile bill of Rs 1900 on 20th of every month" → "Mobile bill";
    /// "Add rupees 5779 as yearly recurring fees of golden debit card" → "Golden debit card fees".
    static func name(_ sentence: String, accounts: [String]) -> String {
        let filler: Set<String> = [
            "add", "please", "set", "up", "make", "create", "save", "a", "an", "the", "my", "i", "have", "pay", "paid", "is", "it",
            "as", "of", "on", "for", "to", "from", "in", "at", "and", "with", "every", "each", "per", "recurring", "recurrent",
            "repeating", "repeats", "monthly", "yearly", "weekly", "annual", "annually", "quarterly", "fortnightly", "biweekly",
            "month", "months", "year", "years", "week", "weeks", "day", "rs", "pkr", "rupees", "rupee", "usd", "dollars",
            "dollar", "thousand", "lakh", "hundred", "k", "uzee", "hey", "ok", "okay", "this", "that", "which", "comes", "due",
            "half", "quarter", "other", "two", "three", "six", "twice", "next", "starting", "start", "from", "account", "bank",
            "debited", "charged", "deducted", "get", "receive", "will", "be", "should", "need", "want", "wanna", "me", "new",
            "payment", "payments", "subscription", "expense", "transaction", "entry"
        ]
        let accountWords = Set(accounts.flatMap { VoiceRuleParser.normalise($0).split(separator: " ").map(String.init) })
        let words = sentence.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        var kept: [String] = []
        for word in words {
            let lower = VoiceRuleParser.normalise(word)
            if lower.isEmpty || filler.contains(lower) || accountWords.contains(lower) || lower.first?.isNumber == true
                || lower.hasPrefix("$") || TextScan.monthWords[lower] != nil { continue }
            kept.append(lower)
        }
        // "fees of golden debit card" reads better as "golden debit card fees".
        if let first = kept.first, ["fee", "fees", "bill", "charges", "charge"].contains(first), kept.count > 1 {
            kept = Array(kept.dropFirst()) + [first]
        }
        let name = kept.prefix(5).joined(separator: " ")
        guard !name.isEmpty else { return "Recurring payment" }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "every month", "every year", "every 3 months".
    public static func describe(_ unit: RecurrenceUnit, _ interval: Int) -> String {
        let noun = switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
        return interval == 1 ? "every \(noun)" : "every \(interval) \(noun)s"
    }
}
