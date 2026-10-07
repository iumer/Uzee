import Foundation

/// Finds amounts and dates in text read from receipts, statements and speech (AI-02, IMP-01, VOX-04).
/// Deterministic and exact: amounts are `Decimal` major units, never floating point.
public enum TextScan {
    /// An amount found in text, e.g. "Rs 1,250.00", "(500)" or "2,000.00 CR".
    public struct FoundAmount: Equatable, Sendable {
        /// Major units, never negative; see `isNegative`.
        public var value: Decimal
        /// Character offsets of the number in the scanned text (start inclusive, end exclusive).
        public var start: Int
        public var end: Int
        public var hasDecimals: Bool
        public var hasGrouping: Bool
        /// Written as "-500" or "(500)".
        public var isNegative: Bool
        /// "rs", "pkr", "usd" or "$" before the number.
        public var currencyMarker: String?
        /// "cr" or "dr" right after the number.
        public var creditDebit: String?

        /// Looks like money rather than a count or a reference: decimals, grouping or a marker.
        public var looksLikeMoney: Bool { hasDecimals || hasGrouping || currencyMarker != nil || creditDebit != nil }
    }

    public struct FoundDate: Equatable, Sendable {
        public var date: LocalDate
        public var start: Int
        public var end: Int
    }

    // MARK: Amounts

