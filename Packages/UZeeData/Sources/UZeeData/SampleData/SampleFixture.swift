import Foundation
import GRDB
import UZeeCore

/// The mockup dataset (docs/mockup-dataset.md) as sample rows. Opening balances are as of 30 Sep and
/// the October transactions bring each account to the dataset balance, so balances stay derived (ACC-007).
enum SampleFixture {
    static let timeZone = TimeZone(identifier: "Asia/Karachi")!

    struct AccountSeed {
        let name: String
        let kind: AccountKind
        let opening: Money
        let colorHex: String
    }

    static func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }
    static func usd(_ cents: Int64) -> Money { Money(minorUnits: cents, currency: .usd) }

    /// Opening = dataset balance − October movement (see the transactions below).
    static let accounts: [AccountSeed] = [
        // HBL also receives the 30 Sep Office settle-up (Rs 24,000), dated on the opening day.
        AccountSeed(name: "HBL", kind: .bank, opening: rs(95_067), colorHex: "#007A3D"),         // → Rs 182,400
        AccountSeed(name: "Meezan", kind: .bank, opening: rs(54_200), colorHex: "#6A1B9A"),      // → Rs 48,000
        AccountSeed(name: "Cash", kind: .cash, opening: rs(29_200), colorHex: "#34C759"),        // → Rs 26,000
        AccountSeed(name: "Easypaisa", kind: .wallet, opening: rs(43_200), colorHex: "#2E7D32"), // → Rs 21,350
        AccountSeed(name: "SadaPay", kind: .wallet, opening: rs(18_980), colorHex: "#00BFA5"),   // → Rs 12,450
        AccountSeed(name: "NayaPay", kind: .wallet, opening: rs(18_740), colorHex: "#FF6D00"),   // → Rs 9,800
        AccountSeed(name: "Wise", kind: .multiCurrency, opening: usd(77_299), colorHex: "#9FE870"), // → $520.00
        AccountSeed(name: "Fasset", kind: .cryptoFiat, opening: usd(9_500), colorHex: "#1E88E5"),   // → $95.00
        AccountSeed(name: "RedotPay", kind: .cryptoFiat, opening: usd(4_500), colorHex: "#E53935")  // → $45.00
    ]

    struct TransactionSeed {
        let day: Int
        let hour: Int
        let kind: TransactionKind
        let payee: String?
        let category: String?
        let account: String?
        let amount: Money
        /// My share when the row is split in the dataset (M5 fills splits; the fixture stores the cache).
        let myShare: Money?
        let toAccount: String?
        let received: Money?
        let note: String?
        var month = 10
        /// Loans, repayments and settlements: the other person.
        var person: String?
        /// Split equally in this group (M5); `paidBy` nil means you paid (or received, for income).
        var group: String?
        var paidBy: String?
        /// Money comes in (a repayment to you, a settlement someone paid you).
        var incoming = false
        var due: LocalDate?
    }

    static func seed(_ day: Int, _ hour: Int, _ kind: TransactionKind, _ payee: String?, _ category: String?, _ account: String?,
                     _ amount: Money, share: Money? = nil, to: String? = nil, received: Money? = nil, note: String? = nil,
                     person: String? = nil, group: String? = nil, paidBy: String? = nil, incoming: Bool = false,
                     due: LocalDate? = nil) -> TransactionSeed {
        TransactionSeed(day: day, hour: hour, kind: kind, payee: payee, category: category, account: account, amount: amount,
                        myShare: share, toAccount: to, received: received, note: note, person: person, group: group,
                        paidBy: paidBy, incoming: incoming, due: due)
    }

    /// People and groups (dataset "People and groups"); "You" is the real self row, never sample.
    static let people = ["Usama", "Bilal", "Sara", "Ali", "Office partner", "Ammi"]
    static let groups: [(name: String, icon: GroupIcon, members: [String])] = [
        ("Office", .office, ["Office partner"]),
        ("Hunza trip", .trip, ["Ali", "Sara", "Bilal"]),
        ("Home groceries", .home, ["Ammi"])
    ]

    /// October 1–6 (dataset table). Spending (my share) adds up to Rs 78,374.
    static let transactions: [TransactionSeed] = [
        seed(1, 10, .expense, "Office rent", "office.office_rent", "HBL", rs(60_000), share: rs(30_000), note: "Office group · you paid · split equally",
             group: "Office"),
        seed(2, 11, .expense, "Jazz postpaid", "utilities.mobile", "HBL", rs(1_500)),
        seed(2, 20, .expense, "Foodpanda", "food.food_delivery", "SadaPay", rs(2_180)),
        seed(3, 13, .expense, "Careem", "transport.ride_hailing", "Easypaisa", rs(1_850)),
        seed(3, 9, .expense, "iCloud+", "subscriptions.cloud_storage", "Wise", usd(299)),
        seed(4, 16, .expense, "Daraz", "personal.clothing", "Meezan", rs(6_200)),
        seed(5, 9, .expense, "Office electricity · K-Electric", "office.office_utilities", nil, rs(12_800), share: rs(6_400),
             note: "Office group · Office partner paid · split equally", group: "Office", paidBy: "Office partner"),
        seed(5, 10, .transfer, "Wise → HBL", nil, "Wise", usd(50_000), to: "HBL", received: rs(139_350)),
        seed(5, 13, .expense, "Imtiaz Super Market", "food.groceries", "NayaPay", rs(8_940)),
        seed(5, 15, .income, "Office reimbursement", "income.reimbursement", "Wise", usd(25_000), share: usd(12_500),
             note: "Office group · received by you · split equally", group: "Office"),
        seed(5, 21, .expense, "Kababjees", "food.dining_out", "SadaPay", rs(4_350)),
        seed(6, 9, .expense, "Shell, Gulberg", "transport.fuel", "HBL", rs(14_517)),
        seed(6, 12, .loanOut, "Usama", nil, "Easypaisa", rs(20_000), note: "Lent to Usama", person: "Usama"),
        seed(6, 17, .expense, "Office tea & snacks", "office.office_refreshments", "Cash", rs(3_200), share: rs(1_600),
             note: "Office group · you paid · split equally", group: "Office")
    ]

    /// Recently Deleted (dataset "Other"): deleted when sample data is loaded, so they stay for 30 days.
    static let deleted: [TransactionSeed] = [
        seed(2, 18, .expense, "Careem", "transport.ride_hailing", "Easypaisa", rs(640)),
        seed(5, 14, .expense, "Duplicate Imtiaz", "food.groceries", "NayaPay", rs(8_940)),
        seed(1, 8, .expense, "Test entry", nil, "Cash", rs(100))
    ]

    /// April–September 2026 history for Budget and Reports (dataset "Reports"): dated before the
    /// accounts' 30 Sep opening, so balances are unchanged. September matches the dataset by category;
    /// earlier months match the six-month totals (Rs thousands): spending 198, 205, 226, 219, 248.
    static var history: [TransactionSeed] {
        var rows: [TransactionSeed] = []
        func add(_ month: Int, _ seed: TransactionSeed) {
            var seed = seed
            seed.month = month
            rows.append(seed)
        }
        let spendingTotals = [4: 198_000, 5: 205_000, 6: 226_000, 7: 219_000, 8: 248_000]
        for month in 4...9 {
            // Income: salary $1,875 on the 21st; my half of the office reimbursement ($250, Aug $500).
            add(month, seed(21, 10, .income, "Salary", "income.salary", "Wise", usd(187_500)))
            let reimbursement = month == 8 ? usd(50_000) : usd(25_000)
            add(month, seed(5, 15, .income, "Office reimbursement", "income.reimbursement", "Wise", reimbursement,
                            share: Money(minorUnits: reimbursement.minorUnits / 2, currency: .usd), note: "Office group · split equally",
                            group: "Office"))
            // Commitments every month.
            add(month, seed(1, 10, .expense, "Office rent", "office.office_rent", "HBL", rs(60_000), share: rs(30_000),
                            note: "Office group · you paid · split equally", group: "Office"))
            add(month, seed(25, 11, .expense, "Office staff salaries", "office.staff_salaries", "HBL", rs(70_000), share: rs(35_000),
                            note: "Office group · you paid · split equally", group: "Office"))
            // Month-end Office settle-up of rent + salaries − my half of the reimbursement (USD at 280):
            // the partner pays Rs 30,000 (Aug: you pay Rs 5,000; Sep: the partner pays Rs 24,000 on the 30th).
            let settle: Int64 = month == 8 ? 5_000 : month == 9 ? 24_000 : 30_000
            add(month, seed(LocalDate.daysIn(year: 2026, month: month), 18, .settlement, "Office partner", nil, "HBL", rs(settle),
                            note: month == 8 ? "You paid Office partner" : "Office partner paid you", person: "Office partner",
                            group: "Office", incoming: month != 8))
            add(month, seed(10, 9, .installment, "Car installment · Meezan", "transport.car_installment", "Meezan", rs(45_000)))
            add(month, seed(12, 9, .expense, "Netflix", "subscriptions.streaming", "HBL", rs(1_100)))
            add(month, seed(3, 9, .expense, "iCloud+", "subscriptions.cloud_storage", "Wise", usd(299)))
            add(month, seed(18, 9, .expense, "ChatGPT Plus", "subscriptions.software_ai_tools", "Wise", usd(2_000)))
            add(month, seed(20, 9, .expense, "Claude Pro", "subscriptions.software_ai_tools", "Wise", usd(2_000)))
            add(month, seed(24, 9, .expense, "YouTube Premium", "subscriptions.streaming", "HBL", rs(479)))
            add(month, seed(27, 9, .expense, "Spotify", "subscriptions.streaming", "HBL", rs(449)))
            if month >= 6 {
                add(month, seed(15, 12, .kametiContribution, "Kameti", "financial.kameti_contribution", "Cash", rs(20_000)))
            }
            if month == 9 {
                // September by category (dataset): Office 71,000 · Transport 67,000 · Food 34,000 · Financial 20,000 ·
                // Subscriptions 14,065 · Utilities 11,200 · Personal 9,800 · Health 4,500 → Rs 231,565.
                add(9, seed(5, 9, .expense, "Office electricity · K-Electric", "office.office_utilities", nil, rs(12_000), share: rs(6_000),
                            note: "Office group · Office partner paid · split equally", group: "Office", paidBy: "Office partner"))
                // Loans: lent Usama Rs 10,000 (Cash), he repaid Rs 5,000 (Easypaisa); lent Bilal Rs 10,000 (HBL), due 31 Oct.
                add(9, seed(2, 19, .loanOut, "Usama", nil, "Cash", rs(10_000), note: "Lent to Usama", person: "Usama"))
                add(9, seed(20, 18, .repayment, "Usama", nil, "Easypaisa", rs(5_000), note: "Usama repaid", person: "Usama", incoming: true))
                add(9, seed(15, 12, .loanOut, "Bilal", nil, "HBL", rs(10_000), note: "Lent to Bilal", person: "Bilal",
                            due: LocalDate(year: 2026, month: 10, day: 31)))
                add(9, seed(14, 18, .expense, "Shell, Gulberg", "transport.fuel", "HBL", rs(14_000)))
                add(9, seed(16, 20, .expense, "Careem", "transport.ride_hailing", "Easypaisa", rs(8_000)))
                add(9, seed(7, 13, .expense, "Imtiaz Super Market", "food.groceries", "NayaPay", rs(18_000)))
                add(9, seed(19, 21, .expense, "Kababjees", "food.dining_out", "SadaPay", rs(9_500)))
                add(9, seed(23, 20, .expense, "Foodpanda", "food.food_delivery", "SadaPay", rs(6_500)))
                add(9, seed(8, 10, .expense, "Internet · Nayatel", "utilities.internet", "HBL", rs(6_500)))
                add(9, seed(6, 10, .expense, "Gas bill · SNGPL", "utilities.gas", "HBL", rs(3_200)))
                add(9, seed(2, 11, .expense, "Jazz postpaid", "utilities.mobile", "HBL", rs(1_500)))
                add(9, seed(12, 16, .expense, "Daraz", "personal.clothing", "Meezan", rs(9_800)))
                add(9, seed(22, 17, .expense, "Doctor visit", "health.doctor", "Cash", rs(4_500)))
            } else {
                // Fixed: Office 65,000 + car 45,000 + subscriptions 14,065.20 (+ kameti from June) + utilities 11,000
                // + fuel 14,000; groceries and dining make up the rest of the month's total.
                add(month, seed(8, 10, .expense, "Internet · Nayatel", "utilities.internet", "HBL", rs(6_500)))
                add(month, seed(6, 10, .expense, "Gas bill · SNGPL", "utilities.gas", "HBL", rs(3_000)))
                add(month, seed(2, 11, .expense, "Jazz postpaid", "utilities.mobile", "HBL", rs(1_500)))
                add(month, seed(14, 18, .expense, "Shell, Gulberg", "transport.fuel", "HBL", rs(14_000)))
                let fixed: Int64 = 65_000 + 45_000 + 14_065 + 11_000 + 14_000 + (month >= 6 ? 20_000 : 0) + (month == 8 ? 19_200 : 0)
                let rest = Int64(spendingTotals[month]!) - fixed
                let groceries = rest * 6 / 10
                add(month, seed(7, 13, .expense, "Imtiaz Super Market", "food.groceries", "NayaPay", rs(groceries)))
                add(month, seed(19, 21, .expense, "Kababjees", "food.dining_out", "SadaPay", rs(rest - groceries)))
            }
        }
        // Hunza trip in August (you, Ali, Sara, Bilal): Ali paid the hotel, you paid the jeep; Sara and Bilal
        // settled with you, so you owe Ali Rs 3,200. Your share Rs 19,200 is part of August's Rs 248,000.
        add(8, seed(12, 20, .expense, "Hotel, Karimabad", "entertainment.travel", nil, rs(44_800), share: rs(11_200),
                    note: "Hunza trip · Ali paid · split equally", group: "Hunza trip", paidBy: "Ali"))
        add(8, seed(13, 9, .expense, "Jeep hire", "entertainment.travel", "Cash", rs(32_000), share: rs(8_000),
                    note: "Hunza trip · you paid · split equally", group: "Hunza trip"))
        add(8, seed(20, 19, .settlement, "Sara", nil, "Easypaisa", rs(8_000), note: "Sara paid you", person: "Sara",
                    group: "Hunza trip", incoming: true))
        add(8, seed(20, 19, .settlement, "Bilal", nil, "Easypaisa", rs(8_000), note: "Bilal paid you", person: "Bilal",
                    group: "Hunza trip", incoming: true))
        // Ammi lent you Rs 75,000 into HBL on 1 Aug, no due date.
        add(8, seed(1, 11, .loanIn, "Ammi", nil, "HBL", rs(75_000), note: "Borrowed from Ammi", person: "Ammi"))
        // Home groceries (you and Ammi) in March, settled at month end.
        add(3, seed(14, 18, .expense, "Imtiaz Super Market", "food.groceries", nil, rs(9_000), share: rs(4_500),
                    note: "Home groceries · Ammi paid · split equally", group: "Home groceries", paidBy: "Ammi"))
        add(3, seed(31, 19, .settlement, "Ammi", nil, "HBL", rs(4_500), note: "You paid Ammi", person: "Ammi", group: "Home groceries"))
        return rows
    }

    /// Budget Rs 235,000 a month since April with the October limits (dataset "Budget"); limits add up to
    /// Rs 232,000, leaving Rs 3,000 unassigned. August went over (Rs 248,000), so "kept 5 of 6".
    static let budgetLimits: [(String, Int64)] = [
        ("office", 75_000), ("transport", 75_000), ("food", 30_000), ("financial", 20_000),
        ("subscriptions", 15_000), ("utilities", 12_000), ("personal", 5_000)
    ]

    static func date(day: Int, hour: Int, month: Int = 10) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Inserts every sample row inside the caller's DB transaction.
    static func insert(_ db: Database) throws {
        var accountIDs: [String: UUID] = [:]
        for (index, seed) in accounts.enumerated() {
            let account = Account(name: seed.name, kind: seed.kind, currency: seed.opening.currency, openingBalance: seed.opening,
                                  openingDate: LocalDate(year: 2026, month: 9, day: 30), colorHex: seed.colorHex,
                                  sortOrder: index, isSample: true)
            try LedgerStore.insert(account, db)
            accountIDs[seed.name] = account.id
        }
        var categoryIDs: [String: UUID] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT id, system_key FROM category WHERE system_key IS NOT NULL") {
            if let id = UUID(uuidString: row["id"]) { categoryIDs[row["system_key"]] = id }
        }
        let me = try PeopleStore.selfID(db)
        var personIDs: [String: UUID] = [:]
        for name in people {
            personIDs[name] = try PeopleStore.insertPerson(Person(name: name, isSample: true), db).id
        }
        var groupIDs: [String: (id: UUID, members: [UUID])] = [:]
        for group in groups {
            let members = [me] + group.members.compactMap { personIDs[$0] }
            let row = SplitGroup(name: group.name, icon: group.icon, memberIDs: members, isSample: true)
            try PeopleStore.insertGroup(row, db)
            groupIDs[group.name] = (row.id, members)
        }
        var loans: [Loan] = []
        let now = Date()
        for (seed, isDeleted) in history.map({ ($0, false) }) + transactions.map({ ($0, false) }) + deleted.map({ ($0, true) }) {
            let when = date(day: seed.day, hour: seed.hour, month: seed.month)
            var legs: [TransactionLeg] = []
            var fxRate: Decimal?
            if let name = seed.account, let accountID = accountIDs[name] {
                let outflow = ![.income, .loanIn, .refund, .kametiPayout].contains(seed.kind) && !seed.incoming
                legs.append(TransactionLeg(accountID: accountID, amount: outflow ? try seed.amount.negated() : seed.amount,
                                           role: seed.kind == .transfer ? .transferOut : .main))
            }
            if let to = seed.toAccount, let toID = accountIDs[to], let received = seed.received {
                legs.append(TransactionLeg(accountID: toID, amount: received, role: .transferIn))
                fxRate = try TransferRate(foreign: seed.amount, base: received, tableRate: 280).rate
            }
            let person = seed.person.flatMap { personIDs[$0] }
            let group = seed.group.flatMap { groupIDs[$0] }
            var transaction = MoneyTransaction(
                kind: seed.kind, occurredAt: when, localDate: LocalDate(when, in: timeZone), timeZoneID: timeZone.identifier,
                amount: seed.amount, myShare: seed.myShare, categoryID: seed.category.flatMap { categoryIDs[$0] },
                payeeName: seed.payee, note: seed.note, fxRate: fxRate, source: .sample,
                counterpartyID: person, groupID: seed.kind == .settlement ? group?.id : nil, legs: legs,
                createdAt: when, deletedAt: isDeleted ? now : nil, isSample: true)
            var split: Split?
            if let group, seed.kind != .settlement {
                let payer = seed.paidBy.flatMap { personIDs[$0] } ?? me
                let shares = try SplitCalculator.shares(total: seed.amount, method: .equal, participants: group.members, firstPayer: payer)
                let made = Split(transactionID: transaction.id, groupID: group.id, method: .equal,
                                 payers: [SplitPayer(personID: payer, amount: seed.amount)], shares: shares)
                try made.validate(total: seed.amount)
                transaction = PeopleStore.applying(made, to: transaction, me: me)
                split = made
            }
            try LedgerStore.save(transaction, db)
            if let split { try PeopleStore.insertSplit(split, isSample: true, db) }
            if let person, seed.kind == .loanOut || seed.kind == .loanIn {
                loans.append(Loan(direction: seed.kind == .loanOut ? .lent : .borrowed, personID: person, principal: seed.amount,
                                  startDate: transaction.localDate, dueDate: seed.due, transactionID: transaction.id, isSample: true))
            }
            if let person, seed.kind == .repayment,
               let index = loans.lastIndex(where: { $0.personID == person && $0.startDate <= transaction.localDate }) {
                loans[index].payments.append(LoanPayment(transactionID: transaction.id, amount: seed.amount, paidOn: transaction.localDate))
            }
        }
        for loan in loans { try PeopleStore.insertLoan(loan, isSample: true, db) }
        let limits = Dictionary(uniqueKeysWithValues: budgetLimits.compactMap { key, limit in
            categoryIDs[key].map { ($0, rs(limit)) }
        })
        for month in 4...10 {
            let plan = BudgetPlan(periodStart: LocalDate(year: 2026, month: month, day: 1), total: rs(235_000), limits: limits)
            try BudgetStore.write(plan, isSample: true, db)
        }
    }
}
