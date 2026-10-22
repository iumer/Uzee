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
    @State private var adding = false
    @State private var renaming: SpendCategory?
    @State private var deleting: SpendCategory?
    @State private var renameText = ""
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
                        .contextMenu { customMenu(category) }
                }
                // Your own lines, like "Loans" (owner, 2026-10-22).
                Button { adding = true } label: {
                    Label("Add a budget line", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("limits.addLine")
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
                Text("Steps of Rs 1,000. Suggestions use what you spent last period. A line named \"Loans\" counts money you lend "
                     + "and pay back. Long-press a line you added to rename or delete it.")
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
        .sheet(isPresented: $adding) {
            BudgetLineSheet(session: session, base: session.ledger.base) { category, limit in
                setLimit(category.id, limit)
            }
        }
        .alert("Rename \(renaming?.name ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let category = renaming {
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        _ = session.perform("Couldn't rename it. Try another name.", { try session.activity.renameCategory(category.id, name) })
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onChange(of: renaming) { renameText = renaming?.name ?? "" }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let category = deleting,
                   session.perform("Couldn't delete it. Try again.", { try session.activity.deleteCategory(category.id) }) {
                    limits[category.id] = nil
                    limitTexts[category.id] = nil
                }
                deleting = nil
            }
        } message: {
            Text("Its limit goes. Anything filed under it moves to Other.")
        }
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

    /// Rename and Delete for lines you added (built-in categories are managed in Settings › Categories).
    @ViewBuilder
    private func customMenu(_ category: SpendCategory) -> some View {
        if category.systemKey == nil {
            Button("Rename", systemImage: "pencil") { renaming = category }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = category }
        }
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

/// A budget line of your own: a name and a limit. It becomes an expense category, so you can file spending under it;
/// "Loans" also counts money you lend and pay back (owner, 2026-10-22).
struct BudgetLineSheet: View {
    @Bindable var session: AppSession
    let base: Currency
    let onAdd: (SpendCategory, Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var limitText = ""
    @State private var problem: String?

    private var isLoans: Bool {
        BudgetCalculator.isLoansLine(SpendCategory(type: .expense, name: name, group: .other))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Loans or Gifts", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("budgetLine.name")
                    HStack {
                        Text(base.symbol).foregroundStyle(UZColor.label2)
                        TextField("Limit", text: $limitText)
                            .keyboardType(.numberPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("budgetLine.limit")
                    }
                } footer: {
                    Text(isLoans ? "Counts money you lend and pay back on loans. It doesn't show as spending anywhere else."
                         : "It's also a new category, so you can file spending under it when you add it.")
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Add a budget line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { afterTyping(add) }.fontWeight(.semibold).accessibilityIdentifier("budgetLine.add")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { problem = "Give it a name."; return }
        let limit = min(Int64(String(limitText.filter(\.isNumber).prefix(12))) ?? 0, 999_999_999_999)
        if let existing = session.ledger.categories.first(where: {
            $0.parentID == nil && $0.type == .expense && NameKey.make($0.name) == NameKey.make(clean)
        }) {
            // Already there (maybe hidden): use it rather than making a second one.
            if existing.isHidden { _ = session.perform("Couldn't show it.", { try session.activity.setCategoryHidden(false, existing.id) }) }
            onAdd(existing, limit)
            dismiss()
            return
        }
        var created: SpendCategory?
        if session.perform("Couldn't add it. Try another name.", { created = try session.activity.createCategory(clean, nil) }), let created {
            onAdd(created, limit)
            dismiss()
        }
    }
}
