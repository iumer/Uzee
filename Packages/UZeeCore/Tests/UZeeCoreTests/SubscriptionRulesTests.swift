import Foundation
import Testing
@testable import UZeeCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }
private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }

/// Budget › Subscriptions after re-categorising (owner, 2026-10-16). Synthetic rows only.
@Suite("Subscription rules")
struct SubscriptionRulesTests {
    let today = day(2026, 10, 16)
    let account = UUID()
    let subscriptions: SpendCategory
    let food = SpendCategory(type: .expense, name: "Food", group: .food, systemKey: "food")
    let apps: SpendCategory

    init() {
        subscriptions = SpendCategory(type: .expense, name: "Subscriptions", group: .subscriptions, systemKey: "subscriptions")
        apps = SpendCategory(type: .expense, parentID: subscriptions.id, name: "Apps", group: .subscriptions)
    }

    func item(_ name: String, _ type: RecurringType, category: UUID? = nil) -> RecurringItem {
        RecurringItem(name: name, type: type, amount: rs(1_100), categoryID: category, rule: RecurrenceRule(anchor: day(2026, 10, 5)))
    }

    func payment(_ payee: String?, kind: TransactionKind = .expense, category: UUID? = nil) -> MoneyTransaction {
        let amount = rs(1_100)
        let leg = TransactionLeg(accountID: account, amount: kind == .income ? amount : try! amount.negated(), role: .main)
        return MoneyTransaction(kind: kind, occurredAt: Date(timeIntervalSince1970: 1_790_000_000), localDate: day(2026, 10, 5),
                                timeZoneID: "Asia/Karachi", amount: amount, categoryID: category, payeeName: payee, legs: [leg])
    }

    @Test("A bill filed under Subscriptions counts as a subscription; plans, income and other categories don't")
    func isSubscription() {
        #expect(SubscriptionRules.isSubscription(item("Cloud", .bill, category: apps.id), category: apps))
        #expect(SubscriptionRules.isSubscription(item("Cloud", .other, category: subscriptions.id), category: subscriptions))
        #expect(SubscriptionRules.isSubscription(item("Music", .subscription), category: nil))
        #expect(!SubscriptionRules.isSubscription(item("Phone", .installment, category: apps.id), category: apps))
        #expect(!SubscriptionRules.isSubscription(item("Refund", .income, category: apps.id), category: apps))
        #expect(!SubscriptionRules.isSubscription(item("Lunch club", .bill, category: food.id), category: food))
    }

    @Test("A payment in Subscriptions drafts a subscription even with an unfamiliar payee")
    func draftType() {
        let draft = SubscriptionRules.draft(from: payment("XYZ SERVICES 4471", category: apps.id), category: apps, today: today)
        #expect(draft.type == .subscription)
        #expect(draft.name == "Xyz Services")
        #expect(draft.categoryID == apps.id)
        #expect(draft.accountID == account)
        #expect(draft.amount == rs(1_100))
        #expect(draft.rule.anchor == day(2026, 11, 5))
        #expect(draft.startedOn == day(2026, 10, 5))
        #expect(SubscriptionRules.draft(from: payment("XYZ SERVICES 4471", category: food.id), category: food, today: today).type == .bill)
        #expect(SubscriptionRules.draft(from: payment("XYZ SERVICES", kind: .income, category: apps.id), category: apps, today: today).type == .income)
    }

    @Test("A payment is tracked when it paid an occurrence or a bill has its payee's name")
    func isTracked() {
        let netflix = item("Netflix.com", .subscription)
        let linked = payment("Test User")
        let record = OccurrenceRecord(itemID: netflix.id, scheduledDate: day(2026, 10, 5), status: .paid, transactionID: linked.id)
        #expect(SubscriptionRules.isTracked(linked, items: [netflix], records: [record]))
        #expect(SubscriptionRules.isTracked(payment("NETFLIX.COM 8812"), items: [netflix], records: []))
        #expect(SubscriptionRules.isTracked(payment("netflix.com"), items: [netflix], records: []))
        #expect(!SubscriptionRules.isTracked(payment("XYZ SERVICES"), items: [netflix], records: [record]))
        #expect(!SubscriptionRules.isTracked(payment(nil), items: [netflix], records: []))
    }
}
