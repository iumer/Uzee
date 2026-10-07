import Foundation
import Testing
@testable import UZeeCore

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
private func usd(cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }
private let rates: [String: Decimal] = ["USD": 280]

/// CUR-001…012 unit parts (docs/TEST_REGISTRY.md §4). Values from docs/mockup-dataset.md.
@Suite("Money engine")
struct MoneyEngineTests {
    @Test("CUR-001 same-currency addition is exact")
    func addition() throws {
        #expect(try Money(minorUnits: 10, currency: .pkr).adding(Money(minorUnits: 20, currency: .pkr)).minorUnits == 30)
        let cents = Array(repeating: Money(minorUnits: 1, currency: .pkr), count: 1_000)
        #expect(try Money.sum(cents, in: .pkr) == rs(10))
        let october = [rs(38_000), rs(16_367), rs(15_470), rs(6_200), rs(1_500), Money(minorUnits: 83_720, currency: .pkr)]
        let total = try Money.sum(october, in: .pkr)
        #expect(total.minorUnits == 7_837_420)
        #expect(MoneyFormatter.string(total) == "Rs 78,374")
    }

    @Test("CUR-002 subtraction and negative results")
    func subtraction() throws {
        let over = try rs(5_000).subtracting(rs(6_200))
        #expect(over == rs(-1_200))
        #expect(MoneyFormatter.string(over) == "\u{2212}Rs 1,200")
        let left = try rs(235_000).subtracting(Money(minorUnits: 7_837_420, currency: .pkr))
        #expect(left.minorUnits == 15_662_580)
        #expect(MoneyFormatter.string(left) == "Rs 156,626")
    }

    @Test("CUR-003 mixed-currency arithmetic refused")
    func mismatch() {
        #expect(throws: MoneyError.currencyMismatch) { try rs(100).adding(usd(cents: 100)) }
        #expect(throws: MoneyError.currencyMismatch) { try rs(100).compare(usd(cents: 100)) }
    }

    @Test("CUR-004 conversion at the table rate")
    func conversion() throws {
        let cases: [(Int64, Int64)] = [(299, 83_720), (2_000, 560_000), (52_000, 14_560_000), (66_000, 18_480_000)]
        for (cents, paisa) in cases {
            #expect(try CurrencyConverter.convertChecked(usd(cents: cents), to: .pkr, rate: 280).minorUnits == paisa)
        }
    }

    @Test("CUR-005 half-up rounding in one place")
    func rounding() throws {
        func d(_ text: String) -> Decimal { Decimal(string: text)! }
        #expect(Rounding.halfUp(d("2.78705"), scale: 2) == d("2.79"))
        #expect(Rounding.halfUp(d("2.785"), scale: 2) == d("2.79"))
        #expect(Rounding.halfUp(d("2.78499"), scale: 2) == d("2.78"))
        #expect(Rounding.halfUp(d("-2.785"), scale: 2) == d("-2.79"))
        #expect(try CurrencyConverter.convertChecked(usd(cents: 1), to: .pkr, rate: d("278.705")).minorUnits == 279)
    }

    @Test("CUR-006 currency formatting")
    func formatting() {
        #expect(MoneyFormatter.string(rs(182_400)) == "Rs 182,400")
        #expect(MoneyFormatter.string(usd(cents: 52_000)) == "$520.00")
        #expect(MoneyFormatter.string(rs(-14_517)) == "\u{2212}Rs 14,517")
        #expect(MoneyFormatter.string(rs(0)) == "Rs 0")
        #expect(MoneyFormatter.string(usd(cents: 299)) == "$2.99")
        #expect(MoneyFormatter.approximate(usd(cents: 299), in: .pkr, rate: 280) == "≈ Rs 837")
        #expect(MoneyFormatter.string(rs(1_000_000)) == "Rs 1,000,000")
    }

    @Test("CUR-007 large amounts and overflow")
    func overflow() throws {
        let big = Money(minorUnits: 999_999_999_999, currency: .pkr)
        #expect(try big.adding(Money(minorUnits: 1, currency: .pkr)) == rs(10_000_000_000))
        let many = Array(repeating: rs(99_999_999), count: 10_000)
        #expect(try Money.sum(many, in: .pkr) == rs(999_999_990_000))
        let max = Money(minorUnits: .max, currency: .pkr)
        #expect(throws: MoneyError.overflow) { try max.adding(Money(minorUnits: 1, currency: .pkr)) }
    }

    @Test("CUR-008 zero values")
    func zero() throws {
        #expect(try rs(0).adding(rs(182_400)) == rs(182_400))
        #expect(MoneyFormatter.string(rs(0)) == "Rs 0")
        #expect(MoneyFormatter.string(usd(cents: 0)) == "$0.00")
    }

