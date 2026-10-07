import Foundation

/// The bank or wallet a statement came from, when UZee recognises its layout (IMP-01).
public enum StatementSource: String, Sendable, CaseIterable {
    case mcb = "MCB"
    case hbl = "HBL"
    case meezan = "Meezan Bank"
    case sadapay = "SadaPay"
    case nayapay = "NayaPay"
    case wise = "Wise"
}

/// Bank-specific parts of statement reading: recognising the source, the two layouts that don't put a
/// transaction on one line (SadaPay, Wise), tidy descriptions and short payees.
/// Layouts were learned from real statements; the tests use made-up rows in the same shapes.
enum StatementLayouts {
    // MARK: Source and currency

    static func source(of lines: [String]) -> StatementSource? {
        let top = lines.prefix(12).joined(separator: " ").lowercased()
        let header = lines.prefix(30).joined(separator: " ").lowercased()
        if header.contains("wise payments") || lines.contains(where: isWiseDateLine) { return .wise }
        // The account's own IBAN names the bank; descriptions below can mention other banks' IBANs.
        if let index = lines.prefix(15).firstIndex(where: { $0.lowercased().contains("iban") }) {
            let iban = lines[index...].prefix(2).joined(separator: " ").lowercased()
            let banks: [(String, StatementSource)] = [("sada", .sadapay), ("naya", .nayapay), ("mezn", .meezan), ("habb", .hbl), ("mucb", .mcb)]
            for (code, bank) in banks where matches(iban, #"pk\d{2}\s?"# + code) { return bank }
        }
        if header.contains("nayapay") { return .nayapay }
        if top.contains("hbl mobile") { return .hbl }
        if top.contains("mcb live") { return .mcb }
        if top.contains("sadapay") { return .sadapay }
        return nil
    }

    static let currencyCodes = ["PKR", "USD", "EUR", "GBP", "AED", "SAR", "CAD", "AUD", "QAR", "OMR", "KWD", "BHD", "TRY", "CNY", "JPY", "INR"]

    /// The statement's currency when the header names one ("Currency : PKR", "USD statement").
    static func currencyCode(_ lines: [String]) -> String? {
        let header = lines.prefix(30).joined(separator: " ")
        let upper = header.uppercased()
        for code in currencyCodes where upper.contains("\(code) STATEMENT") { return code }
        guard let range = upper.range(of: "CURRENCY") else { return nil }
        let after = String(upper[range.upperBound...].prefix(200))
        let words = after.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.first(where: { currencyCodes.contains($0) })
    }

    // MARK: SadaPay

    /// SadaPay prints each transaction as a block: the description wraps around the date and time,
    /// and the amount sits on its own line with a + or − sign. There is no balance column.
    static func readSadaPay(_ lines: [String]) -> StatementReading {
        var drafts: [StatementParser.Draft] = []
        var block: [String] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            guard !line.isEmpty, !isPageNoise(lower) else { continue }
            if isTableHeader(lower) {
                block = []
                continue
            }
            block.append(line)
            guard let amount = trailingSignedAmount(line) else { continue }
            let text = block.joined(separator: " ")
            // Header text can sit above the first block; the transaction's own date is the last one.
            if let date = TextScan.dates(in: text).last?.date {
                let description = cleanBlock(text)
                drafts.append(StatementParser.Draft(id: 0, date: date, description: description.isEmpty ? "Transaction" : description,
                                                    magnitude: amount.magnitude, knownSign: amount.sign, balance: nil))
            }
            block = []
        }
        let (rows, _) = StatementParser.resolveSigns(drafts, opening: nil)
        return StatementReading(rows: rows, openingBalance: nil, closingBalance: nil, signSource: .columns, linesRead: lines.count)
    }

    /// "+ 2,000.00" or "(Card)   - 905.65" at the end of a line.
    static func trailingSignedAmount(_ line: String) -> (magnitude: Decimal, sign: Int)? {
        guard let last = TextScan.amounts(in: line).last, last.looksLikeMoney, last.value > 0 else { return nil }
        let chars = Array(line)
        guard chars[last.end...].allSatisfy(\.isWhitespace) else { return nil }
        var k = last.start - 1
        while k >= 0, chars[k] == " " || chars[k].isLetter || chars[k] == "." { k -= 1 }
        guard k >= 0 else { return nil }
        switch chars[k] {
        case "+": return (last.value, 1)
        case "-", "\u{2212}": return (last.value, -1)
        default: return nil
        }
    }

