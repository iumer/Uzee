import SwiftUI
import UZeeCore

/// One bill, subscription, income or plan (SCR-16/18): next due with Mark paid, price history,
/// billing details, the plan schedule or kameti payouts, past payments, and pause / cancel / delete.
struct RecurringDetailView: View {
    @Bindable var session: AppSession
    let itemID: UUID
    @State private var paying: Occurrence?
    @State private var editing = false
    @State private var askCancel = false
    @State private var askDelete = false
    @State private var payout: KametiPayout?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = RecurringModel(session: session)
        Group {
            if let item = session.recurring.item(itemID) {
                content(item, model: model)
            } else {
                EmptyStateView("Not found", systemImage: "questionmark.circle", description: "This item was deleted.")
            }
        }
        .background(UZColor.bg)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paying) { MarkPaidSheet(session: session, occurrence: $0) }
        .sheet(isPresented: $editing) { RecurringFormSheet(session: session, item: session.recurring.item(itemID)) }
        .sheet(item: $payout) { PayoutSheet(session: session, payout: $0) }
    }

    private func content(_ item: RecurringItem, model: RecurringModel) -> some View {
        let records = model.records(item)
        let next = model.next(item)
        return List {
            Section { header(item, model: model, next: next) }
            if let next, item.isActive {
                Section {
                    LabeledContent(item.type == .subscription ? "Next renewal" : "Next due") {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(DateText.short(next.dueDate)).fontWeight(.semibold)
                            Text(nextLine(item, next, model: model)).font(.caption).foregroundStyle(UZColor.label2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("recurring.next")
                    Button(item.type.isIncome ? "Mark received" : "Mark paid") { paying = next }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("recurring.markPaid")
                }
            }
            if item.type == .installment { installmentSection(item, records: records, model: model) }
            if item.type == .kameti { kametiSection(item, records: records, model: model) }
            if item.priceHistory.count > 1 { priceSection(item) }
            Section("Billing") {
                LabeledContent("Repeats", value: billing(item))
                if let payer = item.paidByID, payer != session.people.selfID {
                    LabeledContent("Paid by", value: session.people.person(payer)?.name ?? "Someone else")
                } else {
                    LabeledContent(item.type.isIncome ? "Goes to" : "Pays from", value: session.ledger.account(item.accountID)?.name ?? "Choose when paid")
                }
                LabeledContent("Category", value: session.ledger.categoryPath(item.categoryID) ?? "None")
                if let group = session.people.group(item.groupID) {
                    NavigationLink(value: Route.group(group.id)) {
                        LabeledContent("Split", value: "Equally with \(group.name)")
                    }
                    LabeledContent("Your share", value: MoneyFormatter.string(model.myShare(item, item.amount)))
                }
                if item.isEstimated { LabeledContent("Amount", value: "Estimated, varies") }
                if let started = item.startedOn { LabeledContent("Since", value: DateText.monthYear(started)) }
                if let notes = item.notes, !notes.isEmpty { Text(notes).foregroundStyle(UZColor.label2) }
            }
            historySection(item, records: records)
            Section {
                if item.status == .active {
                    Button("Pause") { setStatus(.paused, item) }.accessibilityIdentifier("recurring.pause")
                } else {
                    Button("Resume") { setStatus(.active, item) }.accessibilityIdentifier("recurring.resume")
                }
                if item.status != .cancelled {
                    Button(item.type == .subscription ? "Mark as cancelled" : "Stop", role: .destructive) { askCancel = true }
                        .accessibilityIdentifier("recurring.cancel")
                }
                Button("Delete", role: .destructive) { askDelete = true }
                    .accessibilityIdentifier("recurring.delete")
            } footer: {
                if item.type == .subscription {
                    Text("Marking as cancelled only stops reminders in UZee. Cancel the plan with the provider as well.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }.accessibilityIdentifier("recurring.edit")
            }
        }
        .confirmationDialog("Stop \(item.name)?", isPresented: $askCancel, titleVisibility: .visible) {
            Button(item.type == .subscription ? "Mark as cancelled" : "Stop", role: .destructive) { setStatus(.cancelled, item) }
        } message: {
            Text("No more reminders. Past payments stay in Activity.")
        }
        .confirmationDialog("Delete \(item.name)?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if session.perform("Couldn't delete. Try again.", { try session.recurringClient.delete(item.id) }) {
                    session.toasts.show("Deleted")
                    dismiss()
                }
            }
        } message: {
            Text("Past payments stay in Activity.")
        }
    }

    // MARK: Parts

    private func header(_ item: RecurringItem, model: RecurringModel, next: Occurrence?) -> some View {
        HStack(spacing: UZSpacing.l) {
            RecurringTile(item: item, size: 52)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(item.name).font(.title3.bold())
                HStack(alignment: .firstTextBaseline, spacing: UZSpacing.xs) {
                    Text((item.isEstimated ? "~" : "") + MoneyFormatter.string(item.amount)).font(.title2.bold()).monospacedDigit()
                    Text("/ \(unitWord(item))").foregroundStyle(UZColor.label2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recurring.amount")
                if item.amount.currency != model.base {
                    Text(MoneyFormatter.approximate(item.amount, in: model.base, rate: session.ledger.rate(for: item.amount.currency)))
                        .font(.caption).foregroundStyle(UZColor.label2)
                }
                HStack(spacing: UZSpacing.m) {
                    if !item.isActive {
                        StatusBadge(item.status == .paused ? .paused : .cancelled)
                    } else if let next, next.state == .overdue || next.state == .dueToday {
                        StatusBadge(model.badge(next.state))
                    }
                    if item.type == .subscription || !item.type.isPlan {
                        Text("\(MoneyFormatter.string(model.yearly(fromMonthly: model.monthly(item)))) a year")
                            .font(.footnote).foregroundStyle(UZColor.label2)
                    }
                }
            }
        }
        .padding(.vertical, UZSpacing.xs)
    }

    private func unitWord(_ item: RecurringItem) -> String {
        let rule = item.rule
        if rule.interval == 1 { return rule.unit.rawValue }
        return "\(rule.interval) \(rule.unit.rawValue)s"
    }

    private func billing(_ item: RecurringItem) -> String {
        if item.rule.unit == .month {
            return "\(item.rule.text) on the \(DateText.ordinal(item.rule.anchor.day))"
        }
        return "\(item.rule.text) from \(DateText.long(item.rule.anchor))"
    }

    private func nextLine(_ item: RecurringItem, _ next: Occurrence, model: RecurringModel) -> String {
        var parts = [DateText.relative(next.dueDate, today: model.today)]
        if item.type.isPlan, let total = item.rule.limit { parts.append("#\(next.sequence) of \(total)") }
        if let account = session.ledger.account(item.accountID) { parts.append(account.name) }
        return parts.joined(separator: " · ")
    }

    private func setStatus(_ status: SubscriptionStatus, _ item: RecurringItem) {
        if session.perform("Couldn't change it. Try again.", { try session.recurringClient.setStatus(status, item.id) }) {
            session.toasts.show(status == .active ? "Resumed" : status == .paused ? "Paused" : "Marked as cancelled")
        }
    }

    private func priceSection(_ item: RecurringItem) -> some View {
        let points = item.priceHistory.sorted { $0.effectiveFrom < $1.effectiveFrom }
        return Section {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                let until = index + 1 < points.count ? points[index + 1].effectiveFrom.addingMonths(-1) : nil
                LabeledContent(until.map { "\(DateText.monthYear(point.effectiveFrom)) – \(DateText.monthYear($0))" }
                               ?? "From \(DateText.monthYear(point.effectiveFrom))",
                               value: MoneyFormatter.string(point.amount))
            }
        } header: {
            Text("Price history")
        } footer: {
            if points.count > 1 {
                let change = points[points.count - 1].amount.minorUnits - points[points.count - 2].amount.minorUnits
                let money = Money(minorUnits: change.magnitudeClamped, currency: item.amount.currency)
                Text("\(change >= 0 ? "Up" : "Down") \(MoneyFormatter.string(money)) from \(DateText.monthYear(points[points.count - 1].effectiveFrom))")
            }
        }
        .accessibilityIdentifier("recurring.prices")
    }

    private func installmentSection(_ item: RecurringItem, records: [OccurrenceRecord], model: RecurringModel) -> some View {
        let summary = InstallmentSummary(item, records: records)
        let schedule = OccurrenceGenerator.occurrences(item, records: records, from: item.rule.anchor,
                                                       through: summary.endDate ?? item.rule.anchor, today: model.today)
        return Group {
            Section {
                ProgressBarView(fraction: summary.total > 0 ? Double(summary.paid) / Double(summary.total) : 0,
                                tint: Color(hex: item.colorHex), label: "\(summary.paid) of \(summary.total) paid")
                LabeledContent("Paid", value: "\(summary.paid) of \(summary.total)")
                    .accessibilityIdentifier("plan.paid")
                LabeledContent("Remaining", value: "\(MoneyFormatter.string(summary.remaining)) · \(summary.left) left")
                    .accessibilityIdentifier("plan.remaining")
                if let end = summary.endDate { LabeledContent("Ends", value: DateText.monthYear(end)) }
            } header: {
                Text("Plan")
            }
            Section("Schedule · \(summary.total) installments") {
                ForEach(schedule) { occurrence in
                    HStack {
                        Text("#\(occurrence.sequence)").monospacedDigit().foregroundStyle(UZColor.label2).frame(width: 36, alignment: .leading)
                        Text(DateText.long(occurrence.scheduledDate))
                        Spacer()
                        Text(MoneyFormatter.string(occurrence.amount)).monospacedDigit()
                        StatusBadge(model.badge(occurrence.state))
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func kametiSection(_ item: RecurringItem, records: [OccurrenceRecord], model: RecurringModel) -> some View {
        let summary = KametiSummary(item, records: records)
        return Section {
            ProgressBarView(fraction: summary.total > 0 ? Double(summary.paid) / Double(summary.total) : 0,
                            tint: Color(hex: item.colorHex), label: "\(summary.paid) of \(summary.total) paid")
            LabeledContent("Contributed", value: "\(MoneyFormatter.string(summary.contributed)) of \(MoneyFormatter.string(summary.totalContributions))")
                .accessibilityIdentifier("plan.contributed")
            ForEach(item.payouts) { payout in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Payout · \(DateText.monthYear(payout.expectedDate))")
                        Text(payout.isReceived ? "Received" : "Expected").font(.caption).foregroundStyle(UZColor.label2)
                    }
                    Spacer()
                    Text(MoneyFormatter.string(payout.amount)).monospacedDigit().fontWeight(.semibold)
                    if !payout.isReceived {
                        Button("Received") { self.payout = payout }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("plan.payoutReceived")
                    }
                }
            }
            LabeledContent("Net", value: "\(MoneyFormatter.string(summary.payouts)) back vs \(MoneyFormatter.string(summary.totalContributions)) paid in")
            if summary.mismatch {
                Label("Payouts (\(MoneyFormatter.string(summary.payouts))) don't match contributions "
                      + "(\(MoneyFormatter.string(summary.totalContributions))). Check figures with the committee.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(UZColor.warning)
                    .accessibilityIdentifier("plan.mismatch")
            }
        } header: {
            Text("Kameti")
        }
    }

    @ViewBuilder
    private func historySection(_ item: RecurringItem, records: [OccurrenceRecord]) -> some View {
        let paid = records.filter { $0.status == .paid && $0.transactionID != nil }.sorted { $0.scheduledDate > $1.scheduledDate }
        let past = session.transactions.filter { txn in
            txn.payeeName == item.name && !paid.contains { $0.transactionID == txn.id }
        }
        if !paid.isEmpty || !past.isEmpty {
            Section("Payments") {
                ForEach(paid.prefix(12), id: \.scheduledDate) { record in
                    if let id = record.transactionID, let txn = session.transactions.first(where: { $0.id == id }) {
                        NavigationLink(value: Route.transaction(id)) {
                            paymentRow(txn)
                        }
                    }
                }
                ForEach(past.prefix(12)) { txn in
                    NavigationLink(value: Route.transaction(txn.id)) { paymentRow(txn) }
                }
            }
        }
    }

    private func paymentRow(_ txn: MoneyTransaction) -> some View {
        HStack {
            Text(DateText.long(txn.localDate))
            Spacer()
            Text(MoneyFormatter.string(txn.amount)).monospacedDigit()
            if txn.myShare != txn.amount {
                Text("you \(MoneyFormatter.string(txn.myShare))").font(.caption).foregroundStyle(UZColor.label2)
            }
        }
        .font(.subheadline)
    }
}

/// Kameti payout received (KAM-03): which account it went into, and when.
struct PayoutSheet: View {
    @Bindable var session: AppSession
    let payout: KametiPayout
    @Environment(\.dismiss) private var dismiss
    @State private var accountID: UUID?
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount", value: MoneyFormatter.string(payout.amount))
                    Picker("Into account", selection: $accountID) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(session.ledger.activeAccounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    DatePicker("Date received", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("Recorded as Kameti payout income.")
                }
            }
            .navigationTitle("Payout received")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let accountID else { return }
                        if session.perform("Couldn't save. Try again.", { try session.recurringClient.recordPayout(payout.id, accountID, date) }) {
                            session.toasts.show("Payout recorded")
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(accountID == nil)
                }
            }
            .onAppear { accountID = accountID ?? session.ledger.activeAccounts.first?.id }
        }
    }
}
