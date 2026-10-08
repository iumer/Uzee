import Foundation

/// What a spoken or typed request asks for (VOX-03, VOX-04).
public enum VoiceAction: String, Sendable, CaseIterable, Codable {
    case expense, income, transfer, lend, borrow, repaidToMe, repaidByMe, question, unknown

    public var isLoan: Bool { [.lend, .borrow, .repaidToMe, .repaidByMe].contains(self) }
}

public enum VoicePeriod: String, Sendable, CaseIterable, Codable {
    case today, thisWeek, thisMonth, lastMonth

    public var name: String {
        switch self {
        case .today: "today"
        case .thisWeek: "this week"
        case .thisMonth: "this month"
        case .lastMonth: "last month"
        }
    }
}

/// Questions answered from local data (VOX-03), with the same numbers as the screens.
public enum VoiceQuestion: Equatable, Sendable {
    /// "How much do I owe my mother?" (nil person = everyone).
    case iOwe(person: String?)
    /// "How much does Usama owe me?"
    case owesMe(person: String?)
    case budgetLeft
    case spent(category: String?, period: VoicePeriod)
    case nextBill
    case subscriptions
    case balance(account: String?)
    case dueBeforeSalary
    case upcoming
}

/// A request understood from one sentence. Names are as matched against the user's own people,
/// accounts and categories when possible; anything else stays as said so the card can offer to create it.
public struct VoiceCommand: Equatable, Sendable {
    public var action: VoiceAction
    public var amount: SpokenAmount?
    public var person: String?
    public var account: String?
    public var toAccount: String?
    public var category: String?
    public var payee: String?
    public var date: LocalDate?
    public var question: VoiceQuestion?

    public init(action: VoiceAction, amount: SpokenAmount? = nil, person: String? = nil, account: String? = nil,
                toAccount: String? = nil, category: String? = nil, payee: String? = nil, date: LocalDate? = nil,
                question: VoiceQuestion? = nil) {
        self.action = action
        self.amount = amount
        self.person = person
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.payee = payee
        self.date = date
        self.question = question
    }
}

/// The user's own names, so "Meezan", "Ammi" or "Groceries" are recognised (VOX-06).
public struct VoiceVocabulary: Sendable {
    public var people: [String]
    public var accounts: [String]
    public var categories: [String]

    public init(people: [String] = [], accounts: [String] = [], categories: [String] = []) {
        self.people = people
        self.accounts = accounts
        self.categories = categories
    }
}

/// Rule-based understanding of English money sentences. It runs on every device and is the fallback
/// when Apple's on-device model is unavailable (VOX-08), so the common sentences never depend on the model.
public enum VoiceRuleParser {
    static let questionStarts = ["how much", "how many", "what", "whats", "when", "which", "do i", "does", "did i", "is ", "am i",
                                 "tell me", "show me", "who ", "where", "can i", "hows", "how is", "have i", "are there", "any ", "anything",
                                 "is there", "do we", "whos", "list "]
    static let stopWords: Set<String> = [
        "i", "me", "my", "a", "an", "the", "to", "from", "for", "on", "at", "in", "of", "it", "them", "him", "her", "they", "he",
        "she", "back", "friend", "cash", "account", "bank", "card", "today", "yesterday", "rs", "pkr", "usd", "dollars", "rupees",
        "and", "later", "will", "some", "someone", "somebody", "money", "loan", "this", "that", "month", "week", "last",
        "paid", "pay", "sent", "gave", "lent", "borrowed", "returned", "received", "got", "spent", "bought", "salary", "please",
        "uzee", "hey", "ok", "okay", "so", "just", "also", "then", "k", "lakh", "thousand", "hundred", "with", "by", "into",
        "who", "what", "whats", "how", "when", "which", "where", "why", "is", "are", "do", "does", "did", "hello", "hi"
    ]
    static let aliases: [[String]] = [
        ["mother", "mom", "mum", "mommy", "ammi", "amma", "ammy", "maa", "mama"],
        ["father", "dad", "daddy", "abbu", "abba", "baba", "papa", "abu"],
        ["brother", "bhai", "bro", "bhaiya"],
        ["sister", "sis", "baji", "apa", "behen"],
        ["wife", "begum"],
        ["husband"]
    ]

