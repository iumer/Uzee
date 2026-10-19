import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func day(_ m: Int, _ d: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: d) }

/// LOAN and SPL integration tests on the sample dataset and on empty databases (TEST_REGISTRY §LOAN, §SPL).
@Suite("People store")
struct PeopleStoreTests {
    struct World {
        let database: AppDatabase
        let ledger: LedgerStore
        let people: PeopleStore
    }

    func sample() throws -> World {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        return World(database: database, ledger: LedgerStore(database: database), people: PeopleStore(database: database))
    }

    func empty() throws -> World {
        let database = try AppDatabase.inMemory()
        return World(database: database, ledger: LedgerStore(database: database), people: PeopleStore(database: database))
    }

    func balances(_ world: World) throws -> (PeopleLedger, PeopleStore.Snapshot) {
        let snapshot = try world.people.snapshot()
        let ledger = PeopleLedger(selfID: snapshot.selfID, transactions: try world.ledger.transactions(), splits: snapshot.splits,
                                  loans: snapshot.loans, base: .pkr, rates: try world.ledger.rates())
        return (ledger, snapshot)
    }

    func person(_ name: String, _ snapshot: PeopleStore.Snapshot) -> UUID { snapshot.people.first { $0.name == name }!.id }
    func group(_ name: String, _ snapshot: PeopleStore.Snapshot) -> UUID { snapshot.groups.first { $0.name == name }!.id }
    func account(_ name: String, _ world: World) throws -> UUID { try world.ledger.accounts().first { $0.name == name }!.id }

    @Test("SPL-015 sample: Owed to you Rs 35,000 · You owe Rs 88,000, every person as in the dataset")
    func sampleBalances() throws {
        let world = try sample()
        let (ledger, snapshot) = try balances(world)
        #expect(ledger.overall.owedToYou == rs(35_000))
        #expect(ledger.overall.youOwe == rs(88_000))
        let expected: [String: Int64] = ["Usama": 25_000, "Bilal": 10_000, "Sara": 0, "Ali": -3_200, "Office partner": -9_800, "Ammi": -75_000]
        for (name, value) in expected {
            #expect(ledger.net(of: person(name, snapshot)) == rs(value), "\(name)")
        }
        #expect(snapshot.people.filter(\.isSelf).count == 1)
        #expect(snapshot.groups.map(\.name) == ["Office", "Hunza trip", "Home groceries"])
        #expect(ledger.group(group("Home groceries", snapshot)).myNet.isZero)
    }

    @Test("SPL-016 splits keep October spending at Rs 78,374 and HBL at Rs 182,400")
    func spendingUnchanged() throws {
        let world = try sample()
        let october = try world.ledger.transactions(from: day(10, 1), through: day(10, 31))
        let spent = october.filter { SpendingRules.spendingSign($0.kind) == 1 }.reduce(Int64(0)) { total, txn in
            total + (try! RateTable.toBase(txn.myShare, base: .pkr, rates: ["USD": 280])).minorUnits
        }
        #expect(spent == 7_837_420)
        let snapshot = try world.ledger.snapshot()
        #expect(snapshot.balances[try account("HBL", world)] == rs(182_400))
        let electricity = october.first { $0.payeeName == "Office electricity · K-Electric" }!
        #expect(electricity.legs.isEmpty && electricity.myShare == rs(6_400))
    }

    @Test("SPL-017 settle up Rs 9,800 from HBL zeroes the Office balance and is not spending")
    func settleOffice() throws {
        let world = try sample()
        let (_, snapshot) = try balances(world)
        let partner = person("Office partner", snapshot)
        let office = group("Office", snapshot)
        let settlement = try world.people.settle(personID: partner, groupID: office, amount: rs(9_800), iPaid: true,
                                                 accountID: try account("HBL", world), on: day(10, 7))
        #expect(SpendingRules.spendingSign(settlement.kind) == 0)
        let (after, _) = try balances(world)
        #expect(after.net(of: partner).isZero)
        #expect(after.group(office).myNet.total(in: .pkr, rates: ["USD": 280]).isZero)
        #expect(try world.ledger.snapshot().balances[try account("HBL", world)] == rs(172_600))
    }

