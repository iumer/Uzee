import Foundation

/// What UZee could read from a receipt photo (AI-02). Every field is a suggestion the user can change.
public struct ReceiptReading: Equatable, Sendable {
    public var amount: Money?
    public var date: LocalDate?
    public var merchant: String?
    /// A default category's `systemKey` guessed from the shop and the items ("ceramic coating wax" → car maintenance).
    public var categoryKey: String?

    public init(amount: Money? = nil, date: LocalDate? = nil, merchant: String? = nil, categoryKey: String? = nil) {
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.categoryKey = categoryKey
    }

    public var isEmpty: Bool { amount == nil && date == nil && merchant == nil }
}

/// One piece of text found on a receipt photo and where it sits, in 0…1 page units with the origin at the
/// bottom left (as Vision reports it).
public struct ReceiptPiece: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        minX = x
        minY = y
        maxX = x + width
        maxY = y + height
    }

    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
    var height: Double { maxY - minY }
}

/// Turns recognised receipt lines (top to bottom) into an amount, a date and a merchant. On-device text
/// recognition happens elsewhere (UZeeSystem); this part is pure so it is tested on Linux.
public enum ReceiptParser {
    /// Strongest first. "total" alone is weaker than "grand total" because receipts repeat it.
    static let totalWords: [[String]] = [
        // What's left to pay after discounts and tax beats a "Total Amount" printed above them.
        ["net payable", "amount payable", "total payable", "you pay", "amount to pay", "grand total", "net amount", "amount due",
         "balance due", "net total"],
        ["grand total", "net total", "total amount", "amount due", "total due", "net payable", "total payable",
         "amount payable", "balance due", "net amount", "bill amount", "total bill", "amount to pay", "you pay",
         "cod amount", "amount to collect", "collect amount", "order amount", "invoice amount", "total price", "grand amount"],
        ["total", "payable", "amount", "cod", "net", "to pay"]
    ]
    static let notTotal = ["sub total", "subtotal", "sub-total", "total qty", "total quantity", "total items", "total item",
                           "total discount", "total tax", "total gst", "total saving", "items total", "amount paid",
                           "amount tendered", "amount received", "account", "net weight", "net wt", "paid amount", "tendered",
                           "cash amount", "card amount", "change", "amount returned", "cash received", "received amount",
                           "customer paid", "cash paid", "total paid", "after due date", "after due", "late payment", "late surcharge",
                           "item count", "no. of items", "no of items"]
    static let notAmountLines = ["change", "tendered", "cash received", "tel", "phone", "ntn", "strn", "invoice", "receipt no",
                                 "bill no", "order no", "card no", "pos", "qty", "house", "block", "street", "road", "sector",
                                 "phase", "plot", "flat", "floor", "address", "contact", "mobile", "cell", "tracking", "ref",
                                 "order", "#", "pieces", "postal", "zip", "cnic", "iban", "a/c", "weight", "kg", "gram"]
    /// Couriers print their own name at the top of a parcel label; the shop is the shipper.
    static let couriers = ["postex", "tcs", "leopards", "trax", "m&p", "call courier", "blueex", "rider", "swyft", "daewoo"]
    static let labelWords: Set<String> = ["amount", "date", "name", "contact", "address", "order", "tracking", "origin",
                                          "destination", "remarks", "pieces", "type", "details", "city", "weight", "ref"]
    static let sellerWords = ["shipper", "seller", "sold by", "vendor", "merchant name", "store name", "shop name"]
    static let notMerchant = ["receipt", "invoice", "tax", "ntn", "strn", "gst", "tel", "phone", "ph", "date", "time", "welcome",
                              "www", "http", "@", "cashier", "order", "table", "bill", "fbr", "customer", "copy", "duplicate",
                              "sales", "address", "thank", "pos", "counter", "terminal", "branch", "no."]
    /// Whole words that mark an address line (Pakistani and Malaysian slips); "Broadway" is still a shop.
    static let addressWords: Set<String> = ["jalan", "lot", "taman", "street", "st", "road", "rd", "plot", "sector", "floor",
                                            "block", "phase", "lorong", "persiaran"]
    /// A line saying it is a business is the shop name, even below a logo or a cashier's name.
    static let businessWords = ["sdn bhd", "sdn. bhd", "bhd", "enterprise", "trading", "traders", "restaurant", "store",
                                "mart", "pharmacy", "(pvt)", "pvt", "ltd", "limited", "company", "bakery", "cafe", "hotel",
                                "supermarket", "super market", "motors", "foods", "sweets", "hardware", "stationery", "boutique"]
    /// The line after one of these is a person, not the shop.
    static let personLabels = ["cashier", "served by", "operator", "salesman", "salesperson", "waiter", "staff"]