    public static func parse(_ text: String, vocabulary: VoiceVocabulary, today: LocalDate) -> VoiceCommand {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = " " + normalise(original) + " "
        let amount = AmountPhrase.find(in: original)
        let person = findPerson(original, t, vocabulary: vocabulary)
        let accounts = findAccounts(t, vocabulary: vocabulary)
        let category = longestMatch(vocabulary.categories, in: t, allowPlural: true)
        let date = findDate(t, original: original, today: today)

        if isQuestion(t, original: original) {
            var question = classifyQuestion(t, person: person, account: accounts.first?.name, category: category)
            // "How much did I spend on food?": keep the word, so the answer is about food or says it can't find it,
            // never the whole month's spending as if it were food.
            if case .spent(nil, let period)? = question, let range = t.range(of: " on ") {
                let word = t[range.upperBound...].split(separator: " ").first.map(String.init) ?? ""
                if !word.isEmpty, !["this", "last", "the", "today", "my", "it", "average"].contains(word) {
                    question = .spent(category: word, period: period)
                }
            }
            return VoiceCommand(action: question == nil ? .unknown : .question, person: person, account: accounts.first?.name,
                                category: category, question: question)
        }

        let action = classifyAction(t, amount: amount, accounts: accounts)
        var command = VoiceCommand(action: action, amount: amount, date: date)
        switch action {
        case .transfer:
            let ordered = orderTransfer(accounts, in: t)
            command.account = ordered.from
            command.toAccount = ordered.to
        case .lend, .borrow, .repaidToMe, .repaidByMe:
            command.person = person
            command.account = accounts.first?.name
        case .expense, .income:
            command.account = accounts.first?.name
            command.category = category
            command.person = vocabulary.people.contains(where: { $0 == person }) ? person : nil
            command.payee = findPayee(original, t, action: action, exclude: [person, category] + accounts.map { $0.name as String? })
                ?? (command.person == nil ? person : nil)
        case .question, .unknown:
            break
        }
        return command
    }

    /// One of `names` as said by the user or the on-device model ("hbl" → "HBL", "my mother" → "Ammi").
    public static func resolve(_ said: String?, among names: [String]) -> String? {
        guard let said, !said.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let t = " " + normalise(said) + " "
        if let match = longestMatch(names, in: t, allowPlural: true) { return match }
        for group in aliases where group.contains(where: { t.contains(" " + $0 + " ") }) {
            if let name = names.first(where: { group.contains(normalise($0)) }) { return name }
        }
        return nil
    }

    // MARK: Text

    /// Lowercase words separated by single spaces, punctuation removed except inside numbers and "'".
    static func normalise(_ text: String) -> String {
        // Typed on iOS, "that’s" has a curly apostrophe; "Tea & snacks" is said "tea and snacks".
        let text = text.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "&", with: " and ")
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        let chars = Array(folded)
        for (index, c) in chars.enumerated() {
            if c.isLetter || c.isNumber || c == "'" || c == "$" {
                result.append(c)
            } else if (c == "." || c == ","), index > 0, index + 1 < chars.count, chars[index - 1].isNumber, chars[index + 1].isNumber {
                result.append(c)
            } else {
                result.append(" ")
            }
        }
        let spaced = result.split(separator: " ").joined(separator: " ").replacingOccurrences(of: "'ll", with: " will")
            .replacingOccurrences(of: "what's", with: "whats").replacingOccurrences(of: "how's", with: "hows")
        // "Usama's" → "usama"
        return (spaced + " ").replacingOccurrences(of: "'s ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func has(_ t: String, _ phrases: [String]) -> Bool {
        phrases.contains { t.contains($0) }
    }

    /// The longest of `names` said as whole words. With `allowPlural`, "grocery" also matches "Groceries".
    static func longestMatch(_ names: [String], in t: String, allowPlural: Bool = false) -> String? {
        var best: String?
        for name in names {
            let key = normalise(name)
            guard !key.isEmpty else { continue }
            var forms = [key]
            if allowPlural {
                if key.hasSuffix("ies") { forms.append(String(key.dropLast(3)) + "y") }
                else if key.hasSuffix("s") { forms.append(String(key.dropLast())) }
                else { forms.append(key + "s") }
            }
            if forms.contains(where: { t.contains(" " + $0 + " ") }), name.count > (best?.count ?? 0) { best = name }
        }
        return best
    }

    // MARK: People

