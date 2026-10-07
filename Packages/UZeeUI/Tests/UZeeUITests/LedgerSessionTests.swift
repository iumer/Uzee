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
