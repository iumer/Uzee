import Foundation
import GRDB
import UZeeCore

/// Reads and writes accounts, transactions, rates and categories. Every write is one DB transaction
/// (TXN-012); balances are always derived (ACC-03).
public struct LedgerStore: Sendable {
    public enum Problem: Error, Equatable, Sendable {
        case notFound
        case duplicateName
        case currencyLocked
        /// Accounts with transactions are archived, never deleted (ACC-005).
        case accountHasTransactions
    }

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: Reads

    public func snapshot(base: Currency = .pkr) throws -> LedgerSnapshot {
        try database.writer.read { db in
            let accounts = try Self.fetchAccounts(db)
            let transactions = try Self.fetchTransactions(db, from: nil, through: nil)
            let rates = try Self.fetchRates(db)
            let balances = try BalanceCalculator.balances(of: accounts, transactions: transactions)
            let available = try BalanceCalculator.available(accounts: accounts, balances: balances, base: base, rates: rates)
            let counted = accounts.filter { $0.includeInTotals && !$0.isArchived }
            return LedgerSnapshot(base: base, accounts: accounts, balances: balances, available: available,
                                  footnote: RateTable.footnote(for: Set(counted.map(\.currency)), base: base, rates: rates),
                                  rates: rates, categories: try Self.fetchCategories(db))
        }
    }

    public func accounts() throws -> [Account] {
        try database.writer.read { db in try Self.fetchAccounts(db) }
    }

    public func categories() throws -> [SpendCategory] {
        try database.writer.read { db in try Self.fetchCategories(db) }
    }

    public func rates() throws -> [String: Decimal] {
        try database.writer.read { db in try Self.fetchRates(db) }
    }

    /// Non-deleted transactions, newest first, optionally limited to a date range.
    public func transactions(from start: LocalDate? = nil, through end: LocalDate? = nil) throws -> [MoneyTransaction] {
        try database.writer.read { db in try Self.fetchTransactions(db, from: start, through: end) }
    }

    public func transaction(id: UUID) throws -> MoneyTransaction? {
        try database.writer.read { db in try Self.fetchTransactions(db, from: nil, through: nil, id: id).first }
    }