    static func findPerson(_ original: String, _ t: String, vocabulary: VoiceVocabulary) -> String? {
        if let known = longestMatch(vocabulary.people, in: t) { return known }
        for group in aliases where group.contains(where: { t.contains(" " + $0 + " ") }) {
            if let person = vocabulary.people.first(where: { group.contains(normalise($0)) }) { return person }
            if let person = vocabulary.people.first(where: { name in group.contains { normalise(name).contains($0) } }) { return person }
        }
        // A new name: a capitalised word after "to", "from", "lent", "with", or before "paid me", "owes".
        let words = original.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        let lower = words.map { $0.lowercased() }
        func after(_ index: Int) -> Bool {
            index + 1 < lower.count && ["paid", "returned", "gave", "owes", "sent", "lent", "repaid", "has"].contains(lower[index + 1])
        }
        func isName(_ index: Int) -> Bool {
            guard index >= 0, index < words.count, let first = words[index].first, first.isUppercase, first.isLetter else { return false }
            let word = lower[index]
            // Speech capitalises the first word of every sentence.
            if index == 0 && !after(index) { return false }
            return !stopWords.contains(word) && TextScan.monthWords[word] == nil
                && !vocabulary.accounts.contains { normalise($0) == word }
                && !vocabulary.categories.contains { normalise($0) == word }
        }
        for (index, word) in lower.enumerated() {
            if ["to", "from", "lent", "lend", "with", "owe", "borrowed", "paid", "repaid", "returned", "gave"].contains(word) {
                var next = index + 1
                if next < lower.count, ["my", "the"].contains(lower[next]) { next += 1 }
                if isName(next) { return name(at: next, words, lower) }
            }
            if after(index), isName(index) { return name(at: index, words, lower) }
        }
        return nil
    }

    /// One or two capitalised words: "Usama", "Ali Khan".
    private static func name(at index: Int, _ words: [String], _ lower: [String]) -> String {
        var parts = [words[index]]
        if index + 1 < words.count, let first = words[index + 1].first, first.isUppercase, !stopWords.contains(lower[index + 1]),
           TextScan.monthWords[lower[index + 1]] == nil {
            parts.append(words[index + 1])
        }
        return parts.joined(separator: " ")
    }

    // MARK: Accounts

    static func findAccounts(_ t: String, vocabulary: VoiceVocabulary) -> [(name: String, position: Int)] {
        var found: [(name: String, position: Int)] = []
        // Longest names first so "HBL card" wins over "HBL".
        for name in vocabulary.accounts.sorted(by: { $0.count > $1.count }) {
            let key = " " + normalise(name) + " "
            guard key.count > 2, let range = t.range(of: key) else { continue }
            let position = t.distance(from: t.startIndex, to: range.lowerBound)
            if found.contains(where: { abs($0.position - position) < max(key.count, 3) }) { continue }
            found.append((name, position))
        }
        return found.sorted { $0.position < $1.position }
    }

    static func orderTransfer(_ accounts: [(name: String, position: Int)], in t: String) -> (from: String?, to: String?) {
        var from: String?
        var to: String?
        for account in accounts {
            let before = t.prefix(account.position).split(separator: " ").suffix(2).map(String.init)
            if before.contains("from") || before.contains("out") { from = from ?? account.name }
            else if before.contains("to") || before.contains("into") || before.contains("in") { to = to ?? account.name }
        }
        let rest = accounts.map(\.name).filter { $0 != from && $0 != to }
        if from == nil, let first = rest.first { from = first }
        if to == nil, let other = rest.first(where: { $0 != from }) { to = other }
        return (from, to)
    }

    // MARK: Payee, date

