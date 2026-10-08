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
        if !force, let last = wiseRatesUpdated, Date().timeIntervalSince(last) < 3 * 3600 { return false }
        let base = ledger.base
        var currencies = Set(ledger.activeAccounts.map(\.currency).filter { $0 != base })
        if base != .usd { currencies.insert(.usd) }
        var got = false
        for currency in currencies.sorted(by: { $0.code < $1.code }) {
            guard let rate = await smart.wiseRate(currency, base, nil) else { continue }
            got = true
            if rate != ledger.rate(for: currency) {
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
}
