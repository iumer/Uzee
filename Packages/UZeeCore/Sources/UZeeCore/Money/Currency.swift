/// A currency UZee can show. Amounts are always stored in minor units (DATA_MODEL §1);
/// `displayFractionDigits` only controls how many decimals the UI shows.
public struct Currency: Hashable, Sendable {
    /// ISO 4217 code, e.g. "PKR".
    public let code: String
    /// Minor units per major unit as a power of ten (PKR and USD: 2).
    public let minorUnits: Int
    /// Decimals shown on screen. PKR shows whole rupees (tech-decisions brief), USD shows cents.
    public let displayFractionDigits: Int
    /// "Rs", "$", "AED".
    public let symbol: String
    /// Spoken names for VoiceOver ("rupee" / "rupees").
    public let spokenSingular: String
    public let spokenPlural: String
    /// Spoken name of the minor unit when it is shown ("cent" / "cents").
    public let spokenMinorSingular: String
    public let spokenMinorPlural: String

    public init(code: String, minorUnits: Int, displayFractionDigits: Int, symbol: String,
                spokenSingular: String, spokenPlural: String,
                spokenMinorSingular: String = "cent", spokenMinorPlural: String = "cents") {
        precondition((0...3).contains(minorUnits) && (0...minorUnits).contains(displayFractionDigits))
        self.code = code
        self.minorUnits = minorUnits
        self.displayFractionDigits = displayFractionDigits
        self.symbol = symbol
        self.spokenSingular = spokenSingular
        self.spokenPlural = spokenPlural
        self.spokenMinorSingular = spokenMinorSingular
        self.spokenMinorPlural = spokenMinorPlural
    }

    /// Word-like symbols ("Rs", "AED") are followed by a space; "$", "€", "£" are not.
    var symbolNeedsSpace: Bool { symbol.unicodeScalars.allSatisfy { $0.properties.isAlphabetic } }

    public static let pkr = Currency(code: "PKR", minorUnits: 2, displayFractionDigits: 0, symbol: "Rs",
                                     spokenSingular: "rupee", spokenPlural: "rupees",
                                     spokenMinorSingular: "paisa", spokenMinorPlural: "paisa")
    public static let usd = Currency(code: "USD", minorUnits: 2, displayFractionDigits: 2, symbol: "$",
                                     spokenSingular: "US dollar", spokenPlural: "US dollars")
    public static let eur = Currency(code: "EUR", minorUnits: 2, displayFractionDigits: 2, symbol: "€",
                                     spokenSingular: "euro", spokenPlural: "euros")
    public static let gbp = Currency(code: "GBP", minorUnits: 2, displayFractionDigits: 2, symbol: "£",
                                     spokenSingular: "pound", spokenPlural: "pounds",
                                     spokenMinorSingular: "penny", spokenMinorPlural: "pence")
    public static let aed = Currency(code: "AED", minorUnits: 2, displayFractionDigits: 2, symbol: "AED",
                                     spokenSingular: "dirham", spokenPlural: "dirhams",
                                     spokenMinorSingular: "fils", spokenMinorPlural: "fils")
    public static let sar = Currency(code: "SAR", minorUnits: 2, displayFractionDigits: 2, symbol: "SAR",
                                     spokenSingular: "riyal", spokenPlural: "riyals",
                                     spokenMinorSingular: "halala", spokenMinorPlural: "halalas")

    /// Currencies seeded in DATA_MODEL §3.3 (PKR and USD enabled in v1).
    public static let known: [Currency] = [.pkr, .usd, .eur, .gbp, .aed, .sar]

    public static func known(code: String) -> Currency? {
        known.first { $0.code == code.uppercased() }
    }
}