    static func findPayee(_ original: String, _ t: String, action: VoiceAction, exclude: [String?]) -> String? {
        let words = original.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: .punctuationCharacters) }
        let lower = words.map { $0.lowercased() }
        let excluded = Set(exclude.compactMap { $0 }.flatMap { normalise($0).split(separator: " ").map(String.init) })
        let markers = action == .income ? ["from"] : ["at", "to", "for", "on", "from"]
        for (index, word) in lower.enumerated() where markers.contains(word) {
            var parts: [String] = []
            var next = index + 1
            while next < words.count, parts.count < 3 {
                let candidate = lower[next]
                if candidate.isEmpty || stopWords.contains(candidate) || excluded.contains(candidate)
                    || candidate.first?.isNumber == true || TextScan.monthWords[candidate] != nil { break }
                parts.append(words[next])
                next += 1
            }
            if !parts.isEmpty {
                return ReceiptParser.tidy(parts.joined(separator: " ").prefix(1).uppercased() + parts.joined(separator: " ").dropFirst())
            }
        }
        return nil
    }

    static func findDate(_ t: String, original: String, today: LocalDate) -> LocalDate? {
        if t.contains(" day before yesterday ") { return today.addingDays(-2) }
        if t.contains(" yesterday ") { return today.addingDays(-1) }
        if t.contains(" today ") { return today }
        // "last Friday", "on Monday": the most recent one before today.
        for (index, name) in ReminderPhrase.weekdays.enumerated() where t.contains(" " + name + " ") {
            let back = (today.weekday - (index + 1) + 7) % 7
            return today.addingDays(-(back == 0 ? 7 : back))
        }
        if let found = TextScan.dates(in: original, defaultYear: today.year).first?.date {
            return found > today ? LocalDate(year: found.year - 1, month: found.month, day: found.day) : found
        }
        // "on the 5th"
        let words = t.split(separator: " ").map(String.init)
        for (index, word) in words.enumerated() where index > 0 && ["on", "the"].contains(words[index - 1]) {
            let digits = word.prefix { $0.isNumber }
            let suffix = word.dropFirst(digits.count)
            guard let day = Int(digits), ["st", "nd", "rd", "th"].contains(String(suffix)), (1...31).contains(day) else { continue }
            var month = today.firstOfMonth
            if day > today.day { month = month.addingMonths(-1) }
            return LocalDate(year: month.year, month: month.month, day: min(day, month.daysInMonth))
        }
        return nil
    }

    // MARK: Classification

    static func isQuestion(_ t: String, original: String) -> Bool {
        let start = String(t.dropFirst())
        if questionStarts.contains(where: { start.hasPrefix($0) }) { return true }
        if original.hasSuffix("?") { return true }
        return false
    }

    static func classifyQuestion(_ t: String, person: String?, account: String?, category: String?) -> VoiceQuestion? {
        if t.contains(" owe") {
            if has(t, [" owe me ", " owes me ", " owe us ", " owed to me ", " owe me?"]) || t.contains("who owes") { return .owesMe(person: person) }
            return .iOwe(person: person)
        }
        if has(t, [" pay me back ", " paid me back "]) { return .owesMe(person: person) }
        if t.contains(" budget") { return .budgetLeft }
        if t.contains(" subscription") { return .subscriptions }
        if t.contains(" salary"), has(t, [" before ", " until ", " till ", " due ", " bills "]) { return .dueBeforeSalary }
        if t.contains(" next "), has(t, [" bill", " payment", " due", " pay ", " installment", " renewal"]) { return .nextBill }
        if has(t, [" upcoming ", " bills ", " due ", " what do i have to pay ", " what's due "]) { return .upcoming }
        if has(t, [" balance", " how much money", " how much do i have", " have in ", " left in ", " in my "]) || account != nil {
            if !has(t, [" spend", " spent", " spending"]) { return .balance(account: account) }
        }
        if has(t, [" spend", " spent", " spending", " expense", " expenses", " cost "]) {
            let period: VoicePeriod
            if t.contains(" today ") { period = .today }
            else if t.contains(" this week ") || t.contains(" week ") { period = .thisWeek }
            else if t.contains(" last month ") { period = .lastMonth }
            else { period = .thisMonth }
            return .spent(category: category, period: period)
        }
        return nil
    }

    static func classifyAction(_ t: String, amount: SpokenAmount?, accounts: [(name: String, position: Int)]) -> VoiceAction {
        let iSaid = has(t, [" i paid", " i gave", " i returned", " i sent", " i repaid", " i have paid", " i have returned"])
        if t.contains(" back ") || has(t, [" returned ", " repaid ", " return "]) {
            if iSaid && has(t, [" back ", " returned ", " repaid "]) { return .repaidByMe }
            // "Returned 1,000 to Sara", "paid Bilal back": I paid someone back.
            if has(t, [" returned ", " repaid ", " paid back ", " gave back "]), t.contains(" to "), !has(t, [" to me ", " me back "]) {
                return .repaidByMe
            }
            if has(t, [" paid me", " gave me", " returned ", " repaid ", " got ", " received ", " sent me", " back from "])
                && !has(t, [" will return", " will give it back", " will pay me back", " will pay back", " return it later"]) {
                return .repaidToMe
            }
        }
        if has(t, [" borrowed from me", " will pay me back", " will return it", " will return the", " they will return", " he will return",
                   " she will return", " will give it back", " will give back", " pay me back", " return it later", " lent", " lend ",
                   " loaned", " gave a loan", " gave him a loan", " gave her a loan", " as a loan", " as loan"]) {
            if has(t, [" i will return", " i will pay", " i will give it back", " i need to return", " i have to return"]) { return .borrow }
            if has(t, [" lent me", " loaned me"]) { return .borrow }
            return .lend
        }
        // "I took 2k from my mother" (a person, not an account) is borrowing.
        if t.contains(" took "), t.contains(" from "), accounts.isEmpty, !has(t, [" took out ", " withdrew"]) { return .borrow }
        if has(t, [" borrowed", " took a loan", " loan from", " i will return", " i will pay it back", " i will pay back",
                   " i need to return", " i have to return", " gave me a loan", " lent me", " loaned me"]) {
            return .borrow
        }
        if has(t, [" transfer", " moved ", " move ", " withdrew", " withdraw"]) || (accounts.count >= 2 && t.contains(" from ") && t.contains(" to ")) {
            return .transfer
        }
        // "Ali sent me 5,000" is money in; "Paid maid salary", "Got a haircut for 800" are money out.
        if has(t, [" sent me", " gave me", " paid me", " got paid", " transferred me"]) { return .income }
        if has(t, [" spent", " paid ", " i paid", " bought", " purchase", " paid for "]) { return .expense }
        if has(t, [" got a ", " got an ", " got some ", " got new "]),
           !has(t, [" salary", " bonus", " payment", " refund", " gift", " cashback", " profit", " commission", " raise"]) {
            return .expense
        }
        if has(t, [" received", " got paid", " salary", " income", " earned", " credited", " deposit", " got ", " freelance", " bonus"]) {
            return .income
        }
        if has(t, [" spent", " paid", " pay ", " bought", " buy ", " purchase", " cost", " bill", " sent", " gave", " for ", " on ", " at "]) {
            return .expense
        }
        return amount == nil ? .unknown : .expense
    }
}

