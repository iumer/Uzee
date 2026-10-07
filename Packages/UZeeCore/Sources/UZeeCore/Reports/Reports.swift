import Foundation

/// Income and spending for one calendar month, my shares in base (RPT-01).
public struct MonthTotals: Hashable, Sendable, Identifiable {
    public var month: LocalDate
    public var income: Money
    public var spending: Money
    public var id: LocalDate { month }

    public var net: Money { (try? income.subtracting(spending)) ?? .zero(income.currency) }
}

/// One slice of "Where it went": a top-level category and its share of the total.
public struct CategoryShare: Hashable, Sendable, Identifiable {
    public var categoryID: UUID
    public var amount: Money
    /// Half-up whole percent of the period total.
    public var percent: Int
    public var id: UUID { categoryID }
}

/// Report figures (RPT-01…04). Spending and income follow SpendingRules: my share only, transfers,
/// loans and settle-ups never count, foreign amounts at the table rate.
public enum ReportCalculator {
    /// Spending in `start...end` by top-level category, largest first.
    public static func byGroup(_ transactions: [MoneyTransaction], from start: LocalDate, through end: LocalDate,
                               categories: [SpendCategory], base: Currency, rates: [String: Decimal]) -> [CategoryShare] {
        let period = BudgetPeriod(start: start, end: end, kind: .calendarMonth)
        let parentOf = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.parentID) })
        var totals: [UUID: Int64] = [:]
        for (id, money) in BudgetCalculator.spending(transactions, in: period, base: base, rates: rates) {
            let group = parentOf[id].flatMap { $0 } ?? id
            totals[group, default: 0] &+= money.minorUnits
        }
        let positive = totals.filter { $0.value > 0 }
        let total = positive.values.reduce(Int64(0), &+)
        return positive.map { id, minor in
            let amount = Money(minorUnits: minor, currency: base)
            return CategoryShare(categoryID: id, amount: amount, percent: (BudgetCalculator.basisPoints(amount, of: Money(minorUnits: total, currency: base)) + 50) / 100)
        }
        .sorted { $0.amount.minorUnits != $1.amount.minorUnits ? $0.amount.minorUnits > $1.amount.minorUnits : $0.categoryID.uuidString < $1.categoryID.uuidString }
    }

    /// My-share income and spending in `start...end`.
    public static func totals(_ transactions: [MoneyTransaction], from start: LocalDate, through end: LocalDate,
                              base: Currency, rates: [String: Decimal]) -> (income: Money, spending: Money) {
        var income: Int64 = 0
        var spending: Int64 = 0
        for transaction in transactions where transaction.isEffective && transaction.localDate >= start && transaction.localDate <= end {
            guard let share = try? RateTable.toBase(transaction.myShare, base: base, rates: rates) else { continue }
            if SpendingRules.countsAsIncome(transaction.kind) {
                income &+= share.minorUnits
            } else {
                spending &+= SpendingRules.spendingSign(transaction.kind) &* share.minorUnits
            }
        }
        return (Money(minorUnits: income, currency: base), Money(minorUnits: spending, currency: base))
    }

    /// Calendar months from `first` through `last` (both any day in the month), oldest first.
    public static func months(_ transactions: [MoneyTransaction], from first: LocalDate, through last: LocalDate,
                              base: Currency, rates: [String: Decimal]) -> [MonthTotals] {
        var result: [MonthTotals] = []
        var month = first.firstOfMonth
        while month <= last.firstOfMonth {
            let figures = totals(transactions, from: month, through: month.lastOfMonth, base: base, rates: rates)
            result.append(MonthTotals(month: month, income: figures.income, spending: figures.spending))
            month = month.addingMonths(1)
        }
        return result
    }

    /// Spending this month up to `today` against the same number of days last month ("Rs 9,800 less").
    public static func monthToDate(_ transactions: [MoneyTransaction], today: LocalDate, base: Currency,
                                   rates: [String: Decimal]) -> (now: Money, before: Money) {
        let now = totals(transactions, from: today.firstOfMonth, through: today, base: base, rates: rates).spending
        let previous = today.firstOfMonth.addingMonths(-1)
        let sameDay = LocalDate(year: previous.year, month: previous.month,
                                day: min(today.day, LocalDate.daysIn(year: previous.year, month: previous.month)))
        let before = totals(transactions, from: previous, through: sameDay, base: base, rates: rates).spending
        return (now, before)
    }
}