    @Test("CUR-009 transfer stores its own implied rate")
    func transferRate() throws {
        let rate = try TransferRate(foreign: usd(cents: 50_000), base: rs(139_350), tableRate: 280)
        #expect(rate.rate == Decimal(string: "278.70")!)
        #expect(ExchangeRate.display(rate.rate) == "278.70")
        #expect(try CurrencyConverter.convertChecked(usd(cents: 50_000), to: .pkr, rate: rate.rate) == rs(139_350))
        #expect(rate.differenceFromTable == rs(-650))
    }

    @Test("CUR-011 PKR totals include USD at the table rate, with footnote")
    func available() throws {
        let accounts = SampleAccounts.make()
        let balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) })
        #expect(try BalanceCalculator.available(accounts: accounts, balances: balances, base: .pkr, rates: rates) == rs(484_800))
        #expect(RateTable.footnote(for: Set(accounts.map(\.currency)), base: .pkr, rates: rates) == "USD at $1 = Rs 280")
    }

    @Test("CUR-010 a new table rate changes totals, not stored transfers")
    func rateChange() throws {
        let accounts = SampleAccounts.make()
        let balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) })
        #expect(try BalanceCalculator.available(accounts: accounts, balances: balances, base: .pkr, rates: ["USD": 285]) == rs(488_100))
        #expect(MoneyFormatter.approximate(usd(cents: 52_000), in: .pkr, rate: 285) == "≈ Rs 148,200")
    }

    @Test("CUR-012 exchange-rate validation")
    func rateValidation() throws {
        #expect(throws: ExchangeRate.Failure.notPositive) { try ExchangeRate.parseRate("0") }
        #expect(throws: ExchangeRate.Failure.notPositive) { try ExchangeRate.parseRate("-280") }
        #expect(throws: ExchangeRate.Failure.empty) { try ExchangeRate.parseRate("") }
        #expect(throws: ExchangeRate.Failure.notANumber) { try ExchangeRate.parseRate("abc") }
        #expect(throws: ExchangeRate.Failure.notANumber) { try ExchangeRate.parseRate("12abc") }
        #expect(try ExchangeRate.parseRate("278.705") == Decimal(string: "278.705")!)
        #expect(try ExchangeRate.parseRate("280") == 280)
        #expect(ExchangeRate.storageString(Decimal(string: "278.705")!) == "278.705")
    }

    @Test("Amount input is exact and refuses bad text")
    func amountParser() throws {
        #expect(try AmountParser.parse("1,500", currency: .pkr) == rs(1_500))
        #expect(try AmountParser.parse("2.99", currency: .usd) == usd(cents: 299))
        #expect(try AmountParser.parse(".5", currency: .usd) == usd(cents: 50))
        #expect(try AmountParser.parse("0", currency: .pkr) == rs(0))
        #expect(throws: AmountParser.Failure.empty) { try AmountParser.parse("  ", currency: .pkr) }
        #expect(throws: AmountParser.Failure.notANumber) { try AmountParser.parse("abc", currency: .pkr) }
        #expect(throws: AmountParser.Failure.tooManyDecimals(allowed: 2)) { try AmountParser.parse("1.005", currency: .pkr) }
        #expect(throws: AmountParser.Failure.tooLarge) { try AmountParser.parse("1234567890123", currency: .pkr) }
        #expect(try AmountParser.parse("999999999999", currency: .pkr) == rs(999_999_999_999))
        #expect(throws: AmountParser.Failure.negative) { try AmountParser.parse("-5", currency: .pkr) }
    }
}

/// ACC unit parts and TXN-001…015 core rules.
@Suite("Accounts and transactions")
struct TransactionEngineTests {
    let karachi = TimeZone(identifier: "Asia/Karachi")!
    let accounts = SampleAccounts.make()
    var hbl: Account { accounts.first { $0.name == "HBL" }! }
    var cash: Account { accounts.first { $0.name == "Cash" }! }
    var wise: Account { accounts.first { $0.name == "Wise" }! }
    let category = UUID()

