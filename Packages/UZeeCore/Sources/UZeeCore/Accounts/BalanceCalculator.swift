import Foundation

/// Balances are derived, never typed or stored (ACC-03, DATA_MODEL §6).
public enum BalanceCalculator {
    /// Opening balance plus every effective leg on this account dated on or after the opening date.
    public static func balance(of account: Account, transactions: some Sequence<MoneyTransaction>, base: Currency = .pkr,
                               rates: [String: Decimal] = [:]) throws(MoneyError) -> Money {
        var total = account.openingBalance
        for transaction in transactions where transaction.isEffective && transaction.localDate >= account.openingDate {
            for leg in transaction.legs where leg.accountID == account.id {
                guard let amount = inAccountCurrency(leg.amount, account.currency, base: base, rates: rates) else { continue }
                total = try total.adding(amount)
            }
        }
        return total
    }

    /// Balance of every account, keyed by id.
    public static func balances(of accounts: [Account], transactions: [MoneyTransaction], base: Currency = .pkr,
                                rates: [String: Decimal] = [:]) throws(MoneyError) -> [UUID: Money] {
        var result: [UUID: Money] = [:]
        for account in accounts { result[account.id] = account.openingBalance }
        for transaction in transactions where transaction.isEffective {
            for leg in transaction.legs {
                guard let account = accounts.first(where: { $0.id == leg.accountID }),
                      transaction.localDate >= account.openingDate,
                      let current = result[leg.accountID],
                      let amount = inAccountCurrency(leg.amount, account.currency, base: base, rates: rates) else { continue }
                result[leg.accountID] = try current.adding(amount)
            }
        }
        return result
    }

    /// A leg saved in another currency than its account (a $1,875 salary marked received into a rupee account, before
    /// 0.15.12) blanked every screen with "currencyMismatch" (owner, 2026-10-22). It counts at the table rate instead,
    /// or is left out when there's no rate, so one odd row never takes the app down.
    static func inAccountCurrency(_ amount: Money, _ currency: Currency, base: Currency, rates: [String: Decimal]) -> Money? {
        if amount.currency == currency { return amount }
        return try? RateTable.convert(amount, to: currency, base: base, rates: rates)
    }

    /// "Available" (DSH-01): non-archived accounts with include-in-totals, each converted to base
    /// at the table rate first, then summed. Sample: Rs 300,000 + $660 → Rs 484,800.
    /// An account in a currency with no rate yet is left out (the footnote says so) instead of failing the
    /// whole total: a new Wise EUR account broke every screen (BUG-021).
    public static func available(accounts: [Account], balances: [UUID: Money], base: Currency,
                                 rates: [String: Decimal]) throws(MoneyError) -> Money {
        var total = Money.zero(base)
        for account in accounts where account.includeInTotals && !account.isArchived {
            guard let balance = balances[account.id], RateTable.hasRate(balance.currency, base: base, rates: rates) else { continue }
            total = try total.adding(try RateTable.toBase(balance, base: base, rates: rates))
        }
        return total
    }
}

/// Current table rates keyed by currency code, base units per 1 unit (CUR-04).
public enum RateTable {
    public static func hasRate(_ currency: Currency, base: Currency, rates: [String: Decimal]) -> Bool {
        currency == base || rates[currency.code] != nil
    }

    /// Currencies in `currencies` that can't be converted yet, sorted by code.
    public static func missing(_ currencies: Set<Currency>, base: Currency, rates: [String: Decimal]) -> [Currency] {
        currencies.filter { !hasRate($0, base: base, rates: rates) }.sorted { $0.code < $1.code }
    }

    /// Target units per 1 unit of `from`, through the base: USD → PKR is the USD rate, PKR → USD is 1 / that, and
    /// EUR → USD goes across both. Nil when either side has no rate yet.
    public static func crossRate(from: Currency, to: Currency, base: Currency, rates: [String: Decimal]) -> Decimal? {
        if from == to { return 1 }
        let fromRate: Decimal? = from == base ? 1 : rates[from.code]
        let toRate: Decimal? = to == base ? 1 : rates[to.code]
        guard let fromRate, let toRate, fromRate > 0, toRate > 0 else { return nil }
        return fromRate / toRate
    }

    /// `money` in `target` at the table rates; throws when there's no rate for one of them.
    public static func convert(_ money: Money, to target: Currency, base: Currency, rates: [String: Decimal]) throws(MoneyError) -> Money {
        if money.currency == target { return money }
        guard let rate = crossRate(from: money.currency, to: target, base: base, rates: rates) else { throw .currencyMismatch }
        return try CurrencyConverter.convertChecked(money, to: target, rate: rate)
    }

    public static func toBase(_ money: Money, base: Currency, rates: [String: Decimal]) throws(MoneyError) -> Money {
        if money.currency == base { return money }
        guard let rate = rates[money.currency.code] else { throw .currencyMismatch }
        return try CurrencyConverter.convertChecked(money, to: base, rate: rate)
    }

    /// True when a total converted something, so it needs the "USD at $1 = Rs 280" footnote (AUD-04).
    public static func footnote(for currencies: Set<Currency>, base: Currency, rates: [String: Decimal]) -> String? {
        let foreign = currencies.filter { $0 != base }.sorted { $0.code < $1.code }
        guard !foreign.isEmpty else { return nil }
        let parts = foreign.compactMap { currency -> String? in
            guard let rate = rates[currency.code] else { return nil }
            let one = currency.symbol + (currency.symbolNeedsSpace ? " " : "") + "1"
            let value = (try? Money.fromMajor(rate, base)).map { MoneyFormatter.string($0) } ?? ExchangeRate.display(rate)
            return "\(currency.code) at \(one) = \(value)"
        }
        let missing = missing(currencies, base: base, rates: rates).map(\.code)
        let note = missing.isEmpty ? [] : ["\(missing.joined(separator: ", ")) not counted until it has a rate"]
        return (parts + note).joined(separator: " · ")
    }
}

/// Income and spending totals over transactions (TXN-015, DATA_MODEL §5): my share, converted per
/// transaction at the table rate, then summed. Transfers, adjustments and loans never count.
public struct PeriodTotals: Equatable, Sendable {
    public var spending: Money
    public var income: Money

    public init(spending: Money, income: Money) {
        self.spending = spending
        self.income = income
    }

    public static func compute(_ transactions: some Sequence<MoneyTransaction>, from start: LocalDate, through end: LocalDate,
                               base: Currency, rates: [String: Decimal]) throws(MoneyError) -> PeriodTotals {
        var spending = Money.zero(base)
        var income = Money.zero(base)
        for transaction in transactions where transaction.isEffective && transaction.localDate >= start && transaction.localDate <= end {
            // No rate yet for this currency: left out rather than failing every total (BUG-021).
            guard RateTable.hasRate(transaction.myShare.currency, base: base, rates: rates) else { continue }
            let share = try RateTable.toBase(transaction.myShare, base: base, rates: rates)
            switch SpendingRules.spendingSign(transaction.kind) {
            case 1: spending = try spending.adding(share)
            case -1: spending = try spending.subtracting(share)
            default: break
            }
            if SpendingRules.countsAsIncome(transaction.kind) { income = try income.adding(share) }
        }
        return PeriodTotals(spending: spending, income: income)
    }
}
