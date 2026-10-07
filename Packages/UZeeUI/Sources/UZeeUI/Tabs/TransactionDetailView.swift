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
            if let split = session.people.split(for: transaction.id) {
                splitSection(split, transaction: transaction)
            }
            if let person = session.people.person(transaction.counterpartyID) {
                Section {
                    NavigationLink(value: Route.person(person.id)) { LabeledContent("Person", value: person.name) }
                    if let group = session.people.group(transaction.groupID) {
                        NavigationLink(value: Route.group(group.id)) { LabeledContent("Group", value: group.name) }
                    }
                }
            }
            TagsSection(session: session, transactionID: transaction.id)
            ReceiptsSection(session: session, transactionID: transaction.id)
            Section {
                if AddSheet.kinds.contains(transaction.kind) {
                    Button("Edit") { session.openAdd(.edit(transaction)) }
                        .accessibilityIdentifier("detail.edit")
                    Button("Repeat this") { session.openAdd(.repeatOf(transaction)) }
                        .accessibilityIdentifier("detail.repeat")
                }
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

    /// Who paid and everyone's share (SPL-03), with links to the group and people.
    private func splitSection(_ split: Split, transaction: MoneyTransaction) -> some View {
        let model = PeopleModel(session: session)
        let isIncome = SpendingRules.countsAsIncome(transaction.kind)
        return Section {
            if let group = session.people.group(split.groupID) {
                NavigationLink(value: Route.group(group.id)) { LabeledContent("Group", value: group.name) }
            }
            ForEach(split.payers, id: \.personID) { payer in
                LabeledContent(isIncome ? "Received by \(model.name(payer.personID))" : "Paid by \(model.name(payer.personID))",
                               value: MoneyFormatter.string(payer.amount))
            }
            ForEach(split.shares, id: \.personID) { share in
                LabeledContent(share.personID == model.me ? "Your share" : "\(model.name(share.personID))'s share", value: MoneyFormatter.string(share.share))
            }
            if let effect = model.effect(of: split, isIncome: isIncome), !effect.isZero {
                Text(effect.isNegative ? "You owe \(MoneyFormatter.string(SplitText.magnitude(effect)))" : "You are owed \(MoneyFormatter.string(effect))")
                    .foregroundStyle(SplitText.color(effect))
            }
        } header: {
            Text("Split \(split.method.name.lowercased())")
        }
        .accessibilityIdentifier("detail.split")
    }

    private func label(for role: LegRole) -> String {
        switch role {
        case .main: "Account"
        case .transferOut: "From"
        case .transferIn: "To"
        }
    }
}
