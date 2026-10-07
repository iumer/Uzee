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
        let settings = (try? session.budgets.settings()) ?? (.calendarMonth, 80)
        kind = settings.kind
        warnPercent = settings.warnPercent
    }

    var today: LocalDate { LocalDate(Date(), in: .current) }
    var current: BudgetPeriod { BudgetPeriod.containing(today, kind: kind) }

    func summary(for period: BudgetPeriod) -> BudgetSummary? {
        guard let plan = try? session.budgets.plan(period) else { return nil }
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
        if case .calendarMonth = period.kind { return period.start.startDate(in: .current).formatted(format) }
        return DatePresets.text(from: period.start, through: period.end)
    }
}

/// Budget (SCR-11): what's left this period, by category, my share only.
struct BudgetView: View {
    @Bindable var session: AppSession
    @State private var periodStart: LocalDate?

    var body: some View {
        let model = BudgetModel(session: session)
        let period = periodStart.map { BudgetPeriod.containing($0, kind: model.kind) } ?? model.current
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                if let summary = model.summary(for: period) {
                    overview(summary, model: model)
                    categories(summary, model: model)
                    historyCard(model.history(count: 6, before: model.current), model: model)
                    Text("Your shares only · transfers and loans excluded · warning at \(model.warnPercent)%"
                         + (session.ledger.footnote.map { " · " + $0 } ?? ""))
                        .font(.caption).foregroundStyle(UZColor.label2)
                        .accessibilityIdentifier("budget.footnote")
                } else {
                    UZCard {
                        EmptyStateView("No budget yet", systemImage: "chart.pie",
                                       description: "Set a monthly total and limits per category. Your spending still counts while you decide.",
                                       actionTitle: "Set budget") { session.paths[.budget, default: []].append(.budgetLimits) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("budget.empty")
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Budget")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { periodMenu(model: model, selected: period) }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.budgetLimits) { Text("Edit") }
                    .accessibilityIdentifier("budget.edit")
            }
        }
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
                        Text(summary.isOver ? "Over by" : "Left").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
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
            HStack {
                SectionHeader("Categories")
                Spacer()
                Text("your shares").font(.footnote).foregroundStyle(UZColor.label2)
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

/// A category's budget: this period, last six periods and its transactions.
struct BudgetCategoryView: View {
    @Bindable var session: AppSession
    let categoryID: UUID
    let periodStart: LocalDate

    var body: some View {
        let model = BudgetModel(session: session)
        let period = BudgetPeriod.containing(periodStart, kind: model.kind)
        let category = session.ledger.category(categoryID)
        let ids = Set([categoryID] + session.ledger.categories.filter { $0.parentID == categoryID }.map(\.id))
        let rows = session.transactions.filter { period.contains($0.localDate) && ($0.categoryID.map(ids.contains) ?? false) }
        let line = model.summary(for: period)?.lines.first { $0.categoryID == categoryID }
        let history = ([period] + (0..<5).reduce(into: [BudgetPeriod]()) { list, _ in list.append((list.last ?? period).previous) })
            .reversed()
            .map { p in (p, BudgetCalculator.spending(session.transactions, in: p, base: session.ledger.base, rates: session.ledger.rates)
                .filter { ids.contains($0.key) }.values.reduce(Int64(0)) { $0 + $1.minorUnits }) }
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
            Section("\(BudgetModel.title(period)) transactions") {
                if rows.isEmpty {
                    Text("Nothing spent here yet this period.").foregroundStyle(UZColor.label2)
                }
                ForEach(rows) { transaction in
                    NavigationLink(value: Route.transaction(transaction.id)) {
                        TransactionRow(transaction: transaction, ledger: session.ledger)
                    }
                }
            }
        }
        .navigationTitle(category?.name ?? "Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}
