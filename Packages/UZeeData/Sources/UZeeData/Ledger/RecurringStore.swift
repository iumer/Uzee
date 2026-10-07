import Foundation
import GRDB
import UZeeCore

/// Bills, subscriptions, income and plans (REC-01…08, KAM-01…04, LOAN-06). Mark paid posts the linked
/// transaction and the occurrence record in one DB transaction, once (unique item + scheduled date).
public struct RecurringStore: Sendable {
    public enum Problem: Error, Equatable, Sendable {
        case notFound
        case needsAccount
        case invalidAmount
    }

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func snapshot() throws -> RecurringSnapshot {
        try database.writer.read { db in RecurringSnapshot(items: try Self.fetchItems(db), records: try Self.fetchRecords(db)) }
    }

    /// Inserts or updates an item. A changed amount is added to price history from `priceFrom` (REC-03).
    public func save(_ item: RecurringItem, priceFrom: LocalDate? = nil) throws {
        try item.validate()
        try database.writer.write { db in
            let previous = try Self.fetchItems(db, id: item.id).first
            try Self.write(item, db)
            if let previous, previous.amount != item.amount, let from = priceFrom {
                if previous.priceHistory.isEmpty {
                    try Self.addPrice(item.id, PricePoint(effectiveFrom: previous.startedOn ?? previous.rule.anchor, amount: previous.amount),
                                      isSample: item.isSample, db)
                }
                try Self.addPrice(item.id, PricePoint(effectiveFrom: from, amount: item.amount), isSample: item.isSample, db)
            }
        }
    }