    private static func cleanBlock(_ text: String) -> String {
        var result = text
        result = replace(result, #"[+\-−]\s?(?:Rs\.?|PKR)?\s?[\d,]+(?:\.\d{1,2})?\s*$"#, with: "")
        result = replace(result, #"\b\d{1,2} [A-Za-z]{3,9},? \d{4}\b"#, with: " ")
        result = replace(result, typeInBrackets, with: " ")
        return collapse(result)
    }

    private static let typeInBrackets =
        #"(?i)\((?:card|[a-z ]*(?:transfer|payment|top[- ]?up|withdrawal|deposit|refund|reversal|cashback|fee|charges|purchase))\)"#

    // MARK: Wise

    /// "26 December 2025 | Transaction: TRANSFER-1000000001"
    static func isWiseDateLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.lowercased().contains("transaction"),
              let first = TextScan.dates(in: trimmed).first, first.start == 0 else { return false }
        return String(Array(trimmed)[first.end...]).trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }

    /// Wise prints the description and amounts on one line (incoming, outgoing with a minus, then the
    /// balance) and the date on the line below. Newest first.
    static func readWise(_ lines: [String]) -> StatementReading {
        struct Pending {
            var description: String
            var magnitude: Decimal
            var sign: Int
            var balance: Decimal
            var continuations = 0
        }
        var drafts: [StatementParser.Draft] = []
        var pending: Pending?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if isWiseDateLine(line) {
                if let entry = pending, let date = TextScan.dates(in: line).first?.date {
                    drafts.append(StatementParser.Draft(id: 0, date: date, description: entry.description, magnitude: entry.magnitude,
                                                        knownSign: entry.sign, balance: entry.balance))
                }
                pending = nil
                continue
            }
            let money = TextScan.amounts(in: line).filter(\.looksLikeMoney)
            if money.count >= 2 {
                let amount = money[money.count - 2]
                guard amount.value > 0 else { pending = nil; continue }
                let description = collapse(String(Array(line)[0..<amount.start]))
                pending = Pending(description: description.isEmpty ? "Transaction" : description, magnitude: amount.value,
                                  sign: amount.isNegative ? -1 : 1, balance: money[money.count - 1].value)
            } else if var entry = pending, money.isEmpty, entry.continuations < 2, line.count < 90, !isPageNoise(line.lowercased()) {
                // A wrapped description.
                entry.description += " " + line
                entry.continuations += 1
                pending = entry
            }
        }
        let (rows, _) = StatementParser.resolveSigns(drafts, opening: nil)
        return StatementReading(rows: rows, openingBalance: nil, closingBalance: nil, signSource: .columns, linesRead: lines.count)
    }

    // MARK: Page furniture

