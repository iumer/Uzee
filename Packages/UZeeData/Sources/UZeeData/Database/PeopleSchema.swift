import Foundation
import GRDB

/// M5 tables: people, groups and members, splits with payers and shares, loans and payments, and the
/// settlement links on `txn` (DATA_MODEL §3.13–3.16). The loan points at the transaction that created
/// it (`txn_id`), so deleting that transaction takes the loan with it.
enum PeopleSchema {
    static func create(_ db: Database) throws {
        try db.create(table: "person") { t in
            MoneySchema.standardColumns(t)
            t.column("display_name", .text).notNull()
            t.column("name_key", .text).notNull()
            t.column("is_self", .integer).notNull().defaults(to: 0).check { [0, 1].contains($0) }
            t.column("phone", .text)
            t.column("notes", .text)
            t.column("archived_at", .integer)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX person_self ON person(is_self) WHERE is_self = 1 AND deleted_at IS NULL")
        try db.execute(sql: "CREATE INDEX person_name ON person(name_key)")
        let now = Timestamp.now()
        try db.execute(sql: "INSERT INTO person (id, created_at, updated_at, display_name, name_key, is_self) VALUES (?, ?, ?, 'You', 'you', 1)",
                       arguments: [UUID().uuidString, now, now])

        try db.create(table: "split_group") { t in
            MoneySchema.standardColumns(t)
            t.column("name", .text).notNull()
            t.column("icon", .text).notNull().defaults(to: "people")
            t.column("default_split_method", .text).notNull().defaults(to: "equal")
            t.column("simplify_debts", .integer).notNull().defaults(to: 1).check { [0, 1].contains($0) }
            t.column("archived_at", .integer)
        }

        try db.create(table: "group_member") { t in
            MoneySchema.standardColumns(t)
            t.column("group_id", .text).notNull().references("split_group", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person", onDelete: .restrict)
            t.column("sort_order", .integer).notNull().defaults(to: 0)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX group_member_unique ON group_member(group_id, person_id)")
        try db.execute(sql: "CREATE INDEX group_member_person ON group_member(person_id)")

        try db.alter(table: "txn") { t in
            t.add(column: "counterparty_person_id", .text).references("person")
            t.add(column: "group_id", .text).references("split_group")
        }
        try db.execute(sql: "CREATE INDEX txn_counterparty ON txn(counterparty_person_id)")

        try db.create(table: "split") { t in
            MoneySchema.standardColumns(t)
            t.column("txn_id", .text).notNull().unique().references("txn", onDelete: .cascade)
            t.column("group_id", .text).references("split_group")
            t.column("method", .text).notNull()
        }
        try db.execute(sql: "CREATE INDEX split_group_index ON split(group_id)")

        try db.create(table: "split_payer") { t in
            MoneySchema.standardColumns(t)
            t.column("split_id", .text).notNull().references("split", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person")
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("currency_code", .text).notNull()
        }
        try db.execute(sql: "CREATE UNIQUE INDEX split_payer_unique ON split_payer(split_id, person_id)")
        try db.execute(sql: "CREATE INDEX split_payer_person ON split_payer(person_id)")

        try db.create(table: "split_share") { t in
            MoneySchema.standardColumns(t)
            t.column("split_id", .text).notNull().references("split", onDelete: .cascade)
            t.column("person_id", .text).notNull().references("person")
            t.column("input_value", .integer)
            t.column("share_minor", .integer).notNull().check { $0 >= 0 }
            t.column("currency_code", .text).notNull()
            t.column("sort_order", .integer).notNull().defaults(to: 0)
        }
        try db.execute(sql: "CREATE UNIQUE INDEX split_share_unique ON split_share(split_id, person_id)")
        try db.execute(sql: "CREATE INDEX split_share_person ON split_share(person_id)")

        try db.create(table: "loan") { t in
            MoneySchema.standardColumns(t)
            t.column("direction", .text).notNull()
            t.column("person_id", .text).references("person")
            t.column("institution_name", .text)
            t.column("principal_minor", .integer).notNull().check { $0 > 0 }
            t.column("currency_code", .text).notNull().references("currency")
            t.column("start_date", .text).notNull()
            t.column("due_date", .text)
            t.column("interest_rate_bps", .integer)
            t.column("txn_id", .text).references("txn", onDelete: .cascade)
            t.column("written_off_at", .integer)
            t.column("notes", .text)
            t.check(sql: "person_id IS NOT NULL OR institution_name IS NOT NULL")
        }
        try db.execute(sql: "CREATE INDEX loan_person ON loan(person_id)")
        try db.execute(sql: "CREATE INDEX loan_due ON loan(due_date)")

        try db.create(table: "loan_payment") { t in
            MoneySchema.standardColumns(t)
            t.column("loan_id", .text).notNull().references("loan", onDelete: .cascade)
            t.column("txn_id", .text).references("txn", onDelete: .cascade)
            t.column("amount_minor", .integer).notNull().check { $0 > 0 }
            t.column("paid_on", .text).notNull()
        }
        try db.execute(sql: "CREATE INDEX loan_payment_loan ON loan_payment(loan_id)")
        try db.execute(sql: "CREATE UNIQUE INDEX loan_payment_txn ON loan_payment(txn_id) WHERE txn_id IS NOT NULL")
    }
}
