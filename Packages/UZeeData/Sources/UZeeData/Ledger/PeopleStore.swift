import Foundation
import GRDB
import UZeeCore

/// People, groups, splits, loans and settlements (LOAN-01…05, LOAN-08, SPL-01…12). Every write is one
/// DB transaction; balances are never stored, `PeopleLedger` computes them from these rows.
public struct PeopleStore: Sendable {
    public enum Problem: Error, Equatable, Sendable {
        case notFound
        case invalidAmount
        /// A person or group with money still between you is archived, not deleted.
        case hasBalance
        case needsAccount
    }

    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Everything the People screens need, read in one go.
    public struct Snapshot: Sendable {
        public var selfID: UUID
        public var people: [Person]
        public var groups: [SplitGroup]
        public var splits: [Split]
        public var loans: [Loan]

        public init(selfID: UUID, people: [Person], groups: [SplitGroup], splits: [Split], loans: [Loan]) {
            self.selfID = selfID
            self.people = people
            self.groups = groups
            self.splits = splits
            self.loans = loans
        }
    }

    public func snapshot() throws -> Snapshot {
        try database.writer.read { db in
            Snapshot(selfID: try Self.selfID(db), people: try Self.fetchPeople(db), groups: try Self.fetchGroups(db),
                     splits: try Self.fetchSplits(db), loans: try Self.fetchLoans(db))
        }
    }

    public func selfID() throws -> UUID {
        try database.writer.read { db in try Self.selfID(db) }
    }

    // MARK: People

    @discardableResult
    public func createPerson(name: String, phone: String? = nil, notes: String? = nil) throws -> Person {
        try database.writer.write { db in try Self.insertPerson(Person(name: try Person.validateName(name), phone: phone, notes: notes), db) }
    }