    /// Account of the most recent manual entry, to preselect in the Add sheet (TXN-010).
    public func lastUsedAccountID() throws -> UUID? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: """
                SELECT l.account_id FROM transaction_leg l JOIN txn t ON t.id = l.txn_id
                WHERE t.deleted_at IS NULL AND l.role = 'main' ORDER BY t.created_at DESC LIMIT 1
                """).flatMap(UUID.init(uuidString:))
        }
    }

    // MARK: Accounts

    @discardableResult
    public func createAccount(name: String, kind: AccountKind, currency: Currency, openingBalance: Money? = nil,
                              openingDate: LocalDate, includeInTotals: Bool = true, colorHex: String = "#007AFF") throws -> Account {
        try database.writer.write { db in
            let existing = try String.fetchAll(db, sql: "SELECT name FROM account WHERE deleted_at IS NULL AND is_sample = 0")
            let cleanName: String
            do { cleanName = try Account.validateName(name, existingNames: existing) } catch {
                if (error as? Account.Problem) == .duplicateName { throw Problem.duplicateName }
                throw error
            }
            let order = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order) + 1, 0) FROM account") ?? 0
            let account = Account(name: cleanName, kind: kind, currency: currency, openingBalance: openingBalance,
                                  openingDate: openingDate, includeInTotals: includeInTotals, colorHex: colorHex, sortOrder: order)
            try Self.insert(account, db)
            return account
        }
    }

    public func updateAccount(_ account: Account) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT currency_code FROM account WHERE id = ? AND deleted_at IS NULL",
                                             arguments: [account.id.uuidString]) else { throw Problem.notFound }
            let others = try String.fetchAll(db, sql: """
                SELECT name FROM account WHERE deleted_at IS NULL AND id != ?1
                  AND is_sample = (SELECT is_sample FROM account WHERE id = ?1)
                """, arguments: [account.id.uuidString])
            do { _ = try Account.validateName(account.name, existingNames: others) } catch {
                if (error as? Account.Problem) == .duplicateName { throw Problem.duplicateName }
                throw error
            }
            let oldCode: String = row["currency_code"]
            if oldCode != account.currency.code, try Self.legCount(db, accountID: account.id) > 0 {
                throw Problem.currencyLocked
            }
            try db.execute(sql: """
                UPDATE account SET name = ?, name_key = ?, kind = ?, currency_code = ?, opening_balance_minor = ?,
                    opening_date = ?, include_in_totals = ?, symbol_name = ?, color_hex = ?, sort_order = ?,
                    archived_at = ?, updated_at = ?
                WHERE id = ?
                """, arguments: [account.name.trimmingCharacters(in: .whitespacesAndNewlines), NameKey.make(account.name),
                                 account.kind.rawValue, account.currency.code, account.openingBalance.minorUnits,
                                 account.openingDate.description, account.includeInTotals, account.kind.symbolName,
                                 account.colorHex, account.sortOrder, account.archivedAt.map(Timestamp.from),
                                 Timestamp.now(), account.id.uuidString])
        }
    }

    public func setArchived(_ archived: Bool, accountID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE account SET archived_at = ?, updated_at = ? WHERE id = ?",
                           arguments: [archived ? Timestamp.now() : nil, Timestamp.now(), accountID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    /// Soft-deletes an account with no transactions; otherwise it must be archived (ACC-005).
    public func deleteAccount(id: UUID) throws {
        try database.writer.write { db in
            guard try Self.legCount(db, accountID: id) == 0 else { throw Problem.accountHasTransactions }
            try db.execute(sql: "UPDATE account SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE id = ?",
                           arguments: [Timestamp.now(), UUID().uuidString, Timestamp.now(), id.uuidString])
        }
    }

    public func hasTransactions(accountID: UUID) throws -> Bool {
        try database.writer.read { db in try Self.legCount(db, accountID: accountID) > 0 }
    }

    // MARK: Transactions

    /// Inserts or replaces a transaction and its legs atomically (TXN-012).
    /// A transaction touching a sample account is itself sample, so removal never orphans it (PRV-04).
    public func save(_ transaction: MoneyTransaction) throws {
        try database.writer.write { db in try Self.save(transaction, db) }
    }

    /// Soft delete: hidden from lists and totals, restorable from Recently Deleted (TXN-008).
    public func delete(transactionID: UUID) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            let batch = UUID().uuidString
            try db.execute(sql: "UPDATE txn SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [now, batch, now, transactionID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
            try db.execute(sql: "UPDATE transaction_leg SET deleted_at = ?, deletion_batch_id = ?, updated_at = ? WHERE txn_id = ?",
                           arguments: [now, batch, now, transactionID.uuidString])
        }
    }

    /// Undo right after saving: removes the row for good, so it never shows in Recently Deleted (TXN-013).
    public func discard(transactionID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM txn WHERE id = ?", arguments: [transactionID.uuidString])
        }
    }

    // MARK: Rates

    /// Adds a new current rate; old rows stay so history shows which rate was used (CUR-010).
    public func setRate(_ rate: Decimal, for currency: Currency, base: Currency = .pkr, at date: Date = Date()) throws {
        try database.writer.write { db in
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO exchange_rate (id, created_at, updated_at, currency_code, base_currency_code, rate, effective_from)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, currency.code, base.code,
                                 ExchangeRate.storageString(rate), Timestamp.from(date)])
        }
    }
}

// MARK: - Row mapping

extension LedgerStore {
    static func fetchAccounts(_ db: Database) throws -> [Account] {
        try Row.fetchAll(db, sql: "SELECT * FROM account WHERE deleted_at IS NULL ORDER BY sort_order, name_key").compactMap { row in
            guard let id = UUID(uuidString: row["id"]), let currency = Currency.known(code: row["currency_code"]),
                  let opening = LocalDate(row["opening_date"] as String) else { return nil }
            let archived: Int64? = row["archived_at"]
            return Account(id: id, name: row["name"], kind: AccountKind(rawValue: row["kind"]) ?? .other, currency: currency,
                           openingBalance: Money(minorUnits: row["opening_balance_minor"], currency: currency),
                           openingDate: opening, includeInTotals: row["include_in_totals"], colorHex: row["color_hex"],
                           sortOrder: row["sort_order"], archivedAt: archived.map(Timestamp.date), isSample: row["is_sample"])
        }
    }

