import Foundation

/// A spoken amount: "20k", "1.5 lakh", "$20", "Rs 5,000", "two thousand five hundred" (VOX-04).
public struct SpokenAmount: Equatable, Sendable {
    /// Major units.
    public var value: Decimal
    /// Said or written explicitly ("dollars", "$", "rupees", "PKR"); nil means the account's currency.
    public var currency: Currency?

    public init(value: Decimal, currency: Currency? = nil) {
        self.value = value
        self.currency = currency
    }
}

/// Deterministic amount parsing for voice (M9): the language model never decides a number on its own.
public enum AmountPhrase {
    static let units: [String: Decimal] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "a": 1, "an": 1
    ]
    /// Urdu numbers, counted only before a scale word ("do sau", "paanch hazaar") since "do" is also English.
    static let urduUnits: [String: Decimal] = [
        "ek": 1, "do": 2, "teen": 3, "char": 4, "chaar": 4, "paanch": 5, "panch": 5, "chay": 6, "chhe": 6, "saat": 7,
        "aath": 8, "nau": 9, "das": 10, "bees": 20, "tees": 30, "chalees": 40, "pachas": 50, "pachaas": 50
    ]
    static let hundredWords: Set<String> = ["hundred", "hundreds", "sau"]
    static let scales: [String: Decimal] = [
        "k": 1_000, "thousand": 1_000, "thousands": 1_000, "grand": 1_000, "hazaar": 1_000, "hazar": 1_000, "hajar": 1_000,
        "lakh": 100_000, "lakhs": 100_000, "lac": 100_000, "lacs": 100_000, "lack": 100_000, "lakh's": 100_000,
        "million": 1_000_000, "millions": 1_000_000, "m": 1_000_000, "mn": 1_000_000,
        "crore": 10_000_000, "crores": 10_000_000, "cr": 10_000_000
    ]
    static let pkrWords: Set<String> = ["rs", "rs.", "rupees", "rupee", "pkr", "rupay", "rupaiya"]
    static let usdWords: Set<String> = ["$", "usd", "dollars", "dollar", "bucks"]
    static let monthNames = Set(TextScan.monthWords.keys)

    /// The amount in a sentence. Prefers one with a currency or a scale word ("20k") over a bare number,
    /// and ignores day numbers next to a month ("5 October") or ordinals ("5th").
    public static func find(in text: String) -> SpokenAmount? {
        let words = tokenize(text)
        var candidates: [(amount: SpokenAmount, strong: Bool, before: String)] = []
        var i = 0
        while i < words.count {
            guard let found = read(words, at: i) else { i += 1; continue }
            candidates.append((found.0, found.1, i > 0 ? words[i - 1] : ""))
            i = found.2
        }
        if let strong = candidates.first(where: { $0.strong }) { return strong.amount }
        // Bare numbers: "Bought 2 pizzas for 1,500" means 1,500. Prefer the one after a money word, else the largest.
        if let led = candidates.first(where: { ["paid", "spent", "spend", "cost", "costs", "of", "was", "is", "for", "pay", "lent",
                                                 "borrowed", "received", "got", "sent", "gave", "transfer", "transferred"].contains($0.before) }) {
            return led.amount
        }
        return candidates.max { $0.amount.value < $1.amount.value }?.amount
    }

    /// Lowercased words with "$20" → "$", "20" and "20k" → "20", "k".
    static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        for raw in text.lowercased().split(whereSeparator: { $0.isWhitespace }) {
            var word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "?!,;:\"'()"))
            if word.hasSuffix(".") && word != "rs." { word.removeLast() }
            if word.hasPrefix("$") { words.append("$"); word.removeFirst() }
            if word.hasPrefix("rs."), word.count > 3 { words.append("rs"); word.removeFirst(3) }
            else if word.hasPrefix("rs"), word.count > 2, word.dropFirst(2).first?.isNumber == true { words.append("rs"); word.removeFirst(2) }
            guard !word.isEmpty else { continue }
            // "5/10" and "5:30" are dates and times, never amounts.
            if word.contains(where: \.isNumber), word.contains("/") || word.contains(":") || (word.contains("-") && word.first?.isNumber == true) {
                words.append("_"); continue
            }
            // Split a number from a unit glued to it: "20k", "1.5lakh", "500rs".
            if let first = word.first, first.isNumber {
                let number = word.prefix { $0.isNumber || $0 == "." || $0 == "," }
                let rest = word.dropFirst(number.count)
                words.append(String(number))
                if !rest.isEmpty { words.append(String(rest)) }
            } else {
                words.append(word)
            }
        }
        return words
    }

    private static func numeric(_ word: String) -> Decimal? {
        let cleaned = word.replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isNumber || $0 == "." }), cleaned.filter({ $0 == "." }).count <= 1,
              cleaned != "." else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func read(_ words: [String], at start: Int) -> (SpokenAmount, Bool, Int)? {
        var i = start
        var currency: Currency?
        if i < words.count, pkrWords.contains(words[i]) { currency = .pkr; i += 1 }
        else if i < words.count, usdWords.contains(words[i]) { currency = .usd; i += 1 }
        let numberStart = i
        var total: Decimal = 0
        var current: Decimal = 0
        var sawNumber = false
        var sawScale = false
        var lastWasNumber = false
        while i < words.count {
            let word = words[i]
            if let value = numeric(word) {
                if lastWasNumber { break }
                current += value; sawNumber = true; lastWasNumber = true
            } else if let value = units[word] {
                // "a"/"an" only count before a scale word: "a thousand", "an hundred".
                if value == 1, word.count <= 2 {
                    guard i + 1 < words.count, scales[words[i + 1]] != nil || words[i + 1] == "hundred" else { break }
                }
                if lastWasNumber, current.isMultipleOfTen == false || value >= 10 { break }
                current += value; sawNumber = true; lastWasNumber = true
            } else if let value = urduUnits[word], !lastWasNumber, i + 1 < words.count,
                      scales[words[i + 1]] != nil || hundredWords.contains(words[i + 1]) {
                current += value; sawNumber = true; lastWasNumber = true
            } else if hundredWords.contains(word), sawNumber {
                current = (current == 0 ? 1 : current) * 100; lastWasNumber = false
            } else if let scale = scales[word], sawNumber {
                // "cr" after a number is crore only in speech; statements say "CR" for credit, handled elsewhere.
                total += (current == 0 ? 1 : current) * scale
                current = 0; sawScale = true; lastWasNumber = false
            } else if word == "and", sawNumber, i + 1 < words.count, units[words[i + 1]] != nil || numeric(words[i + 1]) != nil {
                lastWasNumber = false
            } else if word == "point", sawNumber, i + 1 < words.count, let digit = units[words[i + 1]], digit < 10 {
                // "two point two five" = 2.25
                var place: Decimal = 1
                while i + 1 < words.count, let digit = units[words[i + 1]], digit < 10, words[i + 1].count > 2 {
                    place /= 10; current += digit * place; i += 1
                }
                lastWasNumber = true
            } else {
                break
            }
            i += 1
        }
        guard sawNumber, i > numberStart else { return nil }
        let value = total + current
        guard value > 0 else { return nil }
        // Trailing currency word: "500 rupees", "20 dollars".
        if i < words.count, currency == nil {
            if pkrWords.contains(words[i]) { currency = .pkr; i += 1 }
            else if usdWords.contains(words[i]) { currency = .usd; i += 1 }
        }
        // "5 October", "October 5", "5th": a day, not an amount.
        let next = i < words.count ? words[i] : ""
        let previous = numberStart > 0 ? words[numberStart - 1] : ""
        if currency == nil, !sawScale {
            if monthNames.contains(next) || monthNames.contains(previous) || ["st", "nd", "rd", "th"].contains(next) { return nil }
            if ["am", "pm", "o'clock", "days", "day", "months", "month", "weeks", "week", "years", "people", "times"].contains(next) { return nil }
        }
        return (SpokenAmount(value: value, currency: currency), currency != nil || sawScale, i)
    }
}

private extension Decimal {
    /// 20, 30 … 90: a tens word that a units word can follow ("twenty five").
    var isMultipleOfTen: Bool {
        var copy = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &copy, -1, .plain)
        return rounded == self && self >= 20 && self < 100
    }
}
