// UZee · Built by iUmer Farooq
// Copyright (c) 2026 iUmer Farooq. All rights reserved. See LICENSE.

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
                    let due: Int64? = row["due_date"]
                    let reminder: Int64? = row["reminder_at"]
                    let direction = PaymentTodo.Direction(rawValue: row["direction"] ?? "pay") ?? .pay
                    // Paid is the sum of its payments, never a stored number (owner, 2026-11-03).
                    let paid = (try? Self.payments(db, todoID: id, currency: currency))?.reduce(Int64(0)) { $0 + $1.amount.minorUnits } ?? 0
                    let amount = Money(minorUnits: row["amount_minor"], currency: currency)
                    // Done only while it's still all paid: lowering a payment in Activity reopens it.
                    let stillDone = paid >= amount.minorUnits
                    return PaymentTodo(id: id, direction: direction, name: row["name"], amount: amount,
                                       paid: Money(minorUnits: paid, currency: currency),
                                       createdAt: Timestamp.date(row["created_at"]),
                                       doneAt: stillDone ? (done.map(Timestamp.date) ?? Timestamp.date(row["updated_at"])) : nil,
                                       dueDate: due.map(Timestamp.date), reminderAt: reminder.map(Timestamp.date))
                }
        }
    }

    /// Its payments, newest first. A linked one counts its transaction as it is now (amount, date, account); a deleted
    /// transaction drops its payment, and restoring the transaction brings it back.
    public func todoPayments(_ todoID: UUID) throws -> [TodoPayment] {
        try database.writer.read { db in
            guard let code = try String.fetchOne(db, sql: "SELECT currency_code FROM payment_todo WHERE id = ?", arguments: [todoID.uuidString]),
                  let currency = Currency.known(code: code) else { return [] }
            return try Self.payments(db, todoID: todoID, currency: currency)
        }
    }

    static func payments(_ db: Database, todoID: UUID, currency: Currency) throws -> [TodoPayment] {
        try Row.fetchAll(db, sql: """
            SELECT p.*, t.amount_minor AS txn_amount, t.currency_code AS txn_currency, t.occurred_at AS txn_at, t.deleted_at AS txn_deleted,
                   t.id AS txn_found, l.account_id AS txn_account
            FROM payment_todo_payment p
            LEFT JOIN txn t ON t.id = p.txn_id
            LEFT JOIN transaction_leg l ON l.txn_id = t.id AND l.role = 'main'
            WHERE p.todo_id = ? AND p.deleted_at IS NULL
            ORDER BY COALESCE(t.occurred_at, p.paid_at) DESC
            """, arguments: [todoID.uuidString]).compactMap { row -> TodoPayment? in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let txnID: String? = row["txn_id"]
            var amount: Int64 = row["amount_minor"]
            var at: Int64 = row["paid_at"]
            var account: String? = row["account_id"]
            if txnID != nil {
                let found: String? = row["txn_found"]
                let deleted: Int64? = row["txn_deleted"]
                guard found != nil, deleted == nil else { return nil }
                if (row["txn_currency"] as String?) == currency.code { amount = row["txn_amount"] }
                at = row["txn_at"]
                account = row["txn_account"] ?? account
            }
            return TodoPayment(id: id, todoID: todoID, amount: Money(minorUnits: amount, currency: currency), paidAt: Timestamp.date(at),
                               transactionID: txnID.flatMap(UUID.init(uuidString:)), accountID: account.flatMap(UUID.init(uuidString:)),
                               isEarlier: row["is_earlier"])
        }
    }

    /// Records one payment (and keeps the old paid column in step for older builds reading a backup).
    public func addTodoPayment(_ payment: TodoPayment) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO payment_todo_payment (id, created_at, updated_at, todo_id, amount_minor, currency_code, paid_at, txn_id, account_id, is_earlier)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, amount_minor = excluded.amount_minor, paid_at = excluded.paid_at,
                    txn_id = excluded.txn_id, account_id = excluded.account_id, deleted_at = NULL
                """, arguments: [payment.id.uuidString, now, now, payment.todoID.uuidString, payment.amount.minorUnits, payment.amount.currency.code,
                                 Timestamp.from(payment.paidAt), payment.transactionID?.uuidString, payment.accountID?.uuidString, payment.isEarlier])
            try Self.syncPaid(db, payment.todoID)
        }
    }

    /// Changes an unlinked payment's amount, date or account (a linked one is changed through its transaction).
    public func updateTodoPayment(_ payment: TodoPayment) throws {
        guard payment.amount.minorUnits > 0 else { throw PaymentTodo.Problem.invalidAmount }
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_todo_payment SET amount_minor = ?, paid_at = ?, account_id = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [payment.amount.minorUnits, Timestamp.from(payment.paidAt), payment.accountID?.uuidString, Timestamp.now(),
                                       payment.id.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
            try Self.syncPaid(db, payment.todoID)
        }
    }

    public func deleteTodoPayment(_ id: UUID) throws {
        try database.writer.write { db in
            guard let todo = try String.fetchOne(db, sql: "SELECT todo_id FROM payment_todo_payment WHERE id = ?", arguments: [id.uuidString]) else {
                throw Problem.notFound
            }
            try db.execute(sql: "UPDATE payment_todo_payment SET deleted_at = ?, updated_at = ? WHERE id = ?", arguments: [Timestamp.now(), Timestamp.now(), id.uuidString])
            if let todoID = UUID(uuidString: todo) { try Self.syncPaid(db, todoID) }
        }
    }

    public func restoreTodoPayment(_ id: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_todo_payment SET deleted_at = NULL, updated_at = ? WHERE id = ?", arguments: [Timestamp.now(), id.uuidString])
            if let todo = try String.fetchOne(db, sql: "SELECT todo_id FROM payment_todo_payment WHERE id = ?", arguments: [id.uuidString]),
               let todoID = UUID(uuidString: todo) { try Self.syncPaid(db, todoID) }
        }
    }

    /// An "Earlier payments" row with no link, and exactly one entry in Activity with the to-do's name, made after it,
    /// that no other payment uses: offered as a one-tap link ("Use Rs 400,000 from Activity?"), never linked silently.
    public func suggestedLink(_ todoID: UUID) throws -> (payment: UUID, transaction: UUID, amount: Money)? {
        try database.writer.read { db in
            guard let todo = try Row.fetchOne(db, sql: "SELECT * FROM payment_todo WHERE id = ? AND deleted_at IS NULL", arguments: [todoID.uuidString]),
                  let currency = Currency.known(code: todo["currency_code"]),
                  let earlier = try String.fetchOne(db, sql: """
                    SELECT id FROM payment_todo_payment WHERE todo_id = ? AND deleted_at IS NULL AND is_earlier = 1 AND txn_id IS NULL
                    """, arguments: [todoID.uuidString]),
                  let earlierID = UUID(uuidString: earlier) else { return nil }
            let kind = (todo["direction"] as String?) == "receive" ? "income" : "expense"
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.id, t.amount_minor FROM txn t JOIN payee p ON p.id = t.payee_id
                WHERE t.deleted_at IS NULL AND t.kind = ? AND t.currency_code = ? AND lower(p.name) = lower(?) AND t.created_at >= ?
                  AND t.id NOT IN (SELECT txn_id FROM payment_todo_payment WHERE txn_id IS NOT NULL AND deleted_at IS NULL)
                """, arguments: [kind, currency.code, todo["name"] as String, todo["created_at"] as Int64])
            guard rows.count == 1, let txn = UUID(uuidString: rows[0]["id"]) else { return nil }
            return (earlierID, txn, Money(minorUnits: rows[0]["amount_minor"], currency: currency))
        }
    }

    public func linkTodoPayment(_ paymentID: UUID, transactionID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_todo_payment SET txn_id = ?, is_earlier = 0, updated_at = ? WHERE id = ?",
                           arguments: [transactionID.uuidString, Timestamp.now(), paymentID.uuidString])
            if let todo = try String.fetchOne(db, sql: "SELECT todo_id FROM payment_todo_payment WHERE id = ?", arguments: [paymentID.uuidString]),
               let todoID = UUID(uuidString: todo) { try Self.syncPaid(db, todoID) }
        }
    }

    /// "Put back on the list": its payments are set aside (the entries they made stay in Activity).
    public func clearTodoPayments(_ todoID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE payment_todo_payment SET deleted_at = ?, updated_at = ? WHERE todo_id = ? AND deleted_at IS NULL",
                           arguments: [Timestamp.now(), Timestamp.now(), todoID.uuidString])
            try Self.syncPaid(db, todoID)
        }
    }

    /// The old paid column follows the payments, so an older UZee reading a backup sees the right total.
    static func syncPaid(_ db: Database, _ todoID: UUID) throws {
        guard let code = try String.fetchOne(db, sql: "SELECT currency_code FROM payment_todo WHERE id = ?", arguments: [todoID.uuidString]),
              let currency = Currency.known(code: code) else { return }
        let paid = try payments(db, todoID: todoID, currency: currency).reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        // Done when it's all paid, open again when a payment goes down or away.
        try db.execute(sql: """
            UPDATE payment_todo SET paid_minor = ?1,
                done_at = CASE WHEN ?1 >= amount_minor THEN COALESCE(done_at, ?2) ELSE NULL END
            WHERE id = ?3
            """, arguments: [paid, Timestamp.now(), todoID.uuidString])
    }

    /// Inserts or updates one.
    public func save(_ todo: PaymentTodo) throws {
        try todo.validate()
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO payment_todo (id, created_at, updated_at, name, amount_minor, paid_minor, currency_code, done_at, due_date, reminder_at, direction)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, name = excluded.name, amount_minor = excluded.amount_minor,
                    currency_code = excluded.currency_code, done_at = excluded.done_at,
                    due_date = excluded.due_date, reminder_at = excluded.reminder_at, direction = excluded.direction,
                    deleted_at = NULL, deletion_batch_id = NULL
                """, arguments: [todo.id.uuidString, Timestamp.from(todo.createdAt), now, todo.name.trimmingCharacters(in: .whitespaces),
                                 todo.amount.minorUnits, todo.paid.minorUnits, todo.amount.currency.code, todo.doneAt.map(Timestamp.from),
                                 todo.dueDate.map(Timestamp.from), todo.reminderAt.map(Timestamp.from), todo.direction.rawValue])
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
