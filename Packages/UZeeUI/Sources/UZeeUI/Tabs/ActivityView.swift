import SwiftUI
import UZeeCore

/// Activity (SCR-08). M2: every transaction by day with the day's spending (my share).
/// Search, filters and Recently Deleted arrive in M3.
struct ActivityView: View {
    @Bindable var session: AppSession

    var body: some View {
        List {
            ForEach(days, id: \.date) { day in
                Section {
                    ForEach(day.transactions) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(transaction: transaction, ledger: session.ledger)
                        }
                    }
                } header: {
                    HStack {
                        Text(day.date.listTitle(today: today))
                        Spacer()
                        if !day.spending.isZero {
                            Text(MoneyFormatter.string(day.spending)).monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .overlay {
            if session.transactions.isEmpty {
                EmptyStateView("No transactions yet", systemImage: "list.bullet.rectangle",
                               description: "Everything you spend, earn and transfer will be listed here by day.",
                               actionTitle: "Add") { session.openAdd(.new) }
                    .accessibilityIdentifier("activity.empty")
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { session.openAdd(.transfer) } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("New transfer")
                    .accessibilityIdentifier("activity.transfer")
            }
        }
    }

    private var today: LocalDate { LocalDate(Date(), in: .current) }

    private struct Day {
        let date: LocalDate
        let transactions: [MoneyTransaction]
        let spending: Money
    }

    /// Groups by recorded day; the header shows spending (my share, base currency) like TXN-020.
    private var days: [Day] {
        let grouped = Dictionary(grouping: session.transactions, by: \.localDate)
        return grouped.keys.sorted(by: >).map { date in
            let rows = grouped[date] ?? []
            let totals = try? PeriodTotals.compute(rows, from: date, through: date, base: session.ledger.base, rates: session.ledger.rates)
            return Day(date: date, transactions: rows, spending: totals?.spending ?? .zero(session.ledger.base))
        }
    }
}

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
            Text("Balances update now. You can undo for a few seconds.")
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

/// Settings → Exchange rate (CUR-03, CUR-012): one table rate for USD; transfers keep their own.
struct ExchangeRateView: View {
    @Bindable var session: AppSession
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("$1 = Rs")
                    TextField("280", text: $text)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .accessibilityIdentifier("rate.field")
                }
            } footer: {
                Text("Used to show USD in rupees and for totals. Transfers keep the rate they actually got.")
            }
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
            Section {
                Button("Save rate", action: save).accessibilityIdentifier("rate.save")
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear { text = ExchangeRate.storageString(session.ledger.rate(for: .usd)) }
    }

    private func save() {
        do {
            let rate = try ExchangeRate.parseRate(text)
            problem = nil
            if session.perform("Couldn't save the rate. Try again.", { try session.client.setRate(rate, .usd) }) {
                session.toasts.show("Rate saved")
            }
        } catch {
            problem = switch error {
            case .empty: "Enter a rate."
            case .notANumber: "Use numbers only, like 280 or 278.70."
            case .notPositive: "The rate must be more than zero."
            }
        }
    }
}
