import Foundation

/// Rates other than Wise's, shown next to it in Settings › Exchange rate (owner, 2026-10-15): the market rate
/// Google shows, and the rate of each money service you use, such as Western Union. A service whose rate can't
/// be read falls back to the market rate. For reference only; UZee's totals keep using the rate above them.
public enum RateProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case westernUnion, remitly, moneyGram, worldRemit, payoneer, sadaPay, nayaPay

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .westernUnion: "Western Union"
        case .remitly: "Remitly"
        case .moneyGram: "MoneyGram"
        case .worldRemit: "WorldRemit"
        case .payoneer: "Payoneer"
        case .sadaPay: "SadaPay"
        case .nayaPay: "NayaPay"
        }
    }

    /// Words in an account's name that mean this service.
    var keywords: [String] {
        switch self {
        case .westernUnion: ["western union", "westernunion"]
        case .remitly: ["remitly"]
        case .moneyGram: ["moneygram", "money gram"]
        case .worldRemit: ["worldremit", "world remit"]
        case .payoneer: ["payoneer"]
        case .sadaPay: ["sadapay", "sada pay"]
        case .nayaPay: ["nayapay", "naya pay"]
        }
    }

    /// Services named in your accounts ("Western Union USD", "Payoneer"), in list order.
    public static func detected(in accountNames: [String]) -> [RateProvider] {
        let names = accountNames.map { $0.lowercased() }
        return allCases.filter { provider in names.contains { name in provider.keywords.contains { name.contains($0) } } }
    }
}

/// The market (mid) rate, the one Google shows, from free keyless sources tried in order.
public enum MarketRates {
    public static func urls(_ source: Currency) -> [URL] {
        let code = source.code.lowercased()
        return [
            "https://open.er-api.com/v6/latest/\(source.code)",
            "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/\(code).json",
            "https://latest.currency-api.pages.dev/v1/currencies/\(code).json",
        ].compactMap { URL(string: $0) }
    }

    /// `{"result":"success","rates":{"PKR":280.1}}` or `{"date":"…","usd":{"pkr":280.1}}`.
    public static func parse(_ data: Data, source: Currency, target: Currency) -> Decimal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let number: NSNumber?
        if let rates = object["rates"] as? [String: Any] {
            number = rates[target.code] as? NSNumber
        } else if let rates = object[source.code.lowercased()] as? [String: Any] {
            number = rates[target.code.lowercased()] as? NSNumber
        } else {
            number = nil
        }
        return number.flatMap(OtherRates.sane)
    }
}

/// Western Union's price list for sending `source` to `target` (its website's own request). Its reply nests the
/// rate as `fx_rate` in each way of paying; the best one is used.
public enum WesternUnionRates {
    public static let url = URL(string: "https://www.westernunion.com/wuconnect/prices/catalog")!

    /// Sending from the US by default; PKR goes to Pakistan.
    public static func body(_ source: Currency, _ target: Currency) -> Data {
        let from = source == .eur ? "DE" : source == .gbp ? "GB" : source == .aed ? "AE" : source == .sar ? "SA" : "US"
        let to = target == .pkr ? "PK" : target == .usd ? "US" : "PK"
        let json: [String: Any] = [
            "header_request": ["version": "0.5", "request_type": "PRICECATALOG"],
            "sender": ["client": "WUCOM", "channel": "WWEB", "funds_in": "*", "curr_iso3": source.code,
                       "cty_iso2_ext": from, "send_amount": "100"],
            "receiver": ["curr_iso3": target.code, "cty_iso2_ext": to, "cty_iso2": to],
        ]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    public static func parse(_ data: Data) -> Decimal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: [Decimal] = []
        collect(object, into: &found)
        return found.max()
    }

    private static func collect(_ value: Any, into found: inout [Decimal]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if key == "fx_rate", let rate = OtherRates.sane(child) { found.append(rate) } else { collect(child, into: &found) }
            }
        } else if let list = value as? [Any] {
            for child in list { collect(child, into: &found) }
        }
    }
}

public enum OtherRates {
    /// A positive rate below a million, four decimals; anything else (text, zero, junk) is nil.
    static func sane(_ value: Any) -> Decimal? {
        let text: String
        if let number = value as? NSNumber { text = number.stringValue } else if let string = value as? String { text = string } else { return nil }
        guard let exact = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let rate = Rounding.halfUp(exact, scale: 4)
        return rate > 0 && rate < 1_000_000 ? rate : nil
    }
}

/// A money service on Settings › Exchange rate (owner, 2026-10-19): Google, Wise, Western Union or any other
/// the owner adds by name. Where its live rate comes from is worked out from the name; a service UZee can't
/// read online keeps the rates typed for it.
public struct RateService: Codable, Hashable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// The mid-market rate Google shows.
        case market
        case wise
        case westernUnion
        /// No live rate online: rates typed by hand, else Google's rate for comparing.
        case typed
    }

    public var id: String
    public var name: String
    public var source: Source
    /// Typed rates by pair key ("SAR>PKR").
    public var typed: [String: Decimal]

    public init(id: String = UUID().uuidString, name: String, source: Source? = nil, typed: [String: Decimal] = [:]) {
        self.id = id
        self.name = name
        self.source = source ?? Self.source(for: name)
        self.typed = typed
    }

    /// "Google" → market, "Wise" → wise, "Western Union" → Western Union; anything else is typed.
    public static func source(for name: String) -> Source {
        let key = NameKey.make(name).replacingOccurrences(of: " ", with: "")
        if key.contains("google") || key.contains("market") || key.contains("openmarket") { return .market }
        if key == "wise" || key.hasPrefix("wise") || key.contains("transferwise") { return .wise }
        if key.contains("westernunion") || key == "wu" { return .westernUnion }
        return .typed
    }

    /// Google first, then the services already shown (NayaPay, Western Union…), as before this screen changed.
    public static func starting(with providers: [RateProvider]) -> [RateService] {
        [RateService(id: "google", name: "Google", source: .market)]
            + providers.map { RateService(id: $0.rawValue, name: $0.name, source: $0 == .westernUnion ? .westernUnion : .typed) }
    }
}

/// One currency pair on Settings › Exchange rate: 1 `from` in `to`, like SAR → PKR or EUR → USD.
public struct RatePair: Codable, Hashable, Sendable, Identifiable {
    public var from: String
    public var to: String

    public init(from: Currency, to: Currency) {
        self.from = from.code
        self.to = to.code
    }

    public var id: String { from + ">" + to }
    public var fromCurrency: Currency? { Currency.known(code: from) }
    public var toCurrency: Currency? { Currency.known(code: to) }

    /// Each foreign currency your accounts use into your base currency, USD at least.
    public static func defaults(accountCurrencies: [Currency], base: Currency) -> [RatePair] {
        var codes = Set(accountCurrencies.map(\.code))
        codes.insert(Currency.usd.code)
        codes.insert(Currency.eur.code)
        codes.remove(base.code)
        let sorted = codes.sorted { $0 == "USD" ? true : $1 == "USD" ? false : $0 < $1 }
        return sorted.compactMap { Currency.known(code: $0) }.map { RatePair(from: $0, to: base) }
    }
}
