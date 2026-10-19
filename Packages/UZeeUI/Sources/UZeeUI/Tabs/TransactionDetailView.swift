import SwiftUI
import UZeeCore

/// Transaction detail (SCR-09): what happened, then Edit, Repeat this and Delete.
struct TransactionDetailView: View {
    @Bindable var session: AppSession
    let transactionID: UUID
    @State private var confirmDelete = false
    /// "Repeat every month": a new bill, subscription or income prefilled from this payment, with reminders.
    @State private var repeating: RecurringItem?
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
                // The logo sits left of the amount (owner, 2026-10-19); tap it to add one.
                HStack(spacing: UZSpacing.l) {
                    if let payee = transaction.payeeName, transaction.kind == .expense || transaction.kind == .income
                        || transaction.kind == .refund {
                        LogoBadge(name: payee) { CategoryTile(group(transaction), size: 64) }
                    } else {
                        CategoryTile(group(transaction), size: 64).clipShape(.circle)
                    }
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        AmountText(transaction.amount, style: .plain, font: .system(.largeTitle, weight: .bold),
                                   base: ledger.base, rate: ledger.rate(for: transaction.amount.currency))
                            .accessibilityIdentifier("detail.amount")
                        Text(transaction.kind.name + (SpendingRules.isNeutral(transaction.kind) ? " · not spending" : ""))
                            .font(.subheadline).foregroundStyle(UZColor.label2)
                    }
                    Spacer(minLength: 0)
                }
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
                    // A lend or borrow opened from Activity leads to its loan page, where payments and notes are.
                    if let loan = loanID(for: transaction) {
                        NavigationLink(value: Route.loan(loan)) { Text("Open the loan") }
                            .accessibilityIdentifier("detail.openLoan")
                    }
                    if let group = session.people.group(transaction.groupID) {
                        NavigationLink(value: Route.group(group.id)) { LabeledContent("Group", value: group.name) }
                    }
                }
            }
            // A loan's notes live on its loan page ("Open the loan"), so a lend, borrow or repayment doesn't get a second set.
            if withPeople(transaction), loanID(for: transaction) == nil {
                EntryNotesSection(session: session, transactionID: transaction.id)
            }
            TagsSection(session: session, transactionID: transaction.id)
            ReceiptsSection(session: session, transactionID: transaction.id)
            Section {
                if AddSheet.kinds.contains(transaction.kind) {
                    Button("Edit") { session.openAdd(.edit(transaction)) }
                        .accessibilityIdentifier("detail.edit")
                    if transaction.kind == .expense || transaction.kind == .income {
                        Button("Repeat…") { repeating = RecurringModel(session: session).draft(from: transaction) }
                            .accessibilityIdentifier("detail.monthly")
                    }
                    // Filing a payment under Subscriptions doesn't add it to the subscriptions list, so offer it here (owner, 2026-10-16).
                    if canTrack(transaction) {
                        Button("Track as subscription") { repeating = RecurringModel(session: session).draft(from: transaction) }
                            .accessibilityIdentifier("detail.trackSubscription")
                    }
                    Button("Add again today") { session.openAdd(.repeatOf(transaction)) }
                        .accessibilityIdentifier("detail.repeat")
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("detail.delete")
            }
        }
        .navigationTitle(transaction.payeeName ?? transaction.kind.name)
        .sheet(item: $repeating) { RecurringFormSheet(session: session, item: nil, draft: $0) }
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

    /// The same icon as the row in Activity.
    private func group(_ transaction: MoneyTransaction) -> CategoryKind {
        switch transaction.kind {
        case .transfer: .transfer
        case .loanOut, .loanIn, .repayment, .settlement: .people
        default: session.ledger.category(transaction.categoryID)?.group ?? .other
        }
    }

    private func label(for role: LegRole) -> String {
        switch role {
        case .main: "Account"
        case .transferOut: "From"
        case .transferIn: "To"
        }
    }

    /// Shared with someone, or money between you and a person: these get notes, like a loan (owner, 2026-10-19).
    private func withPeople(_ transaction: MoneyTransaction) -> Bool {
        transaction.counterpartyID != nil || session.isSharedExpense(transaction)
            || (session.people.split(for: transaction.id)?.people.contains { $0 != session.people.selfID } ?? false)
    }

    private func loanID(for transaction: MoneyTransaction) -> UUID? {
        session.people.loans.first { loan in
            loan.transactionID == transaction.id || loan.payments.contains { $0.transactionID == transaction.id }
        }?.id
    }

    private func canTrack(_ transaction: MoneyTransaction) -> Bool {
        transaction.kind == .expense && session.ledger.category(transaction.categoryID)?.group == .subscriptions
            && !RecurringModel(session: session).isTracked(transaction)
    }
}
