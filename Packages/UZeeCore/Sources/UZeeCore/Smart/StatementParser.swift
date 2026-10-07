import Foundation

/// One transaction read from a bank or wallet statement (IMP-01).
public struct StatementRow: Equatable, Sendable, Identifiable {
    /// Position in the statement, so rows keep their order.
    public var id: Int
    public var date: LocalDate
    public var description: String
    /// Major units. Negative = money left the account.
    public var amount: Decimal
    public var balance: Decimal?

    public init(id: Int, date: LocalDate, description: String, amount: Decimal, balance: Decimal? = nil) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
        self.balance = balance
    }

    public var isMoneyIn: Bool { amount > 0 }
}

public struct StatementReading: Equatable, Sendable {
    /// How sure the reader is about in/out for each row.
    public enum SignSource: String, Sendable {
        /// Checked against the running balance column.
        case balance
        /// Debit and credit columns, "CR"/"DR" or minus signs.
        case columns
        /// Guessed from words such as "salary" or "received". The review screen asks the user to check.
        case words
    }

    public var rows: [StatementRow]
    public var openingBalance: Decimal?
    public var closingBalance: Decimal?
    public var signSource: SignSource
    public var linesRead: Int
    /// The bank or wallet, when the layout is one UZee knows.
    public var source: StatementSource? = nil
    /// The currency the statement names in its header, e.g. "USD" for a Wise dollar statement.
    public var currencyCode: String? = nil

    public var first: LocalDate? { rows.map(\.date).min() }
    public var last: LocalDate? { rows.map(\.date).max() }
}

/// Reads statement text into rows (IMP-01, IMP-06). Most banks print one row per transaction: it starts with
/// a date and ends with the amount and, usually, the running balance. SadaPay and Wise use their own
/// layouts (StatementLayouts). Known sources: MCB, HBL, Meezan, SadaPay, NayaPay and Wise, PDF and CSV.
public enum StatementParser {
    static let openingWords = ["opening balance", "balance b/f", "balance bf", "brought forward", "balance forward", "previous balance"]
    static let closingWords = ["closing balance", "balance c/f", "carried forward", "total", "available balance"]
    static let moneyInWords = ["salary", "credit", "deposit", "received", "receive", "incoming", "inward", "refund", "reversal",
                               "profit", "cashback", "cash back", "markup credit", "from", "funds received", "ibft in", "raast in",
                               "transfer in", "money in", "top up", "topup", "load"]
    static let moneyOutWords = ["purchase", "pos", "payment", "paid", "withdrawal", "atm", "debit", "charges", "fee", "tax",
                                "transfer to", "sent", "bill", "ibft out", "raast out"]

    /// - Parameter lines: the statement's text, line by line, in reading order. Leading spaces show indentation.
    public static func read(lines: [String]) -> StatementReading {
        let source = StatementLayouts.source(of: lines)
        var reading: StatementReading
        switch source {
        case .sadapay: reading = StatementLayouts.readSadaPay(lines)
        case .wise: reading = StatementLayouts.readWise(lines)
        default: reading = readTable(lines)
        }
        reading.source = source
        reading.currencyCode = StatementLayouts.currencyCode(lines)
        return reading
    }

