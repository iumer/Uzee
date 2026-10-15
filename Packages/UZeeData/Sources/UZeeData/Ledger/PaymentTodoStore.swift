import Foundation
import GRDB
import UZeeCore

/// Plan › To pay (owner, 2026-10-15): payments to make, paid in full or in parts, with no month or date.
extension EventStore {
    /// Open ones first (oldest first), then the paid ones, newest paid first.
    public func paymentTodos() throws -> [PaymentTodo] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM payment_todo WHERE deleted_at IS NULL ORDER BY done_at IS NOT NULL, done_at DESC, created_at")
                .compactMap { row in
                    guard let id = UUID(uuidString: row["id"]), let currency = Currency.known(code: row["currency_code"]) else { return nil }
                    let done: Int64? = row["done_at"]
                    return PaymentTodo(id: id, name: row["name"], amount: Money(minorUnits: row["amount_minor"], currency: currency),
                                       paid: Money(minorUnits: row["paid_minor"], currency: currency),
                                       createdAt: Timestamp.date(row["created_at"]), doneAt: done.map(Timestamp.date))
                }
        }
    }

    /// Inserts or updates one.
    public func save(_ todo: PaymentTodo) throws {
        try todo.validate()
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO payment_todo (id, created_at, updated_at, name, amount_minor, paid_minor, currency_code, done_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, name = excluded.name, amount_minor = excluded.amount_minor,
                    paid_minor = excluded.paid_minor, currency_code = excluded.currency_code, done_at = excluded.done_at
                """, arguments: [todo.id.uuidString, Timestamp.from(todo.createdAt), now, todo.name.trimmingCharacters(in: .whitespaces),
                                 todo.amount.minorUnits, todo.paid.minorUnits, todo.amount.currency.code, todo.doneAt.map(Timestamp.from)])
        }
    }

    public func deletePaymentTodo(_ id: UUID) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: "UPDATE payment_todo SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [now, UUID().uuidString, now, id.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }
}