    func date(_ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = karachi
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func save(_ draft: TransactionDraft) throws -> MoneyTransaction {
        try TransactionValidator.build(draft, accounts: accounts, now: date(6))
    }

    @Test("ACC-002 balance = opening + posted transactions")
    func balance() throws {
        let expense = try save(TransactionDraft(kind: .expense, amount: rs(1_500), accountID: hbl.id, categoryID: category, occurredAt: date(6), timeZone: karachi))
        let income = try save(TransactionDraft(kind: .income, amount: rs(5_000), accountID: hbl.id, categoryID: category, occurredAt: date(6), timeZone: karachi))
        let transfer = try save(TransactionDraft(kind: .transfer, amount: rs(2_000), accountID: hbl.id, toAccountID: cash.id, occurredAt: date(6), timeZone: karachi))
        let all = [expense, income, transfer]
        #expect(try BalanceCalculator.balance(of: hbl, transactions: all) == rs(182_400 - 1_500 + 5_000 - 2_000))
        #expect(try BalanceCalculator.balance(of: cash, transactions: all) == rs(28_000))
    }

    @Test("ACC-003 pending is excluded until posted")
    func pending() throws {
        var pending = try save(TransactionDraft(kind: .expense, status: .pending, amount: rs(3_000), accountID: hbl.id, categoryID: category, occurredAt: date(6), timeZone: karachi))
        #expect(try BalanceCalculator.balance(of: hbl, transactions: [pending]) == rs(182_400))
        pending.status = .posted
        #expect(try BalanceCalculator.balance(of: hbl, transactions: [pending]) == rs(179_400))
    }

    @Test("ACC-004 adjustment moves the balance and is not spending")
    func adjustment() throws {
        let adjustment = try save(TransactionDraft(kind: .adjustment, amount: rs(500), accountID: hbl.id, adjustmentIncreases: false, occurredAt: date(6), timeZone: karachi))
        #expect(try BalanceCalculator.balance(of: hbl, transactions: [adjustment]) == rs(181_900))
        let totals = try PeriodTotals.compute([adjustment], from: LocalDate(year: 2026, month: 10, day: 1), through: LocalDate(year: 2026, month: 10, day: 31), base: .pkr, rates: rates)
        #expect(totals == PeriodTotals(spending: rs(0), income: rs(0)))
    }

    @Test("ACC-006 include-in-totals flag")
    func includeInTotals() throws {
        var accounts = SampleAccounts.make()
        let index = accounts.firstIndex { $0.name == "Fasset" }!
        accounts[index].includeInTotals = false
        let balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) })
        #expect(try BalanceCalculator.available(accounts: accounts, balances: balances, base: .pkr, rates: rates) == rs(458_200))
    }

    @Test("ACC-008 account name validation")
    func accountNames() throws {
        #expect(throws: Account.Problem.emptyName) { try Account.validateName("  ", existingNames: []) }
        #expect(throws: Account.Problem.duplicateName) { try Account.validateName(" hbl ", existingNames: ["HBL"]) }
        #expect(try Account.validateName("Test Bank", existingNames: ["HBL"]) == "Test Bank")
        #expect(throws: AmountParser.Failure.tooManyDecimals(allowed: 2)) { try AmountParser.parse("10.123", currency: .usd) }
    }

    @Test("TXN-003/015 transfers are not income or spending")
    func transferNeutral() throws {
        let transfer = try save(TransactionDraft(kind: .transfer, amount: rs(5_000), accountID: hbl.id, toAccountID: cash.id, occurredAt: date(6), timeZone: karachi))
        #expect(transfer.legs.map(\.amount) == [rs(-5_000), rs(5_000)])
        #expect(transfer.fxRate == nil)
        let totals = try PeriodTotals.compute([transfer], from: LocalDate(year: 2026, month: 10, day: 1), through: LocalDate(year: 2026, month: 10, day: 31), base: .pkr, rates: rates)
        #expect(totals.spending == rs(0) && totals.income == rs(0))
    }

    @Test("TXN-004 cross-currency transfer stores the real rate")
    func crossCurrency() throws {
        let transfer = try save(TransactionDraft(kind: .transfer, amount: usd(cents: 50_000), accountID: wise.id, toAccountID: hbl.id, receivedAmount: rs(139_350), occurredAt: date(5), timeZone: karachi))
        #expect(transfer.fxRate == Decimal(string: "278.7")!)
        #expect(transfer.legs.map(\.amount) == [usd(cents: -50_000), rs(139_350)])
        let balances = try BalanceCalculator.balances(of: accounts, transactions: [transfer])
        #expect(balances[wise.id] == usd(cents: 2_000))
        let before = try BalanceCalculator.available(accounts: accounts, balances: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.openingBalance) }), base: .pkr, rates: rates)
        let after = try BalanceCalculator.available(accounts: accounts, balances: balances, base: .pkr, rates: rates)
        #expect(try before.subtracting(after) == rs(650))
    }

    @Test("TXN-005 refund reduces spending, not income")
    func refund() throws {
        let food = try save(TransactionDraft(kind: .expense, amount: rs(2_180), accountID: hbl.id, categoryID: category, occurredAt: date(2), timeZone: karachi))
        let refund = try save(TransactionDraft(kind: .refund, amount: rs(500), accountID: hbl.id, categoryID: category, occurredAt: date(6), timeZone: karachi))
        let totals = try PeriodTotals.compute([food, refund], from: LocalDate(year: 2026, month: 10, day: 1), through: LocalDate(year: 2026, month: 10, day: 31), base: .pkr, rates: rates)
        #expect(totals.spending == rs(1_680))
        #expect(totals.income == rs(0))
    }

    @Test("TXN-008 deleted rows leave balances and totals")
    func softDelete() throws {
        var entry = try save(TransactionDraft(kind: .expense, amount: rs(100), accountID: cash.id, categoryID: category, occurredAt: date(1), timeZone: karachi))
        entry.deletedAt = date(6)
        #expect(try BalanceCalculator.balance(of: cash, transactions: [entry]) == rs(26_000))
    }

    @Test("TXN-009 invalid input refused, each with its own reason")
    func invalid() {
        func problem(_ draft: TransactionDraft) -> TransactionProblem? {
            do { _ = try save(draft); return nil } catch { return error as? TransactionProblem }
        }
        #expect(problem(TransactionDraft(kind: .expense, amount: rs(0), accountID: hbl.id, categoryID: category)) == .zeroAmount)
        #expect(problem(TransactionDraft(kind: .expense, amount: nil, accountID: hbl.id, categoryID: category)) == .missingAmount)
        #expect(problem(TransactionDraft(kind: .expense, amount: rs(10), accountID: nil, categoryID: category)) == .missingAccount)
        #expect(problem(TransactionDraft(kind: .expense, amount: rs(10), accountID: hbl.id)) == .missingCategory)
        #expect(problem(TransactionDraft(kind: .transfer, amount: rs(10), accountID: hbl.id, toAccountID: hbl.id)) == .sameAccount)
        #expect(problem(TransactionDraft(kind: .transfer, amount: usd(cents: 100), accountID: wise.id, toAccountID: hbl.id)) == .missingReceivedAmount)
        #expect(problem(TransactionDraft(kind: .transfer, amount: usd(cents: 100), accountID: wise.id, toAccountID: hbl.id, receivedAmount: rs(0))) == .zeroReceivedAmount)
        #expect(problem(TransactionDraft(kind: .expense, amount: usd(cents: 100), accountID: hbl.id, categoryID: category)) == .currencyDiffersFromAccount)
    }

    @Test("TXN-011 month bucketing uses the recorded time zone")
    func timeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = karachi
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23, minute: 30))!
        let entry = try save(TransactionDraft(kind: .expense, amount: rs(100), accountID: hbl.id, categoryID: category, occurredAt: late, timeZone: karachi))
        #expect(entry.localDate.description == "2026-10-31")
        #expect(entry.timeZoneID == "Asia/Karachi")
        #expect(late.timeIntervalSince1970 == 1_793_471_400)
    }

    @Test("TXN-006/014 edit keeps id and createdAt; repeat reuses the draft")
    func editAndRepeat() throws {
        let original = try save(TransactionDraft(kind: .expense, amount: rs(1_500), accountID: hbl.id, categoryID: category, payeeName: "Jazz postpaid", occurredAt: date(2), timeZone: karachi))
        var draft = TransactionValidator.draft(from: original)
        let meezan = accounts.first { $0.name == "Meezan" }!
        draft.accountID = meezan.id
        let edited = try TransactionValidator.build(draft, accounts: accounts, existing: original, now: date(6, hour: 18))
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.updatedAt > original.updatedAt)
        #expect(edited.legs == [TransactionLeg(accountID: meezan.id, amount: rs(-1_500), role: .main)])
        #expect(draft.payeeName == "Jazz postpaid")
    }
}

/// The nine dataset accounts with today's balances as opening balances (unit tests only;
/// the real sample fixture derives balances from transactions, ACC-007).
enum SampleAccounts {
    static func make() -> [Account] {
        let day = LocalDate(year: 2026, month: 10, day: 1)
        let rows: [(String, AccountKind, Money)] = [
            ("HBL", .bank, rs(182_400)), ("Meezan", .bank, rs(48_000)), ("Cash", .cash, rs(26_000)),
            ("Easypaisa", .wallet, rs(21_350)), ("SadaPay", .wallet, rs(12_450)), ("NayaPay", .wallet, rs(9_800)),
            ("Wise", .multiCurrency, usd(cents: 52_000)), ("Fasset", .cryptoFiat, usd(cents: 9_500)),
            ("RedotPay", .cryptoFiat, usd(cents: 4_500))
        ]
        return rows.enumerated().map { index, row in
            Account(name: row.0, kind: row.1, currency: row.2.currency, openingBalance: row.2, openingDate: day, sortOrder: index)
        }
    }
}
