import Foundation

/// Transactions in a screenshot's text (owner, 2026-10-15): a bank or wallet app's list of transactions, an
/// order or receipt email, or a payment notification. The text comes from on-device text recognition, top to
/// bottom. A list gives a row per amount; an order, receipt or notification gives one row with its total.
public enum ScreenshotParser {
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// Words around a balance or a sum, not a transaction.
    static let notTransaction = ["balance", "available", "total spent", "total received", "total income", "limit", "credit limit",
                                 "statement", "points", "rewards", "cashback earned", "minimum due"]
    /// An order or receipt: many figures (items, delivery, tax) but one payment, the total.
    static let receiptWords = ["order", "subtotal", "sub total", "delivery fee", "invoice", "receipt", "items", "qty", "quantity",
                               "grand total", "amount paid", "order total", "your order", "thank you for your", "tax", "gst"]
    static let moneyInWords = ["received", "credited", "credit", "deposit", "refund", "cashback", "salary", "incoming", "from ",
                               "money in", "added to", "cash in", "reversal"]
    static let moneyOutWords = ["paid", "debited", "debit", "sent", "purchase", "payment to", "spent", "withdraw", "to ", "bill",
                                "money out", "transfer to", "charged", "deducted", "cash out"]

    public static func read(lines raw: [String], currency: Currency, today: LocalDate) -> StatementReading {
        let lines = raw.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n").lowercased()
        let list = readList(lines, today: today)
        let looksLikeReceipt = receiptWords.filter { text.contains($0) }.count >= 2
        if looksLikeReceipt || list.count <= 1 {
            let receipt = ReceiptParser.read(lines, currency: currency, today: today)
            if let amount = receipt.amount, amount.minorUnits > 0 {
                let isIn = moneyIn(text) && !moneyOut(text)
                let value = amount.decimalValue
                let row = StatementRow(id: 0, date: receipt.date ?? list.first?.date ?? today,
                                       description: receipt.merchant ?? list.first?.description ?? "Screenshot",
                                       amount: isIn ? value : -value)
                return StatementReading(rows: [row], signSource: .words, linesRead: lines.count, currencyCode: currencyCode(text))
            }
        }
        return StatementReading(rows: list, signSource: .words, linesRead: lines.count, currencyCode: currencyCode(text))
    }

    /// "Today", "Yesterday" and dates without a year, as dates.
    static func date(in line: String, today: LocalDate) -> LocalDate? {
        let lower = " " + line.lowercased() + " "
        if lower.contains(" today ") || lower.contains(" today,") { return today }
        if lower.contains(" yesterday ") || lower.contains(" yesterday,") { return today.addingDays(-1) }
        guard let found = TextScan.dates(in: line, defaultYear: today.year).first?.date else { return nil }
        // An app shows recent days without the year: a date after today is from last year.
        return found > today ? LocalDate(year: found.year - 1, month: found.month, day: found.day) : found
    }

    /// A row per amount: the text lines just before it are what it was, and the nearest date above (or on the
    /// line, or just below as many apps print it) is when.
    static func readList(_ lines: [String], today: LocalDate) -> [StatementRow] {
        var rows: [StatementRow] = []
        var heading: LocalDate?
        var pendingText: [String] = []
        var pendingDate: LocalDate?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let lineDate = date(in: line, today: today)
            let amounts = TextScan.amounts(in: line).filter { $0.looksLikeMoney && $0.value > 0 }
            if notTransaction.contains(where: { lower.contains($0) }) {
                pendingText = []
                continue
            }
            guard let amount = amounts.last else {
                if let lineDate {
                    let rest = stripDate(line)
                    let isDayWord = [" today", " yesterday"].contains { (" " + lower).hasPrefix($0) }
                    if rest.contains(where: \.isLetter) {
                        // "Grocer Mart · 12 Oct": the row's own text and date.
                        pendingText.append(rest)
                        pendingDate = lineDate
                    } else if pendingText.isEmpty || isDayWord {
                        // "Today", "Monday, 12 October": a day heading over the rows below it.
                        heading = lineDate
                        pendingText = []
                    } else {
                        pendingDate = lineDate
                    }
                } else if line.contains(where: \.isLetter) {
                    pendingText.append(line)
                    if pendingText.count > 3 { pendingText.removeFirst() }
                }
                continue
            }
            // Words on the amount's own line ("Foodpanda  -Rs 1,250") count as the description too.
            let own = stripAmounts(stripDate(line))
            var parts = pendingText
            if own.contains(where: \.isLetter) { parts.append(own) }
            let description = ReceiptParser.tidy(parts.joined(separator: " "))
            // The date can sit on the line after the amount ("12 Oct, 3:45 PM").
            var when = lineDate ?? pendingDate
            if when == nil, index + 1 < lines.count, TextScan.amounts(in: lines[index + 1]).filter(\.looksLikeMoney).isEmpty {
                when = date(in: lines[index + 1], today: today)
            }
            let context = (parts + [line]).joined(separator: " ").lowercased()
            let isIn = amount.hasPlusSign || amount.creditDebit == "cr"
                || (!amount.isNegative && amount.creditDebit != "dr" && moneyIn(context) && !moneyOut(context))
            rows.append(StatementRow(id: rows.count, date: when ?? heading ?? today,
                                     description: description.isEmpty ? "Screenshot" : description,
                                     amount: isIn ? amount.value : -amount.value))
            pendingText = []
            pendingDate = nil
        }
        return rows
    }

    static func moneyIn(_ text: String) -> Bool { moneyInWords.contains { text.contains($0) } }
    static func moneyOut(_ text: String) -> Bool { moneyOutWords.contains { text.contains($0) } }

    static func currencyCode(_ text: String) -> String? {
        let rupees = text.range(of: #"\b(rs\.?|pkr)(\b|\d)"#, options: .regularExpression) != nil
        let dollars = text.contains("$") || text.range(of: #"\busd\b"#, options: .regularExpression) != nil
        if dollars, !rupees { return "USD" }
        return rupees ? "PKR" : nil
    }

    static func stripDate(_ line: String) -> String {
        var result = line
        for found in TextScan.dates(in: line, defaultYear: 2000).reversed() {
            let chars = Array(result)
            guard found.end <= chars.count else { continue }
            result = String(chars[..<found.start]) + String(chars[found.end...])
        }
        for word in ["Today", "Yesterday", "today", "yesterday", "TODAY", "YESTERDAY"] {
            result = result.replacingOccurrences(of: word, with: "")
        }
        // Times: "3:45 PM", "15:20".
        result = result.replacingOccurrences(of: #"\b\d{1,2}:\d{2}(\s?[AaPp][Mm])?"#, with: "", options: .regularExpression)
        return result.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",·-|")))
    }

    static func stripAmounts(_ line: String) -> String {
        var chars = Array(line)
        for found in TextScan.amounts(in: line).reversed() where found.end <= chars.count {
            chars.removeSubrange(found.start..<found.end)
        }
        return String(chars)
            .replacingOccurrences(of: #"(?i)\b(rs\.?|pkr|usd)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[+\-−$()]"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