    public func updatePerson(_ person: Person) throws {
        try database.writer.write { db in
            let name = try Person.validateName(person.name)
            try db.execute(sql: """
                UPDATE person SET display_name = ?, name_key = ?, phone = ?, notes = ?, archived_at = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [name, NameKey.make(name), person.phone, person.notes, person.archivedAt.map(Timestamp.from),
                                 Timestamp.now(), person.id.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    // MARK: Groups

    /// Creates a group; "You" is always a member and comes first (SPL-02).
    @discardableResult
    public func createGroup(name: String, icon: GroupIcon, memberIDs: [UUID], method: SplitMethod = .equal) throws -> SplitGroup {
        try database.writer.write { db in
            let clean = try Person.validateName(name)
            let me = try Self.selfID(db)
            let members = [me] + memberIDs.filter { $0 != me }
            let group = SplitGroup(name: clean, icon: icon, memberIDs: members, defaultMethod: method)
            try Self.insertGroup(group, db)
            return group
        }
    }

    public func updateGroup(_ group: SplitGroup) throws {
        try database.writer.write { db in
            let clean = try Person.validateName(group.name)
            try db.execute(sql: """
                UPDATE split_group SET name = ?, icon = ?, default_split_method = ?, simplify_debts = ?, archived_at = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [clean, group.icon.rawValue, group.defaultMethod.rawValue, group.simplifyDebts,
                                 group.archivedAt.map(Timestamp.from), Timestamp.now(), group.id.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
            let me = try Self.selfID(db)
            let members = [me] + group.memberIDs.filter { $0 != me }
            let isSample = try Bool.fetchOne(db, sql: "SELECT is_sample FROM split_group WHERE id = ?", arguments: [group.id.uuidString]) ?? false
            try db.execute(sql: "DELETE FROM group_member WHERE group_id = ?", arguments: [group.id.uuidString])
            try Self.insertMembers(group.id, members, isSample: isSample, db)
        }
    }

    // MARK: Splits

    /// Saves a transaction with its split in one DB transaction (SPL-03…06, SPL-10). The account leg becomes
    /// what I paid (or received, for income); no leg when someone else paid. `myShare` becomes my share.
    public func save(_ transaction: MoneyTransaction, split: Split?) throws {
        try database.writer.write { db in
            var transaction = transaction
            let me = try Self.selfID(db)
            if let split {
                try split.validate(total: transaction.amount)
                transaction = Self.applying(split, to: transaction, me: me)
            }
            try LedgerStore.save(transaction, db)
            try db.execute(sql: "DELETE FROM split WHERE txn_id = ?", arguments: [transaction.id.uuidString])
            if var split {
                split.transactionID = transaction.id
                try Self.insertSplit(split, isSample: transaction.isSample, db)
            }
        }
    }

    /// The transaction as it is stored for `split`: one leg for my part, or none.
    public static func applying(_ split: Split, to transaction: MoneyTransaction, me: UUID) -> MoneyTransaction {
        var result = transaction
        result.myShare = split.share(of: me) ?? .zero(transaction.amount.currency)
        let account = transaction.legs.first?.accountID
        if let paid = split.paid(by: me), let account {
            let income = SpendingRules.countsAsIncome(transaction.kind) || transaction.kind == .refund
            result.legs = [TransactionLeg(accountID: account, amount: income ? paid : Money(minorUnits: -paid.minorUnits, currency: paid.currency),
                                          role: .main)]
        } else {
            result.legs = []
        }
        return result
    }

    // MARK: Loans

    /// Lend or borrow (LOAN-05): the account transaction and the loan in one go. Without an account it is
    /// an existing balance (LOAN-08): the loan only, no money moves.
    @discardableResult
    public func recordLoan(direction: LoanDirection, personID: UUID, amount: Money, accountID: UUID?, on date: LocalDate,
                           at time: Date = Date(), timeZone: TimeZone = .current, dueDate: LocalDate? = nil,
                           note: String? = nil, source: EntrySource = .manual) throws -> Loan {
        guard amount.minorUnits > 0 else { throw Problem.invalidAmount }
        return try database.writer.write { db in
            var transactionID: UUID?
            if let accountID {
                let name = try Self.personName(personID, db)
                let transaction = MoneyTransaction(
                    kind: direction == .lent ? .loanOut : .loanIn, occurredAt: time, localDate: date, timeZoneID: timeZone.identifier,
                    amount: amount, payeeName: name, note: note ?? (direction == .lent ? "Lent to \(name)" : "Borrowed from \(name)"),
                    source: source, counterpartyID: personID,
                    legs: [TransactionLeg(accountID: accountID, amount: direction == .lent ? Money(minorUnits: -amount.minorUnits, currency: amount.currency) : amount,
                                          role: .main)])
                try LedgerStore.save(transaction, db)
                transactionID = transaction.id
            }
            let loan = Loan(direction: direction, personID: personID, principal: amount, startDate: date, dueDate: dueDate,
                            transactionID: transactionID, notes: note)
            try Self.insertLoan(loan, isSample: try Self.isSamplePerson(personID, db), db)
            return loan
        }
    }

    /// A repayment (LOAN-03): money in for a loan I gave, money out for one I took.
    @discardableResult
    public func recordRepayment(loanID: UUID, amount: Money, accountID: UUID, on date: LocalDate, at time: Date = Date(),
                                timeZone: TimeZone = .current) throws -> MoneyTransaction {
        try database.writer.write { db in
            guard let loan = try Self.fetchLoans(db).first(where: { $0.id == loanID }) else { throw Problem.notFound }
            try LoanCalculator.validatePayment(amount, for: loan)
            let name = try loan.personID.map { try Self.personName($0, db) } ?? loan.institution ?? "Loan"
            let transaction = MoneyTransaction(
                kind: .repayment, occurredAt: time, localDate: date, timeZoneID: timeZone.identifier, amount: amount,
                payeeName: name, note: loan.direction == .lent ? "\(name) repaid" : "Repaid \(name)", counterpartyID: loan.personID,
                legs: [TransactionLeg(accountID: accountID, amount: loan.direction == .lent ? amount : Money(minorUnits: -amount.minorUnits, currency: amount.currency),
                                      role: .main)])
            try LedgerStore.save(transaction, db)
            let now = Timestamp.now()
            try db.execute(sql: """
                INSERT INTO loan_payment (id, created_at, updated_at, is_sample, loan_id, txn_id, amount_minor, paid_on)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, loan.isSample || transaction.isSample, loanID.uuidString,
                                 transaction.id.uuidString, amount.minorUnits, date.description])
            return transaction
        }
    }

    /// Write off (or undo): no money moves, the loan stops counting (LOAN-02 "Written off").
    public func setWrittenOff(_ writtenOff: Bool, loanID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE loan SET written_off_at = ?, updated_at = ? WHERE id = ?",
                           arguments: [writtenOff ? Timestamp.now() : nil, Timestamp.now(), loanID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    public func setDueDate(_ date: LocalDate?, interestBasisPoints: Int?, loanID: UUID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE loan SET due_date = ?, interest_rate_bps = ?, updated_at = ? WHERE id = ?",
                           arguments: [date?.description, interestBasisPoints, Timestamp.now(), loanID.uuidString])
            guard db.changesCount == 1 else { throw Problem.notFound }
        }
    }

    /// Existing balances (LOAN-08): one row per name. A name that matches someone adds to their balance;
    /// a new name creates the person. No account money moves.
    public func addExistingBalances(_ rows: [(name: String, direction: LoanDirection, amount: Money)], on date: LocalDate) throws {
        try database.writer.write { db in
            for row in rows where row.amount.minorUnits > 0 {
                let name = try Person.validateName(row.name)
                let person: UUID
                if let id = try String.fetchOne(db, sql: """
                    SELECT id FROM person WHERE name_key = ? AND deleted_at IS NULL AND is_self = 0 ORDER BY is_sample LIMIT 1
                    """, arguments: [NameKey.make(name)]).flatMap(UUID.init(uuidString:)) {
                    person = id
                } else {
                    person = try Self.insertPerson(Person(name: name), db).id
                }
                try Self.insertLoan(Loan(direction: row.direction, personID: person, principal: row.amount, startDate: date),
                                    isSample: try Self.isSamplePerson(person, db), db)
            }
        }
    }

    // MARK: Settle up

    /// Settle up (SPL-08): `iPaid` sends money from the account to the person; otherwise they paid me.
    @discardableResult
    public func settle(personID: UUID, groupID: UUID?, amount: Money, iPaid: Bool, accountID: UUID, on date: LocalDate,
                       at time: Date = Date(), timeZone: TimeZone = .current) throws -> MoneyTransaction {
        guard amount.minorUnits > 0 else { throw Problem.invalidAmount }
        return try database.writer.write { db in
            let name = try Self.personName(personID, db)
            let transaction = MoneyTransaction(
                kind: .settlement, occurredAt: time, localDate: date, timeZoneID: timeZone.identifier, amount: amount,
                payeeName: name, note: iPaid ? "You paid \(name)" : "\(name) paid you", counterpartyID: personID, groupID: groupID,
                legs: [TransactionLeg(accountID: accountID, amount: iPaid ? Money(minorUnits: -amount.minorUnits, currency: amount.currency) : amount,
                                      role: .main)])
            try LedgerStore.save(transaction, db)
            return transaction
        }
    }
}

// MARK: - Rows

extension PeopleStore {
    static func selfID(_ db: Database) throws -> UUID {
        guard let id = try String.fetchOne(db, sql: "SELECT id FROM person WHERE is_self = 1 AND deleted_at IS NULL").flatMap(UUID.init(uuidString:))
        else { throw Problem.notFound }
        return id
    }

    static func personName(_ id: UUID, _ db: Database) throws -> String {
        guard let name = try String.fetchOne(db, sql: "SELECT display_name FROM person WHERE id = ?", arguments: [id.uuidString])
        else { throw Problem.notFound }
        return name
    }

    static func isSamplePerson(_ id: UUID, _ db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT is_sample FROM person WHERE id = ?", arguments: [id.uuidString]) ?? false
    }

    static func fetchPeople(_ db: Database) throws -> [Person] {
        try Row.fetchAll(db, sql: "SELECT * FROM person WHERE deleted_at IS NULL ORDER BY is_self DESC, name_key").compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let archived: Int64? = row["archived_at"]
            return Person(id: id, name: row["display_name"], phone: row["phone"], notes: row["notes"], isSelf: row["is_self"],
                          archivedAt: archived.map(Timestamp.date), isSample: row["is_sample"])
        }
    }

    static func fetchGroups(_ db: Database) throws -> [SplitGroup] {
        var members: [String: [UUID]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT group_id, person_id FROM group_member WHERE deleted_at IS NULL ORDER BY sort_order") {
            if let person = UUID(uuidString: row["person_id"]) { members[row["group_id"], default: []].append(person) }
        }
        return try Row.fetchAll(db, sql: "SELECT * FROM split_group WHERE deleted_at IS NULL ORDER BY created_at, rowid").compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let archived: Int64? = row["archived_at"]
            return SplitGroup(id: id, name: row["name"], icon: GroupIcon(rawValue: row["icon"]) ?? .people, memberIDs: members[row["id"]] ?? [],
                              defaultMethod: SplitMethod(rawValue: row["default_split_method"]) ?? .equal,
                              simplifyDebts: row["simplify_debts"], archivedAt: archived.map(Timestamp.date), isSample: row["is_sample"])
        }
    }

    /// Splits of live transactions only, so deleting a transaction takes its split out of every balance.
    static func fetchSplits(_ db: Database) throws -> [Split] {
        var payers: [String: [SplitPayer]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM split_payer ORDER BY rowid") {
            guard let person = UUID(uuidString: row["person_id"]), let currency = Currency.known(code: row["currency_code"]) else { continue }
            payers[row["split_id"], default: []].append(SplitPayer(personID: person, amount: Money(minorUnits: row["amount_minor"], currency: currency)))
        }
        var shares: [String: [SplitShare]] = [:]
        for row in try Row.fetchAll(db, sql: "SELECT * FROM split_share ORDER BY sort_order") {
            guard let person = UUID(uuidString: row["person_id"]), let currency = Currency.known(code: row["currency_code"]) else { continue }
            shares[row["split_id"], default: []].append(SplitShare(personID: person, input: row["input_value"],
                                                                   share: Money(minorUnits: row["share_minor"], currency: currency)))
        }
        return try Row.fetchAll(db, sql: """
            SELECT s.* FROM split s JOIN txn t ON t.id = s.txn_id
            WHERE s.deleted_at IS NULL AND t.deleted_at IS NULL ORDER BY t.local_date DESC, t.occurred_at DESC
            """).compactMap { row in
            guard let txn = UUID(uuidString: row["txn_id"]) else { return nil }
            let group: String? = row["group_id"]
            let id: String = row["id"]
            return Split(transactionID: txn, groupID: group.flatMap(UUID.init(uuidString:)),
                         method: SplitMethod(rawValue: row["method"]) ?? .equal, payers: payers[id] ?? [], shares: shares[id] ?? [])
        }
    }

    /// Loans whose creating transaction is live (or that are existing balances), with live payments.
    static func fetchLoans(_ db: Database) throws -> [Loan] {
        var payments: [String: [LoanPayment]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT p.* FROM loan_payment p LEFT JOIN txn t ON t.id = p.txn_id
            WHERE p.deleted_at IS NULL AND (p.txn_id IS NULL OR t.deleted_at IS NULL) ORDER BY p.paid_on
            """) {
            guard let id = UUID(uuidString: row["id"]), let paidOn = LocalDate(row["paid_on"] as String) else { continue }
            let txn: String? = row["txn_id"]
            payments[row["loan_id"], default: []].append(
                LoanPayment(id: id, transactionID: txn.flatMap(UUID.init(uuidString:)),
                            amount: Money(minorUnits: row["amount_minor"], currency: .pkr), paidOn: paidOn))
        }
        return try Row.fetchAll(db, sql: """
            SELECT l.* FROM loan l LEFT JOIN txn t ON t.id = l.txn_id
            WHERE l.deleted_at IS NULL AND (l.txn_id IS NULL OR t.deleted_at IS NULL) ORDER BY l.start_date DESC, l.created_at DESC
            """).compactMap { row in
            guard let id = UUID(uuidString: row["id"]), let currency = Currency.known(code: row["currency_code"]),
                  let start = LocalDate(row["start_date"] as String) else { return nil }
            let person: String? = row["person_id"]
            let due: String? = row["due_date"]
            let txn: String? = row["txn_id"]
            let writtenOff: Int64? = row["written_off_at"]
            let loanPayments = (payments[row["id"]] ?? []).map {
                LoanPayment(id: $0.id, transactionID: $0.transactionID, amount: Money(minorUnits: $0.amount.minorUnits, currency: currency), paidOn: $0.paidOn)
            }
            return Loan(id: id, direction: LoanDirection(rawValue: row["direction"]) ?? .lent, personID: person.flatMap(UUID.init(uuidString:)),
                        institution: row["institution_name"], principal: Money(minorUnits: row["principal_minor"], currency: currency),
                        startDate: start, dueDate: due.flatMap(LocalDate.init), interestBasisPoints: row["interest_rate_bps"],
                        transactionID: txn.flatMap(UUID.init(uuidString:)), writtenOffAt: writtenOff.map(Timestamp.date),
                        notes: row["notes"], payments: loanPayments, isSample: row["is_sample"])
        }
    }

    @discardableResult
    static func insertPerson(_ person: Person, _ db: Database) throws -> Person {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO person (id, created_at, updated_at, is_sample, display_name, name_key, is_self, phone, notes)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
            """, arguments: [person.id.uuidString, now, now, person.isSample, person.name, NameKey.make(person.name), person.phone, person.notes])
        return person
    }

    static func insertGroup(_ group: SplitGroup, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO split_group (id, created_at, updated_at, is_sample, name, icon, default_split_method, simplify_debts)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [group.id.uuidString, now, now, group.isSample, group.name, group.icon.rawValue,
                             group.defaultMethod.rawValue, group.simplifyDebts])
        try insertMembers(group.id, group.memberIDs, isSample: group.isSample, db)
    }

    static func insertMembers(_ group: UUID, _ members: [UUID], isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        for (index, person) in members.enumerated() {
            try db.execute(sql: """
                INSERT INTO group_member (id, created_at, updated_at, is_sample, group_id, person_id, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, isSample, group.uuidString, person.uuidString, index])
        }
    }

    static func insertSplit(_ split: Split, isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO split (id, created_at, updated_at, is_sample, txn_id, group_id, method) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       arguments: [id, now, now, isSample, split.transactionID.uuidString, split.groupID?.uuidString, split.method.rawValue])
        for payer in split.payers {
            try db.execute(sql: """
                INSERT INTO split_payer (id, created_at, updated_at, is_sample, split_id, person_id, amount_minor, currency_code)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, isSample, id, payer.personID.uuidString, payer.amount.minorUnits,
                                 payer.amount.currency.code])
        }
        for (index, share) in split.shares.enumerated() {
            try db.execute(sql: """
                INSERT INTO split_share (id, created_at, updated_at, is_sample, split_id, person_id, input_value, share_minor, currency_code, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, now, now, isSample, id, share.personID.uuidString, share.input,
                                 share.share.minorUnits, share.share.currency.code, index])
        }
    }

    static func insertLoan(_ loan: Loan, isSample: Bool, _ db: Database) throws {
        let now = Timestamp.now()
        try db.execute(sql: """
            INSERT INTO loan (id, created_at, updated_at, is_sample, direction, person_id, institution_name, principal_minor, currency_code,
                start_date, due_date, interest_rate_bps, txn_id, written_off_at, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [loan.id.uuidString, now, now, isSample || loan.isSample, loan.direction.rawValue, loan.personID?.uuidString,
                             loan.institution, loan.principal.minorUnits, loan.principal.currency.code, loan.startDate.description,
                             loan.dueDate?.description, loan.interestBasisPoints, loan.transactionID?.uuidString,
                             loan.writtenOffAt.map(Timestamp.from), loan.notes])
        for payment in loan.payments {
            try db.execute(sql: """
                INSERT INTO loan_payment (id, created_at, updated_at, is_sample, loan_id, txn_id, amount_minor, paid_on)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [payment.id.uuidString, now, now, isSample || loan.isSample, loan.id.uuidString,
                                 payment.transactionID?.uuidString, payment.amount.minorUnits, payment.paidOn.description])
        }
    }
}
