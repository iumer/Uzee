import Foundation
import Testing
@testable import UZeeCore

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }
private func day(_ y: Int, _ m: Int, _ d: Int) -> LocalDate { LocalDate(year: y, month: m, day: d) }
private let rates: [String: Decimal] = ["USD": 280]

/// REC, KAM and LOAN-06 unit parts: rules, occurrences, plans and totals (TEST_REGISTRY §REC).
@Suite("Recurring")
struct RecurringTests {
    func monthly(_ name: String, _ type: RecurringType = .bill, _ amount: Money, day d: Int, status: SubscriptionStatus = .active) -> RecurringItem {
        RecurringItem(name: name, type: type, amount: amount, rule: RecurrenceRule(anchor: day(2026, 10, d)), status: status)
    }

    var car: RecurringItem {
        RecurringItem(name: "Car installment · Meezan", type: .installment, amount: rs(45_000),
                      rule: RecurrenceRule(anchor: day(2025, 8, 10), limit: 36), trackedFrom: day(2026, 10, 1), paidBeforeTracking: 14)
    }

    var kameti: RecurringItem {
        RecurringItem(name: "Kameti", type: .kameti, amount: rs(20_000), rule: RecurrenceRule(anchor: day(2026, 6, 15), limit: 12),
                      trackedFrom: day(2026, 10, 1), paidBeforeTracking: 4,
                      payouts: [KametiPayout(expectedDate: day(2026, 12, 15), amount: rs(150_000)),
                                KametiPayout(expectedDate: day(2027, 6, 15), amount: rs(150_000))])
    }

    @Test("REC-001 months keep the anchor day, clamped to short months, without drift")
    func monthClamping() {
        let rule = RecurrenceRule(anchor: day(2027, 1, 31))
        #expect(rule.date(at: 1) == day(2027, 2, 28))
        #expect(rule.date(at: 2) == day(2027, 3, 31))
        #expect(rule.date(at: 3) == day(2027, 4, 30))
        #expect(RecurrenceRule(unit: .year, anchor: day(2028, 2, 29)).date(at: 1) == day(2029, 2, 28))
        #expect(RecurrenceRule(unit: .week, interval: 2, anchor: day(2026, 10, 1)).date(at: 3) == day(2026, 11, 12))
        #expect(RecurrenceRule(anchor: day(2026, 10, 1), limit: 2).date(at: 2) == nil)
        #expect(RecurrenceRule(anchor: day(2026, 10, 1), end: day(2026, 11, 30)).occurrences(from: day(2026, 9, 1), through: day(2027, 1, 31)).count == 2)
    }

    @Test("REC-002 first index on or after a date, and occurrences in a range")
    func ranges() {
        let rule = RecurrenceRule(anchor: day(2025, 8, 10))
        #expect(rule.firstIndex(onOrAfter: day(2026, 10, 7)) == 14)
        #expect(rule.firstIndex(onOrAfter: day(2026, 10, 10)) == 14)
        #expect(rule.firstIndex(onOrAfter: day(2026, 10, 11)) == 15)
        #expect(rule.firstIndex(onOrAfter: day(2020, 1, 1)) == 0)
        let october = rule.occurrences(from: day(2026, 10, 1), through: day(2026, 10, 31))
        #expect(october.count == 1 && october[0].date == day(2026, 10, 10) && october[0].index == 14)
        #expect(RecurrenceRule(unit: .month, interval: 3, anchor: day(2026, 1, 1)).text == "Every quarter")
        #expect(RecurrenceRule(anchor: day(2026, 1, 1)).text == "Every month")
    }

    @Test("REC-008 states: overdue gas, due today, upcoming; snooze moves; paid and skipped resolve")
    func states() {
        let gas = monthly("Gas bill · SNGPL", .utility, rs(3_250), day: 5)
        let today = day(2026, 10, 7)
        let next = OccurrenceGenerator.next(gas, records: [], today: today)
        #expect(next?.state == .overdue && next?.scheduledDate == day(2026, 10, 5))
        #expect(OccurrenceGenerator.next(gas, records: [], today: day(2026, 10, 5))?.state == .dueToday)
        #expect(OccurrenceGenerator.next(gas, records: [], today: day(2026, 10, 1))?.state == .upcoming)

        let snoozed = OccurrenceRecord(itemID: gas.id, scheduledDate: day(2026, 10, 5), status: .snoozed, snoozedUntil: day(2026, 10, 8))
        let moved = OccurrenceGenerator.next(gas, records: [snoozed], today: today)
        #expect(moved?.dueDate == day(2026, 10, 8) && moved?.state == .upcoming)

        let paid = OccurrenceRecord(itemID: gas.id, scheduledDate: day(2026, 10, 5), status: .paid, transactionID: UUID())
        #expect(OccurrenceGenerator.next(gas, records: [paid], today: today)?.scheduledDate == day(2026, 11, 5))
        let skipped = OccurrenceRecord(itemID: gas.id, scheduledDate: day(2026, 10, 5), status: .skipped)
        #expect(OccurrenceGenerator.next(gas, records: [skipped], today: today)?.scheduledDate == day(2026, 11, 5))

        let october = OccurrenceGenerator.occurrences(gas, records: [paid], from: day(2026, 10, 1), through: day(2026, 10, 31), today: today)
        #expect(october.count == 1 && october[0].state == .paid)
    }

