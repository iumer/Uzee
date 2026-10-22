import Charts
import SwiftUI
import UZeeCore

/// Shared budget figures for a period, read fresh from the session each time.
@MainActor
struct BudgetModel {
    let session: AppSession
    let kind: BudgetPeriodKind
    let warnPercent: Int

    init(session: AppSession) {
        self.session = session
        // Read so a saved budget redraws every screen built from this model.
        _ = session.budgetRevision
        let settings = (try? session.budgets.settings()) ?? (.calendarMonth, 80)
        kind = settings.kind
        warnPercent = settings.warnPercent
    }

    var today: LocalDate { LocalDate(Date(), in: .current) }
    /// This period: your own dates when you picked some that haven't ended yet (owner, 2026-10-19), else the
    /// month or salary cycle from Budget settings.
    var current: BudgetPeriod { custom ?? BudgetPeriod.containing(today, kind: kind) }

    static let customKey = "uzee.budget.customDates"

    /// The dates you picked ("2026-10-19|2026-11-18"), while they still include today or later.
    var custom: BudgetPeriod? {
        guard let text = UserDefaults.standard.string(forKey: Self.customKey) else { return nil }
        let parts = text.split(separator: "|").map(String.init)
        guard parts.count == 2, let start = LocalDate(parts[0]), let end = LocalDate(parts[1]), start <= end, end >= today else { return nil }
        return BudgetPeriod(start: start, end: end, kind: kind)
    }

    var isCustom: Bool { custom != nil }

    static func setCustom(start: LocalDate, end: LocalDate) {
        UserDefaults.standard.set("\(start.description)|\(end.description)", forKey: customKey)
    }

    static func clearCustom() { UserDefaults.standard.removeObject(forKey: customKey) }

    /// The period a list or drill-down that starts on `start` means: your own dates when they start there.
    func period(startingAt start: LocalDate) -> BudgetPeriod {
        if let custom, custom.start == start { return custom }
        return BudgetPeriod.containing(start, kind: kind)
    }

    func summary(for period: BudgetPeriod) -> BudgetSummary? {
        // Your own dates use the budget (total and limits) of the month or cycle they start in.
        let planPeriod = BudgetPeriod.containing(period.start, kind: kind)
        guard let plan = try? session.budgets.plan(planPeriod == period ? period : planPeriod) else { return nil }
        return BudgetCalculator.summary(plan: plan, period: period, transactions: session.transactions,
                                        categories: session.ledger.categories, base: session.ledger.base, rates: session.ledger.rates)
    }

    /// Past periods with a budget, newest first (for history; never creates plans).
    func history(count: Int, before period: BudgetPeriod) -> [BudgetSummary] {
        let plans = (try? session.budgets.existingPlans()) ?? [:]
        var result: [BudgetSummary] = []
        var cursor = period.previous
        for _ in 0..<count {
            if let plan = plans[cursor.start] {
                result.append(BudgetCalculator.summary(plan: plan, period: cursor, transactions: session.transactions,
                                                       categories: session.ledger.categories, base: session.ledger.base,
                                                       rates: session.ledger.rates))
            }
            cursor = cursor.previous
        }
        return result
    }

    static func title(_ period: BudgetPeriod) -> String {
        let format = Date.FormatStyle.dateTime.month(.wide).year()
        if case .calendarMonth = period.kind, period == BudgetPeriod.containing(period.start, kind: period.kind) {
            return period.start.startDate(in: .current).formatted(format)
        }
        return DatePresets.text(from: period.start, through: period.end)
    }
}

/// Budget (SCR-11): what's left this period, by category, my share only.
struct BudgetView: View {
    @Bindable var session: AppSession
    @State private var periodStart: LocalDate?
    @State private var choosingDates = false

