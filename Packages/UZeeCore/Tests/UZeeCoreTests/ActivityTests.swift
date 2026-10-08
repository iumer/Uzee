import Foundation
import Testing
@testable import UZeeCore

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }

/// M3 unit parts: filters, search, day totals, row text, Recently Deleted, suggestions (TEST_REGISTRY §CAT, §TXN, §DATA).
@Suite("Activity and categories")
struct ActivityTests {
    let accounts = SampleAccounts.make()
    let food = SpendCategory(type: .expense, name: "Food", group: .food)
    let transport = SpendCategory(type: .expense, name: "Transport", group: .transport)
    var groceries: SpendCategory { SpendCategory(type: .expense, parentID: food.id, name: "Groceries", group: .food, systemKey: "food.groceries") }
    var dining: SpendCategory { SpendCategory(type: .expense, parentID: food.id, name: "Dining out", group: .food, systemKey: "food.dining_out") }
    var ride: SpendCategory { SpendCategory(type: .expense, parentID: transport.id, name: "Ride-hailing", group: .transport, systemKey: "transport.ride_hailing") }

    func account(_ name: String) -> Account { accounts.first { $0.name == name }! }

    func txn(_ day: Int, _ hour: Int, _ payee: String, _ category: UUID?, _ account: String,
             _ amount: Money, kind: TransactionKind = .expense, share: Money? = nil, note: String? = nil) -> MoneyTransaction {
        let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(day * 86_400 + hour * 3_600))
        let leg = TransactionLeg(accountID: self.account(account).id, amount: kind == .income ? amount : try! amount.negated(), role: .main)
        return MoneyTransaction(kind: kind, occurredAt: date, localDate: LocalDate(year: 2026, month: 10, day: day),
                                timeZoneID: "Asia/Karachi", amount: amount, myShare: share, categoryID: category,
                                payeeName: payee, note: note, legs: [leg])
    }

    func fixture() -> (rows: [MoneyTransaction], snapshot: LedgerSnapshot, cats: [SpendCategory]) {
        let cats = [food, transport, groceries, dining, ride]
        let rows = [
            txn(5, 13, "Imtiaz Super Market", cats[2].id, "NayaPay", rs(8_940)),
            txn(5, 21, "Kababjees", cats[3].id, "SadaPay", rs(4_350)),
            txn(3, 13, "Careem", cats[4].id, "Easypaisa", rs(1_850)),
            txn(6, 9, "Shell, Gulberg", nil, "HBL", rs(14_517), note: "Full tank"),
            txn(6, 12, "Usama", nil, "Easypaisa", rs(20_000), kind: .loanOut)
        ]
        var snapshot = LedgerSnapshot.empty()
        snapshot.accounts = accounts
        snapshot.categories = cats
        return (rows, snapshot, cats)
    }

    @Test("EXP-01 CSV export: oldest first, signed per account, quoted text, no formulas")
    func csvExport() {
        let (rows, snapshot, _) = fixture()
        let tricky = txn(7, 10, "=HYPERLINK(\"x\")", nil, "HBL", rs(500), note: "Milk, eggs")
        var deleted = txn(7, 11, "Gone", nil, "HBL", rs(1))
        deleted.deletedAt = Date()
        let csv = CSVExport.transactions(rows + [tricky, deleted], ledger: snapshot)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.first == "Date,Type,Account,Amount,Currency,Category,Payee,Note,Status")
        #expect(lines.count == 7)
        #expect(lines[1].hasPrefix("2026-10-03,Expense,Easypaisa,-1850,PKR,Transport › Ride-hailing,Careem"))
        #expect(lines[6] == "2026-10-07,Expense,HBL,-500,PKR,,\"'=HYPERLINK(\"\"x\"\")\",\"Milk, eggs\",Posted")
        #expect(!csv.contains("Gone"))
    }

    @Test("TXN-022 filter by account; TXN-024 type and date range")
    func accountTypeDate() {
        let (rows, snapshot, _) = fixture()
        let easypaisa = ActivityQuery.filter(rows, ActivityFilter(accountIDs: [account("Easypaisa").id]), snapshot: snapshot)
        #expect(easypaisa.map(\.payeeName) == ["Usama", "Careem"])
        #expect(ActivityQuery.filter(rows, ActivityFilter(kinds: [.loanOut]), snapshot: snapshot).count == 1)
        let fifth = LocalDate(year: 2026, month: 10, day: 5)
        let range = ActivityQuery.filter(rows, ActivityFilter(from: fifth, through: fifth), snapshot: snapshot)
        #expect(range.map(\.payeeName) == ["Kababjees", "Imtiaz Super Market"])
    }

    @Test("TXN-023 filter by a parent category includes its subcategories")
    func categoryFilter() throws {
        let (rows, snapshot, cats) = fixture()
        let foodRows = ActivityQuery.filter(rows, ActivityFilter(categoryIDs: [cats[0].id]), snapshot: snapshot)
        #expect(foodRows.count == 2)
        #expect(try Money.sum(foodRows.map(\.myShare), in: .pkr) == rs(13_290))
        #expect(ActivityQuery.filter(rows, ActivityFilter(categoryIDs: [cats[4].id]), snapshot: snapshot).map(\.payeeName) == ["Careem"])
    }

    @Test("TXN-025 search payee, note, category and amount, case-insensitive")
    func search() {
        let (rows, snapshot, _) = fixture()
        func find(_ text: String) -> [String?] { ActivityQuery.filter(rows, ActivityFilter(text: text), snapshot: snapshot).map(\.payeeName) }
        #expect(find("8940") == ["Imtiaz Super Market"])
        #expect(find("8,940") == ["Imtiaz Super Market"])
        #expect(find("SHELL") == ["Shell, Gulberg"])
        #expect(find("full tank") == ["Shell, Gulberg"])
        #expect(find("dining") == ["Kababjees"])
        #expect(find("zzz").isEmpty)
        #expect(find("  ").count == rows.count)
    }

    @Test("CAT-006 filter by tag returns exact rows")
    func tags() {
        let (rows, snapshot, _) = fixture()
        let work = UUID()
        let tagged = [rows[0].id: Set([work]), rows[2].id: Set([work, UUID()])]
        let result = ActivityQuery.filter(rows, ActivityFilter(tagIDs: [work]), snapshot: snapshot, tags: tagged)
        #expect(Set(result.map(\.id)) == [rows[0].id, rows[2].id])
    }

    @Test("TXN-020 day totals count my share and skip loans; deleted rows never match")
    func dayTotals() {
        var (rows, snapshot, _) = fixture()
        rows.append(txn(6, 17, "Office tea & snacks", nil, "Cash", rs(3_200), share: rs(1_600)))
        var deleted = txn(6, 18, "Deleted", nil, "Cash", rs(999))
        deleted.deletedAt = Date()
        rows.append(deleted)
        let days = ActivityQuery.days(ActivityQuery.filter(rows, ActivityFilter(), snapshot: snapshot), snapshot: snapshot)
        #expect(days.map(\.date.day) == [6, 5, 3])
        #expect(days[0].spending == rs(16_117))
        #expect(days[0].transactions.map(\.payeeName) == ["Office tea & snacks", "Usama", "Shell, Gulberg"])
        #expect(days[1].spending == rs(13_290))
        #expect(!ActivityFilter().isActive)
        #expect(ActivityFilter(kinds: [.expense], text: "x").count == 1)
    }

    @Test("TXN-021 row says what the money did")
    func rowText() {
        let rent = txn(1, 10, "Office rent", nil, "HBL", rs(60_000), share: rs(30_000))
        #expect(ActivityText.detail(rent) == "You paid Rs 60,000 · your share Rs 30,000")
        #expect(ActivityText.detail(txn(6, 12, "Usama", nil, "Easypaisa", rs(20_000), kind: .loanOut)) == "not spending")
        #expect(ActivityText.detail(txn(5, 13, "Imtiaz", nil, "NayaPay", rs(8_940))) == nil)
    }

    @Test("DATA-012 and DATA-013 purge after 30 days, day 29 still restorable")
    func retention() {
        let deleted = Date(timeIntervalSince1970: 1_790_000_000)
        let day = 86_400.0
        #expect(!RecentlyDeleted.isExpired(deletedAt: deleted, now: deleted.addingTimeInterval(29 * day)))
        #expect(RecentlyDeleted.daysLeft(deletedAt: deleted, now: deleted.addingTimeInterval(29 * day)) == 1)
        #expect(RecentlyDeleted.isExpired(deletedAt: deleted, now: deleted.addingTimeInterval(30 * day)))
        #expect(RecentlyDeleted.isExpired(deletedAt: deleted, now: deleted.addingTimeInterval(31 * day)))
        #expect(RecentlyDeleted.daysLeft(deletedAt: deleted, now: deleted) == 30)
    }

    @Test("CAT-007 and CAT-008 category suggestion from payee")
    func suggestion() {
        let (_, _, cats) = fixture()
        #expect(CategorySuggester.suggest(payee: "Careem", remembered: [:], categories: cats) == cats[4].id)
        #expect(CategorySuggester.suggest(payee: "Unknown shop", remembered: [:], categories: cats) == nil)
        #expect(CategorySuggester.suggest(payee: "  ", remembered: [:], categories: cats) == nil)
        // The payee's own last category beats the built-in list.
        #expect(CategorySuggester.suggest(payee: " careem ", remembered: ["careem": cats[3].id], categories: cats) == cats[3].id)
        #expect(CategorySuggester.suggest(payee: "Kababjees", remembered: [:], categories: cats) == cats[3].id)
    }

    @Test("CAT-002 category names are trimmed and unique among siblings")
    func categoryNames() throws {
        #expect(try SpendCategory.validateName("  Snacks ", siblingNames: ["Groceries"]) == "Snacks")
        #expect(throws: SpendCategory.Problem.duplicateName) { try SpendCategory.validateName("groceries", siblingNames: ["Groceries"]) }
        #expect(throws: SpendCategory.Problem.emptyName) { try SpendCategory.validateName(" ", siblingNames: []) }
        #expect(throws: SpendCategory.Problem.nameTooLong) { try SpendCategory.validateName(String(repeating: "a", count: 31), siblingNames: []) }
    }
}
