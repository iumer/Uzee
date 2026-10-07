import Foundation
import Testing
@testable import UZeeCore

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }
private func day(_ m: Int, _ d: Int) -> LocalDate { LocalDate(year: 2026, month: m, day: d) }

/// M5 unit parts: split arithmetic, pairwise debts, loans, person/group/overall balances and
/// Simplify debts on the mockup dataset (TEST_REGISTRY §SPL, §LOAN).
@Suite("People, loans and splits")
struct PeopleTests {
    let me = UUID()
    let partner = UUID()
    let usama = UUID()
    let bilal = UUID()
    let ammi = UUID()
    let ali = UUID()
    let sara = UUID()
    let office = UUID()
    let hunza = UUID()
    let rates: [String: Decimal] = ["USD": 280]

    func txn(_ kind: TransactionKind, _ amount: Money, on date: LocalDate, leg: Int64? = nil,
             counterparty: UUID? = nil, group: UUID? = nil) -> MoneyTransaction {
        let legs = leg.map { [TransactionLeg(accountID: UUID(), amount: Money(minorUnits: $0, currency: amount.currency), role: .main)] } ?? []
        return MoneyTransaction(kind: kind, occurredAt: Date(), localDate: date, timeZoneID: "Asia/Karachi", amount: amount,
                                counterpartyID: counterparty, groupID: group, legs: legs)
    }

    func equalSplit(_ transaction: MoneyTransaction, paidBy payer: UUID, among people: [UUID], group: UUID?) throws -> Split {
        let shares = try SplitCalculator.shares(total: transaction.amount, method: .equal, participants: people, firstPayer: payer)
        return Split(transactionID: transaction.id, groupID: group, method: .equal,
                     payers: [SplitPayer(personID: payer, amount: transaction.amount)], shares: shares)
    }

    /// The dataset's people: October Office splits, Hunza trip, loans with Usama, Bilal and Ammi.
    func dataset() throws -> (transactions: [MoneyTransaction], splits: [Split], loans: [Loan]) {
        var transactions: [MoneyTransaction] = []
        var splits: [Split] = []
        func add(_ t: MoneyTransaction, payer: UUID, people: [UUID], group: UUID) throws {
            transactions.append(t)
            splits.append(try equalSplit(t, paidBy: payer, among: people, group: group))
        }
        let pair = [me, partner]
        try add(txn(.expense, rs(60_000), on: day(10, 1), leg: -6_000_000), payer: me, people: pair, group: office)
        try add(txn(.expense, rs(12_800), on: day(10, 5)), payer: partner, people: pair, group: office)
        try add(txn(.income, usd(25_000), on: day(10, 5), leg: 25_000), payer: me, people: pair, group: office)
        try add(txn(.expense, rs(3_200), on: day(10, 6), leg: -320_000), payer: me, people: pair, group: office)
        let trip = [me, ali, sara, bilal]
        try add(txn(.expense, rs(44_800), on: day(8, 12)), payer: ali, people: trip, group: hunza)
        try add(txn(.expense, rs(32_000), on: day(8, 13), leg: -3_200_000), payer: me, people: trip, group: hunza)
        transactions.append(txn(.settlement, rs(8_000), on: day(8, 20), leg: 800_000, counterparty: sara, group: hunza))
        transactions.append(txn(.settlement, rs(8_000), on: day(8, 20), leg: 800_000, counterparty: bilal, group: hunza))
        let lent1 = txn(.loanOut, rs(10_000), on: day(9, 2), leg: -1_000_000)
        let repay = txn(.repayment, rs(5_000), on: day(9, 20), leg: 500_000)
        let lent2 = txn(.loanOut, rs(20_000), on: day(10, 6), leg: -2_000_000)
        let lentBilal = txn(.loanOut, rs(10_000), on: day(9, 15), leg: -1_000_000)
        let borrowed = txn(.loanIn, rs(75_000), on: day(8, 1), leg: 7_500_000)
        transactions += [lent1, repay, lent2, lentBilal, borrowed]
        let loans = [
            Loan(direction: .lent, personID: usama, principal: rs(10_000), startDate: day(9, 2), transactionID: lent1.id,
                 payments: [LoanPayment(transactionID: repay.id, amount: rs(5_000), paidOn: day(9, 20))]),
            Loan(direction: .lent, personID: usama, principal: rs(20_000), startDate: day(10, 6), transactionID: lent2.id),
            Loan(direction: .lent, personID: bilal, principal: rs(10_000), startDate: day(9, 15), dueDate: day(10, 31), transactionID: lentBilal.id),
            Loan(direction: .borrowed, personID: ammi, principal: rs(75_000), startDate: day(8, 1), transactionID: borrowed.id)
        ]
        return (transactions, splits, loans)
    }

