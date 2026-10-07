import SwiftUI
import UZeeCore

/// Bills & subscriptions (SCR-15/16): monthly and yearly commitments, what's due now, what's coming,
/// plans (kameti, car installment), subscriptions, group bills, income and paused or cancelled items.
struct BillsHubView: View {
    @Bindable var session: AppSession
    let tab: AppTab
    @State private var paying: Occurrence?
    @State private var showsForm = false

    var body: some View {
        let model = RecurringModel(session: session)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                if session.recurring.items.isEmpty {
                    UZCard {
                        EmptyStateView("No bills yet", systemImage: "arrow.triangle.2.circlepath",
                                       description: "Add rent, utilities, subscriptions, salary, an installment plan or a kameti. UZee reminds you and records each payment.",
                                       actionTitle: "Add recurring") { showsForm = true }
                    }
                } else {
                    summary(model)
                    dueNow(model)
                    upcoming(model)
                    plans(model)
                    subscriptions(model)
                    groupBills(model)
                    list("Bills", items: model.active.filter { model.bucket($0) == .bills && !$0.type.isIncome }, model: model, id: "bills")
                    list("Income", items: model.active.filter { $0.type.isIncome && $0.groupID == nil }, model: model, id: "income")
                    stopped(model)
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Bills & subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add recurring", systemImage: "plus") { showsForm = true }
                    .accessibilityIdentifier("bills.add")
            }
        }
        .sheet(item: $paying) { occurrence in
            MarkPaidSheet(session: session, occurrence: occurrence)
        }
        .sheet(isPresented: $showsForm) {
            RecurringFormSheet(session: session, item: nil)
        }
        .accessibilityIdentifier("screen.bills")
    }

    // MARK: Summary

    private func summary(_ model: RecurringModel) -> some View {
        let monthly = model.monthlyTotal(model.spendingItems)
        let mix = model.mix
        let total = max(1, mix.reduce(Int64(0)) { $0 + $1.amount.minorUnits })
        return UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        Text("Every month").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                        AmountText(monthly, font: .system(.title, weight: .bold))
                            .accessibilityIdentifier("bills.monthly")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: UZSpacing.xxs) {
                        Text("Every year").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                        AmountText(model.yearly(fromMonthly: monthly), font: .title3.weight(.semibold))
                            .accessibilityIdentifier("bills.yearly")
                    }
                }
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(mix) { part in
                            model.bucketColor(part.bucket)
                                .frame(width: max(4, proxy.size.width * CGFloat(part.amount.minorUnits) / CGFloat(total)))
                        }
                    }
                    .clipShape(.capsule)
                }
                .frame(height: 10)
                .accessibilityHidden(true)
                ForEach(mix) { part in
                    HStack(spacing: UZSpacing.m) {
                        Circle().fill(model.bucketColor(part.bucket)).frame(width: 8, height: 8)
                        Text(model.bucketName(part.bucket)).font(.subheadline)
                        Spacer()
                        Text(MoneyFormatter.string(part.amount)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Your shares only · estimates included" + (session.ledger.footnote.map { " · " + $0 } ?? " · USD at $1 = Rs 280"))
                    .font(.caption).foregroundStyle(UZColor.label2)
            }
        }
    }

    // MARK: Due

    @ViewBuilder
    private func dueNow(_ model: RecurringModel) -> some View {
        let rows = model.nextOccurrences.filter { $0.occurrence.state == .overdue || $0.occurrence.state == .dueToday }
        if !rows.isEmpty {
            let overdue = rows.filter { $0.occurrence.state == .overdue }.count
            section("Due now", right: overdue > 0 ? "\(overdue) overdue" : "today", id: "bills.dueNow") {
                ForEach(rows) { row in
                    dueRow(row.item, row.occurrence, model: model)
                }
            }
        }
    }

    @ViewBuilder
    private func upcoming(_ model: RecurringModel) -> some View {
        let end = model.today.addingDays(30)
        let rows = model.nextOccurrences.filter { $0.occurrence.state == .upcoming && $0.occurrence.dueDate <= end }
        if !rows.isEmpty {
            let range = "\(DateText.monthYear(model.today).prefix(3)) – \(DateText.monthYear(end).prefix(3))"
            section("Upcoming", right: range, id: "bills.upcoming", footer: salaryLine(model)) {
                ForEach(rows) { row in
                    dueRow(row.item, row.occurrence, model: model)
                }
            }
        }
    }

    /// "Due before salary (Wed 21 Oct): Rs 83,800".
    private func salaryLine(_ model: RecurringModel) -> String? {
        guard let salary = model.nextSalary, salary.dueDate > model.today else { return nil }
        let rows = model.due(from: model.today, through: salary.dueDate.addingDays(-1))
            .filter { !$0.item.type.isIncome && $0.occurrence.state != .overdue && !$0.occurrence.isResolved }
        return "Due before salary (\(DateText.short(salary.dueDate))): \(MoneyFormatter.string(model.total(rows)))"
    }

    private func dueRow(_ item: RecurringItem, _ occurrence: Occurrence, model: RecurringModel) -> some View {
        HStack(spacing: UZSpacing.m) {
            NavigationLink(value: Route.recurring(item.id)) {
                RecurringRow(model: model, item: item, occurrence: occurrence, showsDate: true)
            }
            .buttonStyle(.plain)
            Button(item.type.isIncome ? "Received" : "Pay") { paying = occurrence }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("bills.pay.\(item.name)")
        }
        .accessibilityIdentifier("bills.row.\(item.name)")
    }

    // MARK: Plans

    @ViewBuilder
    private func plans(_ model: RecurringModel) -> some View {
        let items = model.active.filter(\.type.isPlan)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                HStack {
                    SectionHeader("Plans")
                    Text("\(items.count) active").font(.subheadline).foregroundStyle(UZColor.label2)
                }
                ForEach(items) { item in
                    NavigationLink(value: Route.recurring(item.id)) {
                        PlanCard(model: model, item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bills.plan.\(item.name)")
                }
            }
        }
    }

    // MARK: Lists

    @ViewBuilder
    private func subscriptions(_ model: RecurringModel) -> some View {
        let items = model.active.filter { $0.type == .subscription && $0.groupID == nil }
        if !items.isEmpty {
            let monthly = model.monthlyTotal(items)
            section("Subscriptions", right: "\(items.count) active · \(MoneyFormatter.string(monthly)) / month", id: "bills.subscriptions",
                    footer: "\(MoneyFormatter.string(model.yearly(fromMonthly: monthly))) a year") {
                ForEach(items) { item in link(item, model: model) }
            }
        }
    }

    @ViewBuilder
    private func groupBills(_ model: RecurringModel) -> some View {
        let groups = Dictionary(grouping: model.active.filter { $0.groupID != nil }, by: { $0.groupID! })
        ForEach(session.people.groups.filter { groups[$0.id] != nil }) { group in
            let others = group.memberIDs.filter { $0 != session.people.selfID }.compactMap { session.people.person($0)?.name }
            section("\(group.name) group bills", right: others.isEmpty ? "" : "with \(others.joined(separator: ", "))",
                    id: "bills.group.\(group.name)", footer: "Split equally. Only your share counts toward your budget.") {
                ForEach(groups[group.id] ?? []) { item in link(item, model: model) }
                NavigationLink(value: Route.group(group.id)) {
                    HStack {
                        Text(groupBalance(group)).font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.tint)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupBalance(_ group: SplitGroup) -> String {
        let balance = session.balances.group(group.id)
        let net = balance.myNet.total(in: session.ledger.base, rates: session.ledger.rates)
        if net.isZero { return "\(group.name) group · settled up" }
        let amount = MoneyFormatter.string(Money(minorUnits: net.minorUnits.magnitudeClamped, currency: net.currency))
        if group.memberIDs.count == 2, let other = group.memberIDs.first(where: { $0 != session.people.selfID }),
           let name = session.people.person(other)?.name {
            return net.isNegative ? "\(group.name) group · you owe \(name) \(amount)" : "\(group.name) group · \(name) owes you \(amount)"
        }
        return net.isNegative ? "\(group.name) group · you owe \(amount)" : "\(group.name) group · you're owed \(amount)"
    }

    @ViewBuilder
    private func list(_ title: String, items: [RecurringItem], model: RecurringModel, id: String) -> some View {
        if !items.isEmpty {
            section(title, right: "", id: id) {
                ForEach(items) { item in link(item, model: model) }
            }
        }
    }

    @ViewBuilder
    private func stopped(_ model: RecurringModel) -> some View {
        let items = session.recurring.items.filter { !$0.isActive }
        if !items.isEmpty {
            let paused = items.filter { $0.status == .paused }.count
            section("Paused / cancelled", right: "\(paused) paused · \(items.count - paused) cancelled", id: "bills.stopped") {
                ForEach(items) { item in link(item, model: model) }
            }
        }
    }

    private func link(_ item: RecurringItem, model: RecurringModel) -> some View {
        NavigationLink(value: Route.recurring(item.id)) {
            RecurringRow(model: model, item: item)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bills.item.\(item.name)")
    }

    private func section<Content: View>(_ title: String, right: String, id: String, footer: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                if !right.isEmpty {
                    Text(right).font(.subheadline).foregroundStyle(UZColor.label2).lineLimit(1).fixedSize()
                }
            }
            UZCard(padding: UZSpacing.l) {
                VStack(alignment: .leading, spacing: UZSpacing.l) { content() }
            }
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(UZColor.label2).padding(.horizontal, UZSpacing.xs)
                    .accessibilityIdentifier("\(id).footer")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// Kameti or installment plan card: progress, what's left and what's next (KAM-04, LOAN-06).
struct PlanCard: View {
    let model: RecurringModel
    let item: RecurringItem

    var body: some View {
        let records = model.records(item)
        let next = model.next(item)
        UZCard {
            VStack(alignment: .leading, spacing: UZSpacing.l) {
                HStack(spacing: UZSpacing.l) {
                    RecurringTile(item: item, size: 40)
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        Text(item.type == .kameti ? item.name : item.name.components(separatedBy: " · ").first ?? item.name)
                            .font(.headline).foregroundStyle(UZColor.label)
                        Text(subtitle).font(.footnote).foregroundStyle(UZColor.label2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                }
                if item.type == .kameti {
                    kameti(KametiSummary(item, records: records), next: next)
                } else {
                    installment(InstallmentSummary(item, records: records), next: next)
                }
            }
        }
    }

    private var subtitle: String {
        let amount = MoneyFormatter.string(item.amount)
        let count = item.rule.limit.map { " · \($0) months" } ?? ""
        if item.type == .kameti, let total = item.rule.limit, let last = item.rule.date(at: total - 1) {
            return "\(amount) / month\(count) · \(DateText.monthYear(item.rule.anchor)) → \(DateText.monthYear(last))"
        }
        let bank = model.session.ledger.account(item.accountID)?.name
        return [bank, "\(amount) / month\(count)"].compactMap { $0 }.joined(separator: " · ")
    }

    private func kameti(_ summary: KametiSummary, next: Occurrence?) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            ProgressBarView(fraction: summary.total > 0 ? Double(summary.paid) / Double(summary.total) : 0,
                            tint: Color(hex: item.colorHex), label: "\(summary.paid) of \(summary.total) paid")
            HStack {
                figure("Contributed", MoneyFormatter.string(summary.contributed), "of \(MoneyFormatter.string(summary.totalContributions))")
                Spacer()
                if let next {
                    figure("Next · #\(next.sequence)", DateText.short(next.dueDate), DateText.relative(next.dueDate, today: model.today),
                           alignment: .trailing)
                }
            }
            if summary.mismatch {
                Label("Payouts (\(MoneyFormatter.string(summary.payouts))) don't match contributions "
                      + "(\(MoneyFormatter.string(summary.totalContributions))). Check figures with the committee.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(UZColor.warning)
                    .accessibilityIdentifier("plan.mismatch")
            }
        }
    }

    private func installment(_ summary: InstallmentSummary, next: Occurrence?) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            ProgressBarView(fraction: summary.total > 0 ? Double(summary.paid) / Double(summary.total) : 0,
                            tint: Color(hex: item.colorHex), label: "\(summary.paid) of \(summary.total) paid")
            HStack {
                figure("Remaining", MoneyFormatter.string(summary.remaining), "\(summary.left) left"
                       + (summary.endDate.map { " · ends \(DateText.monthYear($0))" } ?? ""))
                Spacer()
                if let next {
                    figure("Next due", DateText.short(next.dueDate), "#\(next.sequence) · \(DateText.relative(next.dueDate, today: model.today))",
                           alignment: .trailing)
                }
            }
        }
    }

    private func figure(_ title: String, _ value: String, _ sub: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(UZColor.label2)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(UZColor.label)
            Text(sub).font(.caption).foregroundStyle(UZColor.label2)
        }
        .accessibilityElement(children: .combine)
    }
}
