import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func day(_ m: Int, _ d: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: d) }

/// REC, KAM and LOAN-06 integration tests: sample items, Mark paid once, skip, snooze and payouts (TEST_REGISTRY §REC).
@Suite("Recurring store")
struct RecurringStoreTests {
    struct World {
        let database: AppDatabase
        let ledger: LedgerStore
        let recurring: RecurringStore
    }

    func sample() throws -> World {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        return World(database: database, ledger: LedgerStore(database: database), recurring: RecurringStore(database: database))
    }

    func item(_ name: String, _ snapshot: RecurringSnapshot) -> RecurringItem { snapshot.items.first { $0.name == name }! }
    func account(_ name: String, _ world: World) throws -> UUID { try world.ledger.accounts().first { $0.name == name }!.id }

    @Test("REC-010 sample: 17 items, October states, subscriptions Rs 14,065 a month")
    func sampleItems() throws {
        let world = try sample()
        let snapshot = try world.recurring.snapshot()
        #expect(snapshot.items.count == 17)
        let today = day(10, 7)
        #expect(snapshot.next(item("Gas bill · SNGPL", snapshot), today: today)?.state == .overdue)
        #expect(snapshot.next(item("Office rent", snapshot), today: today)?.scheduledDate == day(11, 1))
        #expect(snapshot.next(item("iCloud+", snapshot), today: today)?.scheduledDate == day(11, 3))
        #expect(snapshot.next(item("Internet · Nayatel", snapshot), today: today)?.scheduledDate == day(10, 8))
        #expect(snapshot.next(item("Amazon Prime Video", snapshot), today: today) == nil)
        let rates = try world.ledger.rates()
        let subscriptions = snapshot.items.filter { $0.type == .subscription && $0.isActive }
        #expect(subscriptions.count == 6)
        let monthly = try Money.sum(subscriptions.map { RecurringTotals.monthly($0, base: .pkr, rates: rates) }, in: .pkr)
        #expect(monthly == Money(minorUnits: 1_406_520, currency: .pkr))
        let netflix = item("Netflix", snapshot)
        #expect(netflix.priceHistory.count == 2 && netflix.amount(on: day(3, 12)) == rs(950))
        let car = item("Car installment · Meezan", snapshot)
        #expect(InstallmentSummary(car, records: snapshot.records(for: car.id)).remaining == rs(990_000))
        let kameti = item("Kameti", snapshot)
        let summary = KametiSummary(kameti, records: snapshot.records(for: kameti.id))
        #expect(summary.paid == 4 && summary.mismatch && kameti.payouts.count == 2)
    }

    @Test("REC-011 Mark paid posts one transaction, again returns the same one; balance moves once")
    func markPaidOnce() throws {
        let world = try sample()
        let snapshot = try world.recurring.snapshot()
        let internet = item("Internet · Nayatel", snapshot)
        let hbl = try account("HBL", world)
        let before = try world.ledger.snapshot().balances[hbl]!
        let first = try world.recurring.markPaid(itemID: internet.id, scheduledDate: day(10, 8), amount: rs(6_500), accountID: hbl, on: day(10, 8))
        let again = try world.recurring.markPaid(itemID: internet.id, scheduledDate: day(10, 8), amount: rs(6_500), accountID: hbl, on: day(10, 8))
        #expect(first.id == again.id)
        #expect(first.source == .recurring && first.kind == .expense && first.categoryID == internet.categoryID)
        let after = try world.ledger.snapshot().balances[hbl]!
        #expect(try before.subtracting(after) == rs(6_500))
        let next = try world.recurring.snapshot().next(internet, today: day(10, 8))
        #expect(next?.scheduledDate == day(11, 8))
    }

    @Test("REC-012 deleting the paid transaction makes the bill due again")
    func deletedPayment() throws {
        let world = try sample()
        let gas = item("Gas bill · SNGPL", try world.recurring.snapshot())
        let txn = try world.recurring.markPaid(itemID: gas.id, scheduledDate: day(10, 5), amount: rs(3_310), accountID: try account("HBL", world),
                                               on: day(10, 7))
        #expect(try world.recurring.snapshot().next(gas, today: day(10, 7))?.scheduledDate == day(11, 5))
        try world.ledger.delete(transactionID: txn.id)
        #expect(try world.recurring.snapshot().next(gas, today: day(10, 7))?.state == .overdue)
        // Paying again posts a new transaction rather than reviving the deleted one.
        let second = try world.recurring.markPaid(itemID: gas.id, scheduledDate: day(10, 5), amount: rs(3_310),
                                                  accountID: try account("HBL", world), on: day(10, 7))
        #expect(second.id != txn.id)
    }

