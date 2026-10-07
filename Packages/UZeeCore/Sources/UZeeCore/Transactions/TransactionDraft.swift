import Foundation

/// What the Add and Transfer sheets collect before saving. `TransactionValidator` turns it into a
/// `MoneyTransaction` with the right legs, or explains what is wrong (TXN-009, SMK-012).
public struct TransactionDraft: Sendable, Equatable {
    public var kind: TransactionKind
    public var status: TransactionStatus
    /// Positive amount in the account's currency (for a transfer: the amount sent).
    public var amount: Money?
    public var accountID: UUID?
    /// Transfer only: destination account and the amount it received.
    public var toAccountID: UUID?
    public var receivedAmount: Money?
    /// Adjustment only: true when the real balance is higher than the derived one.
    public var adjustmentIncreases: Bool
    public var categoryID: UUID?
    public var payeeName: String?
    public var note: String?
    public var occurredAt: Date
    public var timeZone: TimeZone
    public var source: EntrySource

    public init(kind: TransactionKind, status: TransactionStatus = .posted, amount: Money? = nil,
                accountID: UUID? = nil, toAccountID: UUID? = nil, receivedAmount: Money? = nil,
                adjustmentIncreases: Bool = false, categoryID: UUID? = nil, payeeName: String? = nil,
                note: String? = nil, occurredAt: Date = Date(), timeZone: TimeZone = .current,
                source: EntrySource = .manual) {
        self.kind = kind
        self.status = status
        self.amount = amount
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.receivedAmount = receivedAmount
        self.adjustmentIncreases = adjustmentIncreases
        self.categoryID = categoryID
        self.payeeName = payeeName
        self.note = note
        self.occurredAt = occurredAt
        self.timeZone = timeZone
        self.source = source
    }
}

/// Why a draft cannot be saved. Each case has its own message in the UI (TXN-009).
public enum TransactionProblem: Error, Equatable, Sendable {
    case missingAmount
    case zeroAmount
    case missingAccount
    case unknownAccount
    case archivedAccount
    case currencyDiffersFromAccount
    case missingDestination
    case sameAccount
    case missingReceivedAmount
    case zeroReceivedAmount
    case missingCategory
    case noteTooLong
    case unsupportedKind
    case amountTooLarge
}

public enum TransactionValidator {
    public static let maxNoteLength = 500

    /// Builds the transaction to save. `existing` keeps id and createdAt when editing.
    /// `base` and `tableRate` are used only to store the real rate of a cross-currency transfer.
    public static func build(_ draft: TransactionDraft, accounts: [Account], base: Currency = .pkr,
                             existing: MoneyTransaction? = nil, now: Date = Date()) throws(TransactionProblem) -> MoneyTransaction {
        guard let amount = draft.amount else { throw .missingAmount }
        guard amount.minorUnits > 0 else { throw .zeroAmount }
        guard let accountID = draft.accountID else { throw .missingAccount }
        guard let account = accounts.first(where: { $0.id == accountID }) else { throw .unknownAccount }
        // Editing an old row on an account archived since is allowed; new rows need a live account.
        if account.isArchived && existing?.legs.contains(where: { $0.accountID == accountID }) != true {
            throw .archivedAccount
        }
        guard amount.currency == account.currency else { throw .currencyDiffersFromAccount }
        if let note = draft.note, note.count > maxNoteLength { throw .noteTooLong }
        if SpendingRules.needsCategory(draft.kind) && draft.kind != .adjustment && draft.categoryID == nil {
            throw .missingCategory
        }

        var legs: [TransactionLeg]
        var fxRate: Decimal?
        do {
            switch draft.kind {
            case .expense, .kametiContribution, .installment, .loanOut:
                legs = [TransactionLeg(accountID: accountID, amount: try amount.negated(), role: .main)]
            case .income, .refund, .kametiPayout, .loanIn:
                legs = [TransactionLeg(accountID: accountID, amount: amount, role: .main)]
            case .adjustment:
                legs = [TransactionLeg(accountID: accountID, amount: draft.adjustmentIncreases ? amount : try amount.negated(), role: .main)]
            case .transfer:
                guard let toID = draft.toAccountID else { throw TransactionProblem.missingDestination }
                guard toID != accountID else { throw TransactionProblem.sameAccount }
                guard let to = accounts.first(where: { $0.id == toID }) else { throw TransactionProblem.unknownAccount }
                if to.isArchived && existing?.legs.contains(where: { $0.accountID == toID }) != true {
                    throw TransactionProblem.archivedAccount
                }
                let received: Money
                if to.currency == account.currency {
                    received = amount
                } else {
                    guard let value = draft.receivedAmount else { throw TransactionProblem.missingReceivedAmount }
                    guard value.minorUnits > 0 else { throw TransactionProblem.zeroReceivedAmount }
                    guard value.currency == to.currency else { throw TransactionProblem.currencyDiffersFromAccount }
                    received = value
                    let (foreign, baseSide) = account.currency == base ? (value, amount) : (amount, value)
                    fxRate = Rounding.halfUp(baseSide.decimalValue / foreign.decimalValue, scale: 6)
                }
                legs = [
                    TransactionLeg(accountID: accountID, amount: try amount.negated(), role: .transferOut),
                    TransactionLeg(accountID: toID, amount: received, role: .transferIn)
                ]
            case .repayment, .settlement:
                throw TransactionProblem.unsupportedKind
            }
        } catch let problem as TransactionProblem {
            throw problem
        } catch {
            throw .amountTooLarge
        }

        let trimmedPayee = draft.payeeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MoneyTransaction(
            id: existing?.id ?? UUID(),
            kind: draft.kind,
            status: draft.status,
            occurredAt: draft.occurredAt,
            localDate: LocalDate(draft.occurredAt, in: draft.timeZone),
            timeZoneID: draft.timeZone.identifier,
            amount: amount,
            myShare: amount,
            categoryID: draft.kind == .transfer ? nil : draft.categoryID,
            payeeName: trimmedPayee?.isEmpty == false ? trimmedPayee : nil,
            note: trimmedNote?.isEmpty == false ? trimmedNote : nil,
            fxRate: fxRate,
            source: draft.source,
            legs: legs,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            isSample: existing?.isSample ?? false
        )
    }

    /// The draft that reproduces a saved transaction, for edit and "Repeat this" (TXN-014).
    public static func draft(from transaction: MoneyTransaction, timeZone: TimeZone? = nil) -> TransactionDraft {
        let main = transaction.legs.first { $0.role != .transferIn }
        let incoming = transaction.legs.first { $0.role == .transferIn }
        return TransactionDraft(
            kind: transaction.kind,
            status: transaction.status,
            amount: transaction.amount,
            accountID: main?.accountID,
            toAccountID: incoming?.accountID,
            receivedAmount: incoming?.amount,
            adjustmentIncreases: (main?.amount.minorUnits ?? 0) > 0,
            categoryID: transaction.categoryID,
            payeeName: transaction.payeeName,
            note: transaction.note,
            occurredAt: transaction.occurredAt,
            timeZone: timeZone ?? TimeZone(identifier: transaction.timeZoneID) ?? .current,
            source: transaction.source
        )
    }
}