    var body: some View {
        let model = BudgetModel(session: session)
        let period = periodStart.map { model.period(startingAt: $0) } ?? model.current
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                PlanSwitch(session: session)
                if let summary = model.summary(for: period) {
                    overview(summary, model: model)
                    categories(summary, model: model)
                    historyCard(model.history(count: 6, before: model.current), model: model)
                    reportsRow
                    let loansLine = summary.lines.contains { line in session.ledger.category(line.categoryID).map(BudgetCalculator.isLoansLine) == true }
                    Text("Your shares only · " + (loansLine ? "transfers excluded, loans count in Loans" : "transfers and loans excluded")
                         + " · warning at \(model.warnPercent)%"
                         + (session.ledger.footnote.map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(UZColor.label2)
                        .accessibilityIdentifier("budget.footnote")
                } else {
                    UZCard {
                        EmptyStateView("No budget yet", systemImage: "chart.pie",
                                       description: "Set a monthly total and limits per category. Your spending still counts while you decide.",
                                       actionTitle: "Set budget") { session.paths[.plan, default: []].append(.budgetLimits) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("budget.empty")
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Plan")
        .toolbar {
            // Top right is the profile icon on every tab, so the period menu sits on the left.
            ToolbarItem(placement: .topBarLeading) { periodMenu(model: model, selected: period) }
        }
        .sheet(isPresented: $choosingDates) {
            BudgetDatesSheet(start: period.start, end: period.end) { start, end in
                BudgetModel.setCustom(start: start, end: end)
                periodStart = nil
                session.budgetRevision += 1
            }
        }
    }

    /// Reports used to sit on Home as Insights; Home is simpler now, so they live with the budget.
    private var reportsRow: some View {
        NavigationLink(value: Route.reports) {
            UZCard(padding: UZSpacing.l) {
                HStack(spacing: UZSpacing.l) {
                    Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(UZColor.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        Text("Reports").font(.body.weight(.medium)).foregroundStyle(UZColor.label)
                        Text("Income, spending and where it went, month by month").font(.footnote).foregroundStyle(UZColor.label2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budget.reports")
    }

    // MARK: Overview ring

    private func overview(_ summary: BudgetSummary, model: BudgetModel) -> some View {
        let base = session.ledger.base
        let total = Double(summary.total.minorUnits)
        let remaining = total > 0 ? Double(summary.left.minorUnits) / total : 0
        let percent = BudgetCalculator.percentText(summary.usedBasisPoints)
        let overLines = summary.lines.filter { $0.overBy != nil }
        return UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.l) {
                HStack(spacing: UZSpacing.xxl) {
                    ProgressRingView(remaining: remaining, label: "\(percent) of budget used") {
                        VStack(spacing: 0) {
                            Text(percent).font(.title2.bold()).monospacedDigit()
                            Text("used").font(.caption).foregroundStyle(UZColor.label2)
                        }
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: UZSpacing.xs) {
                        Text(summary.isOver ? "Over budget by" : "Budget left").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                        AmountText(summary.isOver ? ((try? summary.left.negated()) ?? summary.left) : summary.left,
                                   font: .system(.largeTitle, weight: .bold))
                            .foregroundStyle(summary.isOver ? UZColor.negative : UZColor.label)
                            .accessibilityIdentifier("budget.left")
                        Text("Spent \(MoneyFormatter.string(summary.spent)) of \(MoneyFormatter.string(summary.total))")
                            .font(.subheadline).foregroundStyle(UZColor.label2).monospacedDigit()
                            .accessibilityIdentifier("budget.spent")
                    }
                }
                Text(periodLine(summary.period, model: model)).font(.footnote).foregroundStyle(UZColor.label2)
                ForEach(overLines) { line in
                    Label("\(name(line.categoryID)) over by \(MoneyFormatter.string(line.overBy ?? .zero(base)))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(UZColor.warning)
                        .accessibilityIdentifier("budget.over.\(name(line.categoryID))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func periodLine(_ period: BudgetPeriod, model: BudgetModel) -> String {
        let range = DatePresets.text(from: period.start, through: period.end)
        guard period.contains(model.today) else { return range }
        let left = model.today.days(to: period.end) + 1
        return "\(range) · \(left) \(left == 1 ? "day" : "days") left"
    }

    // MARK: Categories

    private func categories(_ summary: BudgetSummary, model: BudgetModel) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Where it went")
                Text("your shares").font(.footnote).foregroundStyle(UZColor.label2)
                Spacer()
                NavigationLink("Edit limits", value: Route.budgetLimits)
                    .font(.subheadline)
                    .accessibilityIdentifier("budget.edit")
            }
            if summary.unassigned.minorUnits != 0 {
                UZCard(padding: UZSpacing.xl) {
                    HStack {
                        VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                            Text(summary.unassigned.isNegative
                                 ? "Limits are \(MoneyFormatter.string(summary.unassigned, sign: .none)) over the total"
                                 : "\(MoneyFormatter.string(summary.unassigned)) unassigned")
                                .font(.subheadline.weight(.semibold))
                            Text("Limits add up to \(MoneyFormatter.string(summary.assigned)) of \(MoneyFormatter.string(summary.total))")
                                .font(.footnote).foregroundStyle(UZColor.label2)
                        }
                        Spacer()
                        NavigationLink("Assign", value: Route.budgetLimits).font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("budget.unassigned")
            }
            UZCard(padding: UZSpacing.xxl) {
                VStack(spacing: UZSpacing.l) {
                    ForEach(summary.lines) { line in
                        NavigationLink(value: Route.budgetCategory(line.categoryID, summary.period.start)) {
                            BudgetLineRow(line: line, name: name(line.categoryID), kind: group(line.categoryID),
                                          note: note(for: line), warnPercent: model.warnPercent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("budget.line.\(name(line.categoryID))")
                        if line.id != summary.lines.last?.id { Divider() }
                    }
                }
            }
            let extra = summary.unbudgeted.filter { $0.value.minorUnits > 0 }
            if !extra.isEmpty {
                Text("Also spent: " + extra.map { "\(name($0.key)) \(MoneyFormatter.string($0.value))" }.sorted().joined(separator: " · ")
                     + " (no limit set).")
                    .font(.footnote).foregroundStyle(UZColor.label2)
            }
        }
    }

    private func note(for line: BudgetLine) -> String {
        if let over = line.overBy { return "Over by \(MoneyFormatter.string(over))" }
        return "\(MoneyFormatter.string(line.remaining)) left"
    }

    // MARK: History

    private func historyCard(_ history: [BudgetSummary], model: BudgetModel) -> some View {
        let kept = history.filter { !$0.isOver }.count
        let over = history.filter(\.isOver).map { BudgetModel.title($0.period) }
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("History")
            UZCard {
                VStack(alignment: .leading, spacing: UZSpacing.m) {
                    if history.isEmpty {
                        Text("Your record appears after the first full period.").font(.subheadline).foregroundStyle(UZColor.label2)
                    } else {
                        Text("Budget kept \(kept) of \(history.count) \(model.kind == .calendarMonth ? "months" : "periods")")
                            .font(.headline)
                            .accessibilityIdentifier("budget.kept")
                        if !over.isEmpty {
                            Text("Over in " + over.joined(separator: ", ")).font(.footnote).foregroundStyle(UZColor.label2)
                        }
                        Chart(history.reversed(), id: \.period.start) { item in
                            BarMark(x: .value("Period", item.period.start.startDate(in: .current), unit: .month),
                                    y: .value("Spent", chartValue(item.spent)))
                                .foregroundStyle(item.isOver ? UZColor.negative : UZColor.tint)
                            RuleMark(y: .value("Budget", chartValue(item.total)))
                                .foregroundStyle(UZColor.label2)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                        .chartYAxis(.hidden)
                        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                        .frame(height: 120)
                        .accessibilityLabel("Spending against budget for the last \(history.count) periods. Kept \(kept).")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Period menu

    private func periodMenu(model: BudgetModel, selected: BudgetPeriod) -> some View {
        Menu {
            let periods = (0..<7).reduce(into: [model.current]) { list, _ in list.append(list.last!.previous) }
            ForEach(periods.dropLast()) { period in
                Button {
                    periodStart = period == model.current ? nil : period.start
                } label: {
                    if period == selected { Label(BudgetModel.title(period), systemImage: "checkmark") } else { Text(BudgetModel.title(period)) }
                }
            }
            Divider()
            // Pick your own start and end dates (owner, 2026-10-19), e.g. when salary came early.
            Button("Choose dates…", systemImage: "calendar") { choosingDates = true }
                .accessibilityIdentifier("budget.chooseDates")
            if model.isCustom {
                Button("Back to \(BudgetModel.title(BudgetPeriod.containing(model.today, kind: model.kind)))", systemImage: "arrow.uturn.backward") {
                    BudgetModel.clearCustom()
                    periodStart = nil
                    session.budgetRevision += 1
                }
                .accessibilityIdentifier("budget.resetDates")
            }
        } label: {
            HStack(spacing: UZSpacing.xs) {
                Text(BudgetModel.title(selected)).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
        }
        .accessibilityLabel("Period, \(BudgetModel.title(selected))")
        .accessibilityIdentifier("budget.period")
    }

    private func name(_ id: UUID) -> String { session.ledger.category(id)?.name ?? "Category" }
    private func group(_ id: UUID) -> CategoryKind { session.ledger.category(id)?.group ?? .other }
}

/// Charts take Double; used for bar heights only, never for money arithmetic.
func chartValue(_ money: Money) -> Double {
    NSDecimalNumber(decimal: money.decimalValue).doubleValue
}

/// One category: tile, name, spent of limit, bar and what's left.
struct BudgetLineRow: View {
    let line: BudgetLine
    let name: String
    let kind: CategoryKind
    let note: String
    let warnPercent: Int

    var body: some View {
        let fraction = line.limit.minorUnits > 0 ? Double(line.spent.minorUnits) / Double(line.limit.minorUnits) : 0
        VStack(alignment: .leading, spacing: UZSpacing.s) {
            HStack(spacing: UZSpacing.l) {
                CategoryTile(kind, size: 32)
                Text(name).font(.body.weight(.medium))
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(MoneyFormatter.string(line.spent)).font(.body.weight(.semibold)).monospacedDigit()
                    Text("of \(MoneyFormatter.string(line.limit))").font(.caption).foregroundStyle(UZColor.label2).monospacedDigit()
                }
            }
            ProgressBarView(fraction: fraction, tint: CategoryStyle(kind).color,
                            label: "\(name), \(MoneyFormatter.spoken(line.spent)) of \(MoneyFormatter.spoken(line.limit)), \(note)")
            Text(note).font(.footnote)
                .foregroundStyle(line.state(warnPercent: warnPercent) == .over ? UZColor.negative
                                 : line.state(warnPercent: warnPercent) == .warning ? UZColor.warning : UZColor.label2)
        }
        .contentShape(Rectangle())
    }
}


/// A category's budget: this period, last six periods, its transactions and, for Subscriptions, what you track.
struct BudgetCategoryView: View {
    @Bindable var session: AppSession
    let categoryID: UUID
    let periodStart: LocalDate
    /// A subscription drafted from a payment by "Track" (owner, 2026-10-16).
    @State private var repeating: RecurringItem?

    var body: some View {
        let model = BudgetModel(session: session)
        let period = model.period(startingAt: periodStart)
        let category = session.ledger.category(categoryID)
        let ids = Set([categoryID] + session.ledger.categories.filter { $0.parentID == categoryID }.map(\.id))
        let inCategory = session.transactions.filter { $0.categoryID.map(ids.contains) ?? false }
        let rows = inCategory.filter { period.contains($0.localDate) }
        let line = model.summary(for: period)?.lines.first { $0.categoryID == categoryID }
        let history = ([period] + (0..<5).reduce(into: [BudgetPeriod]()) { list, _ in list.append((list.last ?? period).previous) })
            .reversed()
            .map { p in (p, BudgetCalculator.spending(session.transactions, in: p, base: session.ledger.base, rates: session.ledger.rates)
                .filter { ids.contains($0.key) }.values.reduce(Int64(0)) { $0 + $1.minorUnits }) }
        let oldest = history.first?.0.start ?? period.start
        // Re-categorised rows dated before this period count in their own period, so they're listed here (owner, 2026-10-16).
        let earlier: [(BudgetPeriod, [MoneyTransaction])] = history.dropLast().reversed()
            .map { item in (item.0, inCategory.filter { item.0.contains($0.localDate) }) }
            .filter { !$0.1.isEmpty }
        List {
            if let line {
                Section {
                    BudgetLineRow(line: line, name: category?.name ?? "", kind: category?.group ?? .other,
                                  note: line.overBy.map { "Over by \(MoneyFormatter.string($0))" } ?? "\(MoneyFormatter.string(line.remaining)) left",
                                  warnPercent: model.warnPercent)
                }
            }
            Section("Last 6 \(model.kind == .calendarMonth ? "months" : "periods")") {
                Chart(Array(history), id: \.0.start) { item in
                    BarMark(x: .value("Period", item.0.start.startDate(in: .current), unit: .month),
                            y: .value("Spent", chartValue(Money(minorUnits: item.1, currency: session.ledger.base))))
                        .foregroundStyle(line.map { item.1 > $0.limit.minorUnits } == true ? UZColor.negative
                                         : CategoryStyle(category?.group ?? .other).color)
                    if let line {
                        RuleMark(y: .value("Limit", chartValue(line.limit))).foregroundStyle(UZColor.label2)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .frame(height: 140)
                .accessibilityLabel("\(category?.name ?? "") spending for the last six periods")
            }
            Section {
                if rows.isEmpty {
                    Text("Nothing spent here yet this period.").foregroundStyle(UZColor.label2)
                }
                ForEach(rows) { transaction in row(transaction) }
            } header: {
                Text("\(BudgetModel.title(period)) transactions")
            } footer: {
                Text("The total counts \(DatePresets.text(from: period.start, through: period.end)) only.")
            }
            if !earlier.isEmpty {
                Section("Earlier") {
                    ForEach(earlier, id: \.0.start) { group in
                        Text(BudgetModel.title(group.0)).font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label2)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.1) { transaction in row(transaction) }
                    }
                }
            }
            Section {
                Button("See all in Activity") { session.openActivity(categoryID: categoryID, from: oldest, through: period.end) }
                    .accessibilityIdentifier("budgetCategory.activity")
            }
            if category?.group == .subscriptions {
                subscriptions(inCategory.filter { $0.localDate >= oldest && $0.localDate <= period.end })
            }
        }
        .navigationTitle(category?.name ?? "Category")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $repeating) { RecurringFormSheet(session: session, item: nil, draft: $0) }
    }

    private func row(_ transaction: MoneyTransaction) -> some View {
        NavigationLink(value: Route.transaction(transaction.id)) {
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                TransactionRow(transaction: transaction, ledger: session.ledger)
                if let reason = uncountedReason(transaction) {
                    Text(reason).font(.caption).foregroundStyle(UZColor.warning)
                }
            }
        }
    }

    /// Why the spent total leaves a listed row out, so the list and the total agree (owner, 2026-10-16).
    private func uncountedReason(_ transaction: MoneyTransaction) -> String? {
        if transaction.status == .pending { return "Pending · not counted" }
        if SpendingRules.spendingSign(transaction.kind) == 0 { return "\(transaction.kind.name) · not spending" }
        if transaction.myShare.isZero { return "Your share is \(MoneyFormatter.string(transaction.myShare))" }
        if (try? RateTable.toBase(transaction.myShare, base: session.ledger.base, rates: session.ledger.rates)) == nil {
            return "No \(transaction.myShare.currency.code) rate · not counted"
        }
        return nil
    }

    /// Subscriptions you track, and payees in this category no bill covers yet (owner, 2026-10-16).
    @ViewBuilder
    private func subscriptions(_ recent: [MoneyTransaction]) -> some View {
        let recurring = RecurringModel(session: session)
        let tracked = recurring.active.filter { recurring.isSubscription($0) && $0.groupID == nil }
        let untracked = untrackedPayments(recent, recurring: recurring)
        if !tracked.isEmpty {
            Section("Subscriptions you track · \(MoneyFormatter.string(recurring.monthlyTotal(tracked))) / month") {
                ForEach(tracked) { item in
                    NavigationLink(value: Route.recurring(item.id)) { RecurringRow(model: recurring, item: item) }
                        .accessibilityIdentifier("budgetCategory.tracked.\(item.name)")
                }
            }
        }
        if !untracked.isEmpty {
            Section {
                ForEach(untracked) { transaction in
                    HStack(spacing: UZSpacing.l) {
                        VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                            Text(RecurringFinder.displayName(transaction.payeeName ?? "")).lineLimit(1)
                            Text("\(MoneyFormatter.string(transaction.amount)) · \(DateText.short(transaction.localDate))")
                                .font(.footnote).foregroundStyle(UZColor.label2).monospacedDigit()
                        }
                        Spacer(minLength: UZSpacing.m)
                        Button("Track") { repeating = RecurringModel(session: session).draft(from: transaction) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("budgetCategory.track.\(transaction.payeeName ?? "")")
                    }
                }
            } header: {
                Text("Not tracked yet")
            } footer: {
                Text("Track a payment to get reminders and see it with your subscriptions.")
            }
        }
    }

    /// The latest payment per payee that no bill covers yet, newest first.
    private func untrackedPayments(_ transactions: [MoneyTransaction], recurring: RecurringModel) -> [MoneyTransaction] {
        var seen = Set<String>()
        return transactions.sorted { $0.localDate > $1.localDate }.filter { transaction in
            guard transaction.kind == .expense, let payee = transaction.payeeName, !recurring.isTracked(transaction) else { return false }
            return seen.insert(NameKey.make(RecurringFinder.displayName(payee))).inserted
        }
    }
}

/// Your own budget dates: a start and an end, inclusive. Spent, limits and lists use them until the end date
/// passes, then the usual month or cycle comes back.
struct BudgetDatesSheet: View {
    let onSave: (LocalDate, LocalDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(start: LocalDate, end: LocalDate, onSave: @escaping (LocalDate, LocalDate) -> Void) {
        self.onSave = onSave
        _start = State(initialValue: start.startDate(in: .current))
        _end = State(initialValue: end.startDate(in: .current))
    }

    private var startDay: LocalDate { LocalDate(start, in: .current) }
    private var endDay: LocalDate { LocalDate(end, in: .current) }
    private var problem: String? {
        if startDay > endDay { return "The end date is before the start date." }
        if endDay < LocalDate(Date(), in: .current) { return "Pick an end date of today or later; past months are in the period menu." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                        .accessibilityIdentifier("budgetDates.from")
                    DatePicker("To", selection: $end, displayedComponents: .date)
                        .accessibilityIdentifier("budgetDates.to")
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("budgetDates.problem")
                    } else {
                        let days = startDay.days(to: endDay) + 1
                        Text("\(days) \(days == 1 ? "day" : "days"), both dates included. Spent and limits use these dates until \(DatePresets.text(from: endDay, through: endDay)).")
                    }
                }
            }
            .navigationTitle("Budget dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onSave(startDay, endDay)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("budgetDates.use")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
