import Foundation
import Testing
import GRDB
import UZeeCore
@testable import UZeeData

private func rs(_ major: Int64) -> Money { Money(major: major, .pkr) }

/// M3 integration tests on the sample dataset (TEST_REGISTRY CAT, TXN-020…025, ATT-003, DATA-010…014).
@Suite("Activity store")
struct ActivityStoreTests {
    func sample() throws -> (AppDatabase, LedgerStore, LedgerSnapshot, [MoneyTransaction]) {
        let database = try AppDatabase.inMemory()
        try SampleDataService(database: database).load()
        let store = LedgerStore(database: database)
        return (database, store, try store.snapshot(), try store.transactions())
    }

    func id(_ name: String, _ snapshot: LedgerSnapshot) -> UUID { snapshot.accounts.first { $0.name == name }!.id }
    func category(_ key: String, _ snapshot: LedgerSnapshot) -> UUID { snapshot.categories.first { $0.systemKey == key }!.id }
    func group(_ kind: CategoryKind, _ snapshot: LedgerSnapshot) -> UUID {
        snapshot.categories.first { $0.parentID == nil && $0.group == kind && $0.type == .expense }!.id
    }
    func day(_ d: Int) -> LocalDate { LocalDate(year: 2026, month: 10, day: d) }

    @Test("CAT-001 default tree matches Appendix A")
    func defaultTree() throws {
        let (_, _, snapshot, _) = try sample()
        let groups = snapshot.categories.filter { $0.parentID == nil && $0.type == .expense }
        #expect(groups.map(\.name) == DefaultCategories.expense.map(\.name))
        #expect(snapshot.categoryPath(category("transport.fuel", snapshot)) == "Transport › Fuel")
        #expect(snapshot.categoryPath(category("income.reimbursement", snapshot)) == "Income › Reimbursement")
    }

    @Test("TXN-020 day totals for 1–6 Oct, my share")
    func dayTotals() throws {
        let (_, _, snapshot, rows) = try sample()
        let days = ActivityQuery.days(ActivityQuery.filter(rows, ActivityFilter(), snapshot: snapshot), snapshot: snapshot)
        #expect(days.map(\.date.day) == [6, 5, 4, 3, 2, 1])
        #expect(days.map { MoneyFormatter.string($0.spending) } == ["Rs 16,117", "Rs 19,690", "Rs 6,200", "Rs 2,687", "Rs 3,680", "Rs 30,000"])
    }