    func ledger(_ data: (transactions: [MoneyTransaction], splits: [Split], loans: [Loan])) -> PeopleLedger {
        PeopleLedger(selfID: me, transactions: data.transactions, splits: data.splits, loans: data.loans, base: .pkr, rates: rates)
    }

    @Test("SPL-001 equal split hands leftover paisa out in member order from the first payer")
    func equalRemainder() throws {
        let three = [me, ali, sara]
        let shares = try SplitCalculator.shares(total: Money(minorUnits: 10_000, currency: .pkr), method: .equal, participants: three)
        #expect(shares.map(\.share.minorUnits) == [3_334, 3_333, 3_333])
        let fromAli = try SplitCalculator.shares(total: Money(minorUnits: 10_001, currency: .pkr), method: .equal, participants: three, firstPayer: ali)
        #expect(fromAli.map(\.share.minorUnits) == [3_333, 3_334, 3_334])
    }

    @Test("SPL-002 percentages and shares always add up exactly")
    func percentAndShares() throws {
        let three = [me, ali, sara]
        let percent = try SplitCalculator.shares(total: Money(minorUnits: 100_001, currency: .pkr), method: .percent, participants: three,
                                                 inputs: [me: 3_333, ali: 3_333, sara: 3_334])
        #expect(percent.reduce(0) { $0 + $1.share.minorUnits } == 100_001)
        #expect(percent.map(\.input) == [3_333, 3_333, 3_334])
        let shares = try SplitCalculator.shares(total: rs(1_000), method: .shares, participants: [me, ali], inputs: [me: 2, ali: 1])
        #expect(shares.map(\.share) == [Money(minorUnits: 66_667, currency: .pkr), Money(minorUnits: 33_333, currency: .pkr)])
        #expect(throws: SplitProblem.percentNot100(remainingBasisPoints: 100)) {
            try SplitCalculator.shares(total: rs(1_000), method: .percent, participants: [me, ali], inputs: [me: 5_000, ali: 4_900])
        }
    }

    @Test("SPL-003 exact amounts must match the total before saving")
    func exact() throws {
        #expect(throws: SplitProblem.totalsDontMatch(remaining: rs(200))) {
            try SplitCalculator.shares(total: rs(1_000), method: .exact, participants: [me, ali], inputs: [me: 50_000, ali: 30_000])
        }
        let ok = try SplitCalculator.shares(total: rs(1_000), method: .exact, participants: [me, ali], inputs: [me: 70_000, ali: 30_000])
        let t = txn(.expense, rs(1_000), on: day(10, 6))
        let split = Split(transactionID: t.id, method: .exact, payers: [SplitPayer(personID: me, amount: rs(1_000))], shares: ok)
        try split.validate(total: rs(1_000))
        #expect(throws: SplitProblem.paidDoesNotMatch(remaining: rs(400))) {
            try Split(transactionID: t.id, method: .exact, payers: [SplitPayer(personID: me, amount: rs(600))], shares: ok).validate(total: rs(1_000))
        }
    }

    @Test("SPL-004 several payers: each person owes each payer in proportion, exact to the paisa")
    func severalPayers() throws {
        let t = txn(.expense, rs(900), on: day(10, 6))
        let shares = try SplitCalculator.shares(total: rs(900), method: .equal, participants: [me, ali, sara])
        let split = Split(transactionID: t.id, method: .equal,
                          payers: [SplitPayer(personID: me, amount: rs(600)), SplitPayer(personID: ali, amount: rs(300))], shares: shares)
        let debts = SplitCalculator.debts(split, isIncome: false)
        #expect(debts.contains(Debt(debtor: ali, creditor: me, amount: rs(200))))
        #expect(debts.contains(Debt(debtor: me, creditor: ali, amount: rs(100))))
        #expect(debts.contains(Debt(debtor: sara, creditor: me, amount: rs(200))))
        #expect(debts.contains(Debt(debtor: sara, creditor: ali, amount: rs(100))))
    }

    @Test("SPL-010 Office October: you owe Office partner Rs 9,800 (PKR +25,200 and −$125)")
    func officeGroup() throws {
        let people = ledger(try dataset())
        let group = people.group(office)
        #expect(group.withMe[partner]?.total(in: .pkr, rates: rates) == rs(-9_800))
        #expect(group.withMe[partner]?.parts(base: .pkr) == [rs(25_200), usd(-12_500)])
        #expect(people.net(of: partner) == rs(-9_800))
    }

    @Test("SPL-011 settling Rs 9,800 from HBL zeroes the Office balance")
    func settleOffice() throws {
        var data = try dataset()
        data.transactions.append(txn(.settlement, rs(9_800), on: day(10, 7), leg: -980_000, counterparty: partner, group: office))
        let people = ledger(data)
        #expect(people.net(of: partner).isZero)
        #expect(people.group(office).myNet.total(in: .pkr, rates: rates).isZero)
    }

    @Test("LOAN-001 Usama owes Rs 25,000, Bilal Rs 10,000, you owe Ammi Rs 75,000 and Ali Rs 3,200; Sara settled")
    func personBalances() throws {
        let people = ledger(try dataset())
        #expect(people.net(of: usama) == rs(25_000))
        #expect(people.net(of: bilal) == rs(10_000))
        #expect(people.net(of: ammi) == rs(-75_000))
        #expect(people.net(of: ali) == rs(-3_200))
        #expect(people.net(of: sara).isZero)
        #expect(people.balance(of: usama).shared.isZero)
    }

    @Test("SPL-012 overall: owed to you Rs 35,000, you owe Rs 88,000")
    func overall() throws {
        let overall = ledger(try dataset()).overall
        #expect(overall.owedToYou == rs(35_000))
        #expect(overall.youOwe == rs(88_000))
    }

    @Test("LOAN-003 deleting a repayment or a loan's transaction updates the balance")
    func deletedRows() throws {
        var data = try dataset()
        let repayment = data.transactions.firstIndex { $0.kind == .repayment }!
        data.transactions[repayment].deletedAt = Date()
        #expect(ledger(data).net(of: usama) == rs(30_000))
        let bilalLoan = data.loans.first { $0.personID == bilal }!.transactionID!
        data.transactions = data.transactions.filter { $0.id != bilalLoan }
        #expect(ledger(data).net(of: bilal).isZero)
    }

    @Test("LOAN-004 status, outstanding, over-repayment refused, write-off and interest")
    func loanStatus() throws {
        var loan = Loan(direction: .lent, personID: usama, principal: rs(10_000), startDate: day(9, 2))
        #expect(LoanCalculator.status(loan) == .open)
        loan.payments.append(LoanPayment(amount: rs(5_000), paidOn: day(9, 20)))
        #expect(LoanCalculator.status(loan) == .partiallyPaid)
        #expect(LoanCalculator.outstanding(loan) == rs(5_000))
        #expect(throws: LoanCalculator.Problem.moreThanOutstanding(outstanding: rs(5_000))) {
            try LoanCalculator.validatePayment(rs(5_001), for: loan)
        }
        loan.payments.append(LoanPayment(amount: rs(5_000), paidOn: day(9, 25)))
        #expect(LoanCalculator.status(loan) == .settled)
        var bad = Loan(direction: .borrowed, personID: ammi, principal: rs(100_000), startDate: day(1, 1), interestBasisPoints: 1_200)
        #expect(LoanCalculator.interest(bad, asOf: LocalDate(year: 2027, month: 1, day: 1)) == rs(12_000))
        bad.writtenOffAt = Date()
        #expect(LoanCalculator.status(bad) == .writtenOff)
        #expect(LoanCalculator.signedOutstanding(bad).isZero)
    }

    @Test("SPL-013 shared income: the receiver owes the others their share")
    func sharedIncome() throws {
        let t = txn(.income, usd(25_000), on: day(10, 5))
        let split = try equalSplit(t, paidBy: me, among: [me, partner], group: office)
        #expect(SplitCalculator.debts(split, isIncome: true) == [Debt(debtor: me, creditor: partner, amount: usd(12_500))])
    }

    @Test("SPL-014 Simplify debts in Hunza trip: nets preserved, at most n − 1 payments")
    func simplify() throws {
        let group = ledger(try dataset()).group(hunza)
        let nets = group.nets.mapValues { $0.total(in: .pkr, rates: rates) }
        #expect(nets[ali] == rs(25_600) && nets[me] == rs(-3_200) && nets[sara] == rs(-11_200) && nets[bilal] == rs(-11_200))
        let payments = DebtSimplifier.simplify(nets: nets, order: [me, ali, sara, bilal])
        #expect(payments.count == 3)
        #expect(payments.allSatisfy { $0.creditor == ali })
        #expect(payments.reduce(0) { $0 + $1.amount.minorUnits } == rs(25_600).minorUnits)
        #expect(group.withMe[ali]?.total(in: .pkr, rates: rates) == rs(-3_200))
    }

    @Test("LOAN-008 names are trimmed and required")
    func names() throws {
        #expect(try Person.validateName("  Usama ") == "Usama")
        #expect(throws: Person.Problem.emptyName) { try Person.validateName("   ") }
        #expect(Person(name: "office partner").initial == "O")
    }
}
