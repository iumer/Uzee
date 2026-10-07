import SwiftUI
import UZeeCore

/// Budget limits (SCR-12): total, a limit per category in steps of Rs 1,000 with "Use last period"
/// suggestions, warning threshold and period type. Saved with Done; new periods copy these.
struct BudgetLimitsView: View {
    @Bindable var session: AppSession
    @State private var totalText = ""
    @State private var limits: [UUID: Int64] = [:]
    @State private var warnPercent = 80
    @State private var kind: BudgetPeriodKind = .calendarMonth
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    private static let step: Int64 = 1_000

    var body: some View {
        let base = session.ledger.base
        let total = Int64(totalText.filter(\.isNumber)) ?? 0
        let sum = limits.values.reduce(0, +)
        let unassigned = total - sum
        Form {
            Section {
                HStack {
                    Text("Total budget")
                    Spacer()
                    Text(base.symbol).foregroundStyle(UZColor.label2)
                    TextField("235000", text: $totalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 140)
                        .accessibilityIdentifier("limits.total")
                }
                HStack {
                    Text(unassigned == 0 ? "Every rupee assigned"
                         : unassigned > 0 ? "\(money(unassigned)) unassigned" : "\(money(-unassigned)) over the total")
                        .foregroundStyle(unassigned < 0 ? UZColor.negative : unassigned == 0 ? UZColor.positive : UZColor.label)
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
                        for category in groups { limits[category.id] = rounded(suggestion(category.id)) }
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
        .navigationTitle("Budget limits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(category.name)
                    Text(money(value)).font(.headline).monospacedDigit()
                }
                Spacer()
                Stepper("", onIncrement: { limits[category.id] = value + Self.step },
                        onDecrement: { limits[category.id] = max(0, value - Self.step) })
                    .labelsHidden()
                    .accessibilityLabel("\(category.name) limit")
                    .accessibilityValue(money(value))
                    .accessibilityIdentifier("limits.stepper.\(category.name)")
            }
            HStack {
                Text("Last period \(money(suggestion(category.id)))").font(.footnote).foregroundStyle(UZColor.label2)
                Spacer()
                if suggested != value && suggested > 0 {
                    Button("Use \(money(suggested))") { limits[category.id] = suggested }
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
            let plan = BudgetPlan(periodStart: currentPeriod.start, total: Money(major: total, base),
                                  limits: limits.filter { $0.value > 0 }.mapValues { Money(major: $0, base) })
            try session.budgets.save(plan)
        }
        if ok {
            session.toasts.show(previousKind == kind ? "Budget saved" : "Budget saved · period changed")
            dismiss()
        }
    }
}
