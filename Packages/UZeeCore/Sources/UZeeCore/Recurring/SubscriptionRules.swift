import Foundation

/// One rule for "is this a subscription", whether a payment is already tracked, and bills drafted from a payment (owner, 2026-10-16).
public enum SubscriptionRules {
    /// A subscription by type, or a bill filed under the Subscriptions category; plans and income keep their own lists.
    public static func isSubscription(_ item: RecurringItem, category: SpendCategory?) -> Bool {
        guard !item.type.isPlan, !item.type.isIncome else { return false }
        return item.type == .subscription || category?.group == .subscriptions
    }

    /// True when a bill already covers this payment: it paid one of the bill's occurrences, or a bill has the payee's name.
    public static func isTracked(_ transaction: MoneyTransaction, items: [RecurringItem], records: [OccurrenceRecord]) -> Bool {
        if records.contains(where: { $0.transactionID == transaction.id }) { return true }
        guard let payee = transaction.payeeName else { return false }
        // Drafts are named with `displayName`, so "NETFLIX.COM 8812" matches the bill "Netflix.com".
        let keys = Set([NameKey.make(payee), NameKey.make(RecurringFinder.displayName(payee))])
        return items.contains { keys.contains(NameKey.make($0.name)) }
    }

    /// A monthly bill, subscription or income prefilled from a payment; an expense in Subscriptions drafts as a subscription.
    public static func draft(from transaction: MoneyTransaction, category: SpendCategory?, today: LocalDate) -> RecurringItem {
        let isIncome = transaction.kind == .income
        let payee = transaction.payeeName ?? transaction.kind.name
        let amount = transaction.amount.isNegative ? ((try? transaction.amount.negated()) ?? transaction.amount) : transaction.amount
        let next = RecurrenceRule.nextMonthly(day: transaction.localDate.day, onOrAfter: today.addingDays(1))
        let type: RecurringType = !isIncome && category?.group == .subscriptions
            ? .subscription : RecurringFinder.suggestedType(payee, isMoneyIn: isIncome)
        return RecurringItem(name: RecurringFinder.displayName(payee), type: type,
                             amount: amount, accountID: transaction.legs.first?.accountID, categoryID: transaction.categoryID,
                             // A split bill stays split with the same group, so only your share counts toward the budget.
                             groupID: transaction.groupID,
                             rule: RecurrenceRule(anchor: next), trackedFrom: next, startedOn: transaction.localDate,
                             colorHex: isIncome ? "#34C759" : "#5E5CE6")
    }
}