    static func isPageNoise(_ lower: String) -> Bool {
        lower.hasPrefix("generated on") || lower.contains("generated on:") || matches(lower, #"page \d+ of \d+"#)
            || lower.hasPrefix("iban") || lower.hasPrefix("note:") || lower.contains("account transactions from")
            || lower.contains("system generated") || lower.hasPrefix("ref:") || lower == "transaction"
            || lower.hasPrefix("account statement") || lower.hasPrefix("account activity")
    }

    /// A column header row such as "Date  Description  Debit/Credit".
    static func isTableHeader(_ lower: String) -> Bool {
        let words = ["date", "description", "debit", "credit", "balance", "amount", "particulars", "narration", "details"]
        return words.filter { lower.contains($0) }.count >= 2 && TextScan.amounts(in: lower).filter(\.looksLikeMoney).isEmpty
    }

    // MARK: Descriptions

    /// Removes times, empty " -  - " runs and zero service-charge notes from a description.
    static func tidyDescription(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\n", with: " ")
        result = replace(result, #"\b\d{1,2}:\d{2}(?::\d{2})?\s?(?:AM|PM|am|pm)?\b"#, with: " ")
        result = replace(result, #"(?i)service charges\s+rs\.?\s?0(?:\.00)?\b"#, with: " ")
        result = replace(result, #"(\s+-)+\s*$"#, with: "")
        result = replace(result, #"(\s*-\s+){2,}"#, with: " - ")
        result = collapse(result)
        while result.hasPrefix("- ") { result.removeFirst(2) }
        return result
    }

    // MARK: Payees

    /// Words that end a name: "Sara Khan IBAN XXXX-0001 Thru Raast" → "Sara Khan".
    private static let nameStops: Set<String> = ["iban", "thru", "through", "with", "via", "visa", "mastercard", "transaction", "nickname",
                                                 "raast", "ref", "reference", "stan", "a/c", "acc", "account", "on", "for", "fee", "and"]

    private static let lead = ["sent money to", "received money from", "money sent to", "money received from", "money transferred to",
                               "incoming fund transfer from", "outgoing fund transfer to", "fund transfer from", "fund transfer to",
                               "funds transfer from", "funds transfer to", "transfer from", "transfer to", "paid to", "payment to",
                               "received from", "from", "frm", "fr", "to"]

    private static let countryCodes: Set<String> = ["pk", "us", "ie", "gb", "sg", "nl", "ae", "uk", "irl", "sgp", "usa", "gbr", "nld", "are"]

    /// A payee for a known layout, or nil to use the generic rules.
    static func payee(from description: String) -> String? {
        let lower = description.lowercased()
        if lower.hasPrefix("wise charges") { return "Wise fees" }
        if lower.hasPrefix("converted ") { return "Currency conversion" }
        if lower.contains("originator") { return mcbPayee(description) }
        if lower.contains("debit card/pos") || lower.hasPrefix("pos ") {
            // HBL: "Debit Card/POS 1234… PKR 2600.00 111111 0106 1234567 FOOD PANDA KARACHI": the merchant is at the end.
            let words = description.split(separator: " ").map(String.init)
            let tail = words.reversed().prefix { !$0.contains(where: \.isNumber) && !$0.contains("/") && !$0.contains("+") }.reversed()
            if !tail.isEmpty { return finishName(Array(tail)) }
        }
        let words = description.split(whereSeparator: { $0.isWhitespace || $0 == "|" }).map(String.init)
        let lowered = words.map { $0.lowercased() }
        for phrase in lead {
            let parts = phrase.split(separator: " ").map(String.init)
            guard parts.count <= lowered.count else { continue }
            for start in 0...(lowered.count - parts.count) where Array(lowered[start..<(start + parts.count)]) == parts {
                var name: [String] = []
                for word in words.dropFirst(start + parts.count) {
                    let clean = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    if word.contains(where: \.isNumber) || word.hasPrefix("(") || nameStops.contains(clean) || clean.hasPrefix("xxxx") { break }
                    if word == "-" { break }
                    name.append(word)
                    if name.count == 4 { break }
                }
                if let result = finishName(name) { return result }
            }
        }
        return nil
    }

    /// MCB: "IBFT SENDING-MCB LIVE - ALI RAZA - 1111… - Originator : - AYESHA KHAN …".
    private static func mcbPayee(_ description: String) -> String? {
        let segments = description.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let kind = segments.first else { return nil }
        let upperKind = kind.uppercased()
        func isName(_ text: String) -> Bool {
            // "BILAL AHMED - PK00…" or "BILAL AHMED 8518479701": numbers don't count against a name.
            let words = text.split(separator: " ").filter { $0.filter(\.isNumber).count < 3 }
            return words.contains { $0.contains(where: \.isLetter) } && !text.lowercased().contains("originator")
        }
        if upperKind.contains("RECEIV") || (upperKind.contains("DEPOSIT") && !upperKind.contains("CHEQUE")),
           let marker = segments.firstIndex(where: { $0.lowercased().hasPrefix("originator") }) {
            if let name = segments.dropFirst(marker + 1).first(where: isName) { return finishName(name.split(separator: " ").map(String.init)) }
        }
        if upperKind.contains("SENDING"), segments.count > 1, isName(segments[1]) {
            return finishName(segments[1].split(separator: " ").map(String.init))
        }
        var cleaned = kind
        for suffix in ["-MCB LIVE", " MCB LIVE", "-MCB", "-LIVE"] {
            if let range = cleaned.range(of: suffix, options: [.caseInsensitive, .backwards]) { cleaned.removeSubrange(range) }
        }
        return finishName(cleaned.split(separator: " ").map(String.init))
    }

    private static func finishName(_ words: [String]) -> String? {
        var kept = words.filter { word in
            let lower = word.lowercased()
            return lower.filter(\.isNumber).count < 3 && !lower.hasPrefix("xxxx") && lower != "|"
        }
        while let last = kept.last, countryCodes.contains(last.lowercased()) || last.count == 1 { kept.removeLast() }
        guard !kept.isEmpty else { return nil }
        let name = ReceiptParser.tidy(kept.prefix(4).joined(separator: " "))
        return name.isEmpty ? nil : name
    }

    // MARK: Text helpers

    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    static func replace(_ text: String, _ pattern: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