    @Test("REC-013 a group bill splits equally; paid by someone else needs no account")
    func groupBill() throws {
        let world = try sample()
        let snapshot = try world.recurring.snapshot()
        let salaries = item("Office staff salaries", snapshot)
        let txn = try world.recurring.markPaid(itemID: salaries.id, scheduledDate: day(10, 25), amount: rs(70_000),
                                               accountID: try account("HBL", world), on: day(10, 25))
        #expect(txn.myShare == rs(35_000))
        let split = try PeopleStore(database: world.database).snapshot().split(for: txn.id)
        #expect(split?.shares.count == 2)
        let electricity = item("Office electricity · K-Electric", snapshot)
        let partner = try world.recurring.markPaid(itemID: electricity.id, scheduledDate: day(11, 5), amount: rs(13_000), accountID: nil, on: day(11, 5))
        #expect(partner.legs.isEmpty && partner.myShare == rs(6_500))
        let internet = item("Internet · Nayatel", snapshot)
        #expect(throws: RecurringStore.Problem.needsAccount) {
            try world.recurring.markPaid(itemID: internet.id, scheduledDate: day(10, 8), amount: rs(6_500), accountID: nil, on: day(10, 8))
        }
    }

    @Test("REC-014 skip and snooze, and reopen undoes them")
    func skipSnooze() throws {
        let world = try sample()
        let netflix = item("Netflix", try world.recurring.snapshot())
        try world.recurring.snooze(itemID: netflix.id, scheduledDate: day(10, 12), until: day(10, 13))
        #expect(try world.recurring.snapshot().next(netflix, today: day(10, 12))?.dueDate == day(10, 13))
        try world.recurring.skip(itemID: netflix.id, scheduledDate: day(10, 12))
        #expect(try world.recurring.snapshot().next(netflix, today: day(10, 12))?.scheduledDate == day(11, 12))
        try world.recurring.reopen(itemID: netflix.id, scheduledDate: day(10, 12))
        #expect(try world.recurring.snapshot().next(netflix, today: day(10, 12))?.state == .dueToday)
    }

    @Test("REC-015 price change keeps history; pause stops occurrences; delete hides the item")
    func editPauseDelete() throws {
        let world = try sample()
        var spotify = item("Spotify", try world.recurring.snapshot())
        spotify.amount = rs(499)
        try world.recurring.save(spotify, priceFrom: day(11, 27))
        var saved = item("Spotify", try world.recurring.snapshot())
        #expect(saved.amount(on: day(10, 27)) == rs(449) && saved.amount(on: day(11, 27)) == rs(499))
        try world.recurring.setStatus(.paused, itemID: saved.id, on: day(10, 7))
        saved = item("Spotify", try world.recurring.snapshot())
        #expect(saved.status == .paused && saved.statusChangedAt == day(10, 7))
        #expect(try world.recurring.snapshot().next(saved, today: day(10, 7)) == nil)
        try world.recurring.delete(itemID: saved.id)
        #expect(try world.recurring.snapshot().items.contains { $0.name == "Spotify" } == false)
    }

    @Test("KAM-003 a kameti contribution and a payout post the right kinds")
    func kametiPayout() throws {
        let world = try sample()
        let kameti = item("Kameti", try world.recurring.snapshot())
        let cash = try account("Cash", world)
        let contribution = try world.recurring.markPaid(itemID: kameti.id, scheduledDate: day(10, 15), amount: rs(20_000), accountID: cash, on: day(10, 15))
        #expect(contribution.kind == .kametiContribution)
        let snapshot = try world.recurring.snapshot()
        #expect(KametiSummary(item("Kameti", snapshot), records: snapshot.records(for: kameti.id)).paid == 5)
        let payout = try world.recurring.recordPayout(payoutID: kameti.payouts[0].id, accountID: try account("HBL", world), on: day(12, 15))
        #expect(payout.kind == .kametiPayout && payout.amount == rs(150_000))
        #expect(item("Kameti", try world.recurring.snapshot()).payouts[0].isReceived)
    }

    @Test("REC-016 removing sample data removes every recurring row and keeps real ones")
    func removeSample() throws {
        let world = try sample()
        let real = RecurringItem(name: "Water", type: .utility, amount: rs(800), rule: RecurrenceRule(anchor: day(10, 10)))
        try world.recurring.save(real)
        try SampleDataService(database: world.database).removeAll()
        let snapshot = try world.recurring.snapshot()
        #expect(snapshot.items.map(\.name) == ["Water"])
        #expect(snapshot.records.isEmpty)
        let leftovers = try world.database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT (SELECT COUNT(*) FROM price_history) + (SELECT COUNT(*) FROM kameti_payout) + (SELECT COUNT(*) FROM occurrence)")
        }
        #expect(leftovers == 0)
    }
}
