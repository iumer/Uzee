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
        AccountSeed(name: "HBL", kind: .bank, opening: rs(119_067), colorHex: "#007A3D"),        // → Rs 182,400
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
    }

    static func seed(_ day: Int, _ hour: Int, _ kind: TransactionKind, _ payee: String?, _ category: String?, _ account: String?,
                     _ amount: Money, share: Money? = nil, to: String? = nil, received: Money? = nil, note: String? = nil) -> TransactionSeed {
        TransactionSeed(day: day, hour: hour, kind: kind, payee: payee, category: category, account: account, amount: amount,
                        myShare: share, toAccount: to, received: received, note: note)
    }

    /// October 1–6 (dataset table). Spending (my share) adds up to Rs 78,374.
    static let transactions: [TransactionSeed] = [
        seed(1, 10, .expense, "Office rent", "office.office_rent", "HBL", rs(60_000), share: rs(30_000), note: "Office group · you paid · split equally"),
        seed(2, 11, .expense, "Jazz postpaid", "utilities.mobile", "HBL", rs(1_500)),
        seed(2, 20, .expense, "Foodpanda", "food.food_delivery", "SadaPay", rs(2_180)),
        seed(3, 13, .expense, "Careem", "transport.ride_hailing", "Easypaisa", rs(1_850)),
        seed(3, 9, .expense, "iCloud+", "subscriptions.cloud_storage", "Wise", usd(299)),
        seed(4, 16, .expense, "Daraz", "personal.clothing", "Meezan", rs(6_200)),
        seed(5, 9, .expense, "Office electricity · K-Electric", "office.office_utilities", nil, rs(12_800), share: rs(6_400),
             note: "Office group · Office partner paid · split equally"),
        seed(5, 10, .transfer, "Wise → HBL", nil, "Wise", usd(50_000), to: "HBL", received: rs(139_350)),
        seed(5, 13, .expense, "Imtiaz Super Market", "food.groceries", "NayaPay", rs(8_940)),
        seed(5, 15, .income, "Office reimbursement", "income.reimbursement", "Wise", usd(25_000), share: usd(12_500),
             note: "Office group · received by you · split equally"),
        seed(5, 21, .expense, "Kababjees", "food.dining_out", "SadaPay", rs(4_350)),
        seed(6, 9, .expense, "Shell, Gulberg", "transport.fuel", "HBL", rs(14_517)),
        seed(6, 12, .loanOut, "Usama", nil, "Easypaisa", rs(20_000), note: "Lent to Usama"),
        seed(6, 17, .expense, "Office tea & snacks", "office.office_refreshments", "Cash", rs(3_200), share: rs(1_600),
             note: "Office group · you paid · split equally")
    ]

    /// Recently Deleted (dataset "Other"): deleted when sample data is loaded, so they stay for 30 days.
    static let deleted: [TransactionSeed] = [
        seed(2, 18, .expense, "Careem", "transport.ride_hailing", "Easypaisa", rs(640)),
        seed(5, 14, .expense, "Duplicate Imtiaz", "food.groceries", "NayaPay", rs(8_940)),
        seed(1, 8, .expense, "Test entry", nil, "Cash", rs(100))
    ]

    static func date(day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
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
        let now = Date()
        for (seed, isDeleted) in transactions.map({ ($0, false) }) + deleted.map({ ($0, true) }) {
            let when = date(day: seed.day, hour: seed.hour)
            var legs: [TransactionLeg] = []
            var fxRate: Decimal?
            if let name = seed.account, let accountID = accountIDs[name] {
                let outflow = seed.kind == .expense || seed.kind == .loanOut || seed.kind == .transfer
                legs.append(TransactionLeg(accountID: accountID, amount: outflow ? try seed.amount.negated() : seed.amount,
                                           role: seed.kind == .transfer ? .transferOut : .main))
            }
            if let to = seed.toAccount, let toID = accountIDs[to], let received = seed.received {
                legs.append(TransactionLeg(accountID: toID, amount: received, role: .transferIn))
                fxRate = try TransferRate(foreign: seed.amount, base: received, tableRate: 280).rate
            }
            let transaction = MoneyTransaction(
                kind: seed.kind, occurredAt: when, localDate: LocalDate(when, in: timeZone), timeZoneID: timeZone.identifier,
                amount: seed.amount, myShare: seed.myShare, categoryID: seed.category.flatMap { categoryIDs[$0] },
                payeeName: seed.payee, note: seed.note, fxRate: fxRate, source: .sample, legs: legs,
                createdAt: when, deletedAt: isDeleted ? now : nil, isSample: true)
            try LedgerStore.save(transaction, db)
        }
    }
}
