import Foundation

/// Balances are derived, never typed or stored (ACC-03, DATA_MODEL §6).
public enum BalanceCalculator {
    /// Opening balance plus every effective leg on this account dated on or after the opening date.
    public static func balance(of account: Account, transactions: some Sequence<MoneyTransaction>) throws(MoneyError) -> Money {
        var total = account.openingBalance
        for transaction in transactions where transaction.isEffective && transaction.localDate >= account.openingDate {
            for leg in transaction.legs where leg.accountID == account.id {
                total = try total.adding(leg.amount)
            }
        }
        return total
    }

    /// Balance of every account, keyed by id.
    public static func balances(of accounts: [Account], transactions: [MoneyTransaction]) throws(MoneyError) -> [UUID: Money] {
        var result: [UUID: Money] = [:]
        for account in accounts { result[account.id] = account.openingBalance }
        for transaction in transactions where transaction.isEffective {
            for leg in transaction.legs {
                guard let account = accounts.first(where: { $0.id == leg.accountID }),
                      transaction.localDate >= account.openingDate,
                      let current = result[leg.accountID] else { continue }
                result[leg.accountID] = try current.adding(leg.amount)
            }
        }
        return result
    }

    /// "Available" (DSH-01): non-archived accounts with include-in-totals, each converted to base
    /// at the table rate first, then summed. Sample: Rs 300,000 + $660 → Rs 484,800.
    public static func available(accounts: [Account], balances: [UUID: Money], base: Currency,
                                 rates: [String: Decimal]) throws(MoneyError) -> Money {
        var total = Money.zero(base)
        for account in accounts where account.includeInTotals && !account.isArchived {
            guard let balance = balances[account.id] else { continue }
            total = try total.adding(try RateTable.toBase(balance, base: base, rates: rates))
        }
        return total
    }
}

/// Current table rates keyed by currency code, base units per 1 unit (CUR-04).
public enum RateTable {
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
        return parts.joined(separator: " · ")
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