    public func delete(itemID: UUID) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: "UPDATE recurring_item SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE id = ?",
                           arguments: [now, UUID().uuidString, now, itemID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    public func setStatus(_ status: SubscriptionStatus, itemID: UUID, on date: LocalDate) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE recurring_item SET subscription_status = ?, status_changed_on = ?, updated_at = ? WHERE id = ?",
                           arguments: [status.rawValue, date.description, Timestamp.now(), itemID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    /// Mark paid (REC-02/08): posts the transaction (split with the item's group when set) and records the
    /// occurrence. Calling it again for the same occurrence returns the first transaction, never a second.
    @discardableResult
    public func markPaid(itemID: UUID, scheduledDate: LocalDate, amount: Money, accountID: UUID?, on date: LocalDate,
                         at time: Date = Date(), timeZone: TimeZone = .current) throws -> MoneyTransaction {
        guard amount.minorUnits > 0 else { throw Problem.invalidAmount }
        return try database.writer.write { db in
            guard let item = try Self.fetchItems(db, id: itemID).first else { throw Problem.notFound }
            if let existing = try Self.liveRecord(db, item: itemID, date: scheduledDate), existing.status == .paid,
               let txn = existing.transactionID, let transaction = try LedgerStore.fetchTransactions(db, from: nil, through: nil, id: txn).first {
                return transaction
            }
            let me = try PeopleStore.selfID(db)
            let payer = item.paidByID ?? me
            guard accountID != nil || payer != me else { throw Problem.needsAccount }
            let kind = item.type.transactionKind
            let inflow = SpendingRules.countsAsIncome(kind)
            let legs = accountID.map {
                [TransactionLeg(accountID: $0, amount: inflow ? amount : Money(minorUnits: -amount.minorUnits, currency: amount.currency), role: .main)]
            } ?? []
            var transaction = MoneyTransaction(kind: kind, occurredAt: time, localDate: date, timeZoneID: timeZone.identifier, amount: amount,
                                               categoryID: item.categoryID, payeeName: item.name, note: Self.note(item, db: db),
                                               source: .recurring, legs: legs, isSample: item.isSample)
            var split: Split?
            if let groupID = item.groupID {
                let members = try PeopleStore.fetchGroups(db).first { $0.id == groupID }?.memberIDs ?? []
                if members.count > 1 {
                    let shares = try SplitCalculator.shares(total: amount, method: .equal, participants: members, firstPayer: payer)
                    let made = Split(transactionID: transaction.id, groupID: groupID, method: .equal,
                                     payers: [SplitPayer(personID: payer, amount: amount)], shares: shares)
                    transaction = PeopleStore.applying(made, to: transaction, me: me)
                    split = made
                }
            }
            try LedgerStore.save(transaction, db)
            if let split { try PeopleStore.insertSplit(split, isSample: transaction.isSample, db) }
            try Self.upsertRecord(OccurrenceRecord(itemID: itemID, scheduledDate: scheduledDate, status: .paid, transactionID: transaction.id),
                                  isSample: item.isSample, db)
            return transaction
        }
    }

    /// Skip this time (REC-08): no transaction, the next date comes up.
    public func skip(itemID: UUID, scheduledDate: LocalDate) throws {
        try database.writer.write { db in
            try Self.upsertRecord(OccurrenceRecord(itemID: itemID, scheduledDate: scheduledDate, status: .skipped),
                                  isSample: try Self.isSample(itemID, db), db)
        }
    }

    /// Snooze (REC-08): moves this occurrence to `until`.
    public func snooze(itemID: UUID, scheduledDate: LocalDate, until: LocalDate) throws {
        try database.writer.write { db in
            try Self.upsertRecord(OccurrenceRecord(itemID: itemID, scheduledDate: scheduledDate, status: .snoozed, snoozedUntil: until),
                                  isSample: try Self.isSample(itemID, db), db)
        }
    }

    /// Undo of Mark paid / Skip / Snooze: the occurrence is due again (its transaction, if any, is removed by the caller).
    public func reopen(itemID: UUID, scheduledDate: LocalDate) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM occurrence WHERE recurring_item_id = ? AND scheduled_date = ?",
                           arguments: [itemID.uuidString, scheduledDate.description])
        }
    }

    /// A kameti payout received (KAM-03): income transaction into the account, linked to the payout.
    @discardableResult
    public func recordPayout(payoutID: UUID, accountID: UUID, on date: LocalDate, at time: Date = Date(),
                             timeZone: TimeZone = .current) throws -> MoneyTransaction {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT p.*, r.name AS item_name, r.is_sample AS item_sample FROM kameti_payout p JOIN recurring_item r ON r.id = p.recurring_item_id
                WHERE p.id = ?
                """, arguments: [payoutID.uuidString]), let currency = Currency.known(code: row["currency_code"]) else { throw Problem.notFound }
            let amount = Money(minorUnits: row["amount_minor"], currency: currency)
            let category = try String.fetchOne(db, sql: "SELECT id FROM category WHERE system_key = 'income.kameti_payout'").flatMap(UUID.init(uuidString:))
            let name: String = row["item_name"]
            let transaction = MoneyTransaction(kind: .kametiPayout, occurredAt: time, localDate: date, timeZoneID: timeZone.identifier,
                                               amount: amount, categoryID: category, payeeName: name, note: "\(name) payout",
                                               source: .recurring, legs: [TransactionLeg(accountID: accountID, amount: amount, role: .main)],
                                               isSample: row["item_sample"])
            try LedgerStore.save(transaction, db)
            try db.execute(sql: "UPDATE kameti_payout SET txn_id = ?, updated_at = ? WHERE id = ?",
                           arguments: [transaction.id.uuidString, Timestamp.now(), payoutID.uuidString])
            return transaction
        }
    }
}

// MARK: - Rows

extension RecurringStore {
    static func note(_ item: RecurringItem, db: Database) -> String? {
        switch item.type {
        case .installment, .kameti: return item.notes
        default: return item.notes
        }
    }

    static func isSample(_ id: UUID, _ db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT is_sample FROM recurring_item WHERE id = ?", arguments: [id.uuidString]) ?? false
    }

    static func fetchItems(_ db: Database, id: UUID? = nil) throws -> [RecurringItem] {
        var prices: [String: [PricePoint]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM price_history WHERE deleted_at IS NULL ORDER BY effective_from") {
            guard let from = LocalDate(row["effective_from"] as String), let currency = Currency.known(code: row["currency_code"]) else { continue }
            prices[row["recurring_item_id"], default: []].append(PricePoint(effectiveFrom: from, amount: Money(minorUnits: row["amount_minor"], currency: currency)))
        }
        var payouts: [String: [KametiPayout]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT p.*, t.deleted_at AS txn_deleted FROM kameti_payout p LEFT JOIN txn t ON t.id = p.txn_id
            WHERE p.deleted_at IS NULL ORDER BY p.expected_date
            """) {
            guard let id = UUID(uuidString: row["id"]), let date = LocalDate(row["expected_date"] as String),
                  let currency = Currency.known(code: row["currency_code"]) else { continue }
            let txn: String? = row["txn_id"]
            let deleted: Int64? = row["txn_deleted"]
            payouts[row["recurring_item_id"], default: []].append(
                KametiPayout(id: id, expectedDate: date, amount: Money(minorUnits: row["amount_minor"], currency: currency),
                             transactionID: deleted == nil ? txn.flatMap(UUID.init(uuidString:)) : nil))
        }
        var sql = "SELECT * FROM recurring_item WHERE deleted_at IS NULL"
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let id { sql += " AND id = ?"; arguments.append(id.uuidString) }
        sql += " ORDER BY sort_order, rowid"
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).compactMap { row in
            guard let id = UUID(uuidString: row["id"]), let currency = Currency.known(code: row["currency_code"]),
                  let anchor = LocalDate(row["anchor_date"] as String), let tracked = LocalDate(row["tracked_from"] as String) else { return nil }
            let end: String? = row["end_date"]
            let account: String? = row["account_id"]
            let category: String? = row["category_id"]
            let group: String? = row["group_id"]
            let paidBy: String? = row["paid_by_person_id"]
            let changed: String? = row["status_changed_on"]
            let started: String? = row["started_on"]
            let key: String = row["id"]
            let rule = RecurrenceRule(unit: RecurrenceUnit(rawValue: row["rule_unit"]) ?? .month, interval: row["rule_interval"], anchor: anchor,
                                      end: end.flatMap(LocalDate.init), limit: row["occurrence_limit"])
            return RecurringItem(id: id, name: row["name"], type: RecurringType(rawValue: row["item_type"]) ?? .other,
                                 amount: Money(minorUnits: row["amount_minor"], currency: currency), isEstimated: row["is_estimated"],
                                 accountID: account.flatMap(UUID.init(uuidString:)), categoryID: category.flatMap(UUID.init(uuidString:)),
                                 groupID: group.flatMap(UUID.init(uuidString:)), paidByID: paidBy.flatMap(UUID.init(uuidString:)),
                                 rule: rule, trackedFrom: tracked, paidBeforeTracking: row["paid_before_tracking"],
                                 status: SubscriptionStatus(rawValue: row["subscription_status"]) ?? .active,
                                 statusChangedAt: changed.flatMap(LocalDate.init), startedOn: started.flatMap(LocalDate.init),
                                 colorHex: row["color_hex"], priceHistory: prices[key] ?? [], payouts: payouts[key] ?? [],
                                 notes: row["notes"], isSample: row["is_sample"])
        }
    }

    /// Stored records; a paid record whose transaction was deleted no longer counts, so the bill is due again.
    static func fetchRecords(_ db: Database) throws -> [OccurrenceRecord] {
        try Row.fetchAll(db, sql: """
            SELECT o.* FROM occurrence o LEFT JOIN txn t ON t.id = o.txn_id
            WHERE o.deleted_at IS NULL AND (o.status != 'paid' OR (t.id IS NOT NULL AND t.deleted_at IS NULL))
            """).compactMap(record)
    }

    static func liveRecord(_ db: Database, item: UUID, date: LocalDate) throws -> OccurrenceRecord? {
        try Row.fetchOne(db, sql: """
            SELECT o.* FROM occurrence o LEFT JOIN txn t ON t.id = o.txn_id
            WHERE o.recurring_item_id = ? AND o.scheduled_date = ? AND (o.status != 'paid' OR (t.id IS NOT NULL AND t.deleted_at IS NULL))
            """, arguments: [item.uuidString, date.description]).flatMap(record)
    }

    private static func record(_ row: Row) -> OccurrenceRecord? {
        guard let item = UUID(uuidString: row["recurring_item_id"]), let date = LocalDate(row["scheduled_date"] as String) else { return nil }
        let until: String? = row["snoozed_until"]
        let txn: String? = row["txn_id"]
        return OccurrenceRecord(itemID: item, scheduledDate: date, status: OccurrenceStatus(rawValue: row["status"]) ?? .scheduled,
                                snoozedUntil: until.flatMap(LocalDate.init), transactionID: txn.flatMap(UUID.init(uuidString:)))
    }

    static func upsertRecord(_ record: OccurrenceRecord, isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO occurrence (id, created_at, updated_at, is_sample, recurring_item_id, scheduled_date, status, snoozed_until, txn_id, resolved_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recurring_item_id, scheduled_date) DO UPDATE SET status = excluded.status, snoozed_until = excluded.snoozed_until,
                txn_id = excluded.txn_id, resolved_at = excluded.resolved_at, updated_at = excluded.updated_at, deleted_at = NULL
            """, arguments: [UUID().uuidString, now, now, isSample, record.itemID.uuidString, record.scheduledDate.description,
                             record.status.rawValue, record.snoozedUntil?.description, record.transactionID?.uuidString, now])
    }

    static func write(_ item: RecurringItem, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO recurring_item (id, created_at, updated_at, is_sample, name, item_type, amount_minor, is_estimated, currency_code,
                account_id, category_id, group_id, paid_by_person_id, rule_unit, rule_interval, anchor_date, end_date, occurrence_limit,
                tracked_from, paid_before_tracking, subscription_status, status_changed_on, started_on, color_hex, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, name = excluded.name, item_type = excluded.item_type,
                amount_minor = excluded.amount_minor, is_estimated = excluded.is_estimated, currency_code = excluded.currency_code,
                account_id = excluded.account_id, category_id = excluded.category_id, group_id = excluded.group_id,
                paid_by_person_id = excluded.paid_by_person_id, rule_unit = excluded.rule_unit, rule_interval = excluded.rule_interval,
                anchor_date = excluded.anchor_date, end_date = excluded.end_date, occurrence_limit = excluded.occurrence_limit,
                tracked_from = excluded.tracked_from, paid_before_tracking = excluded.paid_before_tracking,
                subscription_status = excluded.subscription_status, status_changed_on = excluded.status_changed_on,
                started_on = excluded.started_on, color_hex = excluded.color_hex, notes = excluded.notes
            """, arguments: [item.id.uuidString, now, now, item.isSample, item.name.trimmingCharacters(in: .whitespaces), item.type.rawValue,
                             item.amount.minorUnits, item.isEstimated, item.amount.currency.code, item.accountID?.uuidString,
                             item.categoryID?.uuidString, item.groupID?.uuidString, item.paidByID?.uuidString, item.rule.unit.rawValue,
                             item.rule.interval, item.rule.anchor.description, item.rule.end?.description, item.rule.limit,
                             item.trackedFrom.description, item.paidBeforeTracking, item.status.rawValue, item.statusChangedAt?.description,
                             item.startedOn?.description, item.colorHex, item.notes])
        for payout in item.payouts {
            try db.execute(sql: """
                INSERT INTO kameti_payout (id, created_at, updated_at, is_sample, recurring_item_id, expected_date, amount_minor, currency_code, txn_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET expected_date = excluded.expected_date, amount_minor = excluded.amount_minor, updated_at = excluded.updated_at
                """, arguments: [payout.id.uuidString, now, now, item.isSample, item.id.uuidString, payout.expectedDate.description,
                                 payout.amount.minorUnits, payout.amount.currency.code, payout.transactionID?.uuidString])
        }
    }

    static func addPrice(_ item: UUID, _ point: PricePoint, isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO price_history (id, created_at, updated_at, is_sample, recurring_item_id, effective_from, amount_minor, currency_code)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(recurring_item_id, effective_from) DO UPDATE SET amount_minor = excluded.amount_minor, updated_at = excluded.updated_at
            """, arguments: [UUID().uuidString, now, now, isSample, item.uuidString, point.effectiveFrom.description,
                             point.amount.minorUnits, point.amount.currency.code])
    }
}
