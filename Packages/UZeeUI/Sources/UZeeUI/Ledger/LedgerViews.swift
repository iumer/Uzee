import SwiftUI
import UZeeCore

/// Plain-words messages for refused input (TXN-009, SMK-012). One place, so every screen says the same thing.
enum ProblemText {
    static func message(_ problem: TransactionProblem) -> String {
        switch problem {
        case .missingAmount: "Enter an amount."
        case .zeroAmount: "The amount must be more than zero."
        case .missingAccount: "Choose an account."
        case .unknownAccount: "That account no longer exists. Choose another."
        case .archivedAccount: "That account is archived. Choose another."
        case .currencyDiffersFromAccount: "The amount's currency doesn't match the account."
        case .missingDestination: "Choose where the money goes."
        case .sameAccount: "From and To must be different accounts."
        case .missingReceivedAmount: "Enter the amount that arrived."
        case .zeroReceivedAmount: "The amount that arrived must be more than zero."
        case .missingCategory: "Choose a category."
        case .noteTooLong: "The note is too long (500 characters at most)."
        case .unsupportedKind: "This type can't be added here yet."
        case .amountTooLarge: "Amount too large."
        }
    }

    static func message(_ failure: AmountParser.Failure) -> String {
        switch failure {
        case .empty: "Enter an amount."
        case .notANumber: "Use numbers only, like 1500 or 2.99."
        case .tooManyDecimals(let allowed): allowed == 0 ? "No decimals for this currency." : "Use at most \(allowed) decimals."
        case .tooLarge: "Amount too large."
        case .negative: "Enter the amount without a minus sign."
        }
    }
}

/// Account tile: generic symbol on the account colour (AUD-42, never bank logos).
struct AccountIcon: View {
    let account: Account
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: account.kind.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: account.colorHex), in: .rect(cornerRadius: UZRadius.tile, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One account in a list: name, type, balance with "≈ Rs" for USD.
struct AccountRow: View {
    let account: Account
    let ledger: LedgerSnapshot

    var body: some View {
        HStack(spacing: UZSpacing.l) {
            AccountIcon(account: account)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(account.name).font(.body)
                Text(subtitle).font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer(minLength: UZSpacing.m)
            AmountText(ledger.balance(of: account), style: .transfer, base: ledger.base, rate: ledger.rate(for: account.currency))
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        // The id goes on the NavigationLink around this row; an inner id is hidden from UI tests.
    }

    private var subtitle: String {
        var parts = [account.kind.name]
        if account.currency != ledger.base { parts.append(account.currency.code) }
        if !account.includeInTotals { parts.append("not in total") }
        if account.isArchived { parts.append("archived") }
        return parts.joined(separator: " · ")
    }
}

/// One transaction in a list. Says what the money did; transfers and loans read "not spending" (TXN-021).
struct TransactionRow: View {
    let transaction: MoneyTransaction
    let ledger: LedgerSnapshot
    /// When shown inside an account, the amount is this account's leg.
    var accountID: UUID?
    /// Shows a paperclip when a receipt is attached.
    var hasReceipt = false

    var body: some View {
        HStack(spacing: UZSpacing.l) {
            CategoryTile(group)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                HStack(spacing: UZSpacing.xs) {
                    Text(title).font(.body).lineLimit(1)
                    if hasReceipt {
                        Image(systemName: "paperclip").font(.footnote).foregroundStyle(UZColor.label2)
                            .accessibilityLabel("Receipt attached")
                    }
                }
                Text(subtitle).font(.footnote).foregroundStyle(UZColor.label2).lineLimit(2)
            }
            Spacer(minLength: UZSpacing.m)
            AmountText(shownAmount, style: style, base: ledger.base, rate: ledger.rate(for: shownAmount.currency))
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("txn.\(title)")
    }

    private var group: CategoryKind {
        switch transaction.kind {
        case .transfer: .transfer
        case .loanOut, .loanIn, .repayment, .settlement: .people
        default: ledger.category(transaction.categoryID)?.group ?? .other
        }
    }

    private var title: String {
        if let payee = transaction.payeeName { return payee }
        if transaction.kind == .transfer {
            let from = ledger.account(transaction.legs.first { $0.role == .transferOut }?.accountID)?.name ?? "?"
            let to = ledger.account(transaction.legs.first { $0.role == .transferIn }?.accountID)?.name ?? "?"
            return "\(from) → \(to)"
        }
        return ledger.category(transaction.categoryID)?.name ?? transaction.kind.name
    }

    private var subtitle: String {
        var parts: [String] = []
        if transaction.kind == .transfer || transaction.kind == .adjustment || SpendingRules.isNeutral(transaction.kind) {
            parts.append("\(transaction.kind.name) · not spending")
        } else if let path = ledger.categoryPath(transaction.categoryID), transaction.payeeName != nil {
            parts.append(path)
        }
        if transaction.myShare != transaction.amount, let detail = ActivityText.detail(transaction) {
            // "You paid Rs 60,000 · your share Rs 30,000" (TXN-021).
            parts.append(detail)
        }
        if transaction.status == .pending { parts.append("Pending") }
        if accountID == nil, transaction.kind != .transfer,
           let account = ledger.account(transaction.legs.first?.accountID) {
            parts.append(account.name)
        }
        return parts.joined(separator: " · ")
    }

    private var shownAmount: Money {
        if let accountID, let leg = transaction.legs.first(where: { $0.accountID == accountID }) { return leg.amount }
        return transaction.amount
    }

    private var style: AmountText.Style {
        if let accountID, let leg = transaction.legs.first(where: { $0.accountID == accountID }) {
            return leg.amount.minorUnits < 0 ? .outflow : .inflow
        }
        switch transaction.kind {
        case .income, .refund, .kametiPayout, .loanIn: return .inflow
        case .transfer, .adjustment: return .transfer
        default: return .outflow
        }
    }
}

extension Color {
    /// "#RRGGBB" from the database; grey when malformed.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0x8E8E93
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension LocalDate {
    /// "Tue 6 Oct" in lists; today and yesterday by name.
    func listTitle(today: LocalDate) -> String {
        if self == today { return "Today" }
        let date = startDate(in: .current)
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today.startDate(in: .current)),
           LocalDate(yesterday, in: .current) == self { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
