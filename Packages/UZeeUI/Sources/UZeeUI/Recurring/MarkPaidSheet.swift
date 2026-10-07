import SwiftUI
import UZeeCore

/// Mark paid (SCR-17, REC-02/08): confirm the amount, account and date; or skip this time, or snooze a day.
/// Estimated bills open with the estimate, ready to correct.
struct MarkPaidSheet: View {
    @Bindable var session: AppSession
    let occurrence: Occurrence
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var problem: String?
    @State private var didLoad = false

    private var model: RecurringModel { RecurringModel(session: session) }
    private var item: RecurringItem? { session.recurring.item(occurrence.itemID) }
    private var someoneElsePays: String? {
        guard let item, let payer = item.paidByID, payer != session.people.selfID else { return nil }
        return session.people.person(payer)?.name ?? "Someone else"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        HStack(spacing: UZSpacing.l) {
                            RecurringTile(item: item, size: 44)
                            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                                Text(item.name).font(.headline)
                                Text(note(item)).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                        }
                        HStack {
                            StatusBadge(model.badge(occurrence.state))
                            Text("Due \(DateText.short(occurrence.dueDate))").font(.subheadline).foregroundStyle(UZColor.label2)
                        }
                        .accessibilityIdentifier("markPaid.status")
                    }
                    Section {
                        HStack {
                            Text(occurrence.amount.currency.symbol).font(.title.bold()).foregroundStyle(UZColor.label2)
                            TextField("0", text: $amountText)
                                .font(.title.bold())
                                .keyboardType(.decimalPad)
                                .monospacedDigit()
                                .accessibilityIdentifier("markPaid.amount")
                        }
                    } header: {
                        Text(item.isEstimated ? "Amount · estimated, correct it if needed" : "Amount")
                    }
                    Section {
                        if let someoneElsePays {
                            LabeledContent("Paid by", value: someoneElsePays)
                        } else {
                            Picker(item.type.isIncome ? "Into account" : "From account", selection: $accountID) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(session.ledger.activeAccounts) { account in
                                    Text("\(account.name) · \(MoneyFormatter.string(session.ledger.balance(of: account)))")
                                        .tag(UUID?.some(account.id))
                                }
                            }
                            .accessibilityIdentifier("markPaid.account")
                        }
                        DatePicker(item.type.isIncome ? "Date received" : "Date paid", selection: $date, displayedComponents: .date)
                    } footer: {
                        Text(footer(item))
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                    }
                    Section {
                        Button(item.type.isIncome ? "Mark received" : "Mark paid", action: save)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("markPaid.confirm")
                    }
                    Section {
                        Button("Skip this time") {
                            session.skip(occurrence)
                            dismiss()
                        }
                        .accessibilityIdentifier("markPaid.skip")
                        Button("Snooze 1 day") {
                            session.snooze(occurrence)
                            dismiss()
                        }
                        .accessibilityIdentifier("markPaid.snooze")
                    } footer: {
                        Text("Skip moves on to the next date with no payment. Snooze reminds you tomorrow.")
                    }
                }
            }
            .navigationTitle(item?.type.isIncome == true ? "Mark received" : "Mark paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear(perform: load)
        }
        .accessibilityIdentifier("sheet.markPaid")
    }

    private func note(_ item: RecurringItem) -> String {
        if item.type == .installment, let total = item.rule.limit {
            let summary = InstallmentSummary(item, records: model.records(item))
            return "Installment \(occurrence.sequence) of \(total) · \(summary.left) left · \(MoneyFormatter.string(summary.remaining)) remaining"
        }
        if item.type == .kameti, let total = item.rule.limit {
            let summary = KametiSummary(item, records: model.records(item))
            return "Contribution \(occurrence.sequence) of \(total) · \(MoneyFormatter.string(summary.contributed)) of "
                + "\(MoneyFormatter.string(summary.totalContributions)) paid so far"
        }
        var parts = [session.ledger.categoryPath(item.categoryID) ?? item.type.name]
        parts.append(item.isEstimated ? "estimated amount" : item.rule.text.lowercased())
        return parts.joined(separator: " · ")
    }

    private func footer(_ item: RecurringItem) -> String {
        if let group = session.people.group(item.groupID) {
            let share = model.myShare(item, occurrence.amount)
            return "Split equally with \(group.name). Your share \(MoneyFormatter.string(share)) counts toward your budget."
        }
        if item.type.isPlan { return "Counts as spending this month. The plan moves to the next payment." }
        return item.type.isIncome ? "Added to the account as income." : "Saved as a transaction in Activity."
    }

    private func load() {
        guard !didLoad, let item else { return }
        didLoad = true
        amountText = Self.plain(occurrence.amount)
        accountID = item.accountID ?? session.ledger.activeAccounts.first?.id
        let due = occurrence.dueDate.startDate(in: .current)
        date = due > Date() ? Date() : due
        if occurrence.dueDate < session.today { date = Date() }
    }

    static func plain(_ money: Money) -> String {
        let scale = Money.scale(money.currency.minorUnits)
        let whole = money.minorUnits / scale
        let cents = money.minorUnits % scale
        return cents == 0 ? String(whole) : String(format: "%lld.%02lld", whole, cents)
    }

    private func save() {
        let money: Money
        do {
            money = try AmountParser.parse(amountText, currency: occurrence.amount.currency)
            guard money.minorUnits > 0 else { problem = "The amount must be more than zero."; return }
        } catch {
            problem = ProblemText.message(error)
            return
        }
        let account = someoneElsePays == nil ? accountID : nil
        if someoneElsePays == nil && account == nil {
            problem = "Choose the account it was paid from."
            return
        }
        if session.markPaid(occurrence, amount: money, account: account, date: date) { dismiss() }
    }
}
