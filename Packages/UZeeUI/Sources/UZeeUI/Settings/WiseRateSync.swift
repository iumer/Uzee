import Foundation
import UZeeCore

/// Live exchange rates from Wise (CUR-03): when UZee opens it asks Wise for today's rate of each currency your
/// accounts use (USD at least) and saves it as the table rate, at most every few hours. Switched off in
/// Settings › Exchange rate, the typed rate is used instead.
extension AppSession {
    static let wiseRatesKey = "uzee.rate.wise"
    static let wiseUpdatedKey = "uzee.rate.wise.updated"

    /// On unless the user turned it off.
    var usesWiseRates: Bool {
        get { UserDefaults.standard.object(forKey: Self.wiseRatesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.wiseRatesKey) }
    }

    /// When the rate last came from Wise.
    var wiseRatesUpdated: Date? { UserDefaults.standard.object(forKey: Self.wiseUpdatedKey) as? Date }

    /// Asks Wise for today's rates; skipped when fetched in the last 3 hours unless `force`. True when a rate came back.
    @discardableResult
    func refreshWiseRates(force: Bool = false) async -> Bool {
        guard usesWiseRates, !ProcessInfo.processInfo.arguments.contains("-uzee-in-memory") else { return false }
        let base = ledger.base
        // A currency with no rate at all is always fetched, however recent the last refresh (BUG-021).
        let missing = !RateTable.missing(Set(ledger.activeAccounts.map(\.currency)), base: base, rates: ledger.rates).isEmpty
        if !force, !missing, let last = wiseRatesUpdated, Date().timeIntervalSince(last) < 3 * 3600 { return false }
        var currencies = Set(ledger.activeAccounts.map(\.currency).filter { $0 != base })
        if base != .usd { currencies.insert(.usd) }
        var got = false
        for currency in currencies.sorted(by: { $0.code < $1.code }) {
            guard let rate = await smart.wiseRate(currency, base, nil) else { continue }
            got = true
            if ledger.rates[currency.code] != rate {
                _ = perform("Couldn't save the rate from Wise.") { try client.setRate(rate, currency) }
            }
        }
        if got { UserDefaults.standard.set(Date(), forKey: Self.wiseUpdatedKey) }
        return got
    }

    /// Wise's rate for 1 `currency` in the base currency on a past day, for entries added later (backlog).
    func wiseRate(_ currency: Currency, on day: LocalDate) async -> Decimal? {
        guard usesWiseRates, currency != ledger.base else { return nil }
        return await smart.wiseRate(currency, ledger.base, day >= today ? nil : day)
    }

    /// "USD at $1 = Rs 277.01" from the rate UZee is using now (Wise's when on), for card footnotes.
    var usdRateNote: String {
        let base = ledger.base
        guard base != .usd else { return "" }
        return "USD at $1 = \(base.symbol) \(ExchangeRate.display(ledger.rate(for: .usd)))"
    }

    // MARK: Other rates (owner, 2026-10-15)

    static let providersAddedKey = "uzee.rate.providers.added"
    static let providersRemovedKey = "uzee.rate.providers.removed"

    /// Money services whose rates show in Settings › Exchange rate: those you added, plus those named in your
    /// accounts ("Western Union USD"), minus those you removed.
    var rateProviders: [RateProvider] {
        let defaults = UserDefaults.standard
        let added = Set((defaults.stringArray(forKey: Self.providersAddedKey) ?? []).compactMap(RateProvider.init(rawValue:)))
        let removed = Set((defaults.stringArray(forKey: Self.providersRemovedKey) ?? []).compactMap(RateProvider.init(rawValue:)))
        let detected = Set(RateProvider.detected(in: ledger.activeAccounts.map(\.name)))
        return RateProvider.allCases.filter { (added.contains($0) || detected.contains($0)) && !removed.contains($0) }
    }

    func setRateProvider(_ provider: RateProvider, shown: Bool) {
        let defaults = UserDefaults.standard
        var added = Set(defaults.stringArray(forKey: Self.providersAddedKey) ?? [])
        var removed = Set(defaults.stringArray(forKey: Self.providersRemovedKey) ?? [])
        if shown { added.insert(provider.rawValue); removed.remove(provider.rawValue) }
        else { added.remove(provider.rawValue); removed.insert(provider.rawValue) }
        defaults.set(added.sorted(), forKey: Self.providersAddedKey)
        defaults.set(removed.sorted(), forKey: Self.providersRemovedKey)
    }

    // MARK: Services and currency pairs (owner, 2026-10-19)

    static let rateServicesKey = "uzee.rate.services"
    static let ratePairsKey = "uzee.rate.pairs"

    /// The services on Settings › Exchange rate, in order. The first time, Google and the services shown before.
    var rateServices: [RateService] {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.rateServicesKey),
               let list = try? JSONDecoder().decode([RateService].self, from: data) { return list }
            return RateService.starting(with: rateProviders)
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.rateServicesKey) }
    }

    /// The currency pairs shown for every service. The first time, each foreign account currency into the base.
    var ratePairs: [RatePair] {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.ratePairsKey),
               let list = try? JSONDecoder().decode([RatePair].self, from: data) { return list }
            return RatePair.defaults(accountCurrencies: ledger.activeAccounts.map(\.currency), base: ledger.base)
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.ratePairsKey) }
    }

    /// A service's live rate for one pair, or nil when it can't be read (typed services return their typed rate).
    func liveRate(_ service: RateService, _ pair: RatePair) async -> Decimal? {
        guard let from = pair.fromCurrency, let to = pair.toCurrency else { return nil }
        switch service.source {
        case .market: return await smart.marketRate(from, to)
        case .wise: return await smart.wiseRate(from, to, nil)
        case .westernUnion: return await smart.providerRate(.westernUnion, from, to)
        case .typed: return service.typed[pair.id]
        }
    }
}
