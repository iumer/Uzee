import Charts
import SwiftUI
import UZeeCore

/// Reports (SCR-27, RPT-01…05): income, spending and net for a period, spending by category, six months of
/// income vs spending, budget kept, subscriptions, people balances and account balances. My shares only.
struct ReportsView: View {
    @Bindable var session: AppSession
    @State private var choice: Choice = .thisMonth
    @State private var pdf: SharedFile?
    /// Dates picked by hand (owner, 2026-11-03); the whole report follows them until "Back to this month".
    @State private var custom: (start: LocalDate, end: LocalDate)?
    @State private var choosingDates = false

    enum Choice: String, CaseIterable, Identifiable {
        // Last month, this month, last 6 months, left to right (owner, 2026-10-19).
        case lastMonth = "Last month"
        case thisMonth = "This month"
        case sixMonths = "Last 6 months"
        var id: String { rawValue }
    }

    private var base: Currency { session.ledger.base }
    private var rates: [String: Decimal] { session.ledger.rates }
    private var today: LocalDate { session.today }

    private var range: (start: LocalDate, end: LocalDate) {
        if let custom { return custom }
        return switch choice {
        case .thisMonth: (today.firstOfMonth, today.lastOfMonth)
        case .lastMonth: (today.firstOfMonth.addingMonths(-1), today.firstOfMonth.addingDays(-1))
        case .sixMonths: (today.firstOfMonth.addingMonths(-6), today.firstOfMonth.addingDays(-1))
        }
    }

