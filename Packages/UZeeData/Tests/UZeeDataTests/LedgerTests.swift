import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }

/// ACC, CUR and TXN integration tests (docs/TEST_REGISTRY.md §4–6) against a real SQLite database.
@Suite("Ledger")
struct LedgerTests {
    let karachi = TimeZone(identifier: "Asia/Karachi")!
    let october = (LocalDate(year: 2026, month: 10, day: 1), LocalDate(year: 2026, month: 10, day: 31))

    func sampleDatabase() throws -> (AppDatabase, LedgerStore) {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        return (database, LedgerStore(database: database))
    }

    func account(_ name: String, _ snapshot: LedgerSnapshot) -> Account { snapshot.accounts.first { $0.name == name }! }

    func category(_ key: String, _ snapshot: LedgerSnapshot) -> UUID { snapshot.categories.first { $0.systemKey == key }!.id }

    func date(_ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = karachi
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("ACC-007 / CUR-011 sample balances are derived and total Rs 484,800")
    func sampleBalances() throws {
        let (_, store) = try sampleDatabase()
        let snapshot = try store.snapshot()
        let expected: [(String, Money)] = [
            ("HBL", rs(182_400)), ("Meezan", rs(48_000)), ("Cash", rs(26_000)), ("Easypaisa", rs(21_350)),
            ("SadaPay", rs(12_450)), ("NayaPay", rs(9_800)), ("Wise", usd(52_000)), ("Fasset", usd(9_500)), ("RedotPay", usd(4_500))
        ]
        #expect(snapshot.accounts.map(\.name) == expected.map(\.0))
        for (name, balance) in expected {
            #expect(snapshot.balance(of: account(name, snapshot)) == balance, "\(name)")
        }
        #expect(snapshot.available == rs(484_800))
        #expect(snapshot.footnote == "USD at $1 = Rs 280")
    }

    @Test("October spending (my share) is Rs 78,374; the transfer and loan are not spending")
    func octoberSpending() throws {
        let (_, store) = try sampleDatabase()
        let totals = try PeriodTotals.compute(try store.transactions(), from: october.0, through: october.1, base: .pkr, rates: try store.rates())
        #expect(totals.spending.minorUnits == 7_837_420)
        #expect(MoneyFormatter.string(totals.spending) == "Rs 78,374")
        #expect(totals.income == rs(35_000))
    }

    @Test("TXN-001 expense reduces the balance")
    func expense() throws {
        let (_, store) = try sampleDatabase()
        var snapshot = try store.snapshot()
        let hbl = account("HBL", snapshot)
        let draft = TransactionDraft(kind: .expense, amount: rs(1_500), accountID: hbl.id,
                                     categoryID: category("utilities.mobile", snapshot), payeeName: "Jazz", occurredAt: date(6), timeZone: karachi)
        try store.save(try TransactionValidator.build(draft, accounts: snapshot.accounts))
        snapshot = try store.snapshot()
        #expect(snapshot.balance(of: hbl) == rs(180_900))
    }

    @Test("TXN-003 same-currency transfer leaves the total unchanged")
    func sameCurrencyTransfer() throws {
        let (_, store) = try sampleDatabase()
        var snapshot = try store.snapshot()
        let (hbl, cash) = (account("HBL", snapshot), account("Cash", snapshot))
        let draft = TransactionDraft(kind: .transfer, amount: rs(5_000), accountID: hbl.id, toAccountID: cash.id, occurredAt: date(6), timeZone: karachi)
        try store.save(try TransactionValidator.build(draft, accounts: snapshot.accounts))
        snapshot = try store.snapshot()
        #expect(snapshot.balance(of: hbl) == rs(177_400))
        #expect(snapshot.balance(of: cash) == rs(31_000))
        #expect(snapshot.available == rs(484_800))
    }

    @Test("TXN-004 / CUR-009 the sample Wise → HBL transfer keeps its own rate")
    func storedRate() throws {
        let (_, store) = try sampleDatabase()
        let transfer = try store.transactions().first { $0.kind == .transfer }!
        #expect(transfer.fxRate == Decimal(string: "278.7")!)
        #expect(transfer.legs.map(\.amount) == [usd(-50_000), rs(139_350)])
    }

    @Test("CUR-010 a new table rate changes totals but not the stored transfer")
    func rateHistory() throws {
        let (_, store) = try sampleDatabase()
        try store.setRate(285, for: .usd)
        var snapshot = try store.snapshot()
        #expect(snapshot.available == rs(488_100))
        #expect(try store.transactions().first { $0.kind == .transfer }!.fxRate == Decimal(string: "278.7")!)
        try store.setRate(280, for: .usd, at: Date().addingTimeInterval(1))
        snapshot = try store.snapshot()
        #expect(snapshot.available == rs(484_800))
    }

    @Test("TXN-006 editing the account moves the balance effect")
    func editAccount() throws {
        let (_, store) = try sampleDatabase()
        let snapshot = try store.snapshot()
        let jazz = try store.transactions().first { $0.payeeName == "Jazz postpaid" }!
        var draft = TransactionValidator.draft(from: jazz)
        draft.accountID = account("Meezan", snapshot).id
        try store.save(try TransactionValidator.build(draft, accounts: snapshot.accounts, existing: jazz))
        let after = try store.snapshot()
        #expect(after.balance(of: account("HBL", after)) == rs(183_900))
        #expect(after.balance(of: account("Meezan", after)) == rs(46_500))
        #expect(after.available == rs(484_800))
        let saved = try store.transaction(id: jazz.id)!
        #expect(saved.createdAt == jazz.createdAt)
    }

    @Test("TXN-008 delete is soft and restores the balance")
    func softDelete() throws {
        let (database, store) = try sampleDatabase()
        let tea = try store.transactions().first { $0.payeeName == "Office tea & snacks" }!
        try store.delete(transactionID: tea.id)
        let snapshot = try store.snapshot()
        #expect(snapshot.balance(of: account("Cash", snapshot)) == rs(29_200))
        #expect(try store.transaction(id: tea.id) == nil)
        let stillThere = try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM txn WHERE id = ? AND deleted_at IS NOT NULL", arguments: [tea.id.uuidString]) }
        #expect(stillThere == 1)
    }

    @Test("TXN-013 undo removes the row for good")
    func undo() throws {
        let (database, store) = try sampleDatabase()
        let snapshot = try store.snapshot()
        let draft = TransactionDraft(kind: .expense, amount: rs(640), accountID: account("Easypaisa", snapshot).id,
                                     categoryID: category("transport.ride_hailing", snapshot), payeeName: "Careem", occurredAt: date(6), timeZone: karachi)
        let saved = try TransactionValidator.build(draft, accounts: snapshot.accounts)
        try store.save(saved)
        try store.discard(transactionID: saved.id)
        let rows = try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM txn WHERE id = ?", arguments: [saved.id.uuidString]) }
        #expect(rows == 0)
        #expect(try store.snapshot().balance(of: account("Easypaisa", snapshot)) == rs(21_350))
    }

    @Test("TXN-012 a failing write saves nothing")
    func atomic() throws {
        let (_, store) = try sampleDatabase()
        let snapshot = try store.snapshot()
        let hbl = account("HBL", snapshot)
        // The second leg points at an account that does not exist, so the FK check fails mid-write.
        let broken = MoneyTransaction(kind: .transfer, occurredAt: date(6), localDate: LocalDate(date(6), in: karachi), timeZoneID: karachi.identifier,
                                 amount: rs(5_000), legs: [TransactionLeg(accountID: hbl.id, amount: rs(-5_000), role: .transferOut),
                                                           TransactionLeg(accountID: UUID(), amount: rs(5_000), role: .transferIn)])
        #expect(throws: (any Error).self) { try store.save(broken) }
        #expect(try store.transaction(id: broken.id) == nil)
        #expect(try store.snapshot().balance(of: hbl) == rs(182_400))
    }

    @Test("ACC-001 / ACC-005 / ACC-008 create, archive instead of delete, lock currency")
    func accountLifecycle() throws {
        let store = LedgerStore(database: try AppDatabase.inMemory())
        let bank = try store.createAccount(name: "Test Bank", kind: .bank, currency: .pkr, openingBalance: rs(10_000),
                                           openingDate: LocalDate(year: 2026, month: 10, day: 1))
        #expect(try store.snapshot().available == rs(10_000))
        #expect(throws: LedgerStore.Problem.duplicateName) {
            try store.createAccount(name: "test  bank", kind: .bank, currency: .pkr, openingDate: LocalDate(year: 2026, month: 10, day: 1))
        }
        let categories = try store.categories()
        let mobile = categories.first { $0.systemKey == "utilities.mobile" }!.id
        let draft = TransactionDraft(kind: .expense, amount: rs(1_500), accountID: bank.id, categoryID: mobile, occurredAt: date(2), timeZone: karachi)
        try store.save(try TransactionValidator.build(draft, accounts: try store.accounts()))
        #expect(throws: LedgerStore.Problem.accountHasTransactions) { try store.deleteAccount(id: bank.id) }
        var changed = bank
        changed.currency = .usd
        changed.openingBalance = .zero(.usd)
        #expect(throws: LedgerStore.Problem.currencyLocked) { try store.updateAccount(changed) }
        try store.setArchived(true, accountID: bank.id)
        let snapshot = try store.snapshot()
        #expect(snapshot.activeAccounts.isEmpty)
        #expect(snapshot.balance(of: account("Test Bank", snapshot)) == rs(8_500))
        #expect(try store.transactions().count == 1)
    }

