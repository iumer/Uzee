import Foundation

/// What a transaction did (DATA_MODEL §3.6). Raw values are stored; never rename them.
public enum TransactionKind: String, CaseIterable, Sendable, Codable {
    case expense, income, transfer, refund, adjustment
    case loanOut, loanIn, repayment, settlement
    case kametiContribution, kametiPayout, installment

    public var name: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        case .refund: "Refund"
        case .adjustment: "Balance adjustment"
        case .loanOut: "Lent"
        case .loanIn: "Borrowed"
        case .repayment: "Repayment"
        case .settlement: "Settle up"
        case .kametiContribution: "Kameti contribution"
        case .kametiPayout: "Kameti payout"
        case .installment: "Installment"
        }
    }
}

public enum TransactionStatus: String, CaseIterable, Sendable, Codable {
    /// Counts in balances and totals.
    case posted
    /// Shown, marked "Pending", excluded from balances and budgets (ACC-003).
    case pending
}

/// Where a transaction came from (DATA_MODEL §3.6 `source`).
public enum EntrySource: String, CaseIterable, Sendable, Codable {
    case manual, voice, `import`, recurring, notification, sample
}

/// The single source of truth for what counts as spending and income (DATA_MODEL §3.6 table, TXN-015).
public enum SpendingRules {
    /// +1 when my share adds to spending, −1 when it reduces spending (refund), 0 when not spending.
    public static func spendingSign(_ kind: TransactionKind) -> Int64 {
        switch kind {
        case .expense, .kametiContribution, .installment: 1
        case .refund: -1
        default: 0
        }
    }

    public static func countsAsIncome(_ kind: TransactionKind) -> Bool {
        kind == .income || kind == .kametiPayout
    }

    /// Kinds that need a category (expense or income tree).
    public static func needsCategory(_ kind: TransactionKind) -> Bool {
        switch kind {
        case .expense, .income, .refund, .installment, .kametiContribution, .kametiPayout, .adjustment: true
        default: false
        }
    }

    /// Rows that read "not spending" in Activity (TXN-021).
    public static func isNeutral(_ kind: TransactionKind) -> Bool {
        spendingSign(kind) == 0 && !countsAsIncome(kind)
    }
}