    /// One transaction per line, with wrapped descriptions on the lines below.
    static func readTable(_ lines: [String]) -> StatementReading {
        let year = headerYear(lines)
        var drafts: [Draft] = []
        var opening: Decimal?
        var closing: Decimal?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if openingWords.contains(where: { lower.contains($0) }) {
                if opening == nil, drafts.isEmpty, let value = TextScan.amounts(in: line).last(where: \.looksLikeMoney) {
                    opening = signed(value)
                }
                continue
            }
            if closingWords.contains(where: { lower.hasPrefix($0) || lower.contains(" " + $0) }), !startsWithDate(line, year: year) {
                if let value = TextScan.amounts(in: line).last(where: \.looksLikeMoney) { closing = signed(value) }
                continue
            }
            if let draft = row(from: line, year: year) {
                drafts.append(draft)
            } else if var previous = drafts.last, previous.continuations < 4, line.contains(where: \.isLetter), line.count < 100,
                      !StatementLayouts.isTableHeader(lower), !StatementLayouts.isPageNoise(lower),
                      TextScan.amounts(in: line).filter(\.looksLikeMoney).isEmpty || raw.prefix(while: \.isWhitespace).count >= 4 {
                // A wrapped description. Indented lines can hold figures ("PKR 2600.00 … FOOD PANDA" on HBL).
                previous.description += " " + line
                previous.continuations += 1
                drafts[drafts.count - 1] = previous
            }
        }
        let (rows, source) = resolveSigns(drafts, opening: opening)
        return StatementReading(rows: rows, openingBalance: opening, closingBalance: closing, signSource: source, linesRead: lines.count)
    }

    /// Reads a CSV export (IMP-07): finds the date, description, amount (or debit and credit) and balance columns by name.
    public static func read(csv text: String) -> StatementReading? {
        let table = CSVReader.rows(text)
        guard let headerIndex = table.prefix(20).firstIndex(where: { row in
            let names = row.map { $0.lowercased() }
            return names.contains(where: { $0.contains("date") || $0.contains("timestamp") })
                && names.contains(where: { $0.contains("amount") || $0.contains("debit") || $0.contains("credit") || $0.contains("withdraw") })
        }) else { return nil }
        let header = table[headerIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func column(_ names: [String], excluding: [String] = []) -> Int? {
            header.firstIndex { cell in names.contains(where: { cell.contains($0) }) && !excluding.contains(where: { cell.contains($0) }) }
        }
        guard let dateColumn = column(["date"], excluding: ["value date"]) ?? column(["date", "timestamp"]) else { return nil }
        let descriptionColumn = column(["description", "details", "narration", "particulars", "remarks", "merchant", "title", "reference", "note"])
        // "Cr/Dr" (MCB): a column that says which way each amount went.
        let directionColumn = column(["cr/dr", "dr/cr", "debit/credit", "credit/debit", "cr / dr", "dr / cr"])
        let debitColumn = column(["debit", "withdraw", "money out", "paid out", "dr"], excluding: ["credit", "/"])
        let creditColumn = column(["credit", "deposit", "money in", "paid in", "cr"], excluding: ["debit", "description", "/", "currency"])
        let amountColumn = column(["amount"])
        let balanceColumn = column(["balance"])
        guard amountColumn != nil || debitColumn != nil || creditColumn != nil else { return nil }
        let year = headerYear(table.prefix(headerIndex).map { $0.joined(separator: " ") })

        // A single amount column with minus signs: every unsigned figure is money in.
        let signedColumn = amountColumn.map { index in
            table.dropFirst(headerIndex + 1).contains { $0.count > index && TextScan.amounts(in: $0[index]).first?.isNegative == true }
        } ?? false
        var drafts: [Draft] = []
        var hasColumns = false
        for (offset, cells) in table.dropFirst(headerIndex + 1).enumerated() {
            func cell(_ index: Int?) -> String { index.flatMap { $0 < cells.count ? cells[$0] : nil } ?? "" }
            guard let date = TextScan.dates(in: cell(dateColumn), defaultYear: year).first?.date
                    ?? LocalDate(String(cell(dateColumn).prefix(10))) else { continue }
            var amount: Decimal?
            var signKnown = false
            if let debit = TextScan.amounts(in: cell(debitColumn)).first, debit.value > 0 {
                amount = -debit.value; signKnown = true
            } else if let credit = TextScan.amounts(in: cell(creditColumn)).first, credit.value > 0 {
                amount = credit.value; signKnown = true
            } else if let value = TextScan.amounts(in: cell(amountColumn)).first {
                amount = signed(value)
                signKnown = signedColumn || value.isNegative || value.creditDebit != nil
                switch cell(directionColumn).trimmingCharacters(in: .whitespaces).lowercased() {
                case "dr", "debit", "d": amount = -value.value; signKnown = true
                case "cr", "credit", "c": amount = value.value; signKnown = true
                default: break
                }
            }
            guard let amount, amount != 0 else { continue }
            hasColumns = hasColumns || signKnown
            let balance = TextScan.amounts(in: cell(balanceColumn)).first.map(signed)
            let description = csvDescription(cell(descriptionColumn))
            drafts.append(Draft(id: offset, date: date, description: description.isEmpty ? "Transaction" : description,
                                magnitude: abs(amount), knownSign: signKnown ? (amount < 0 ? -1 : 1) : nil, balance: balance))
        }
        let headerLines = table.prefix(headerIndex + 8).map { $0.joined(separator: " ") }
        guard !drafts.isEmpty else { return nil }
        let (rows, source) = resolveSigns(drafts, opening: nil)
        var reading = StatementReading(rows: rows, openingBalance: nil, closingBalance: nil,
                                       signSource: hasColumns && source == .words ? .columns : source, linesRead: table.count)
        reading.source = StatementLayouts.source(of: headerLines)
        let currencyColumn = column(["currency"])
        let firstCurrency = table.dropFirst(headerIndex + 1).first.flatMap { cells in
            currencyColumn.flatMap { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespaces).uppercased() : nil }
        }
        reading.currencyCode = StatementLayouts.currencyCodes.contains(firstCurrency ?? "") ? firstCurrency
            : StatementLayouts.currencyCode(table.prefix(headerIndex).map { $0.joined(separator: " ") })
        return reading
    }

    /// NayaPay puts several lines in one cell ("Incoming fund transfer from Ali\nSadaPay-0001|Transaction ID …"):
    /// keep the useful parts, joined with " | ".
    static func csvDescription(_ cell: String) -> String {
        let parts = cell.components(separatedBy: CharacterSet(charactersIn: "|\n\r"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { part in
                let lower = part.lowercased()
                return !part.isEmpty && lower != "null" && !lower.hasPrefix("transaction id")
            }
        return parts.joined(separator: " | ")
    }

    // MARK: Rows

    struct Draft {
        var id: Int
        var date: LocalDate
        var description: String
        var magnitude: Decimal
        /// −1 out, +1 in, nil when the line doesn't say.
        var knownSign: Int?
        var balance: Decimal?
        var continuations = 0
    }

    private static func signed(_ found: TextScan.FoundAmount) -> Decimal {
        (found.isNegative || found.creditDebit == "dr") ? -found.value : found.value
    }

    private static func startsWithDate(_ line: String, year: Int?) -> Bool {
        guard let first = TextScan.dates(in: line, defaultYear: year).first else { return false }
        return first.start <= 12
    }

    /// The statement year, from the first full date in the header ("Period 01/09/2026 – 30/09/2026").
    static func headerYear(_ lines: [String]) -> Int? {
        for line in lines.prefix(40) {
            if let date = TextScan.dates(in: line).first?.date { return date.year }
        }
        return nil
    }

    static func row(from line: String, year: Int?) -> Draft? {
        let dates = TextScan.dates(in: line, defaultYear: year)
        // A row starts with its date, maybe after a serial number.
        guard let first = dates.first, first.start <= 12 else { return nil }
        let chars = Array(line)
        var bodyStart = first.end
        // A value date right after the posting date.
        if dates.count > 1, dates[1].start - first.end <= 12, String(chars[first.end..<dates[1].start]).allSatisfy(\.isWhitespace) {
            bodyStart = dates[1].end
        }
        let body = String(chars[bodyStart...])
        let amounts = TextScan.amounts(in: body).filter(\.looksLikeMoney)
        guard !amounts.isEmpty else { return nil }
        // Amount columns sit at the end of the row: take the trailing run (at most three: debit, credit, balance).
        let trailing = Array(amounts.suffix(3))
        let descriptionEnd = trailing[0].start
        var description = String(Array(body)[0..<descriptionEnd]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var words = description.split(whereSeparator: \.isWhitespace).map(String.init)
        // "… from + PKR" or "… GB -Rs.": the amount's currency belongs to the amount.
        while let last = words.last, TextScan.currencyWord(last.trimmingCharacters(in: CharacterSet(charactersIn: "+-.\u{2212}"))) != nil {
            words.removeLast()
        }
        description = words.joined(separator: " ").trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        var magnitude: Decimal
        var knownSign: Int?
        var balance: Decimal?
        switch trailing.count {
        case 3:
            // Debit, credit, balance; one of the first two is usually 0.00.
            balance = signed(trailing[2])
            if trailing[0].value > 0, trailing[1].value == 0 {
                magnitude = trailing[0].value; knownSign = -1
            } else if trailing[1].value > 0, trailing[0].value == 0 {
                magnitude = trailing[1].value; knownSign = 1
            } else {
                // Three real figures: the first is part of the description (e.g. a reference with decimals).
                magnitude = trailing[1].value
                knownSign = sign(of: trailing[1])
            }
        case 2:
            magnitude = trailing[0].value
            knownSign = sign(of: trailing[0])
            balance = signed(trailing[1])
        default:
            magnitude = trailing[0].value
            knownSign = sign(of: trailing[0])
        }
        guard magnitude > 0 else { return nil }
        if description.isEmpty { description = "Transaction" }
        return Draft(id: 0, date: first.date, description: description, magnitude: magnitude, knownSign: knownSign, balance: balance)
    }

    private static func sign(of found: TextScan.FoundAmount) -> Int? {
        if found.isNegative || found.creditDebit == "dr" { return -1 }
        if found.creditDebit == "cr" || found.hasPlusSign { return 1 }
        return nil
    }

    // MARK: Signs

    /// Uses the running balance where it is there (oldest-first or newest-first), then explicit markers, then words.
    static func resolveSigns(_ input: [Draft], opening: Decimal?) -> ([StatementRow], StatementReading.SignSource) {
        var drafts = input
        for index in drafts.indices { drafts[index].id = index }
        var signs = drafts.map(\.knownSign)
        var source: StatementReading.SignSource = signs.contains { $0 != nil } ? .columns : .words

        let balances = drafts.map(\.balance)
        if balances.filter({ $0 != nil }).count >= 2 {
            var forward = 0, backward = 0
            for i in 1..<drafts.count {
                guard let now = balances[i], let before = balances[i - 1] else { continue }
                let change = abs(now - before)
                if change == drafts[i].magnitude { forward += 1 }
                if change == drafts[i - 1].magnitude { backward += 1 }
            }
            let pairs = max(forward, backward)
            if pairs > 0 {
                let oldestFirst = forward >= backward
                for i in drafts.indices {
                    let previousIndex = oldestFirst ? i - 1 : i + 1
                    var before: Decimal?
                    if previousIndex >= 0, previousIndex < drafts.count { before = balances[previousIndex] }
                    if before == nil, let opening, (oldestFirst ? i == 0 : i == drafts.count - 1) { before = opening }
                    if let now = balances[i], let before, abs(now - before) == drafts[i].magnitude {
                        signs[i] = now > before ? 1 : -1
                    }
                }
                source = .balance
            }
        }
        let rows = drafts.enumerated().map { index, draft in
            let sign = signs[index] ?? guessSign(draft.description)
            let description = StatementLayouts.tidyDescription(draft.description)
            return StatementRow(id: index, date: draft.date, description: description.isEmpty ? "Transaction" : description,
                                amount: sign < 0 ? -draft.magnitude : draft.magnitude, balance: draft.balance)
        }
        return (rows, source)
    }

    static func guessSign(_ description: String) -> Int {
        let lower = " " + description.lowercased() + " "
        if moneyOutWords.contains(where: { lower.contains(" " + $0) }) && !lower.contains(" from ") { return -1 }
        if moneyInWords.contains(where: { lower.contains(" " + $0) }) { return 1 }
        return -1
    }

    // MARK: Payees

    static let noiseWords: Set<String> = ["pos", "purchase", "ibft", "ft", "funds", "fund", "transfer", "trf", "atm", "debit", "credit",
                                          "card", "visa", "mastercard", "paypak", "txn", "trx", "ref", "no", "id", "online", "mobile",
                                          "app", "raast", "inward", "outward", "payment", "via", "dr", "cr", "pk", "pak", "lhr", "khi", "isb"]

    /// A short payee from a statement description: "POS PURCHASE FOODPANDA LHR 4411" → "Foodpanda",
    /// "Paid to FOOD PANDA KARACHI PK | Visa xxxx5592" → "Food Panda Karachi".
    public static func payee(from description: String) -> String {
        if let known = StatementLayouts.payee(from: description) { return known }
        let words = description.split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "*" || $0 == "-" }).map(String.init)
        let kept = words.filter { word in
            let lower = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard !lower.isEmpty, !noiseWords.contains(lower) else { return false }
            return lower.filter(\.isNumber).count < 3
        }
        let text = kept.prefix(4).joined(separator: " ")
        return text.isEmpty ? ReceiptParser.tidy(description) : ReceiptParser.tidy(text)
    }
}

/// Minimal CSV reader: commas, quoted fields with "" escapes, CRLF or LF line ends.
public enum CSVReader {
    public static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }
        while let c = next() {
            if quoted {
                if c == "\"" {
                    if let following = next() {
                        if following == "\"" { field.append("\"") } else { quoted = false; pending = following }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}

/// Why a statement file couldn't be read (IMP-06, IMP-007).
public enum StatementFileProblem: Error, Equatable, Sendable {
    /// Not a PDF or CSV UZee can open.
    case unreadable
    /// The PDF has a password.
    case needsPassword
    case wrongPassword
    /// A scanned PDF: pictures of pages, no text.
    case noText
}
