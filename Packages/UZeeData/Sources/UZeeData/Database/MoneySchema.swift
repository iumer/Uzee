import Foundation
import GRDB
import UZeeCore

/// Schema for currencies, rates, categories, payees, accounts, transactions and legs (DATA_MODEL §3.3–3.9).
/// Money is INTEGER minor units, rates TEXT decimals, timestamps INTEGER ms UTC, days TEXT 'YYYY-MM-DD'.
enum MoneySchema {
    /// Placeholder owner until households arrive (PRD §18); one value in v1.
    static let ownerID = "local"

    /// Standard columns on every synced table (DATA_MODEL §1 "S").
    static func standardColumns(_ t: TableDefinition) {
        t.primaryKey("id", .text)
        t.column("owner_id", .text).notNull().defaults(to: ownerID)
        t.column("created_at", .integer).notNull()
        t.column("updated_at", .integer).notNull()
        t.column("deleted_at", .integer)
        t.column("deletion_batch_id", .text)
        t.column("is_sample", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
    }

    static func create(_ db: Database) throws {
        try db.create(table: "currency") { t in
            t.primaryKey("code", .text)
            t.column("minor_units", .integer).notNull().defaults(to: 2)
            t.column("symbol", .text).notNull()
            t.column("is_enabled", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
            t.column("sort_order", .integer).notNull().defaults(to: 0)
        }
        for (index, currency) in Currency.known.enumerated() {
            try db.execute(sql: "INSERT INTO currency (code, minor_units, symbol, is_enabled, sort_order) VALUES (?, ?, ?, ?, ?)",
                           arguments: [currency.code, currency.minorUnits, currency.symbol,
                                       currency == .pkr || currency == .usd, index])
        }

        try db.create(table: "exchange_rate") { t in
            standardColumns(t)
            t.column("currency_code", .text).notNull().references("currency")
            t.column("base_currency_code", .text).notNull().defaults(to: "PKR").references("currency")
            t.column("rate", .text).notNull()
            t.column("effective_from", .integer).notNull()
            t.column("source", .text).notNull().defaults(to: "manual")
        }
        try db.create(index: "exchange_rate_current", on: "exchange_rate", columns: ["currency_code", "effective_from"])
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO exchange_rate (id, created_at, updated_at, currency_code, base_currency_code, rate, effective_from)
            VALUES (?, ?, ?, 'USD', 'PKR', '280', 0)
            """, arguments: [UUID().uuidString, now, now])

        try db.create(table: "category") { t in
            standardColumns(t)
            t.column("kind", .text).notNull()
            t.column("parent_id", .text).references("category")
            t.column("name", .text).notNull()
            t.column("name_key", .text).notNull()
            t.column("group_key", .text).notNull()
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("is_hidden", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
            t.column("system_key", .text)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX category_system_key ON category(system_key) WHERE system_key IS NOT NULL")
        try db.execute(sql: "CREATE INDEX category_parent ON category(parent_id, sort_order)")
        for (order, node) in DefaultCategories.all.enumerated() {
            let parentID = UUID().uuidString
            try insertCategory(db, id: parentID, node: node, name: node.name, key: node.key, parentID: nil, order: order, now: now)
            for (childOrder, child) in node.children.enumerated() {
                try insertCategory(db, id: UUID().uuidString, node: node, name: child.name, key: child.key,
                                   parentID: parentID, order: childOrder, now: now)
            }
        }

        try db.create(table: "account") { t in
            standardColumns(t)
            t.column("name", .text).notNull()
            t.column("name_key", .text).notNull()
            t.column("kind", .text).notNull()
            t.column("currency_code", .text).notNull().references("currency")
            t.column("opening_balance_minor", .integer).notNull().defaults(to: 0)
            t.column("opening_date", .text).notNull()
            t.column("include_in_totals", .integer).notNull().defaults(to: 1).check { [0, 1].contains($0) }
            t.column("symbol_name", .text).notNull()
            t.column("color_hex", .text).notNull()
            t.column("sort_order", .integer).notNull().defaults(to: 0)
            t.column("archived_at", .integer)
            t.column("institution_hint", .text)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX account_name ON account(name_key) WHERE deleted_at IS NULL")

        try db.create(table: "payee") { t in
            standardColumns(t)
            t.column("name", .text).notNull()
            t.column("name_key", .text).notNull()
            t.column("last_category_id", .text).references("category", onDelete: .setNull)
            t.column("last_account_id", .text).references("account", onDelete: .setNull)
            t.column("use_count", .integer).notNull().defaults(to: 0)
        }
        // Sample and real payees with the same name stay separate rows (PRV-04).
        try db.execute(sql: "CREATE UNIQUE INDEX payee_name ON payee(name_key, is_sample) WHERE deleted_at IS NULL")

        try db.create(table: "txn") { t in
            standardColumns(t)
            t.column("kind", .text).notNull()
            t.column("status", .text).notNull().defaults(to: "posted")
            t.column("occurred_at", .integer).notNull()
            t.column("local_date", .text).notNull()
            t.column("time_zone_id", .text).notNull()
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("currency_code", .text).notNull().references("currency")
            t.column("my_share_minor", .integer).notNull()
            t.column("category_id", .text).references("category")
            t.column("payee_id", .text).references("payee", onDelete: .setNull)
            t.column("note", .text)
            t.column("fx_rate", .text)
            t.column("source", .text).notNull().defaults(to: "manual")
        }
        try db.execute(sql: "CREATE INDEX txn_date ON txn(local_date DESC) WHERE deleted_at IS NULL")
        try db.execute(sql: "CREATE INDEX txn_category ON txn(category_id, local_date)")
        try db.execute(sql: "CREATE INDEX txn_sample ON txn(is_sample)")

        try db.create(table: "transaction_leg") { t in
            standardColumns(t)
            t.column("txn_id", .text).notNull().references("txn", onDelete: .cascade)
            t.column("account_id", .text).notNull().references("account", onDelete: .restrict)
            t.column("amount_minor", .integer).notNull().check { $0 != 0 }
            t.column("currency_code", .text).notNull()
            t.column("role", .text).notNull().defaults(to: "main")
        }
        try db.execute(sql: "CREATE UNIQUE INDEX leg_role ON transaction_leg(txn_id, role)")
        try db.execute(sql: "CREATE INDEX leg_account ON transaction_leg(account_id, txn_id)")
    }

    private static func insertCategory(_ db: Database, id: String, node: DefaultCategories.Node, name: String, key: String,
                                       parentID: String?, order: Int, now: Int64) throws {
        try db.execute(sql: """
            INSERT INTO category (id, created_at, updated_at, kind, parent_id, name, name_key, group_key, sort_order, system_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [id, now, now, node.type.rawValue, parentID, name, NameKey.make(name), node.group.rawValue, order, key])
    }
}

/// Date ↔ INTEGER milliseconds since 1970 UTC (DATA_MODEL §1).
enum Timestamp {
    static func now() -> Int64 { from(Date()) }
    static func from(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000) }
}