    @Test("REC-003 paused and cancelled items make no new occurrences; price history picks the amount")
    func statusAndPrice() {
        let paused = monthly("Spotify", .subscription, rs(449), day: 27, status: .paused)
        #expect(OccurrenceGenerator.next(paused, records: [], today: day(2026, 10, 7)) == nil)
        #expect(OccurrenceGenerator.occurrences(paused, records: [], from: day(2026, 10, 1), through: day(2026, 12, 31), today: day(2026, 10, 7)).isEmpty)
        var netflix = monthly("Netflix", .subscription, rs(1_100), day: 12)
        netflix.priceHistory = [PricePoint(effectiveFrom: day(2025, 1, 12), amount: rs(950)),
                                PricePoint(effectiveFrom: day(2026, 4, 12), amount: rs(1_100))]
        #expect(netflix.amount(on: day(2026, 3, 12)) == rs(950))
        #expect(netflix.amount(on: day(2026, 4, 12)) == rs(1_100))
        #expect(netflix.amount(on: day(2024, 1, 1)) == rs(1_100))
    }

    @Test("REC-004 subscriptions Rs 14,065 a month in base; yearly and quarterly items per month")
    func monthlyTotals() throws {
        let subscriptions = [
            monthly("Netflix", .subscription, rs(1_100), day: 12), monthly("iCloud+", .subscription, usd(299), day: 3),
            monthly("ChatGPT Plus", .subscription, usd(2_000), day: 18), monthly("Claude Pro", .subscription, usd(2_000), day: 20),
            monthly("YouTube Premium", .subscription, rs(479), day: 24), monthly("Spotify", .subscription, rs(449), day: 27)
        ]
        let total = try Money.sum(subscriptions.map { RecurringTotals.monthly($0, base: .pkr, rates: rates) }, in: .pkr)
        #expect(total == Money(minorUnits: 1_406_520, currency: .pkr))
        let yearly = RecurringItem(name: "Insurance", type: .insurance, amount: rs(12_000), rule: RecurrenceRule(unit: .year, anchor: day(2026, 1, 1)))
        #expect(RecurringTotals.monthly(yearly, base: .pkr, rates: rates) == rs(1_000))
        let rent = monthly("Office rent", .rent, rs(60_000), day: 1)
        #expect(RecurringTotals.monthly(rent, myShareDivisor: 2, base: .pkr, rates: rates) == rs(30_000))
    }

    @Test("LOAN-006 car plan: 14 paid before tracking, October is 15 of 36, Rs 990,000 left, ends Jul 2028")
    func carPlan() {
        let summary = InstallmentSummary(car, records: [])
        #expect(summary.paid == 14 && summary.total == 36 && summary.left == 22)
        #expect(summary.remaining == rs(990_000))
        #expect(summary.endDate == day(2028, 7, 10))
        let next = OccurrenceGenerator.next(car, records: [], today: day(2026, 10, 7))
        #expect(next?.sequence == 15 && next?.scheduledDate == day(2026, 10, 10))
        let paid = OccurrenceRecord(itemID: car.id, scheduledDate: day(2026, 10, 10), status: .paid, transactionID: UUID())
        #expect(InstallmentSummary(car, records: [paid]).paid == 15)
        // Pre-tracked installments never show as overdue.
        let september = OccurrenceGenerator.occurrences(car, records: [], from: day(2026, 9, 1), through: day(2026, 9, 30), today: day(2026, 10, 7))
        #expect(september.first?.state == .paid)
        #expect(OccurrenceGenerator.occurrences(car, records: [], from: day(2026, 10, 1), through: day(2026, 10, 31), today: day(2026, 10, 7),
                                                includeOverdue: true).count == 1)
        #expect(car.rule.date(at: 36) == nil)
    }

    @Test("KAM-004 kameti: 4 of 12 paid, Rs 80,000 of Rs 240,000, payouts Rs 300,000 don't match")
    func kametiPlan() {
        let summary = KametiSummary(kameti, records: [])
        #expect(summary.paid == 4 && summary.total == 12)
        #expect(summary.contributed == rs(80_000))
        #expect(summary.totalContributions == rs(240_000))
        #expect(summary.payouts == rs(300_000))
        #expect(summary.mismatch)
        #expect(OccurrenceGenerator.next(kameti, records: [], today: day(2026, 10, 7))?.sequence == 5)
        var matching = kameti
        matching.payouts = [KametiPayout(expectedDate: day(2026, 12, 15), amount: rs(240_000))]
        #expect(!KametiSummary(matching, records: []).mismatch)
    }

    @Test("REC-005 validation: name, amount and rule")
    func validation() {
        var item = monthly("Internet", .bill, rs(6_500), day: 8)
        #expect(throws: Never.self) { try item.validate() }
        item.name = "  "
        #expect(throws: RecurringItem.Problem.emptyName) { try item.validate() }
        item.name = "Internet"
        item.amount = rs(0)
        #expect(throws: RecurringItem.Problem.invalidAmount) { try item.validate() }
        item.amount = rs(6_500)
        item.rule.end = day(2026, 1, 1)
        #expect(throws: RecurringItem.Problem.invalidRule) { try item.validate() }
        #expect(RecurringType.kameti.transactionKind == .kametiContribution)
        #expect(RecurringType.salary.transactionKind == .income && RecurringType.installment.isPlan)
    }
}
