import Foundation

/// A bill coming soon from an account that hasn't enough in it (owner, 2026-10-15: "if the payment date is coming
/// soon but that card is empty, alert me to top up that card").
public struct TopUpWarning: Hashable, Sendable, Identifiable {
    public var itemID: UUID
    public var itemName: String
    public var accountID: UUID
    public var accountName: String
    public var dueDate: LocalDate
    /// The bill, in the account's currency.
    public var amount: Money
    public var balance: Money
    /// What to add so this bill (and the ones before it from the same account) go through.
    public var shortBy: Money

    public var id: String { "\(itemID.uuidString)|\(dueDate)" }
}

public enum TopUpCheck {
    /// Bills due from today through `within` days, account by account in due order: when the balance won't cover
    /// them all, each one that doesn't fit is a warning. Credit cards are left out (their limit isn't known), and
    /// so are bills someone else pays.
    public static func warnings(recurring: RecurringSnapshot, accounts: [Account], balances: [UUID: Money], base: Currency,
                                rates: [String: Decimal], selfID: UUID?, today: LocalDate, within: Int = 5) -> [TopUpWarning] {
        let byID = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var due: [(item: RecurringItem, account: Account, date: LocalDate, amount: Money)] = []
        for item in recurring.items where item.isActive && !item.type.isIncome {
            guard let accountID = item.accountID, let account = byID[accountID], !account.isArchived,
                  account.kind != .creditCard else { continue }
            if let payer = item.paidByID, payer != selfID { continue }
            for occurrence in OccurrenceGenerator.occurrences(item, records: recurring.records(for: item.id), from: today,
                                                             through: today.addingDays(within), today: today, includeOverdue: true)
            where !occurrence.isResolved && occurrence.dueDate >= today && occurrence.dueDate <= today.addingDays(within) {
                guard let amount = convert(occurrence.amount, to: account.currency, base: base, rates: rates) else { continue }
                due.append((item, account, occurrence.dueDate, amount))
            }
        }
        var warnings: [TopUpWarning] = []
        for (accountID, bills) in Dictionary(grouping: due, by: { $0.account.id }) {
            guard let account = byID[accountID] else { continue }
            let balance = balances[accountID] ?? account.openingBalance
            var needed: Int64 = 0
            for bill in bills.sorted(by: { $0.date < $1.date }) {
                needed += bill.amount.minorUnits
                guard needed > balance.minorUnits else { continue }
                warnings.append(TopUpWarning(itemID: bill.item.id, itemName: bill.item.name, accountID: accountID, accountName: account.name,
                                             dueDate: bill.date, amount: bill.amount, balance: balance,
                                             shortBy: Money(minorUnits: needed - max(0, balance.minorUnits), currency: account.currency)))
            }
        }
        return warnings.sorted { ($0.dueDate, $0.accountName) < ($1.dueDate, $1.accountName) }
    }

    /// One reminder per warning, in the morning at the reminder time, two days before (or today if that's past).
    public static func reminders(_ warnings: [TopUpWarning], settings: ReminderSettings, today: LocalDate, minuteNow: Int,
                                 format: (Money) -> String) -> [PlannedReminder] {
        guard settings.isOn else { return [] }
        return warnings.compactMap { warning in
            var fire = max(today, warning.dueDate.addingDays(-2))
            var minute = settings.minuteOfDay
            if fire == today, minute <= minuteNow {
                // Too late for the usual time today: in a few minutes instead.
                minute = minuteNow + 2
                if minute >= 24 * 60 { fire = fire.addingDays(1); minute = settings.minuteOfDay }
            }
            guard fire <= warning.dueDate else { return nil }
            let when = today.days(to: warning.dueDate) == 0 ? "today" : today.days(to: warning.dueDate) == 1 ? "tomorrow" : "on \(warning.dueDate)"
            return PlannedReminder(id: "\(PlannedReminder.idPrefix)topup.\(warning.id)", kind: .bill, fireDate: fire, minuteOfDay: minute,
                                   title: "Top up \(warning.accountName)",
                                   body: settings.hideAmounts ? "\(warning.itemName) is due \(when) and the balance won't cover it."
                                       : "\(warning.itemName) (\(format(warning.amount))) is due \(when). Add \(format(warning.shortBy)) to cover it.",
                                   itemID: nil, scheduledDate: nil)
        }
    }

    static func convert(_ money: Money, to target: Currency, base: Currency, rates: [String: Decimal]) -> Money? {
        if money.currency == target { return money }
        guard let inBase = try? RateTable.toBase(money, base: base, rates: rates) else { return nil }
        if target == base { return inBase }
        guard let rate = rates[target.code], rate > 0 else { return nil }
        return CurrencyConverter.convert(inBase, to: target, rate: 1 / rate)
    }
}