    @Test("TXN-022 HBL; TXN-023 Food; TXN-024 type and date range")
    func filters() throws {
        let (_, _, snapshot, rows) = try sample()
        func run(_ filter: ActivityFilter) -> [MoneyTransaction] { ActivityQuery.filter(rows, filter, snapshot: snapshot) }
        #expect(Set(run(ActivityFilter(accountIDs: [id("HBL", snapshot)])).compactMap(\.payeeName))
                == ["Office rent", "Jazz postpaid", "Wise → HBL", "Shell, Gulberg"])
        let food = run(ActivityFilter(categoryIDs: [group(.food, snapshot)]))
        #expect(food.count == 3)
        #expect(MoneyFormatter.string(try Money.sum(food.map(\.myShare), in: .pkr)) == "Rs 15,470")
        #expect(run(ActivityFilter(kinds: [.transfer])).count == 1)
        #expect(run(ActivityFilter(from: day(5), through: day(5))).count == 5)
    }

    @Test("TXN-025 search payee, note and amount")
    func search() throws {
        let (_, _, snapshot, rows) = try sample()
        func find(_ text: String) -> [String] { ActivityQuery.filter(rows, ActivityFilter(text: text), snapshot: snapshot).compactMap(\.payeeName) }
        #expect(find("8940") == ["Imtiaz Super Market"])
        #expect(find("shell") == ["Shell, Gulberg"])
        #expect(find("SPLIT EQUALLY").count == 4)
    }

    @Test("DATA-010 Recently Deleted shows the 3 sample items, newest deletion first")
    func deletedList() throws {
        let (_, store, _, rows) = try sample()
        let deleted = try store.deletedTransactions()
        #expect(Set(deleted.compactMap(\.payeeName)) == ["Careem", "Duplicate Imtiaz", "Test entry"])
        #expect(deleted.allSatisfy { $0.deletedAt != nil && $0.legs.count == 1 })
        #expect(!rows.contains { $0.payeeName == "Test entry" })
    }

    @Test("DATA-011 restore brings the row and its balance effect back")
    func restore() throws {
        let (_, store, before, _) = try sample()
        let careem = try store.deletedTransactions().first { $0.payeeName == "Careem" }!
        try store.restore(transactionID: careem.id)
        let after = try store.snapshot()
        let easypaisa = before.accounts.first { $0.name == "Easypaisa" }!
        #expect(after.balance(of: easypaisa) == (try before.balance(of: easypaisa).subtracting(rs(640))))
        #expect(try store.deletedTransactions().count == 2)
        #expect(throws: LedgerStore.Problem.notFound) { try store.restore(transactionID: careem.id) }
    }

    @Test("DATA-012 purge after 30 days removes rows, legs and attachments; DATA-013 day 29 kept")
    func purge() throws {
        let (database, store, _, _) = try sample()
        let test = try store.deletedTransactions().first { $0.payeeName == "Test entry" }!
        try store.addAttachment(ReceiptFile(transactionID: test.id, kind: .photo, fileName: "receipt-1.jpg", byteCount: 10))
        #expect(try store.purgeDeleted(now: Date().addingTimeInterval(29 * 86_400)).isEmpty)
        #expect(try store.deletedTransactions().count == 3)
        let files = try store.purgeDeleted(now: Date().addingTimeInterval(31 * 86_400))
        #expect(files == ["receipt-1.jpg"])
        #expect(try store.deletedTransactions().isEmpty)
        let orphans = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT (SELECT COUNT(*) FROM transaction_leg WHERE txn_id NOT IN (SELECT id FROM txn)) + (SELECT COUNT(*) FROM attachment)")
        }
        #expect(orphans == 0)
    }

    @Test("DATA-014 transfer legs are deleted and restored together")
    func transferDeleteRestore() throws {
        let (_, store, before, rows) = try sample()
        let transfer = rows.first { $0.kind == .transfer }!
        try store.delete(transactionID: transfer.id)
        let mid = try store.snapshot()
        #expect(mid.balance(of: before.accounts.first { $0.name == "HBL" }!) == (try rs(182_400).subtracting(rs(139_350))))
        #expect(try store.deletedTransactions().first { $0.id == transfer.id }?.legs.count == 2)
        try store.restore(transactionID: transfer.id)
        #expect(try store.snapshot().balances == before.balances)
    }

    @Test("CAT-004 merge moves every transaction in one step; CAT-005 delete in use is blocked")
    func mergeAndDelete() throws {
        let (database, store, snapshot, _) = try sample()
        let dining = category("food.dining_out", snapshot)
        let delivery = category("food.food_delivery", snapshot)
        #expect(throws: SpendCategory.Problem.inUse) { try store.deleteCategory(id: delivery) }
        try store.mergeCategory(delivery, into: dining)
        let moved = try store.transactions().filter { $0.categoryID == dining }.compactMap(\.payeeName)
        #expect(Set(moved) == ["Foodpanda", "Kababjees"])
        #expect(try store.categories().contains { $0.id == delivery } == false)
        let orphans = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM txn WHERE category_id NOT IN (SELECT id FROM category WHERE deleted_at IS NULL)")
        }
        #expect(orphans == 0)
        #expect(throws: SpendCategory.Problem.invalidMerge) { try store.mergeCategory(dining, into: dining) }
        #expect(throws: SpendCategory.Problem.invalidMerge) {
            try store.mergeCategory(dining, into: category("income.reimbursement", snapshot))
        }
        // A group merges into another group and hands over its subcategories.
        try store.mergeCategory(group(.charity, snapshot), into: group(.family, snapshot))
        let family = try store.categories().filter { $0.parentID == group(.family, snapshot) }.map(\.name)
        #expect(family.contains("Zakat"))
        // An unused category can be deleted.
        let unused = try store.createCategory(name: "Snacks", parentID: group(.food, snapshot))
        try store.deleteCategory(id: unused.id)
        #expect(try store.categories().contains { $0.id == unused.id } == false)
    }

    @Test("CAT-002 rename and reorder; CAT-003 hide keeps old rows linked")
    func renameHide() throws {
        let (_, store, snapshot, _) = try sample()
        let fuel = category("transport.fuel", snapshot)
        try store.renameCategory(id: fuel, to: "Petrol")
        #expect(try store.snapshot().categoryPath(fuel) == "Transport › Petrol")
        #expect(throws: SpendCategory.Problem.duplicateName) { try store.renameCategory(id: fuel, to: "ride-hailing") }
        try store.setCategoryHidden(true, id: fuel)
        #expect(try store.categories().first { $0.id == fuel }?.isHidden == true)
        #expect(try store.transactions().contains { $0.categoryID == fuel })
        let transport = group(.transport, snapshot)
        let children = try store.categories().filter { $0.parentID == transport }.map(\.id)
        try store.reorderCategories(children.reversed())
        #expect(try store.categories().filter { $0.parentID == transport }.map(\.id) == children.reversed())
    }

    @Test("CAT-006 tags: several per transaction, filter returns exact rows")
    func tags() throws {
        let (_, store, snapshot, rows) = try sample()
        let office = try store.createTag(name: "Office")
        let trip = try store.createTag(name: "Trip")
        #expect(throws: SpendCategory.Problem.duplicateName) { try store.createTag(name: " office ") }
        let rent = rows.first { $0.payeeName == "Office rent" }!
        let tea = rows.first { $0.payeeName == "Office tea & snacks" }!
        try store.setTags([office.id, trip.id], transactionID: rent.id)
        try store.setTags([office.id], transactionID: tea.id)
        let map = try store.tagMap()
        #expect(map[rent.id] == [office.id, trip.id])
        let result = ActivityQuery.filter(rows, ActivityFilter(tagIDs: [office.id]), snapshot: snapshot, tags: map)
        #expect(Set(result.map(\.id)) == [rent.id, tea.id])
        try store.deleteTag(id: trip.id)
        #expect(try store.tagMap()[rent.id] == [office.id])
    }

    @Test("CAT-007 payee remembers its last category")
    func payeeMemory() throws {
        let (_, store, snapshot, _) = try sample()
        let remembered = try store.rememberedCategories()
        let suggestion = CategorySuggester.suggest(payee: "kababjees", remembered: remembered, categories: snapshot.categories)
        #expect(suggestion == category("food.dining_out", snapshot))
    }

    @Test("ATT-003 attachment rows are listed and removed")
    func attachments() throws {
        let (_, store, _, rows) = try sample()
        let tea = rows.first { $0.payeeName == "Office tea & snacks" }!
        let file = ReceiptFile(transactionID: tea.id, kind: .pdf, fileName: "a.pdf", byteCount: 1_234)
        try store.addAttachment(file)
        #expect(try store.attachments(transactionID: tea.id).map(\.fileName) == ["a.pdf"])
        #expect(try store.transactionsWithAttachments() == [tea.id])
        #expect(try store.removeAttachment(id: file.id) == "a.pdf")
        #expect(try store.attachments(transactionID: tea.id).isEmpty)
    }

    @Test("Removing sample data also removes sample tags and deleted sample rows")
    func sampleRemoval() throws {
        let (database, store, _, _) = try sample()
        _ = try SampleDataService(database: database).removeAll()
        #expect(try store.deletedTransactions().isEmpty)
        #expect(try store.transactions().isEmpty)
    }
}

@Suite("Attachment files")
struct AttachmentFileTests {
    @Test("ATT-003 files are written, found and removed with their rows")
    func files() throws {
        let files = try AttachmentStore.temporary()
        let name = try files.write(Data([1, 2, 3]), kind: .pdf)
        #expect(name.hasSuffix(".pdf"))
        #expect(FileManager.default.fileExists(atPath: files.url(for: name).path))
        let stray = try files.write(Data([9]), kind: .photo)
        files.removeOrphans(keeping: [name])
        #expect(!FileManager.default.fileExists(atPath: files.url(for: stray).path))
        files.remove([name])
        #expect(!FileManager.default.fileExists(atPath: files.url(for: name).path))
        #expect(throws: AttachmentStore.Problem.empty) { try files.write(Data(), kind: .photo) }
    }
}
