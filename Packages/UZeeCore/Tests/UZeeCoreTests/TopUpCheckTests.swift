import Foundation
import Testing
@testable import UZeeCore

/// Owner, 2026-10-15: warn before a bill when the card it comes from hasn't enough in it.
@Suite("Top up before a bill")
struct TopUpCheckTests {
    let today = LocalDate(year: 2026, month: 10, day: 15)
    func rs(_ major: Int64) -> Money { Money(minorUnits: major * 100, currency: .pkr) }

    @Test("A card with Rs 1,000 and Netflix Rs 1,100 + mobile Rs 500 due this week")
    func warns() {
        let card = Account(name: "Debit card", kind: .bank, currency: .pkr, openingBalance: rs(1_000), openingDate: today.addingDays(-30))
        let netflix = RecurringItem(name: "Netflix", type: .subscription, amount: rs(1_100), accountID: card.id,
                                    rule: RecurrenceRule(anchor: today.addingDays(2)))
        let mobile = RecurringItem(name: "Mobile", type: .bill, amount: rs(500), accountID: card.id,
                                   rule: RecurrenceRule(anchor: today.addingDays(1)))
        let later = RecurringItem(name: "Rent", type: .rent, amount: rs(30_000), accountID: card.id,
                                  rule: RecurrenceRule(anchor: today.addingDays(20)))
        let warnings = TopUpCheck.warnings(recurring: RecurringSnapshot(items: [netflix, mobile, later], records: []), accounts: [card],
                                           balances: [card.id: rs(1_000)], base: .pkr, rates: [:], selfID: nil, today: today)
        #expect(warnings.map(\.itemName) == ["Netflix"])
        #expect(warnings[0].shortBy == rs(600))
        let reminders = TopUpCheck.reminders(warnings, settings: ReminderSettings(), today: today, minuteNow: 8 * 60, format: { "\($0.minorUnits / 100)" })
        #expect(reminders.count == 1)
        #expect(reminders[0].title == "Top up Debit card")
    }

    @Test("A dollar subscription from a rupee card is converted; credit cards are skipped")
    func dollars() {
        let card = Account(name: "Meezan", kind: .bank, currency: .pkr, openingDate: today)
        let credit = Account(name: "Credit", kind: .creditCard, currency: .pkr, openingDate: today)
        let chatgpt = RecurringItem(name: "ChatGPT", type: .subscription, amount: Money(minorUnits: 20_00, currency: .usd), accountID: card.id,
                                    rule: RecurrenceRule(anchor: today.addingDays(3)))
        let other = RecurringItem(name: "Gym", type: .membership, amount: rs(5_000), accountID: credit.id, rule: RecurrenceRule(anchor: today))
        let warnings = TopUpCheck.warnings(recurring: RecurringSnapshot(items: [chatgpt, other], records: []), accounts: [card, credit],
                                           balances: [card.id: rs(2_000), credit.id: rs(0)], base: .pkr, rates: ["USD": 280], selfID: nil, today: today)
        #expect(warnings.count == 1)
        #expect(warnings[0].amount == rs(5_600))
        #expect(warnings[0].shortBy == rs(3_600))
    }
}
