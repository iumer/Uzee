import SwiftUI
import UZeeCore

/// Transaction detail (SCR-09): what happened, then Edit, Repeat this and Delete.
struct TransactionDetailView: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let transaction = session.transactions.first(where: { $0.id == transactionID }) {
            content(transaction)
        } else {
            EmptyStateView("Transaction deleted", systemImage: "trash", description: "It no longer appears in your lists and totals.")
        }
    }

    private func content(_ transaction: MoneyTransaction) -> some View {
        let ledger = session.ledger
        return List {
            Section {
                VStack(spacing: UZSpacing.s) {
                    AmountText(transaction.amount, style: .plain, font: .system(.largeTitle, weight: .bold),
                               base: ledger.base, rate: ledger.rate(for: transaction.amount.currency))
                        .accessibilityIdentifier("detail.amount")
                    Text(transaction.kind.name + (SpendingRules.isNeutral(transaction.kind) ? " · not spending" : ""))
                        .font(.subheadline).foregroundStyle(UZColor.label2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, UZSpacing.m)
            }
            Section {
                if let payee = transaction.payeeName { LabeledContent(transaction.kind == .income ? "From" : "Paid to", value: payee) }
                if let path = ledger.categoryPath(transaction.categoryID) { LabeledContent("Category", value: path) }
                ForEach(transaction.legs, id: \.role) { leg in
                    LabeledContent(label(for: leg.role)) {
                        Text("\(ledger.account(leg.accountID)?.name ?? "Account") · \(MoneyFormatter.string(leg.amount, sign: .always))")
                    }
                }
                if let rate = transaction.fxRate {
                    LabeledContent("Rate", value: ExchangeRate.display(rate))
                }
                if transaction.myShare != transaction.amount {
                    LabeledContent("Your share", value: MoneyFormatter.string(transaction.myShare))
                }
                LabeledContent("Date", value: transaction.occurredAt.formatted(date: .complete, time: .shortened))
                if transaction.status == .pending { LabeledContent("Status", value: "Pending · not in balance") }
                if let note = transaction.note { LabeledContent("Note", value: note) }
            }
            TagsSection(session: session, transactionID: transaction.id)
            ReceiptsSection(session: session, transactionID: transaction.id)
            Section {
                Button("Edit") { session.openAdd(.edit(transaction)) }
                    .accessibilityIdentifier("detail.edit")
                Button("Repeat this") { session.openAdd(.repeatOf(transaction)) }
                    .accessibilityIdentifier("detail.repeat")
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("detail.delete")
            }
        }
        .navigationTitle(transaction.payeeName ?? transaction.kind.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this transaction?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                session.delete(transaction)
                dismiss()
            }
            .accessibilityIdentifier("detail.confirmDelete")
        } message: {
            Text("Balances update now. It stays in Recently Deleted for 30 days.")
        }
    }

    private func label(for role: LegRole) -> String {
        switch role {
        case .main: "Account"
        case .transferOut: "From"
        case .transferIn: "To"
        }
    }
}
