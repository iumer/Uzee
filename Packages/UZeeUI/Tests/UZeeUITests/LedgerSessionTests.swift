import Foundation
import Testing
import UZeeCore
@testable import UZeeUI

/// TXN-013 (undo after save) and the edit/undo path, with an in-memory fake ledger.
@Suite("Ledger session")
@MainActor
struct LedgerSessionTests {
    final class FakeLedger: @unchecked Sendable {
        var saved: [UUID: MoneyTransaction] = [:]
        var discarded: [UUID] = []
    }

    func makeSession(_ fake: FakeLedger) -> AppSession {
        let client = LedgerClient(
            snapshot: { .empty() }, transactions: { Array(fake.saved.values) }, lastUsedAccountID: { nil },
            save: { fake.saved[$0.id] = $0 }, delete: { fake.saved[$0]?.deletedAt = Date() },
            discard: { fake.saved[$0] = nil; fake.discarded.append($0) },
            createAccount: { _ in throw CoreError.notFound }, updateAccount: { _ in }, setArchived: { _, _ in },
            deleteAccount: { _ in }, hasTransactions: { _ in false }, setRate: { _, _ in })
        return AppSession(info: AppInfo(marketingVersion: "0.2.0", buildNumber: "3"), isDatabaseReady: true,
                          sampleData: .unavailable, ledger: client)
    }

    func expense(_ amount: Int64) -> MoneyTransaction {
        MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: LocalDate(Date(), in: .current), timeZoneID: "Asia/Karachi",
                    amount: Money(major: amount, .pkr), legs: [TransactionLeg(accountID: UUID(), amount: Money(major: -amount, .pkr), role: .main)])
    }

    @Test("TXN-013 undo after save removes the new row for good")
    func undoNew() {
        let fake = FakeLedger()
        let session = makeSession(fake)
        let transaction = expense(640)
        #expect(session.save(transaction, isNew: true))
        #expect(session.transactions.count == 1)
        session.toasts.performUndo()
        #expect(fake.discarded == [transaction.id])
        #expect(session.transactions.isEmpty)
    }

    @Test("Paid early, counting from today: the dates move, and Undo puts them back and removes the payment")
    func paidEarlyUndo() {
        final class Calls: @unchecked Sendable { var moved: [LocalDate] = []; var undone: [RecurrenceRule] = []; var reopened: [LocalDate] = [] }
        let calls = Calls()
        let fake = FakeLedger()
        let today = LocalDate(Date(), in: .current)
        let due = today.addingDays(3)
        let rule = RecurrenceRule(unit: .month, anchor: due.addingMonths(-2))
        let item = RecurringItem(name: "Mobile", type: .bill, amount: Money(major: 1_500, .pkr), rule: rule, trackedFrom: due)
        let paymentID = UUID()
        let recurring = RecurringClient(
            snapshot: { RecurringSnapshot(items: [item], records: []) }, save: { _, _ in }, delete: { _ in }, setStatus: { _, _ in },
            markPaid: { _, _, _, _, _ in paymentID }, skip: { _, _ in }, snooze: { _, _, _ in },
            reopen: { _, scheduled in calls.reopened.append(scheduled) }, recordPayout: { _, _, _ in },
            countFromPayment: { _, _, paidOn in calls.moved.append(paidOn); return rule },
            undoCountFromPayment: { _, before, _, _ in calls.undone.append(before) })
        let client = LedgerClient(
            snapshot: { .empty() }, transactions: { Array(fake.saved.values) }, lastUsedAccountID: { nil },
            save: { fake.saved[$0.id] = $0 }, delete: { _ in }, discard: { fake.discarded.append($0) },
            createAccount: { _ in throw CoreError.notFound }, updateAccount: { _ in }, setArchived: { _, _ in },
            deleteAccount: { _ in }, hasTransactions: { _ in false }, setRate: { _, _ in })
        let session = AppSession(info: AppInfo(marketingVersion: "0.2.0", buildNumber: "3"), isDatabaseReady: true,
                                 sampleData: .unavailable, ledger: client, recurring: recurring)
        guard let occurrence = OccurrenceGenerator.next(item, records: [], today: today) else { Issue.record("no occurrence"); return }
        #expect(occurrence.scheduledDate == due)
        #expect(session.markPaid(occurrence, amount: item.amount, account: UUID(), date: Date(), countFromPayment: true))
        #expect(calls.moved == [today])
        session.toasts.performUndo()
        #expect(calls.undone == [rule])
        #expect(calls.reopened == [due])
        #expect(fake.discarded == [paymentID])
        // Keeping the dates: nothing moves.
        #expect(session.markPaid(occurrence, amount: item.amount, account: UUID(), date: Date(), countFromPayment: false))
        #expect(calls.moved.count == 1)
    }

    @Test("Undo after an edit restores the previous version")
    func undoEdit() {
        let fake = FakeLedger()
        let session = makeSession(fake)
        let original = expense(1_500)
        session.save(original, isNew: true)
        var edited = original
        edited.amount = Money(major: 1_650, .pkr)
        session.save(edited, isNew: false)
        session.toasts.performUndo()
        #expect(fake.saved[original.id]?.amount == Money(major: 1_500, .pkr))
    }

    @Test("Repeat and edit requests open the Add sheet")
    func addRequests() {
        let session = makeSession(FakeLedger())
        let transaction = expense(1_850)
        session.openAdd(.repeatOf(transaction))
        #expect(session.isAddPresented)
        #expect(session.addRequest == .repeatOf(transaction))
        session.isAddPresented = false
        #expect(session.addRequest == .new)
    }
}
