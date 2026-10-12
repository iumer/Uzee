import SwiftUI
import UZeeCore

/// Budget limits (SCR-12): total, a limit per category in steps of Rs 1,000 with "Use last period"
/// suggestions, warning threshold and period type. Saved with Done; new periods copy these.
struct BudgetLimitsView: View {
    @Bindable var session: AppSession
    @State private var totalText = ""
    @State private var limits: [UUID: Int64] = [:]
    /// What's in each limit box, as typed. Kept apart from `limits` so the box is never rewritten mid-typing.
    @State private var limitTexts: [UUID: String] = [:]
    @State private var warnPercent = 80
    @State private var kind: BudgetPeriodKind = .calendarMonth
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private static let step: Int64 = 1_000

    var body: some View {
        let base = session.ledger.base
        // Capped at 12 digits so an over-long number can never overflow into a crash.
        let total = min(Int64(String(totalText.filter(\.isNumber).prefix(12))) ?? 0, 999_999_999_999)
        let sum = limits.values.reduce(0, +)
        let unassigned = total - sum
        Form {
            Section {
                HStack {
                    Text("Total budget")
                    Spacer()
                    Text(base.symbol).foregroundStyle(UZColor.label2)
                    TextField("Limits added up", text: $totalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("limits.total")
                }
                HStack {
                    // No total typed: the limits add up to the total, never "over the total" (owner screenshot, 2026-10-12).
                    let fromLimits = total == 0 && sum > 0
                    Text(fromLimits ? "Total will be \(money(sum))" : unassigned == 0 ? "Every rupee assigned"
                         : unassigned > 0 ? "\(money(unassigned)) unassigned" : "\(money(-unassigned)) over the total")
                        .foregroundStyle(fromLimits || unassigned == 0 ? UZColor.positive : unassigned < 0 ? UZColor.negative : UZColor.label)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("limits \(money(sum))").font(.footnote).foregroundStyle(UZColor.label2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("limits.unassigned")
            } header: {
                Text(BudgetModel.title(currentPeriod) + " total")
            } footer: {
                Text("Assign the rest to a category, or leave it as a buffer.")
            }

            Section {
                ForEach(groups) { category in
                    limitRow(category)
                }
            } header: {
                HStack {
                    Text("Categories · your share")
                    Spacer()
                    Button("Use all suggestions") {
                        for category in groups { setLimit(category.id, rounded(suggestion(category.id))) }
                    }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                }
            } footer: {
                Text("Steps of Rs 1,000. Suggestions use what you spent last period.")
            }

            Section {
                Picker("Warn me at", selection: $warnPercent) {
                    ForEach([70, 80, 90], id: \.self) { Text("\($0)% used").tag($0) }
                }
                .accessibilityIdentifier("limits.warn")
                Picker("Budget period", selection: periodChoice) {
                    Text("Calendar month").tag(0)
                    Text("Salary cycle").tag(1)
                }
                .accessibilityIdentifier("limits.period")
                if case .salaryCycle(let startDay) = kind {
                    Picker("Starts on day", selection: Binding(get: { startDay }, set: { kind = .salaryCycle(startDay: $0) })) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            } header: {
                Text("Settings")
            } footer: {
                Text("\(DatePresets.text(from: currentPeriod.start, through: currentPeriod.end)). New periods copy these limits; nothing rolls over.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Budget limits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { save(total: total) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("limits.done")
            }
        }
        .onAppear(perform: load)
    }

    private func limitRow(_ category: SpendCategory) -> some View {
        let value = limits[category.id] ?? 0
        let suggested = rounded(suggestion(category.id))
        return VStack(alignment: .leading, spacing: UZSpacing.s) {
            HStack(spacing: UZSpacing.l) {
                CategoryTile(category.group, size: 30)
                // Type the limit, or nudge it with − / + (owner, 2026-10-12: tapping + a thousand at a time was slow).
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.name)
                    HStack(spacing: UZSpacing.xxs) {
                        Text(session.ledger.base.symbol).font(.headline).foregroundStyle(UZColor.label2)
                        TextField("0", text: limitText(category.id))
                            .font(.headline).monospacedDigit()
                            .keyboardType(.numberPad)
                            .accessibilityLabel("\(category.name) limit amount")
                            .frame(minWidth: 110, minHeight: 32, alignment: .leading)
                            .contentShape(.rect)
                            .accessibilityIdentifier("limits.amount.\(category.name)")
                    }
                }
                Spacer()
                Stepper("", onIncrement: { setLimit(category.id, value + Self.step) },
                        onDecrement: { setLimit(category.id, max(0, value - Self.step)) })
                    .labelsHidden()
                    .accessibilityLabel("\(category.name) limit")
                    .accessibilityValue(money(value))
                    .accessibilityIdentifier("limits.stepper.\(category.name)")
            }
            HStack {
                Text("Last period \(money(suggestion(category.id)))").font(.footnote).foregroundStyle(UZColor.label2)
                Spacer()
                if suggested != value && suggested > 0 {
                    Button("Use \(money(suggested))") { setLimit(category.id, suggested) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, UZSpacing.xs)
    }

    // MARK: Data

    private var groups: [SpendCategory] {
        session.ledger.categories.filter { $0.parentID == nil && $0.type == .expense && !$0.isHidden }
    }

    private var currentPeriod: BudgetPeriod {
        BudgetPeriod.containing(LocalDate(Date(), in: .current), kind: kind)
    }

    private var periodChoice: Binding<Int> {
        Binding(get: { if case .salaryCycle = kind { 1 } else { 0 } },
                set: { kind = $0 == 1 ? .salaryCycle(startDay: 21) : .calendarMonth })
    }

    /// Last period's spending in this group, in whole base units.
    private func suggestion(_ groupID: UUID) -> Int64 {
        let ids = Set([groupID] + session.ledger.categories.filter { $0.parentID == groupID }.map(\.id))
        let spent = BudgetCalculator.spending(session.transactions, in: currentPeriod.previous,
                                              base: session.ledger.base, rates: session.ledger.rates)
        let minor = spent.filter { ids.contains($0.key) }.values.reduce(Int64(0)) { $0 + $1.minorUnits }
        return minor / Money.scale(session.ledger.base.minorUnits)
    }

    /// The limit box: shows what was typed (never rewritten while typing, BUG-017); empty means no limit.
    private func limitText(_ id: UUID) -> Binding<String> {
        Binding(get: {
            limitTexts[id] ?? ((limits[id] ?? 0) > 0 ? String(limits[id] ?? 0) : "")
        }, set: { typed in
            limitTexts[id] = typed
            limits[id] = min(Int64(String(typed.filter(\.isNumber).prefix(12))) ?? 0, 999_999_999_999)
        })
    }

    /// − / + and "Use …" change the number, so the box shows the new value.
    private func setLimit(_ id: UUID, _ value: Int64) {
        limits[id] = value
        limitTexts[id] = nil
    }

    private func rounded(_ value: Int64) -> Int64 {
        (value + Self.step / 2) / Self.step * Self.step
    }

    private func money(_ whole: Int64) -> String {
        MoneyFormatter.string(Money(major: whole, session.ledger.base))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let settings = (try? session.budgets.settings()) ?? (.calendarMonth, 80)
        kind = settings.kind
        warnPercent = settings.warnPercent
        let scale = Money.scale(session.ledger.base.minorUnits)
        if let plan = try? session.budgets.plan(currentPeriod) {
            totalText = String(plan.total.minorUnits / scale)
            limits = plan.limits.mapValues { $0.minorUnits / scale }
        }
    }

    private func save(total: Int64) {
        let base = session.ledger.base
        let previousKind = (try? session.budgets.settings().kind) ?? .calendarMonth
        let ok = session.perform("Couldn't save the budget. Try again.") {
            try session.budgets.setSettings(kind, warnPercent)
            // No total typed but limits set: the total is the limits added up (owner screenshot, 2026-10-12).
            let effective = total > 0 ? total : limits.values.filter { $0 > 0 }.reduce(0, +)
            let plan = BudgetPlan(periodStart: currentPeriod.start, total: Money(major: effective, base),
                                  limits: limits.filter { $0.value > 0 }.mapValues { Money(major: $0, base) })
            try session.budgets.save(plan)
        }
        if ok {
            session.budgetRevision += 1
            session.toasts.show(previousKind == kind ? "Budget saved" : "Budget saved · period changed")
            dismiss()
        }
    }
}