    @Test("LOAN-005 lend Usama Rs 20,000 from Easypaisa, he repays Rs 5,000: loan and transaction together")
    func lendAndRepay() throws {
        let world = try empty()
        let easypaisa = try world.ledger.createAccount(name: "Easypaisa", kind: .wallet, currency: .pkr, openingBalance: rs(50_000),
                                                       openingDate: day(10, 1))
        let usama = try world.people.createPerson(name: "Usama")
        let loan = try world.people.recordLoan(direction: .lent, personID: usama.id, amount: rs(20_000), accountID: easypaisa.id, on: day(10, 6))
        try world.people.recordRepayment(loanID: loan.id, amount: rs(5_000), accountID: easypaisa.id, on: day(10, 7))
        let (ledger, snapshot) = try balances(world)
        #expect(ledger.net(of: usama.id) == rs(15_000))
        #expect(LoanCalculator.status(snapshot.loans[0]) == .partiallyPaid)
        #expect(try world.ledger.snapshot().balances[easypaisa.id] == rs(35_000))
        #expect(throws: LoanCalculator.Problem.moreThanOutstanding(outstanding: rs(15_000))) {
            try world.people.recordRepayment(loanID: loan.id, amount: rs(15_001), accountID: easypaisa.id, on: day(10, 8))
        }
        // Deleting the lend transaction takes the loan with it; restoring brings it back.
        let lend = try world.ledger.transactions().first { $0.kind == .loanOut }!
        try world.ledger.delete(transactionID: lend.id)
        #expect(try world.people.snapshot().loans.isEmpty)
        try world.ledger.restore(transactionID: lend.id)
        #expect(try balances(world).0.net(of: usama.id) == rs(15_000))
    }

    @Test("Notes on a shared expense: add, list oldest first, delete; empty refused")
    func entryNotes() throws {
        let world = try empty()
        let cash = try world.ledger.createAccount(name: "Cash", kind: .cash, currency: .pkr, openingBalance: rs(60_000), openingDate: day(10, 1))
        let friend = try world.people.createPerson(name: "Test Friend")
        let me = try world.people.selfID()
        let expense = MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: day(10, 5), timeZoneID: "Asia/Karachi",
                                       amount: rs(50_000), payeeName: "Car repair",
                                       legs: [TransactionLeg(accountID: cash.id, amount: rs(-50_000), role: .main)])
        let split = Split(transactionID: expense.id, method: .equal, payers: [SplitPayer(personID: me, amount: rs(50_000))],
                          shares: [SplitShare(personID: me, share: rs(25_000)), SplitShare(personID: friend.id, share: rs(25_000))])
        try world.people.save(expense, split: split)
        let first = try world.people.addEntryNote("Paid at the workshop", transactionID: expense.id, at: Date(timeIntervalSince1970: 1_790_000_000))
        try world.people.addEntryNote("Half back next week", transactionID: expense.id, at: Date(timeIntervalSince1970: 1_790_000_100))
        #expect(try world.people.entryNotes(transactionID: expense.id).map(\.text) == ["Paid at the workshop", "Half back next week"])
        try world.people.deleteEntryNote(first.id)
        #expect(try world.people.entryNotes(transactionID: expense.id).map(\.text) == ["Half back next week"])
        #expect(throws: PeopleStore.Problem.emptyNote) { try world.people.addEntryNote("  ", transactionID: expense.id) }
        #expect(throws: PeopleStore.Problem.notFound) { try world.people.addEntryNote("x", transactionID: UUID()) }
    }

    @Test("LOAN-009 a debt kept as a record: I owe Ammi Rs 150,000, pay Rs 50,000 outside my accounts, Rs 100,000 left")
    func debtPaidDownWithoutAccount() throws {
        let world = try empty()
        let ammi = try world.people.createPerson(name: "Ammi")
        let loan = try world.people.recordLoan(direction: .borrowed, personID: ammi.id, amount: rs(150_000), accountID: nil, on: day(10, 1))
        let transaction = try world.people.recordRepayment(loanID: loan.id, amount: rs(50_000), accountID: nil, on: day(10, 8))
        #expect(transaction == nil)
        let (ledger, snapshot) = try balances(world)
        #expect(ledger.net(of: ammi.id) == Money(minorUnits: -rs(100_000).minorUnits, currency: .pkr))
        #expect(LoanCalculator.outstanding(snapshot.loans[0]) == rs(100_000))
        #expect(try world.ledger.transactions().isEmpty)
    }

    @Test("Notes on a loan, oldest first, with their time; deleted ones go")
    func loanNotes() throws {
        let world = try empty()
        let other = try world.people.createPerson(name: "Other Person")
        let loan = try world.people.recordLoan(direction: .borrowed, personID: other.id, amount: rs(150_000), accountID: nil, on: day(10, 1))
        let first = try world.people.addNote("Pay back by Eid", loanID: loan.id, at: Date(timeIntervalSince1970: 1_790_000_000))
        try world.people.addNote("  Paid 20k in cash, more next month  ", loanID: loan.id, at: Date(timeIntervalSince1970: 1_790_100_000))
        #expect(throws: PeopleStore.Problem.emptyNote) { try world.people.addNote("   ", loanID: loan.id) }
        var saved = try world.people.snapshot().loans[0]
        #expect(saved.noteLog.map(\.text) == ["Pay back by Eid", "Paid 20k in cash, more next month"])
        #expect(saved.noteLog[0].createdAt == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(saved.createdAt != nil)
        try world.people.deleteNote(first.id)
        saved = try world.people.snapshot().loans[0]
        #expect(saved.noteLog.map(\.text) == ["Paid 20k in cash, more next month"])
    }

    @Test("LOAN-008 existing balances: no money moves, matching names add up, write-off zeroes")
    func existingBalances() throws {
        let world = try empty()
        let ammi = try world.people.createPerson(name: "Ammi")
        try world.people.addExistingBalances([("ammi", .borrowed, rs(75_000)), ("Bilal", .lent, rs(10_000))], on: day(10, 1))
        let (ledger, snapshot) = try balances(world)
        #expect(ledger.net(of: ammi.id) == rs(-75_000))
        #expect(ledger.net(of: person("Bilal", snapshot)) == rs(10_000))
        #expect(try world.ledger.transactions().isEmpty)
        try world.people.setWrittenOff(true, loanID: snapshot.loans.first { $0.personID == ammi.id }!.id)
        #expect(try balances(world).0.net(of: ammi.id).isZero)
    }

    @Test("SPL-018 an expense someone else paid moves no account money; I owe the payer my share")
    func paidBySomeoneElse() throws {
        let world = try empty()
        let hbl = try world.ledger.createAccount(name: "HBL", kind: .bank, currency: .pkr, openingBalance: rs(100_000), openingDate: day(10, 1))
        let partner = try world.people.createPerson(name: "Office partner")
        let office = try world.people.createGroup(name: "Office", icon: .office, memberIDs: [partner.id])
        let me = try world.people.selfID()
        #expect(office.memberIDs == [me, partner.id])
        let category = try world.ledger.categories().first { $0.systemKey == "office.office_utilities" }!.id
        let bill = MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: day(10, 5), timeZoneID: "Asia/Karachi", amount: rs(12_800),
                                    categoryID: category, payeeName: "K-Electric",
                                    legs: [TransactionLeg(accountID: hbl.id, amount: rs(-12_800), role: .main)])
        let shares = try SplitCalculator.shares(total: rs(12_800), method: .equal, participants: office.memberIDs, firstPayer: partner.id)
        try world.people.save(bill, split: Split(transactionID: bill.id, groupID: office.id, method: .equal,
                                                 payers: [SplitPayer(personID: partner.id, amount: rs(12_800))], shares: shares))
        let saved = try world.ledger.transaction(id: bill.id)!
        #expect(saved.legs.isEmpty && saved.myShare == rs(6_400))
        #expect(try world.ledger.snapshot().balances[hbl.id] == rs(100_000))
        #expect(try balances(world).0.net(of: partner.id) == rs(-6_400))
        // A split that doesn't add up is refused and nothing changes.
        let bad = Split(transactionID: bill.id, groupID: office.id, method: .exact, payers: [SplitPayer(personID: me, amount: rs(12_800))],
                        shares: [SplitShare(personID: me, input: 500_000, share: rs(5_000))])
        #expect(throws: SplitProblem.self) { try world.people.save(bill, split: bad) }
        #expect(try world.ledger.transaction(id: bill.id)!.myShare == rs(6_400))
    }

    @Test("DATA-003 removing sample data removes sample people and groups but keeps You")
    func removeSample() throws {
        let world = try sample()
        try SampleDataService(database: world.database).removeAll()
        let snapshot = try world.people.snapshot()
        #expect(snapshot.people.map(\.name) == ["You"])
        #expect(snapshot.groups.isEmpty && snapshot.splits.isEmpty && snapshot.loans.isEmpty)
    }

    @Test("BUG-026: settling up with Usama pays off his open loans, oldest first, and he's settled everywhere")
    func settleClosesLoans() throws {
        let world = try sample()
        var (ledger, snapshot) = try balances(world)
        let usama = person("Usama", snapshot)
        #expect(ledger.net(of: usama) == rs(25_000))
        try world.people.settle(personID: usama, groupID: nil, amount: rs(25_000), iPaid: false, accountID: try account("HBL", world), on: day(10, 12))
        (ledger, snapshot) = try balances(world)
        #expect(ledger.net(of: usama) == rs(0))
        #expect(ledger.balance(of: usama).loans.isZero)
        let open = snapshot.loans.filter { $0.personID == usama && !LoanCalculator.outstanding($0).isZero }
        #expect(open.isEmpty)
        #expect(ledger.overall.owedToYou == rs(10_000))
    }

    @Test("BUG-026: a settle-up bigger than the loans pays them off and the rest settles shared expenses")
    func settleMoreThanLoans() throws {
        let world = try empty()
        let friend = try world.people.createPerson(name: "Test Friend")
        let cash = try world.ledger.createAccount(name: "Cash", kind: .cash, currency: .pkr, openingBalance: rs(100_000), openingDate: day(9, 1))
        _ = try world.people.recordLoan(direction: .lent, personID: friend.id, amount: rs(3_000), accountID: cash.id, on: day(10, 1))
        try world.people.settle(personID: friend.id, groupID: nil, amount: rs(5_000), iPaid: false, accountID: cash.id, on: day(10, 2))
        let (ledger, snapshot) = try balances(world)
        #expect(snapshot.loans.allSatisfy { LoanCalculator.outstanding($0).isZero })
        #expect(ledger.balance(of: friend.id).shared.total(in: .pkr, rates: [:]) == rs(-2_000))
        #expect(ledger.net(of: friend.id) == rs(-2_000))
    }

    @Test("Renaming a person renames their loans, repayments and settle-ups in Activity, and nothing else")
    func renameReachesActivity() throws {
        let world = try empty()
        let person = try world.people.createPerson(name: "Tset User")
        let cash = try world.ledger.createAccount(name: "Cash", kind: .cash, currency: .pkr, openingBalance: rs(100_000), openingDate: day(9, 1))
        let lent = try world.people.recordLoan(direction: .lent, personID: person.id, amount: rs(5_000), accountID: cash.id, on: day(10, 1))
        let borrowed = try world.people.recordLoan(direction: .borrowed, personID: person.id, amount: rs(2_000), accountID: cash.id,
                                                   on: day(10, 2), note: "Cash for rent")
        let repaid = try world.people.recordRepayment(loanID: lent.id, amount: rs(1_000), accountID: cash.id, on: day(10, 3))!
        let paid = try world.people.settle(personID: person.id, groupID: nil, amount: rs(500), iPaid: true, accountID: cash.id, on: day(10, 4))
        let gotPaid = try world.people.settle(personID: person.id, groupID: nil, amount: rs(500), iPaid: false, accountID: cash.id, on: day(10, 4))
        let expense = MoneyTransaction(kind: .expense, occurredAt: Date(), localDate: day(10, 5), timeZoneID: "Asia/Karachi", amount: rs(300),
                                       payeeName: "Tset User", legs: [TransactionLeg(accountID: cash.id, amount: rs(-300), role: .main)])
        try world.ledger.save(expense)
        try world.ledger.delete(transactionID: gotPaid.id)
        #expect(try world.ledger.transaction(id: lent.transactionID!)?.note == "Lent to Tset User")

        var renamed = person
        renamed.name = "Test User"
        try world.people.updatePerson(renamed)

        func saved(_ id: UUID) throws -> MoneyTransaction { try world.ledger.transaction(id: id)! }
        func storedPayee(_ id: UUID) throws -> String? {
            try world.database.writer.read { db in
                try String.fetchOne(db, sql: "SELECT p.name FROM txn t JOIN payee p ON p.id = t.payee_id WHERE t.id = ?",
                                    arguments: [id.uuidString])
            }
        }
        #expect(try saved(lent.transactionID!).payeeName == "Test User")
        #expect(try saved(lent.transactionID!).note == "Lent to Test User")
        #expect(try storedPayee(lent.transactionID!) == "Test User")
        #expect(try saved(borrowed.transactionID!).payeeName == "Test User")
        #expect(try saved(borrowed.transactionID!).note == "Cash for rent")
        #expect(try saved(repaid.id).note == "Test User repaid")
        #expect(try saved(paid.id).note == "You paid Test User")
        let deleted = try world.ledger.deletedTransactions().first { $0.id == gotPaid.id }
        #expect(deleted?.payeeName == "Test User")
        #expect(deleted?.note == "Test User paid you")
        #expect(try saved(expense.id).payeeName == "Tset User")
        #expect(try storedPayee(expense.id) == "Tset User")
    }

    @Test("A rename only rewrites notes the app wrote")
    func generatedNotes() {
        #expect(PeopleStore.renamedGeneratedNote("Borrowed from Tset User", old: "Tset User", new: "Test User") == "Borrowed from Test User")
        #expect(PeopleStore.renamedGeneratedNote("Repaid Tset User", old: "Tset User", new: "Test User") == "Repaid Test User")
        #expect(PeopleStore.renamedGeneratedNote("Lent to Tset User for rent", old: "Tset User", new: "Test User") == nil)
        #expect(PeopleStore.renamedGeneratedNote("Lent to Other Person", old: "Tset User", new: "Test User") == nil)
    }
}
