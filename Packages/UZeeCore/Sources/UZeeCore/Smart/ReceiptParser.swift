import Foundation

/// What UZee could read from a receipt photo (AI-02). Every field is a suggestion the user can change.
public struct ReceiptReading: Equatable, Sendable {
    public var amount: Money?
    public var date: LocalDate?
    public var merchant: String?

    public init(amount: Money? = nil, date: LocalDate? = nil, merchant: String? = nil) {
        self.amount = amount
        self.date = date
        self.merchant = merchant
    }

    public var isEmpty: Bool { amount == nil && date == nil && merchant == nil }
}

/// Turns recognised receipt lines (top to bottom) into an amount, a date and a merchant. On-device text
/// recognition happens elsewhere (UZeeSystem); this part is pure so it is tested on Linux.
public enum ReceiptParser {
    /// Strongest first. "total" alone is weaker than "grand total" because receipts repeat it.
    static let totalWords: [[String]] = [
        ["grand total", "net total", "total amount", "amount due", "total due", "net payable", "total payable",
         "amount payable", "balance due", "net amount", "bill amount", "total bill", "amount to pay", "you pay"],
        ["total", "payable"]
    ]
    static let notTotal = ["sub total", "subtotal", "sub-total", "total qty", "total quantity", "total items", "total item",
                           "total discount", "total tax", "total gst", "total saving", "items total"]
    static let notAmountLines = ["change", "tendered", "cash received", "tel", "phone", "ntn", "strn", "invoice", "receipt no",
                                 "bill no", "order no", "card no", "pos", "qty"]
    static let notMerchant = ["receipt", "invoice", "tax", "ntn", "strn", "gst", "tel", "phone", "ph", "date", "time", "welcome",
                              "www", "http", "@", "cashier", "order", "table", "bill", "fbr", "customer", "copy", "duplicate",
                              "sales", "address", "thank", "pos", "counter", "terminal", "branch", "no."]

    public static func read(_ lines: [String], currency: Currency, today: LocalDate) -> ReceiptReading {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return ReceiptReading(amount: amount(cleaned, currency: currency), date: date(cleaned, today: today),
                              merchant: merchant(cleaned))
    }

    static func amount(_ lines: [String], currency: Currency) -> Money? {
        for words in totalWords {
            var best: Decimal?
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                guard words.contains(where: { lower.contains($0) }), !notTotal.contains(where: { lower.contains($0) }) else { continue }
                // The figure is on the same line, or on the next one when the reader split the columns.
                var candidates = TextScan.amounts(in: line).filter { !$0.isNegative }
                if candidates.isEmpty, index + 1 < lines.count {
                    candidates = TextScan.amounts(in: lines[index + 1]).filter { !$0.isNegative }
                }
                if let value = candidates.last?.value, value > 0, value > (best ?? 0) { best = value }
            }
            if let best { return try? Money.fromMajor(best, currency) }
        }
        // No total line: the largest figure that looks like money.
        var largest: Decimal?
        for line in lines {
            let lower = line.lowercased()
            guard !notAmountLines.contains(where: { lower.contains($0) }) else { continue }
            for found in TextScan.amounts(in: line) where found.looksLikeMoney && !found.isNegative && found.value > 0 {
                if found.value > (largest ?? 0) { largest = found.value }
            }
        }
        return largest.flatMap { try? Money.fromMajor($0, currency) }
    }

    /// The first date that isn't in the future or more than two years old; lines saying "date" win.
    static func date(_ lines: [String], today: LocalDate) -> LocalDate? {
        let earliest = today.addingMonths(-24)
        let plausible = { (date: LocalDate) in date <= today && date >= earliest }
        let labelled = lines.filter { $0.lowercased().contains("date") }
        for line in labelled + lines {
            if let date = TextScan.dates(in: line, defaultYear: today.year).map(\.date).first(where: plausible) { return date }
        }
        return nil
    }

    /// The shop name is usually the first line of words near the top.
    static func merchant(_ lines: [String]) -> String? {
        for line in lines.prefix(6) {
            let lower = line.lowercased()
            let wordsOnly = lower.split(whereSeparator: { !$0.isLetter && $0 != "." && $0 != "@" }).map(String.init)
            guard !notMerchant.contains(where: { word in wordsOnly.contains(word) || (word.count > 3 && lower.contains(word)) }) else { continue }
            let letters = line.filter(\.isLetter).count
            let visible = line.filter { !$0.isWhitespace }.count
            guard letters >= 3, visible > 0, Double(letters) / Double(visible) >= 0.6 else { continue }
            return tidy(line)
        }
        return nil
    }

    /// "** IMTIAZ SUPER MARKET **" → "Imtiaz Super Market".
    public static func tidy(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: ")")))
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let letters = collapsed.filter(\.isLetter)
        let shouted = !letters.isEmpty && letters.allSatisfy(\.isUppercase)
        let result = shouted ? collapsed.lowercased().split(separator: " ").map(capitalised).joined(separator: " ") : collapsed
        return String(result.prefix(40))
    }

    private static let keptUpper: Set<String> = ["llc", "ltd", "pvt", "kfc", "hbl", "atm", "pos", "ubl", "mcb", "pso", "ibft"]

    private static func capitalised(_ word: Substring) -> String {
        let text = String(word)
        if keptUpper.contains(text) { return text.uppercased() }
        return text.prefix(1).uppercased() + String(text.dropFirst())
    }
}