    public static func amounts(in text: String) -> [FoundAmount] {
        let chars = Array(text)
        var found: [FoundAmount] = []
        var i = 0
        while i < chars.count {
            guard chars[i].isASCIIDigit else { i += 1; continue }
            let start = i
            // Glued to a word ("INV1234") unless the word is a currency ("Rs1,250").
            var marker: String?
            if start > 0, chars[start - 1].isLetter {
                let word = letters(before: start, in: chars)
                guard let known = currencyWord(word) else { i = skipToken(from: i, in: chars); continue }
                marker = known
            }
            if start > 0, chars[start - 1].isASCIIDigit || chars[start - 1] == "." || chars[start - 1] == "," {
                i = skipToken(from: i, in: chars)
                continue
            }
            // Integer part with optional grouping commas.
            var j = i
            var digits = ""
            var groups: [Int] = []
            var current = 0
            while j < chars.count {
                if chars[j].isASCIIDigit {
                    digits.append(chars[j]); current += 1; j += 1
                } else if chars[j] == ",", j + 1 < chars.count, chars[j + 1].isASCIIDigit {
                    groups.append(current); current = 0; j += 1
                } else {
                    break
                }
            }
            groups.append(current)
            // Dates and times ("06/10/2026", "12:30", "06-10-26") are not amounts.
            if j < chars.count, "/:".contains(chars[j]) || (chars[j] == "-" && j + 1 < chars.count && chars[j + 1].isASCIIDigit) {
                i = skipToken(from: j, in: chars)
                continue
            }
            var fraction = ""
            if j < chars.count, chars[j] == ".", j + 1 < chars.count, chars[j + 1].isASCIIDigit {
                var k = j + 1
                while k < chars.count, chars[k].isASCIIDigit { fraction.append(chars[k]); k += 1 }
                // "12.10.2026" or "1.2345": not money.
                if fraction.count > 2 || (k < chars.count && chars[k] == "." && k + 1 < chars.count && chars[k + 1].isASCIIDigit) {
                    i = skipToken(from: k, in: chars)
                    continue
                }
                j = k
            }
            if j < chars.count, chars[j].isLetter, letters(after: j, in: chars).count > 0 {
                // "20k", "5th", "3pm": leave units to callers that understand them, but skip ordinals and ids.
                let word = letters(after: j, in: chars).lowercased()
                if !["cr", "dr", "k"].contains(word), currencyWord(word) == nil { i = skipToken(from: j, in: chars); continue }
            }
            let hasGrouping = groups.count > 1
            if hasGrouping {
                // Western 1,250,000 or South Asian 12,50,000: first group 1–3 digits, middle 2–3, last 3.
                let valid = (1...3).contains(groups[0]) && groups.last == 3
                    && groups.dropFirst().dropLast().allSatisfy { $0 == 2 || $0 == 3 }
                if !valid { i = j; continue }
            }
            let significant = digits.drop { $0 == "0" }
            if significant.count > AmountParser.maxIntegerDigits { i = j; continue }
            // Long plain digit runs are phone numbers, card numbers or references.
            if !hasGrouping, fraction.isEmpty, marker == nil, digits.count >= 7 { i = j; continue }

            if marker == nil { marker = markerBefore(start, in: chars) }
            let negative = isNegative(start: start, end: j, in: chars)
            let creditDebit = creditDebitAfter(j, in: chars)
            let literal = fraction.isEmpty ? digits : digits + "." + fraction
            if let value = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")) {
                found.append(FoundAmount(value: value, start: start, end: j, hasDecimals: !fraction.isEmpty,
                                         hasGrouping: hasGrouping, isNegative: negative, currencyMarker: marker,
                                         creditDebit: creditDebit))
            }
            i = j
        }
        return found
    }

    static func currencyWord(_ word: String) -> String? {
        switch word.lowercased() {
        case "rs", "rs.", "pkr", "rupees", "rupee": "rs"
        case "usd": "usd"
        default: nil
        }
    }

    private static func letters(before index: Int, in chars: [Character]) -> String {
        var k = index - 1
        var word = ""
        while k >= 0, chars[k].isLetter { word.insert(chars[k], at: word.startIndex); k -= 1 }
        return word
    }

    private static func letters(after index: Int, in chars: [Character]) -> String {
        var k = index
        var word = ""
        while k < chars.count, chars[k].isLetter { word.append(chars[k]); k += 1 }
        return word
    }

    /// Skips the rest of a run of digits, letters and number punctuation.
    private static func skipToken(from index: Int, in chars: [Character]) -> Int {
        var k = index
        while k < chars.count, chars[k].isLetter || chars[k].isASCIIDigit || "/:.,-".contains(chars[k]) {
            // Stop at ", " or ". " so a following amount is still found.
            if ",.".contains(chars[k]), k + 1 < chars.count, !chars[k + 1].isASCIIDigit { break }
            k += 1
        }
        return max(k, index + 1)
    }

    private static func markerBefore(_ start: Int, in chars: [Character]) -> String? {
        var k = start - 1
        while k >= 0, chars[k] == " " || chars[k] == "-" || chars[k] == "(" { k -= 1 }
        if k >= 0, chars[k] == "$" { return "$" }
        if k >= 0, chars[k] == "." { k -= 1 }
        guard k >= 0, chars[k].isLetter else { return nil }
        var word = ""
        while k >= 0, chars[k].isLetter { word.insert(chars[k], at: word.startIndex); k -= 1 }
        return currencyWord(word)
    }

    private static func isNegative(start: Int, end: Int, in chars: [Character]) -> Bool {
        var k = start - 1
        while k >= 0, chars[k] == " " { k -= 1 }
        // "Rs -500" or "-Rs 500"
        if k >= 0, chars[k] == "-" || chars[k] == "\u{2212}" {
            return k == 0 || !chars[k - 1].isASCIIDigit
        }
        if k >= 0, chars[k] == "(" {
            var e = end
            while e < chars.count, chars[e] == " " { e += 1 }
            return e < chars.count && chars[e] == ")"
        }
        if k >= 1, chars[k].isLetter {
            var m = k
            while m >= 0, chars[m].isLetter || chars[m] == "." { m -= 1 }
            while m >= 0, chars[m] == " " { m -= 1 }
            return m >= 0 && (chars[m] == "-" || chars[m] == "\u{2212}") && (m == 0 || !chars[m - 1].isASCIIDigit)
        }
        return false
    }

    private static func creditDebitAfter(_ end: Int, in chars: [Character]) -> String? {
        var k = end
        while k < chars.count, chars[k] == " " { k += 1 }
        guard k + 1 < chars.count else { return nil }
        let word = String(chars[k...min(k + 1, chars.count - 1)]).lowercased()
        guard word == "cr" || word == "dr" else { return nil }
        if k + 2 < chars.count, chars[k + 2].isLetter { return nil }
        return word
    }

    // MARK: Dates

    static let monthWords: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
        "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    private enum TokenKind { case number, word, space, symbol }

    private struct Token {
        var kind: TokenKind
        var text: String
        var start: Int
        var end: Int
    }

    private static func tokens(_ chars: [Character]) -> [Token] {
        var result: [Token] = []
        var i = 0
        while i < chars.count {
            let start = i
            let kind: TokenKind
            if chars[i].isASCIIDigit {
                while i < chars.count, chars[i].isASCIIDigit { i += 1 }
                kind = .number
            } else if chars[i].isLetter {
                while i < chars.count, chars[i].isLetter { i += 1 }
                kind = .word
            } else if chars[i].isWhitespace {
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                kind = .space
            } else {
                i += 1
                kind = .symbol
            }
            result.append(Token(kind: kind, text: String(chars[start..<i]), start: start, end: i))
        }
        return result
    }

    /// Dates such as "06/10/2026", "6-10-26", "2026-10-06", "06 Oct 2026", "6-OCT-26", "Oct 6, 2026".
    /// Numeric dates are read day first (Pakistan), unless that is impossible. Without a year
    /// ("06 Oct"), `defaultYear` is used, or the date is skipped when it is nil.
    public static func dates(in text: String, defaultYear: Int? = nil) -> [FoundDate] {
        let t = tokens(Array(text))
        var found: [FoundDate] = []
        var i = 0
        while i < t.count {
            if let hit = match(t, at: i, defaultYear: defaultYear) {
                found.append(FoundDate(date: hit.0, start: t[i].start, end: t[hit.1 - 1].end))
                i = hit.1
            } else {
                i += 1
            }
        }
        return found
    }

    private static func match(_ t: [Token], at i: Int, defaultYear: Int?) -> (LocalDate, Int)? {
        let first = t[i]
        // Not the tail of a longer number ("1,250" or "12.5").
        if i > 0, t[i - 1].kind == .number || (t[i - 1].kind == .symbol && i > 1 && t[i - 2].kind == .number && ".,".contains(t[i - 1].text)) {
            if first.kind == .number { return nil }
        }
        if first.kind == .number {
            // d/m/y, y-m-d
            if i + 4 < t.count, t[i + 1].kind == .symbol, "/-.".contains(t[i + 1].text), t[i + 2].kind == .number,
               t[i + 3].kind == .symbol, t[i + 3].text == t[i + 1].text, t[i + 4].kind == .number,
               !continuesNumber(t, after: i + 4) {
                let a = first.text, b = t[i + 2].text, c = t[i + 4].text
                if a.count == 4, (1...2).contains(b.count), (1...2).contains(c.count),
                   let date = valid(year: Int(a)!, month: Int(b)!, day: Int(c)!) {
                    return (date, i + 5)
                }
                if (1...2).contains(a.count), (1...2).contains(b.count), c.count == 2 || c.count == 4 {
                    let year = c.count == 2 ? 2000 + Int(c)! : Int(c)!
                    if let date = valid(year: year, month: Int(b)!, day: Int(a)!) ?? valid(year: year, month: Int(a)!, day: Int(b)!) {
                        return (date, i + 5)
                    }
                }
                return nil
            }
            // d Mon [y]
            guard (1...2).contains(first.text.count) else { return nil }
            var k = i + 1
            if k < t.count, t[k].kind == .space || (t[k].kind == .symbol && "-/.".contains(t[k].text)) { k += 1 }
            // "6th October"
            if k < t.count, t[k].kind == .word, ["st", "nd", "rd", "th"].contains(t[k].text.lowercased()) {
                k += 1
                if k < t.count, t[k].kind == .space { k += 1 }
            }
            guard k < t.count, t[k].kind == .word, let month = monthWords[t[k].text.lowercased()] else { return nil }
            let day = Int(first.text)!
            var end = k + 1
            var year = defaultYear
            var m = end
            var separators = 0
            while m < t.count, separators < 2, t[m].kind == .space || (t[m].kind == .symbol && "-/.,'".contains(t[m].text)) {
                m += 1; separators += 1
            }
            if m < t.count, t[m].kind == .number, t[m].text.count == 4 || t[m].text.count == 2, !continuesNumber(t, after: m) {
                year = t[m].text.count == 2 ? 2000 + Int(t[m].text)! : Int(t[m].text)!
                end = m + 1
            }
            guard let year, let date = valid(year: year, month: month, day: day) else { return nil }
            return (date, end)
        }
        if first.kind == .word, let month = monthWords[first.text.lowercased()] {
            // Mon d, yyyy
            var k = i + 1
            if k < t.count, t[k].kind == .symbol, t[k].text == "." { k += 1 }
            guard k < t.count, t[k].kind == .space || (t[k].kind == .symbol && t[k].text == "-") else { return nil }
            k += 1
            guard k < t.count, t[k].kind == .number, (1...2).contains(t[k].text.count) else { return nil }
            let day = Int(t[k].text)!
            var m = k + 1
            if m < t.count, t[m].kind == .word, ["st", "nd", "rd", "th"].contains(t[m].text.lowercased()) { m += 1 }
            var separators = 0
            while m < t.count, separators < 2, t[m].kind == .space || (t[m].kind == .symbol && ",-".contains(t[m].text)) {
                m += 1; separators += 1
            }
            if m < t.count, t[m].kind == .number, t[m].text.count == 4, !continuesNumber(t, after: m),
               let date = valid(year: Int(t[m].text)!, month: month, day: day) {
                return (date, m + 1)
            }
            return nil
        }
        return nil
    }

    /// "2026" in "2026.50" or "26,000" is part of an amount, not a year.
    private static func continuesNumber(_ t: [Token], after index: Int) -> Bool {
        guard index + 2 < t.count, t[index + 1].kind == .symbol, ".,".contains(t[index + 1].text) else { return false }
        return t[index + 2].kind == .number
    }

    static func valid(year: Int, month: Int, day: Int) -> LocalDate? {
        guard (1990...2100).contains(year), (1...12).contains(month), day >= 1,
              day <= LocalDate.daysIn(year: year, month: month) else { return nil }
        return LocalDate(year: year, month: month, day: day)
    }
}