    var body: some View {
        let range = range
        let totals = ReportCalculator.totals(session.transactions, from: range.start, through: range.end, base: base, rates: rates)
        let net = (try? totals.income.subtracting(totals.spending)) ?? .zero(base)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                Picker("Period", selection: $choice) {
                    ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reports.period")
                .onChange(of: choice) { custom = nil }
                dates(range)
                content(range: range, totals: totals, net: net)
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, 96)
        }
        .background(UZColor.bg)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Export PDF", systemImage: "square.and.arrow.up") { exportPDF(range: range, totals: totals, net: net) }
                    .accessibilityIdentifier("reports.pdf")
            }
        }
        .sheet(item: $pdf) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $choosingDates) {
            ReportDatesSheet(start: range.start, end: range.end) { custom = ($0, $1) }
                .presentationDetents([.medium])
        }
        .accessibilityIdentifier("screen.reports")
    }

    /// The dates the report covers; tap to pick any start and end.
    private func dates(_ range: (start: LocalDate, end: LocalDate)) -> some View {
        HStack {
            Button { choosingDates = true } label: {
                Label(DatePresets.text(from: range.start, through: range.end), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("reports.dates")
            Spacer()
            if custom != nil {
                Button("Back to \(choice.rawValue.lowercased())") { custom = nil }
                    .font(.subheadline)
                    .accessibilityIdentifier("reports.resetDates")
            } else {
                Text("Tap to choose dates").font(.footnote).foregroundStyle(UZColor.label2)
            }
        }
    }

    @ViewBuilder
    private func content(range: (start: LocalDate, end: LocalDate), totals: (income: Money, spending: Money), net: Money) -> some View {
        HStack(spacing: UZSpacing.l) {
            kpi("Income", totals.income, color: UZColor.positive)
            kpi("Spending", totals.spending, color: UZColor.label)
            kpi("Net", net, color: net.isZero ? UZColor.label : net.isNegative ? UZColor.negative : UZColor.positive, signed: true)
        }
        .accessibilityIdentifier("reports.kpis")
        categories(range)
        incomeVsSpending
        budgetKept
        commitments
        people
        accounts
        Text("Your shares only · transfers excluded" + (session.ledger.footnote.map { " · " + $0 } ?? ""))
            .font(.caption).foregroundStyle(UZColor.label2)
    }

    /// The report as an A4 PDF (RPT, M8): the same cards as on screen, in light mode, split across pages.
    private func exportPDF(range: (start: LocalDate, end: LocalDate), totals: (income: Money, spending: Money), net: Money) {
        let page = CGSize(width: 595, height: 842), margin: CGFloat = 32
        let printable = VStack(alignment: .leading, spacing: UZSpacing.xl) {
            HStack {
                UZeeLogo(size: 36, tile: true)
                VStack(alignment: .leading) {
                    Text("UZee report · \(choice.rawValue)").font(.title3.bold())
                    Text("Made \(Date().formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(UZColor.label2)
                }
            }
            content(range: range, totals: totals, net: net)
        }
        .padding(margin)
        .frame(width: page.width, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: printable)
        renderer.proposedSize = ProposedViewSize(width: page.width, height: nil)
        let name = "UZee report \(DatePresets.text(from: range.start, through: range.end)).pdf".replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var box = CGRect(origin: .zero, size: page)
        renderer.render { size, draw in
            guard let file = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            let pages = max(1, Int((size.height / page.height).rounded(.up)))
            for index in 0..<pages {
                file.beginPDFPage(nil)
                // PDF space starts bottom-left: shift so page `index` of the tall view is in the box.
                file.translateBy(x: 0, y: page.height - size.height + CGFloat(index) * page.height)
                draw(file)
                file.endPDFPage()
            }
            file.closePDF()
        }
        pdf = SharedFile(url: url)
    }

    private func kpi(_ title: String, _ money: Money, color: Color, signed: Bool = false) -> some View {
        UZCard(padding: UZSpacing.l) {
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(UZColor.label2)
                Text(MoneyFormatter.string(money, sign: signed ? .always : .negativeOnly))
                    .font(.headline).monospacedDigit().foregroundStyle(color)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Categories

    @ViewBuilder
    private func categories(_ range: (start: LocalDate, end: LocalDate)) -> some View {
        let shares = ReportCalculator.byGroup(session.transactions, from: range.start, through: range.end,
                                              categories: session.ledger.categories, base: base, rates: rates)
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Spending by category")
                Text("your shares").font(.subheadline).foregroundStyle(UZColor.label2).fixedSize()
            }
            UZCard {
                if shares.isEmpty {
                    Text("No spending in this period.").foregroundStyle(UZColor.label2)
                } else {
                    VStack(spacing: UZSpacing.l) {
                        Chart(shares) { share in
                            SectorMark(angle: .value("Amount", Double(share.amount.minorUnits)), innerRadius: .ratio(0.6), angularInset: 1.5)
                                .foregroundStyle(color(share.categoryID))
                        }
                        .frame(height: 180)
                        .accessibilityHidden(true)
                        ForEach(shares) { share in
                            // Tap a category to see its transactions in this period (owner, 2026-10-15).
                            Button {
                                session.openActivity(categoryID: share.categoryID, from: range.start, through: range.end)
                            } label: {
                                HStack(spacing: UZSpacing.m) {
                                    Circle().fill(color(share.categoryID)).frame(width: 10, height: 10)
                                    Text(session.ledger.category(share.categoryID)?.name ?? "Other").foregroundStyle(UZColor.label)
                                    Spacer()
                                    Text(MoneyFormatter.string(share.amount)).monospacedDigit().foregroundStyle(UZColor.label)
                                    Text("\(share.percent)%").foregroundStyle(UZColor.label2).monospacedDigit().frame(width: 44, alignment: .trailing)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(UZColor.label3)
                                }
                                .font(.subheadline)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("reports.category.\(session.ledger.category(share.categoryID)?.name ?? "Other")")
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("reports.categories")
        }
    }

    private func color(_ id: UUID) -> Color {
        session.ledger.category(id).map { CategoryStyle($0.group).color } ?? UZColor.label3
    }

    // MARK: Six months

    private var incomeVsSpending: some View {
        let months = ReportCalculator.cashFlow(session.transactions, from: today.firstOfMonth.addingMonths(-5),
                                               through: today.firstOfMonth, base: base, rates: rates)
        let scale = Double(Money.scale(base.minorUnits)) * 1_000
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Money in vs out")
                Text("\(base.code), thousands").font(.subheadline).foregroundStyle(UZColor.label2).fixedSize()
            }
            UZCard {
                Chart {
                    ForEach(months) { month in
                        let label = month.month.startDate(in: .current).formatted(.dateTime.month(.abbreviated))
                        BarMark(x: .value("Month", label), y: .value("Amount", Double(month.income.minorUnits) / scale))
                            .foregroundStyle(by: .value("Type", "In"))
                            .position(by: .value("Type", "In"))
                        BarMark(x: .value("Month", label), y: .value("Amount", Double(month.spending.minorUnits) / scale))
                            .foregroundStyle(by: .value("Type", "Out"))
                            .position(by: .value("Type", "Out"))
                    }
                }
                .chartForegroundStyleScale(["In": UZColor.positive, "Out": Color(uiColor: .systemOrange)])
                .frame(height: 200)
                .accessibilityLabel(months.map {
                    "\($0.month.startDate(in: .current).formatted(.dateTime.month(.wide))): income \(MoneyFormatter.string($0.income)), spending \(MoneyFormatter.string($0.spending))"
                }.joined(separator: ". "))
            }
            .accessibilityIdentifier("reports.months")
            Text("Everything that came into and went out of your accounts, including loans and the full amount of splits. Moves between your own accounts aren't counted.")
                .font(.footnote).foregroundStyle(UZColor.label2)
        }
    }

    // MARK: Budget kept

    @ViewBuilder
    private var budgetKept: some View {
        let budget = BudgetModel(session: session)
        let history = budget.history(count: 6, before: budget.current).reversed()
        if !history.isEmpty {
            let kept = history.filter { !$0.isOver }.count
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Budget kept")
                    Text("\(kept) of \(history.count) months").font(.subheadline).foregroundStyle(UZColor.label2).fixedSize()
                }
                UZCard {
                    HStack {
                        ForEach(Array(history), id: \.period.start) { summary in
                            VStack(spacing: UZSpacing.xs) {
                                Image(systemName: summary.isOver ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.title3).foregroundStyle(summary.isOver ? UZColor.warning : UZColor.positive)
                                Text(summary.period.start.startDate(in: .current).formatted(.dateTime.month(.abbreviated)))
                                    .font(.caption2).foregroundStyle(UZColor.label2)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(summary.period.start.startDate(in: .current).formatted(.dateTime.month(.wide))) \(summary.isOver ? "over budget" : "within budget")")
                        }
                    }
                }
                .accessibilityIdentifier("reports.budgetKept")
            }
        }
    }

    // MARK: Subscriptions and plans

    @ViewBuilder
    private var commitments: some View {
        let model = RecurringModel(session: session)
        let subscriptions = model.active.filter { model.isSubscription($0) && $0.groupID == nil }
        if !subscriptions.isEmpty {
            let monthly = model.monthlyTotal(subscriptions)
            NavigationLink(value: Route.bills) {
                UZCard(padding: UZSpacing.l) {
                    HStack {
                        VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                            Text("Subscriptions").font(.subheadline.weight(.semibold))
                            Text("\(subscriptions.count) active · \(MoneyFormatter.string(model.yearly(fromMonthly: monthly))) / year")
                                .font(.caption).foregroundStyle(UZColor.label2)
                        }
                        Spacer()
                        Text("\(MoneyFormatter.string(monthly)) /mo").font(.headline).monospacedDigit()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(UZColor.label3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reports.subscriptions")
        }
    }

    // MARK: People and accounts

    @ViewBuilder
    private var people: some View {
        let overall = session.balances.overall
        let rows = session.people.others.map { ($0, session.balances.net(of: $0.id)) }.filter { !$0.1.isZero }
            .sorted { $0.1.minorUnits.magnitudeClamped > $1.1.minorUnits.magnitudeClamped }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: UZSpacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("People balances")
                    Text("as of today").font(.subheadline).foregroundStyle(UZColor.label2).fixedSize()
                }
                UZCard {
                    VStack(spacing: UZSpacing.m) {
                        LabeledContent("Owed to you", value: MoneyFormatter.string(overall.owedToYou))
                        LabeledContent("You owe", value: MoneyFormatter.string(overall.youOwe))
                        Divider()
                        ForEach(rows.indices, id: \.self) { index in
                            let (person, net) = rows[index]
                            NavigationLink(value: Route.person(person.id)) {
                                HStack {
                                    PersonAvatar(name: person.name, size: 28)
                                    Text(person.name).foregroundStyle(UZColor.label)
                                    Spacer()
                                    Text(net.isNegative ? "you owe \(MoneyFormatter.string(Money(minorUnits: net.minorUnits.magnitudeClamped, currency: net.currency)))"
                                                        : "owes you \(MoneyFormatter.string(net))")
                                        .font(.subheadline).foregroundStyle(net.isNegative ? UZColor.negative : UZColor.positive)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .accessibilityIdentifier("reports.people")
            }
        }
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Account balances")
            UZCard {
                VStack(spacing: UZSpacing.m) {
                    ForEach(session.ledger.activeAccounts) { account in
                        let balance = session.ledger.balance(of: account)
                        HStack {
                            Text(account.name)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(MoneyFormatter.string(balance)).monospacedDigit()
                                if balance.currency != base {
                                    Text(MoneyFormatter.approximate(balance, in: base, rate: session.ledger.rate(for: balance.currency)))
                                        .font(.caption).foregroundStyle(UZColor.label2)
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                    Divider()
                    HStack {
                        Text("Total today").fontWeight(.semibold)
                        Spacer()
                        Text(MoneyFormatter.string(session.ledger.available)).fontWeight(.semibold).monospacedDigit()
                    }
                }
            }
            .accessibilityIdentifier("reports.accounts")
        }
    }
}

/// A file to hand to the share sheet.
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet (Save to Files, AirDrop, Mail, Print).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Any start and end for Reports, both days included.
struct ReportDatesSheet: View {
    let onUse: (LocalDate, LocalDate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(start: LocalDate, end: LocalDate, onUse: @escaping (LocalDate, LocalDate) -> Void) {
        self.onUse = onUse
        _start = State(initialValue: start.startDate(in: .current))
        _end = State(initialValue: end.startDate(in: .current))
    }

    private var startDay: LocalDate { LocalDate(start, in: .current) }
    private var endDay: LocalDate { LocalDate(end, in: .current) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("From", selection: $start, displayedComponents: .date).accessibilityIdentifier("reportDates.from")
                    DatePicker("To", selection: $end, displayedComponents: .date).accessibilityIdentifier("reportDates.to")
                } footer: {
                    if startDay > endDay {
                        Text("The end date is before the start date.").foregroundStyle(UZColor.negative)
                    } else {
                        let days = startDay.days(to: endDay) + 1
                        Text("\(days) \(days == 1 ? "day" : "days"), both dates included. Income, spending, where it went and the PDF all use these dates.")
                    }
                }
            }
            .navigationTitle("Report dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onUse(startDay, endDay)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(startDay > endDay)
                    .accessibilityIdentifier("reportDates.use")
                }
            }
        }
    }
}