    public static func read(_ lines: [String], currency: Currency, today: LocalDate) -> ReceiptReading {
        let cleaned = lines.map { fixDigits($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let shop = merchant(cleaned)
        return ReceiptReading(amount: amount(cleaned, currency: currency), date: date(cleaned, today: today),
                              merchant: shop, categoryKey: CategorySuggester.systemKey(inText: cleaned + [shop ?? ""]))
    }

    /// Reads pieces with their positions: the amount comes from the value written next to (or under) a label such
    /// as "Amount" or "Grand Total", which still works when a tilted photo or a table puts them on different lines.
    public static func read(pieces: [ReceiptPiece], currency: Currency, today: LocalDate) -> ReceiptReading {
        let pieces = pieces.map { piece in var fixed = piece; fixed.text = fixDigits(piece.text); return fixed }
        var reading = read(lines(pieces), currency: currency, today: today)
        if let paired = labelledAmount(pieces) { reading.amount = try? Money.fromMajor(paired, currency) }
        return reading
    }

    /// Pieces whose vertical centres are close, joined left to right with three spaces.
    public static func lines(_ pieces: [ReceiptPiece]) -> [String] {
        var rows: [[ReceiptPiece]] = []
        for piece in pieces.sorted(by: { $0.midY > $1.midY }) {
            if let first = rows.last?.first, abs(first.midY - piece.midY) < max(first.height, piece.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "   ") }
    }

    /// Letters the reader mistakes for digits inside numbers: "2,77O.00" → "2,770.00", "1,25S" → "1,255",
    /// "1l5" → "115". Words are left alone.
    static func fixDigits(_ text: String) -> String {
        var result = text
        for (pattern, digit) in [(#"(?<=[0-9][,.]?)[Oo](?=[0-9,.]|\b|$)"#, "0"), (#"(?<![A-Za-z])[Oo](?=[0-9])"#, "0"),
                                 (#"(?<=[0-9][,.]?)[lI](?=[0-9,.]|\b|$)"#, "1"), (#"(?<=[0-9][,.]?)[S](?=[0-9,.]|$)"#, "5")] {
            result = result.replacingOccurrences(of: pattern, with: digit, options: .regularExpression)
        }
        return result
    }

    /// Spaces and case evened out, so "Sub   Total" (columns joined) still reads as "sub total".
    static func plain(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    /// "Total Incl. GST @6%" is about a 6 % tax, not Rs 6: percentages are taken out before reading figures.
    static func withoutPercents(_ text: String) -> String {
        text.replacingOccurrences(of: #"@?\s*\d+(?:[.,]\d+)?\s*%"#, with: " ", options: .regularExpression)
    }

    static func labelledAmount(_ pieces: [ReceiptPiece]) -> Decimal? {
        func money(_ piece: ReceiptPiece) -> [TextScan.FoundAmount] {
            let lower = piece.text.lowercased()
            guard !notAmountLines.contains(where: { containsWord(lower, $0) }) else { return [] }
            return TextScan.amounts(in: withoutPercents(piece.text)).filter { !$0.isNegative && $0.value > 0 && $0.looksLikeMoney }
        }
        for (tier, words) in totalWords.enumerated() {
            var best: Decimal?
            // Top to bottom; in the first tier the lowest line wins (the amount after discounts), else the largest.
            for label in pieces.sorted(by: { $0.midY > $1.midY }) {
                let lower = plain(label.text)
                guard words.contains(where: { containsWord(lower, $0) }), !notTotal.contains(where: { lower.contains($0) }) else { continue }
                // "Sub" read as its own piece just left of "Total", or "Cash"/"Paid" before "Amount".
                let leftWord = pieces.filter { $0 != label && $0.maxX <= label.minX + 0.01 && label.minX - $0.maxX < max(label.height, 0.005) * 3
                    && abs($0.midY - label.midY) < max(label.height, 0.005) * 0.7 }
                    .max { $0.maxX < $1.maxX }.map { plain($0.text) } ?? ""
                if !leftWord.isEmpty, notTotal.contains(where: { (leftWord + " " + lower).contains($0) }) { continue }
                if let own = TextScan.amounts(in: withoutPercents(label.text)).filter({ !$0.isNegative && $0.value > 0 }).last {
                    if tier == 0 || own.value > (best ?? 0) { best = own.value }
                    continue
                }
                // The nearest value to the right on the same printed line (allowing for a tilted photo), else the
                // one just below the label.
                let height = max(label.height, 0.005)
                var nearest: (distance: Double, value: Decimal)?
                for piece in pieces where piece != label {
                    guard let value = money(piece).last?.value else { continue }
                    let dx = piece.minX - label.maxX
                    let dy = abs(piece.midY - label.midY)
                    var distance: Double?
                    if dx > -height, dy < height * 0.7 + abs(dx) * 0.15 {
                        distance = max(dx, 0) + dy * 4
                    } else if piece.maxY < label.midY, label.minY - piece.maxY < height * 2.5,
                              piece.maxX > label.minX, piece.minX < label.maxX + height * 4 {
                        distance = 1 + (label.minY - piece.maxY)
                    }
                    if let distance, distance < (nearest?.distance ?? .infinity) { nearest = (distance, value) }
                }
                if let value = nearest?.value, tier == 0 || value > (best ?? 0) { best = value }
            }
            if let best { return best }
        }
        return nil
    }

    static func amount(_ lines: [String], currency: Currency) -> Money? {
        for (tier, words) in totalWords.enumerated() {
            var best: Decimal?
            for (index, line) in lines.enumerated() {
                let lower = plain(line)
                guard words.contains(where: { containsWord(lower, $0) }), !notTotal.contains(where: { lower.contains($0) }) else { continue }
                // The figure is on the same line, or on one of the next two when the reader split the columns.
                var candidates = TextScan.amounts(in: withoutPercents(line)).filter { !$0.isNegative && $0.value > 0 }
                for next in lines.dropFirst(index + 1).prefix(2) where candidates.isEmpty {
                    let nextLower = next.lowercased()
                    guard !notAmountLines.contains(where: { containsWord(nextLower, $0) }) else { continue }
                    candidates = TextScan.amounts(in: withoutPercents(next)).filter { !$0.isNegative && $0.value > 0 && $0.looksLikeMoney }
                }
                if let value = candidates.last?.value, tier == 0 || value > (best ?? 0) { best = value }
            }
            if let best { return try? Money.fromMajor(best, currency) }
        }
        // No total line: the largest figure that looks like money, preferring ones written as money
        // ("1,829.96", "Rs 500", "1,830/-") over bare grouped numbers, and never addresses or phone numbers.
        var strong: Decimal?
        var weak: Decimal?
        for line in lines {
            let lower = line.lowercased()
            guard !notAmountLines.contains(where: { containsWord(lower, $0) }) else { continue }
            for found in TextScan.amounts(in: withoutPercents(line)) where found.looksLikeMoney && !found.isNegative && found.value > 0 {
                if found.hasDecimals || found.currencyMarker != nil {
                    if found.value > (strong ?? 0) { strong = found.value }
                } else if found.value > (weak ?? 0) {
                    weak = found.value
                }
            }
        }
        return (strong ?? weak).flatMap { try? Money.fromMajor($0, currency) }
    }

    /// "amount" in "Amount: 1,830" but not in "amounts"; symbols ("#", "a/c") match anywhere.
    static func containsWord(_ text: String, _ word: String) -> Bool {
        guard word.allSatisfy({ $0.isLetter || $0 == " " }) else { return text.contains(word) }
        var searchStart = text.startIndex
        while let range = text.range(of: word, range: searchStart..<text.endIndex) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return true }
            searchStart = range.upperBound
        }
        return false
    }

    /// The first date that isn't in the future or more than two years old; lines saying "date" win.
    static func date(_ lines: [String], today: LocalDate) -> LocalDate? {
        let earliest = today.addingMonths(-24)
        let plausible = { (date: LocalDate) in date <= today && date >= earliest }
        let labelled = lines.filter { $0.lowercased().contains("date") }
        for line in labelled + lines {
            if let date = TextScan.dates(in: line, defaultYear: today.year).map(\.date).first(where: plausible) { return date }
        }
        // A bill shows only when it's due ("Due Date: 15-OCT-2026"), which can be ahead.
        for line in lines where line.lowercased().contains("due") {
            if let date = TextScan.dates(in: line, defaultYear: today.year).map(\.date)
                .first(where: { $0 > today && $0 <= today.addingDays(60) }) { return date }
        }
        return nil
    }

    /// The shop name is usually the first line of words near the top. On a parcel label it is the shipper.
    static func merchant(_ lines: [String]) -> String? {
        if let seller = lines.firstIndex(where: { line in sellerWords.contains { line.lowercased().contains($0) } }) {
            for line in lines.dropFirst(seller + 1).prefix(4) {
                // "UMER MOTORS   Return City: Lahore": the next label on the line ends the name.
                let value = line.replacingOccurrences(of: #"(?i)^\s*name\s*:?\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+[A-Za-z]+(\s+[A-Za-z]+)?\s*:.*$"#, with: "", options: .regularExpression)
                if let name = shopName(value), !couriers.contains(where: { name.lowercased().contains($0) }) { return name }
            }
        }
        let top = Array(lines.prefix(10))
        func isCourier(_ name: String) -> Bool { couriers.contains { name.lowercased() == $0 || name.lowercased().hasPrefix($0 + " ") } }
        // "ABC TRADING SDN BHD" under a logo and a cashier's name.
        for line in top where businessWords.contains(where: { containsWord(line.lowercased(), $0) }) {
            if let name = shopName(line), !isCourier(name) { return name }
        }
        for (index, line) in top.prefix(8).enumerated() {
            // The name under "Cashier:" is a person.
            if index > 0, personLabels.contains(where: { plain(top[index - 1]).hasSuffix($0) || plain(top[index - 1]).hasSuffix($0 + ":") }) { continue }
            if let name = shopName(line), !isCourier(name) { return name }
        }
        return nil
    }

    private static func shopName(_ line: String) -> String? {
        let lower = line.lowercased()
        let wordsOnly = lower.split(whereSeparator: { !$0.isLetter && $0 != "." && $0 != "@" }).map(String.init)
        guard !notMerchant.contains(where: { word in wordsOnly.contains(word) || (word.count > 3 && lower.contains(word)) }),
              !wordsOnly.contains("name"), !wordsOnly.contains("information"),
              !wordsOnly.contains(where: addressWords.contains),
              // A form label ("Amount:", "Order Type") is not a shop.
              !line.trimmingCharacters(in: .whitespaces).hasSuffix(":"),
              !(wordsOnly.count <= 3 && wordsOnly.contains(where: labelWords.contains)) else { return nil }
        let letters = line.filter(\.isLetter).count
        let visible = line.filter { !$0.isWhitespace }.count
        guard letters >= 3, visible > 0, Double(letters) / Double(visible) >= 0.6 else { return nil }
        // A postcode ("81100 Johor Bahru") means an address.
        guard line.range(of: #"\b\d{5}\b"#, options: .regularExpression) == nil else { return nil }
        // A misread logo ("FRwOnL", "RSk"): letters switching case inside a word.
        let words = line.split(whereSeparator: { !$0.isLetter })
        guard !words.contains(where: isJumbled) else { return nil }
        return tidy(line)
    }

    /// "FRwOnL", "RSk", "aBc": not upper, lower, Capitalised or CamelCase ("McDonald", "PostEx", "FoodPanda").
    static func isJumbled(_ word: Substring) -> Bool {
        guard word.count >= 2, !word.allSatisfy(\.isUppercase), !word.allSatisfy(\.isLowercase) else { return false }
        var parts: [String] = []
        for letter in word {
            if letter.isUppercase || parts.isEmpty { parts.append(String(letter)) } else { parts[parts.count - 1].append(letter) }
        }
        return parts.contains { $0.count < 2 || !($0.first?.isUppercase ?? false) }
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
