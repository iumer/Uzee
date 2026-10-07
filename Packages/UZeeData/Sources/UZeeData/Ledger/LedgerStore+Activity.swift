import Foundation
import GRDB
import UZeeCore

/// M3: Recently Deleted, categories, tags, payee memory and receipt attachments. Every write is one DB transaction.
extension LedgerStore {
    // MARK: Recently Deleted (DATA-010…014)

    /// Soft-deleted transactions, most recently deleted first.
    public func deletedTransactions() throws -> [MoneyTransaction] {
        try database.writer.read { db in try Self.fetchTransactions(db, from: nil, through: nil, deleted: true) }
    }

    /// Brings a deleted transaction back with the legs deleted together with it (DATA-014).
    public func restore(transactionID: UUID) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            guard let row = try Row.fetchOne(db, sql: "SELECT deletion_batch_id FROM txn WHERE id = ? AND deleted_at IS NOT NULL",
                                             arguments: [transactionID.uuidString]) else { throw Problem.notFound }
            let batch: String? = row["deletion_batch_id"]
            try db.execute(sql: "UPDATE transaction_leg SET deleted_at = NULL, deletion_batch_id = NULL, updated_at = ? WHERE txn_id = ? AND deletion_batch_id IS ?",
                           arguments: [now, transactionID.uuidString, batch])
            try db.execute(sql: "UPDATE txn SET deleted_at = NULL, deletion_batch_id = NULL, updated_at = ? WHERE id = ?",
                           arguments: [now, transactionID.uuidString])
        }
    }

    /// Removes deleted transactions for good: those past 30 days, or the given ones ("Delete now").
    /// Returns attachment file names the caller must delete from disk.
    @discardableResult
    public func purgeDeleted(now: Date = Date(), only ids: [UUID]? = nil) throws -> [String] {
        try database.writer.write { db in
            var condition = "deleted_at IS NOT NULL"
            var arguments: [(any DatabaseValueConvertible)?] = []
            if let ids {
                guard !ids.isEmpty else { return [] }
                condition += " AND id IN (\(Array(repeating: "?", count: ids.count).joined(separator: ",")))"
                arguments = ids.map(\.uuidString)
            } else {
                condition += " AND deleted_at <= ?"
                arguments = [Timestamp.from(RecentlyDeleted.cutoff(now: now))]
            }
            let files = try String.fetchAll(db, sql: "SELECT file_name FROM attachment WHERE txn_id IN (SELECT id FROM txn WHERE \(condition))",
                                            arguments: StatementArguments(arguments))
            try db.execute(sql: "DELETE FROM txn WHERE \(condition)", arguments: StatementArguments(arguments))
            return files
        }
    }

    // MARK: Categories (CAT-002…005)

    /// Adds a subcategory under `parentID`, or a top-level group when `parentID` is nil.
    @discardableResult
    public func createCategory(name: String, parentID: UUID?, type: CategoryType = .expense) throws -> SpendCategory {
        try database.writer.write { db in
            let parent = try parentID.map { id throws -> Row in
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM category WHERE id = ? AND deleted_at IS NULL", arguments: [id.uuidString])
                else { throw SpendCategory.Problem.notFound }
                return row
            }
            let siblings = try Self.siblingNames(db, parentID: parentID, excluding: nil)
            let clean = try SpendCategory.validateName(name, siblingNames: siblings)
            let kind: String = parent?["kind"] ?? type.rawValue
            let group: String = parent?["group_key"] ?? CategoryKind.other.rawValue
            let order = (try Int.fetchOne(db, sql: "SELECT MAX(sort_order) FROM category WHERE parent_id IS ?",
                                          arguments: [parentID?.uuidString]) ?? -1) + 1
            let id = UUID()
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO category (id, created_at, updated_at, kind, parent_id, name, name_key, group_key, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id.uuidString, now, now, kind, parentID?.uuidString, clean, NameKey.make(clean), group, order])
            return SpendCategory(id: id, type: CategoryType(rawValue: kind) ?? .expense, parentID: parentID, name: clean,
                                 group: CategoryKind(rawValue: group) ?? .other, sortOrder: order)
        }
    }

    /// Renames in place; history keeps the link because rows point at the id (CAT-002).
    public func renameCategory(id: UUID, to name: String) throws {
        try database.writer.write { db in
            guard let parent = try Row.fetchOne(db, sql: "SELECT parent_id FROM category WHERE id = ? AND deleted_at IS NULL",
                                                arguments: [id.uuidString]) else { throw SpendCategory.Problem.notFound }
            let parentID: String? = parent["parent_id"]
            let siblings = try Self.siblingNames(db, parentID: parentID.flatMap(UUID.init(uuidString:)), excluding: id)
            let clean = try SpendCategory.validateName(name, siblingNames: siblings)
            try db.execute(sql: "UPDATE category SET name = ?, name_key = ?, updated_at = ? WHERE id = ?",
                           arguments: [clean, NameKey.make(clean), Timestamp.now(), id.uuidString])
        }
    }

    /// Hidden categories leave the pickers; old transactions still show them (CAT-003).
    public func setCategoryHidden(_ hidden: Bool, id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE category SET is_hidden = ?, updated_at = ? WHERE id = ? AND system_key IS NOT ?",
                           arguments: [hidden, Timestamp.now(), id.uuidString, DefaultCategories.adjustmentKey])
        }
    }

    /// Saves a new order for one level of the tree (the given ids, in order).
    public func reorderCategories(_ ids: [UUID]) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            for (order, id) in ids.enumerated() {
                try db.execute(sql: "UPDATE category SET sort_order = ?, updated_at = ? WHERE id = ?", arguments: [order, now, id.uuidString])
            }
        }
    }

    /// Deletes an unused category. Blocked when any transaction (deleted ones too) or subcategory uses it (CAT-005).
    public func deleteCategory(id: UUID) throws {
        try database.writer.write { db in
            let inUse = try Int.fetchOne(db, sql: """
                SELECT (SELECT COUNT(*) FROM txn WHERE category_id = ?1)
                     + (SELECT COUNT(*) FROM category WHERE parent_id = ?1 AND deleted_at IS NULL)
                """, arguments: [id.uuidString]) ?? 0
            guard inUse == 0 else { throw SpendCategory.Problem.inUse }
            try Self.requireEditable(db, id)
            try db.execute(sql: "UPDATE payee SET last_category_id = NULL WHERE last_category_id = ?", arguments: [id.uuidString])
            try db.execute(sql: "UPDATE category SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2",
                           arguments: [Timestamp.now(), id.uuidString])
        }
    }

    /// Moves every transaction, payee memory and subcategory of `source` into `target`, then removes `source`,
    /// all in one DB transaction (CAT-004). Budget limits join this when budgets arrive (M4).
    public func mergeCategory(_ source: UUID, into target: UUID) throws {
        try database.writer.write { db in
            guard source != target,
                  let from = try Row.fetchOne(db, sql: "SELECT * FROM category WHERE id = ? AND deleted_at IS NULL", arguments: [source.uuidString]),
                  let into = try Row.fetchOne(db, sql: "SELECT * FROM category WHERE id = ? AND deleted_at IS NULL", arguments: [target.uuidString]),
                  (from["kind"] as String) == (into["kind"] as String), (from["kind"] as String) != CategoryType.system.rawValue
            else { throw SpendCategory.Problem.invalidMerge }
            let hasChildren = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM category WHERE parent_id = ? AND deleted_at IS NULL",
                                                arguments: [source.uuidString]) ?? 0) > 0
            let targetParent: String? = into["parent_id"]
            // A group with subcategories can only merge into another group, which then takes them over.
            if hasChildren && targetParent != nil { throw SpendCategory.Problem.invalidMerge }
            if targetParent == source.uuidString { throw SpendCategory.Problem.invalidMerge }
            let now = Timestamp.now()
            try db.execute(sql: "UPDATE txn SET category_id = ?, updated_at = ? WHERE category_id = ?",
                           arguments: [target.uuidString, now, source.uuidString])
            try db.execute(sql: "UPDATE payee SET last_category_id = ?, updated_at = ? WHERE last_category_id = ?",
                           arguments: [target.uuidString, now, source.uuidString])
            if hasChildren {
                let children = try Row.fetchAll(db, sql: "SELECT id, name FROM category WHERE parent_id = ? AND deleted_at IS NULL",
                                                arguments: [source.uuidString])
                for child in children {
                    let childID: String = child["id"]
                    let match = try String.fetchOne(db, sql: "SELECT id FROM category WHERE parent_id = ? AND name_key = ? AND deleted_at IS NULL",
                                                    arguments: [target.uuidString, NameKey.make(child["name"])])
                    if let match {
                        // Same-named subcategory on both sides: fold into the existing one.
                        try db.execute(sql: "UPDATE txn SET category_id = ?, updated_at = ? WHERE category_id = ?", arguments: [match, now, childID])
                        try db.execute(sql: "UPDATE payee SET last_category_id = ? WHERE last_category_id = ?", arguments: [match, childID])
                        try db.execute(sql: "UPDATE category SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, childID])
                    } else {
                        try db.execute(sql: "UPDATE category SET parent_id = ?, group_key = ?, updated_at = ? WHERE id = ?",
                                       arguments: [target.uuidString, into["group_key"] as String, now, childID])
                    }
                }
            }
            try db.execute(sql: "UPDATE category SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [now, now, source.uuidString])
        }
    }

    /// Transactions per category (deleted ones included, since they block delete).
    public func categoryUsage() throws -> [UUID: Int] {
        try database.writer.read { db in
            var usage: [UUID: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT category_id, COUNT(*) AS n FROM txn WHERE category_id IS NOT NULL GROUP BY category_id") {
                if let id = UUID(uuidString: row["category_id"]) { usage[id] = row["n"] }
            }
            return usage
        }
    }

    /// Payee name key → the category last used with it (CAT-007).
    public func rememberedCategories() throws -> [String: UUID] {
        try database.writer.read { db in
            var map: [String: UUID] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT name_key, last_category_id FROM payee WHERE deleted_at IS NULL AND last_category_id IS NOT NULL ORDER BY use_count") {
                if let id = UUID(uuidString: row["last_category_id"]) { map[row["name_key"]] = id }
            }
            return map
        }
    }

    // MARK: Tags (CAT-006)

    public func tags() throws -> [MoneyTag] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, is_sample FROM tag WHERE deleted_at IS NULL ORDER BY name_key").compactMap { row in
                UUID(uuidString: row["id"]).map { MoneyTag(id: $0, name: row["name"], isSample: row["is_sample"]) }
            }
        }
    }

    @discardableResult
    public func createTag(name: String) throws -> MoneyTag {
        try database.writer.write { db in
            let existing = try String.fetchAll(db, sql: "SELECT name FROM tag WHERE deleted_at IS NULL")
            let clean = try SpendCategory.validateTagName(name, existing: existing)
            let tag = MoneyTag(name: clean)
            let now = Timestamp.now()
            try db.execute(sql: "INSERT INTO tag (id, created_at, updated_at, name, name_key) VALUES (?, ?, ?, ?, ?)",
                           arguments: [tag.id.uuidString, now, now, clean, NameKey.make(clean)])
            return tag
        }
    }

    /// Removes the tag and its links; transactions themselves are untouched.
    public func deleteTag(id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM tag WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Transaction id → its tag ids, for filters and rows.
    public func tagMap() throws -> [UUID: Set<UUID>] {
        try database.writer.read { db in
            var map: [UUID: Set<UUID>] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT txn_id, tag_id FROM txn_tag") {
                if let txn = UUID(uuidString: row["txn_id"]), let tag = UUID(uuidString: row["tag_id"]) { map[txn, default: []].insert(tag) }
            }
            return map
        }
    }

    /// Replaces a transaction's tags.
    public func setTags(_ tagIDs: Set<UUID>, transactionID: UUID) throws {
        try database.writer.write { db in
            guard let sample = try Bool.fetchOne(db, sql: "SELECT is_sample FROM txn WHERE id = ?", arguments: [transactionID.uuidString])
            else { throw Problem.notFound }
            try db.execute(sql: "DELETE FROM txn_tag WHERE txn_id = ?", arguments: [transactionID.uuidString])
            for tag in tagIDs {
                try db.execute(sql: "INSERT INTO txn_tag (txn_id, tag_id, is_sample) VALUES (?, ?, ?)",
                               arguments: [transactionID.uuidString, tag.uuidString, sample])
            }
        }
    }

    // MARK: Attachments (ATT-003)

    public func attachments(transactionID: UUID) throws -> [ReceiptFile] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM attachment WHERE txn_id = ? AND deleted_at IS NULL ORDER BY created_at",
                             arguments: [transactionID.uuidString]).compactMap(Self.receipt)
        }
    }

    /// Transactions that have at least one receipt, for the paperclip on rows.
    public func transactionsWithAttachments() throws -> Set<UUID> {
        try database.writer.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT txn_id FROM attachment WHERE deleted_at IS NULL").compactMap(UUID.init(uuidString:)))
        }
    }

    public func addAttachment(_ file: ReceiptFile) throws {
        try database.writer.write { db in
            guard let sample = try Bool.fetchOne(db, sql: "SELECT is_sample FROM txn WHERE id = ?", arguments: [file.transactionID.uuidString])
            else { throw Problem.notFound }
            let created = Timestamp.from(file.createdAt)
            try db.execute(sql: """
                INSERT INTO attachment (id, created_at, updated_at, is_sample, txn_id, kind, file_name, byte_count)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [file.id.uuidString, created, created, sample, file.transactionID.uuidString,
                                 file.kind.rawValue, file.fileName, file.byteCount])
        }
    }

    /// Removes the row and returns the file name to delete from disk.
    @discardableResult
    public func removeAttachment(id: UUID) throws -> String? {
        try database.writer.write { db in
            let name = try String.fetchOne(db, sql: "SELECT file_name FROM attachment WHERE id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM attachment WHERE id = ?", arguments: [id.uuidString])
            return name
        }
    }

    /// Every file name the database knows, so the store can clear orphans left by a crash.
    public func attachmentFileNames() throws -> Set<String> {
        try database.writer.read { db in Set(try String.fetchAll(db, sql: "SELECT file_name FROM attachment")) }
    }

    // MARK: Helpers

    static func siblingNames(_ db: Database, parentID: UUID?, excluding: UUID?) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT name FROM category WHERE parent_id IS ? AND deleted_at IS NULL AND id IS NOT ?",
                            arguments: [parentID?.uuidString, excluding?.uuidString])
    }

    static func requireEditable(_ db: Database, _ id: UUID) throws {
        let kind = try String.fetchOne(db, sql: "SELECT kind FROM category WHERE id = ? AND deleted_at IS NULL", arguments: [id.uuidString])
        guard let kind else { throw SpendCategory.Problem.notFound }
        guard kind != CategoryType.system.rawValue else { throw SpendCategory.Problem.invalidMerge }
    }

    static func receipt(_ row: Row) -> ReceiptFile? {
        guard let id = UUID(uuidString: row["id"]), let txn = UUID(uuidString: row["txn_id"]),
              let kind = ReceiptFile.Kind(rawValue: row["kind"]) else { return nil }
        return ReceiptFile(id: id, transactionID: txn, kind: kind, fileName: row["file_name"], byteCount: row["byte_count"],
                           createdAt: Timestamp.date(row["created_at"]), isSample: row["is_sample"])
    }
}
