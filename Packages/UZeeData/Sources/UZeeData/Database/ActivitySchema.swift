import Foundation
import GRDB

/// M3 tables: tags, transaction tags and receipt attachments (DATA_MODEL §3.10–3.12).
/// Categories and payees already exist from v3_money.
enum ActivitySchema {
    static func create(_ db: Database) throws {
        try db.create(table: "tag") { t in
            MoneySchema.standardColumns(t)
            t.column("name", .text).notNull()
            t.column("name_key", .text).notNull()
        }
        try db.execute(sql: "CREATE UNIQUE INDEX tag_name ON tag(name_key, is_sample) WHERE deleted_at IS NULL")

        try db.create(table: "txn_tag") { t in
            t.column("txn_id", .text).notNull().references("txn", onDelete: .cascade)
            t.column("tag_id", .text).notNull().references("tag", onDelete: .cascade)
            t.column("is_sample", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
            t.primaryKey(["txn_id", "tag_id"])
        }
        try db.execute(sql: "CREATE INDEX txn_tag_tag ON txn_tag(tag_id)")

        try db.create(table: "attachment") { t in
            MoneySchema.standardColumns(t)
            t.column("txn_id", .text).notNull().references("txn", onDelete: .cascade)
            t.column("kind", .text).notNull()
            t.column("file_name", .text).notNull().unique()
            t.column("byte_count", .integer).notNull()
        }
        try db.execute(sql: "CREATE INDEX attachment_txn ON attachment(txn_id)")
        try db.execute(sql: "CREATE INDEX txn_deleted ON txn(deleted_at) WHERE deleted_at IS NOT NULL")
    }
}