    @Test("ACC-004 adjustment is a visible transaction in the system category")
    func adjustment() throws {
        let (_, store) = try sampleDatabase()
        let snapshot = try store.snapshot()
        let hbl = account("HBL", snapshot)
        let draft = TransactionDraft(kind: .adjustment, amount: rs(500), accountID: hbl.id, adjustmentIncreases: false, occurredAt: date(6), timeZone: karachi)
        try store.save(try TransactionValidator.build(draft, accounts: snapshot.accounts))
        let saved = try store.transactions().first { $0.kind == .adjustment }!
        #expect(snapshot.category(saved.categoryID)?.systemKey == DefaultCategories.adjustmentKey)
        #expect(try store.snapshot().balance(of: hbl) == rs(181_900))
    }

    @Test("DATA-002 / DATA-003 removing sample data keeps real rows")
    func removeSampleKeepsReal() throws {
        let (database, store) = try sampleDatabase()
        let real = try store.createAccount(name: "My Bank", kind: .bank, currency: .pkr, openingBalance: rs(1_000),
                                           openingDate: LocalDate(year: 2026, month: 10, day: 1))
        let food = try store.categories().first { $0.systemKey == "food.groceries" }!.id
        let draft = TransactionDraft(kind: .expense, amount: rs(100), accountID: real.id, categoryID: food, payeeName: "Imtiaz Super Market",
                                     occurredAt: date(6), timeZone: karachi)
        try store.save(try TransactionValidator.build(draft, accounts: try store.accounts()))
        try SampleDataService(database: database).removeAll()
        let snapshot = try store.snapshot()
        #expect(snapshot.accounts.map(\.name) == ["My Bank"])
        #expect(snapshot.available == rs(900))
        #expect(try store.transactions().count == 1)
        #expect(try store.categories().count > 60)
    }

    @Test("Default category tree is seeded once with stable keys")
    func categoriesSeeded() throws {
        let store = LedgerStore(database: try AppDatabase.inMemory())
        let snapshot = try store.snapshot()
        #expect(snapshot.categoryPath(category("transport.fuel", snapshot)) == "Transport › Fuel")
        #expect(snapshot.categoryPath(category("income.salary", snapshot)) == "Income › Salary")
        #expect(snapshot.categoryPath(category("income.reimbursement", snapshot)) == "Income › Reimbursement")
        #expect(snapshot.categories.contains { $0.systemKey == DefaultCategories.adjustmentKey })
    }
}
