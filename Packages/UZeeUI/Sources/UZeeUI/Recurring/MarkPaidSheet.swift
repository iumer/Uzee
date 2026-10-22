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
    /// Paid a different amount (exchange rate, tax, a new price): use it from now on (owner, 2026-10-15).
    @State private var keepNewPrice = true
    /// Paid early: keep the next dates, or count them from the day it was paid (owner, 2026-10-19).
    @State private var countFromPayment: Bool?
    /// What actually arrived or left in the chosen account when it's in another currency: a $1,875 salary that
    /// came as Rs 517,000 into HBL (owner, 2026-10-22).
    @State private var accountAmountText = ""

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
                        if let changed = changedAmount(item) {
                            Toggle("Use \(MoneyFormatter.string(changed)) from now on", isOn: $keepNewPrice)
                                .accessibilityIdentifier("markPaid.keepPrice")
                        }
                    } header: {
                        Text(item.isEstimated ? "Amount · estimated, correct it if needed" : "Amount")
                    } footer: {
                        if changedAmount(item) != nil {
                            Text(keepNewPrice ? "The next ones expect this amount. Earlier payments stay as they were."
                                 : "Only this payment changes; the next ones stay \(MoneyFormatter.string(occurrence.amount)).")
                        }
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
                            if let other = otherCurrencyAccount {
                                HStack {
                                    Text(item.type.isIncome ? "Arrived in \(other.name)" : "Taken from \(other.name)")
                                    Spacer()
                                    Text(other.currency.symbol).foregroundStyle(UZColor.label2)
                                    TextField("0", text: $accountAmountText)
                                        .keyboardType(.decimalPad)
                                        .monospacedDigit()
                                        .multilineTextAlignment(.trailing)
                                        .frame(maxWidth: 140)
                                        .accessibilityIdentifier("markPaid.accountAmount")
                                }
                            }
                        }
                        DatePicker(item.type.isIncome ? "Date received" : "Date paid", selection: $date, displayedComponents: .date)
                            .accessibilityIdentifier("markPaid.date")
                    } footer: {
                        if let other = otherCurrencyAccount {
                            Text("\(other.name) is in \(other.currency.code). Type the \(other.currency.code) amount that "
                                 + (item.type.isIncome ? "arrived" : "left") + "; it starts at today's rate. " + footer(item))
                        } else {
                            Text(footer(item))
                        }
                    }
                    if let early = earlyChoice(item) {
                        Section {
                            choiceRow(title: "Keep the dates as they are",
                                      detail: "Next due \(DateText.short(early.keep)), reminders as now", selected: countFromPayment == false) {
                                countFromPayment = false
                            }
                            .accessibilityIdentifier("markPaid.keepDates")
                            choiceRow(title: "Count from \(DateText.short(early.paid))",
                                      detail: "Next due \(DateText.short(early.moved)), and every later date and reminder moves too",
                                      selected: countFromPayment == true) {
                                countFromPayment = true
                            }
                            .accessibilityIdentifier("markPaid.moveDates")
                        } header: {
                            Text("Paid \(early.days) \(early.days == 1 ? "day" : "days") early")
                        } footer: {
                            if countFromPayment == nil { Text("Choose one to save.").foregroundStyle(UZColor.warning) }
                        }
                    }
                    if let problem {
                        Section { Label(problem, systemImage: "exclamationmark.circle.fill").foregroundStyle(UZColor.negative) }
                    }
                    Section {
                        Button(item.type.isIncome ? "Mark received" : "Mark paid") { afterTyping(save) }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("markPaid.confirm")
                    }
                    Section {
                        Button(item.type.isIncome ? "Got nothing this time (Rs 0)" : "Not charged this time (Rs 0)") { chargedNothing() }
                            .accessibilityIdentifier("markPaid.skip")
                        Button("Snooze 1 day") {
                            session.snooze(occurrence)
                            dismiss()
                        }
                        .accessibilityIdentifier("markPaid.snooze")
                    } footer: {
                        Text("On hold or cancelled this time? Rs 0 records nothing for this date; the next one stays \(MoneyFormatter.string(item.amount)). You can also type 0 above. Snooze reminds you tomorrow.")
                    }
                }
            }
            .navigationTitle(item?.type.isIncome == true ? "Mark received" : "Mark paid")
            .sessionErrors(session)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear(perform: load)
            .onChange(of: countFromPayment) { problem = nil }
            .onChange(of: accountID) { fillAccountAmount() }
        }
        .accessibilityIdentifier("sheet.markPaid")
    }

    /// When the date paid is before the due date: the next due date both ways. Nil when paid on time or late, or
    /// when the dates can't move (an earlier one still unpaid, or before the one before it).
    private func earlyChoice(_ item: RecurringItem) -> (paid: LocalDate, keep: LocalDate, moved: LocalDate, days: Int)? {
        let paid = LocalDate(date, in: .current)
        guard !item.type.isIncome, paid < occurrence.scheduledDate else { return nil }
        let index = item.rule.firstIndex(onOrAfter: occurrence.scheduledDate)
        guard item.rule.date(at: index) == occurrence.scheduledDate,
              let moved = item.rule.restarting(at: index, on: paid), let movedNext = moved.date(at: index + 1),
              let keepNext = item.rule.date(at: index + 1) else { return nil }
        // Something earlier still to pay: pay that first, so the dates aren't moved past it.
        let earlierOpen = OccurrenceGenerator.occurrences(item, records: model.records(item), from: occurrence.scheduledDate,
                                                          through: occurrence.scheduledDate, today: session.today, includeOverdue: true)
            .contains { $0.scheduledDate < occurrence.scheduledDate && !$0.isResolved }
        guard !earlierOpen else { return nil }
        return (paid, keepNext, movedNext, paid.days(to: occurrence.scheduledDate))
    }

    private func choiceRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: UZSpacing.m) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? UZColor.tint : UZColor.label3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(UZColor.label)
                    Text(detail).font(.footnote).foregroundStyle(UZColor.label2)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        // Paying before it's due: today, so paying early is the default (owner, 2026-10-19).
        let due = occurrence.dueDate.startDate(in: .current)
        date = due > Date() ? Date() : due
        if occurrence.dueDate < session.today { date = Date() }
        fillAccountAmount()
    }

    /// The chosen account when its currency isn't the bill's.
    private var otherCurrencyAccount: Account? {
        guard someoneElsePays == nil, let account = session.ledger.account(accountID),
              account.currency != occurrence.amount.currency else { return nil }
        return account
    }

    /// Starts the other-currency amount at today's rate, from the amount typed above.
    private func fillAccountAmount() {
        guard let other = otherCurrencyAccount else { accountAmountText = ""; return }
        let typed = (try? AmountParser.parse(amountText, currency: occurrence.amount.currency)) ?? occurrence.amount
        let converted = try? RateTable.convert(typed, to: other.currency, base: session.ledger.base, rates: session.ledger.rates)
        accountAmountText = converted.map(Self.plain) ?? ""
    }

    static func plain(_ money: Money) -> String {
        let scale = Money.scale(money.currency.minorUnits)
        let whole = money.minorUnits / scale
        let cents = money.minorUnits % scale
        return cents == 0 ? String(whole) : String(format: "%lld.%02lld", whole, cents)
    }

    /// The typed amount when it's a real amount different from what was expected.
    private func changedAmount(_ item: RecurringItem) -> Money? {
        guard let money = try? AmountParser.parse(amountText, currency: occurrence.amount.currency), money.minorUnits > 0,
              money != occurrence.amount, !item.type.isPlan else { return nil }
        return money
    }

    private func chargedNothing() {
        session.skip(occurrence)
        dismiss()
    }

    private func save() {
        let money: Money
        do {
            money = try AmountParser.parse(amountText, currency: occurrence.amount.currency)
            // Rs 0: on hold or cancelled this time; the next one is back to the usual amount (owner, 2026-10-15).
            guard money.minorUnits > 0 else { chargedNothing(); return }
        } catch {
            problem = ProblemText.message(error)
            return
        }
        if let item, earlyChoice(item) != nil, countFromPayment == nil {
            problem = "Paid early: choose whether the next dates stay or count from the day you paid."
            return
        }
        let account = someoneElsePays == nil ? accountID : nil
        if someoneElsePays == nil && account == nil {
            problem = "Choose the account it was paid from."
            return
        }
        var posted = money
        if let other = otherCurrencyAccount {
            do {
                posted = try AmountParser.parse(accountAmountText, currency: other.currency)
                guard posted.minorUnits > 0 else { throw AmountParser.Failure.empty }
            } catch {
                problem = "Type the \(other.currency.code) amount that " + (item?.type.isIncome == true ? "arrived in " : "left ") + "\(other.name)."
                return
            }
        }
        let moving = item.map { earlyChoice($0) != nil } == true && countFromPayment == true
        guard session.markPaid(occurrence, amount: posted, account: account, date: date, countFromPayment: moving) else { return }
        if keepNewPrice, money != occurrence.amount, var updated = item {
            updated.amount = money
            _ = session.perform("Saved the payment, but couldn't change the usual amount.", {
                try session.recurringClient.save(updated, occurrence.scheduledDate)
            })
        }
        dismiss()
    }
}