/// Follow-up questions for missing details (VOX-05) and applying the answer.
public enum VoiceDialog {
    public enum Need: Equatable, Sendable {
        case person, amount, fromAccount, toAccount
    }

    public static func need(_ command: VoiceCommand) -> Need? {
        switch command.action {
        case .question, .unknown: return nil
        case .lend, .borrow, .repaidToMe, .repaidByMe:
            if command.person == nil { return .person }
        case .transfer:
            if command.amount == nil { return .amount }
            if command.account == nil { return .fromAccount }
            if command.toAccount == nil { return .toAccount }
            return nil
        case .expense, .income:
            break
        }
        return command.amount == nil ? .amount : nil
    }

    public static func prompt(_ need: Need, for command: VoiceCommand) -> String {
        switch need {
        case .person:
            switch command.action {
            case .borrow: "Who did you borrow it from?"
            case .repaidToMe: "Who paid you back?"
            case .repaidByMe: "Who did you pay back?"
            default: "Who did you lend it to?"
            }
        case .amount: command.action == .income ? "How much did you get?" : "How much was it?"
        case .fromAccount: "Which account did the money come from?"
        case .toAccount: "Which account did the money go to?"
        }
    }

    public static func apply(_ answer: String, to command: VoiceCommand, need: Need, vocabulary: VoiceVocabulary) -> VoiceCommand {
        var command = command
        let t = " " + VoiceRuleParser.normalise(answer) + " "
        switch need {
        case .person:
            if let known = VoiceRuleParser.findPerson(answer, t, vocabulary: vocabulary) {
                command.person = known
            } else {
                let filler: Set<String> = ["it", "its", "it's", "was", "is", "to", "my", "friend", "his", "her", "name", "the", "from", "i", "lent", "him"]
                let words = answer.split(whereSeparator: { $0.isWhitespace }).map { $0.trimmingCharacters(in: .punctuationCharacters) }
                    .filter { !$0.isEmpty && !filler.contains($0.lowercased()) }
                let name = words.prefix(2).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                command.person = name.isEmpty ? nil : name
            }
        case .amount:
            command.amount = AmountPhrase.find(in: answer)
        case .fromAccount:
            command.account = VoiceRuleParser.longestMatch(vocabulary.accounts, in: t)
        case .toAccount:
            command.toAccount = VoiceRuleParser.longestMatch(vocabulary.accounts, in: t)
        }
        return command
    }
}