    static func fetchCategories(_ db: Database) throws -> [SpendCategory] {
        try Row.fetchAll(db, sql: "SELECT * FROM category WHERE deleted_at IS NULL ORDER BY sort_order").compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let parent: String? = row["parent_id"]
            return SpendCategory(id: id, type: CategoryType(rawValue: row["kind"]) ?? .expense, parentID: parent.flatMap(UUID.init(uuidString:)),
                            name: row["name"], group: CategoryKind(rawValue: row["group_key"]) ?? .other,
                            systemKey: row["system_key"], sortOrder: row["sort_order"], isHidden: row["is_hidden"])
        }
    }

    /// Latest rate per currency (CUR-04).
    static func fetchRates(_ db: Database) throws -> [String: Decimal] {
        var rates: [String: Decimal] = [:]
        let rows = try Row.fetchAll(db, sql: """
            SELECT currency_code, rate FROM exchange_rate WHERE deleted_at IS NULL
            ORDER BY effective_from, created_at
            """)
        for row in rows {
            if let rate = ExchangeRate.fromStorage(row["rate"]) { rates[row["currency_code"]] = rate }
        }
        return rates
    }

    /// `deleted` reads Recently Deleted instead: soft-deleted rows with the legs deleted alongside them.
    static func fetchTransactions(_ db: Database, from start: LocalDate?, through end: LocalDate?, id: UUID? = nil,
                                  deleted: Bool = false) throws -> [MoneyTransaction] {
        var conditions = [deleted ? "t.deleted_at IS NOT NULL" : "t.deleted_at IS NULL"]
        var arguments: [(any DatabaseValueConvertible)?] = []
        if let start { conditions.append("t.local_date >= ?"); arguments.append(start.description) }
        if let end { conditions.append("t.local_date <= ?"); arguments.append(end.description) }
        if let id { conditions.append("t.id = ?"); arguments.append(id.uuidString) }
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.*, p.name AS payee_name FROM txn t LEFT JOIN payee p ON p.id = t.payee_id
            WHERE \(conditions.joined(separator: " AND "))
            ORDER BY \(deleted ? "t.deleted_at DESC," : "") t.local_date DESC, t.occurred_at DESC
            """, arguments: StatementArguments(arguments))
        var legsByTxn: [String: [TransactionLeg]] = [:]
        let legRows = try Row.fetchAll(db, sql: """
            SELECT l.* FROM transaction_leg l JOIN txn t ON t.id = l.txn_id
            WHERE \(deleted ? "l.deletion_batch_id IS t.deletion_batch_id" : "l.deleted_at IS NULL") AND \(conditions.joined(separator: " AND "))
            ORDER BY l.role
            """, arguments: StatementArguments(arguments))
        for row in legRows {
            guard let account = UUID(uuidString: row["account_id"]), let currency = Currency.known(code: row["currency_code"]) else { continue }
            legsByTxn[row["txn_id"], default: []].append(
                TransactionLeg(accountID: account, amount: Money(minorUnits: row["amount_minor"], currency: currency),
                               role: LegRole(rawValue: row["role"]) ?? .main))
        }
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]), let currency = Currency.known(code: row["currency_code"]),
                  let localDate = LocalDate(row["local_date"] as String) else { return nil }
            let category: String? = row["category_id"]
            let counterparty: String? = row["counterparty_person_id"]
            let group: String? = row["group_id"]
            let rate: String? = row["fx_rate"]
            let deleted: Int64? = row["deleted_at"]
            let legs = (legsByTxn[row["id"]] ?? []).sorted { order($0.role) < order($1.role) }
            return MoneyTransaction(
                id: id, kind: TransactionKind(rawValue: row["kind"]) ?? .expense,
                status: TransactionStatus(rawValue: row["status"]) ?? .posted,
                occurredAt: Timestamp.date(row["occurred_at"]), localDate: localDate, timeZoneID: row["time_zone_id"],
                amount: Money(minorUnits: row["amount_minor"], currency: currency),
                myShare: Money(minorUnits: row["my_share_minor"], currency: currency),
                categoryID: category.flatMap(UUID.init(uuidString:)), payeeName: row["payee_name"], note: row["note"],
                fxRate: rate.flatMap(ExchangeRate.fromStorage), source: EntrySource(rawValue: row["source"]) ?? .manual,
                counterpartyID: counterparty.flatMap(UUID.init(uuidString:)), groupID: group.flatMap(UUID.init(uuidString:)),
                legs: legs, createdAt: Timestamp.date(row["created_at"]), updatedAt: Timestamp.date(row["updated_at"]),
                deletedAt: deleted.map(Timestamp.date), isSample: row["is_sample"])
        }
    }

    private static func order(_ role: LegRole) -> Int {
        switch role { case .main: 0; case .transferOut: 1; case .transferIn: 2 }
    }

    static func legCount(_ db: Database, accountID: UUID) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transaction_leg WHERE account_id = ? AND deleted_at IS NULL",
                         arguments: [accountID.uuidString]) ?? 0
    }

    static func insert(_ account: Account, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO account (id, created_at, updated_at, is_sample, name, name_key, kind, currency_code,
                opening_balance_minor, opening_date, include_in_totals, symbol_name, color_hex, sort_order, archived_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [account.id.uuidString, now, now, account.isSample, account.name, NameKey.make(account.name),
                             account.kind.rawValue, account.currency.code, account.openingBalance.minorUnits,
                             account.openingDate.description, account.includeInTotals, account.kind.symbolName,
                             account.colorHex, account.sortOrder, account.archivedAt.map(Timestamp.from)])
    }

    static func save(_ transaction: MoneyTransaction, _ db: Database) throws {
        var transaction = transaction
        let legAccounts = transaction.legs.map(\.accountID.uuidString)
        if !legAccounts.isEmpty {
            let placeholders = Array(repeating: "?", count: legAccounts.count).joined(separator: ",")
            let sampleLegs = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM account WHERE is_sample = 1 AND id IN (\(placeholders))",
                                              arguments: StatementArguments(legAccounts)) ?? 0
            if sampleLegs > 0 { transaction.isSample = true }
        }
        if transaction.kind == .adjustment && transaction.categoryID == nil {
            transaction.categoryID = try String.fetchOne(db, sql: "SELECT id FROM category WHERE system_key = ?",
                                                         arguments: [DefaultCategories.adjustmentKey]).flatMap(UUID.init(uuidString:))
        }
        let payeeID = try transaction.payeeName.map { try upsertPayee($0, transaction: transaction, db) }
        let id = transaction.id.uuidString
        try db.execute(sql: "DELETE FROM transaction_leg WHERE txn_id = ?", arguments: [id])
        try db.execute(sql: """
            INSERT INTO txn (id, created_at, updated_at, deleted_at, is_sample, kind, status, occurred_at, local_date, time_zone_id,
                amount_minor, currency_code, my_share_minor, category_id, payee_id, note, fx_rate, source,
                counterparty_person_id, group_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at, deleted_at = excluded.deleted_at,
                kind = excluded.kind, status = excluded.status, occurred_at = excluded.occurred_at,
                local_date = excluded.local_date, time_zone_id = excluded.time_zone_id, amount_minor = excluded.amount_minor,
                currency_code = excluded.currency_code, my_share_minor = excluded.my_share_minor,
                category_id = excluded.category_id, payee_id = excluded.payee_id, note = excluded.note,
                fx_rate = excluded.fx_rate, source = excluded.source,
                counterparty_person_id = excluded.counterparty_person_id, group_id = excluded.group_id
            """, arguments: [id, Timestamp.from(transaction.createdAt), Timestamp.from(transaction.updatedAt),
                             transaction.deletedAt.map(Timestamp.from), transaction.isSample, transaction.kind.rawValue,
                             transaction.status.rawValue, Timestamp.from(transaction.occurredAt),
                             transaction.localDate.description, transaction.timeZoneID, transaction.amount.minorUnits,
                             transaction.amount.currency.code, transaction.myShare.minorUnits,
                             transaction.categoryID?.uuidString, payeeID, transaction.note,
                             transaction.fxRate.map(ExchangeRate.storageString), transaction.source.rawValue,
                             transaction.counterpartyID?.uuidString, transaction.groupID?.uuidString])
        for leg in transaction.legs {
            let now = Timestamp.from(transaction.updatedAt)
            try db.execute(sql: """
                INSERT INTO transaction_leg (id, created_at, updated_at, is_sample, txn_id, account_id, amount_minor, currency_code, role)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, transaction.isSample, id, leg.accountID.uuidString,
                                 leg.amount.minorUnits, leg.amount.currency.code, leg.role.rawValue])
        }
    }

    private static func upsertPayee(_ name: String, transaction: MoneyTransaction, _ db: Database) throws -> String {
        let key = NameKey.make(name)
        let account = transaction.legs.first?.accountID.uuidString
        if let existing = try String.fetchOne(db, sql: "SELECT id FROM payee WHERE name_key = ? AND is_sample = ? AND deleted_at IS NULL",
                                              arguments: [key, transaction.isSample]) {
            try db.execute(sql: """
                UPDATE payee SET last_category_id = COALESCE(?, last_category_id), last_account_id = COALESCE(?, last_account_id),
                    use_count = use_count + 1, updated_at = ? WHERE id = ?
                """, arguments: [transaction.categoryID?.uuidString, account, Timestamp.now(), existing])
            return existing
        }
        let id = UUID().uuidString
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO payee (id, created_at, updated_at, is_sample, name, name_key, last_category_id, last_account_id, use_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, arguments: [id, now, now, transaction.isSample, name, key, transaction.categoryID?.uuidString, account])
        return id
    }
}
