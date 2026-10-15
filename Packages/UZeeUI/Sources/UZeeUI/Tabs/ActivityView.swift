import SwiftUI
import UZeeCore

/// Activity (SCR-08): every transaction by day with the day's spending (my share), search and filters (M3).
struct ActivityView: View {
    @Bindable var session: AppSession
    @State private var showingRange = false
    /// Imported rows that look like moves between your accounts, still to review (owner, 2026-10-14).
    @State private var toReview = 0

    var body: some View {
        let shown = session.activityDays()
        List {
            if toReview > 0 {
                Section {
                    NavigationLink {
                        OwnTransfersView(session: session)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                                Text(toReview == 1 ? "1 to review" : "\(toReview) to review").font(.body.weight(.semibold))
                                Text("Imported rows that look like moves between your accounts or ATM cash")
                                    .font(.caption).foregroundStyle(UZColor.label2)
                            }
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right.circle.fill").foregroundStyle(UZColor.tint)
                        }
                    }
                    .accessibilityIdentifier("activity.toReview")
                }
            }
            if session.activityFilter.count > 0 {
                Section {
                    Button("Clear filters", systemImage: "xmark.circle") { clearFilters() }
                        .accessibilityIdentifier("activity.clearFilters")
                } footer: {
                    Text(filterSummary).accessibilityIdentifier("activity.filterSummary")
                }
            }
            ForEach(shown.days) { day in
                Section {
                    ForEach(day.transactions) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(transaction: transaction, ledger: session.ledger,
                                           hasReceipt: session.withReceipts.contains(transaction.id))
                        }
                    }
                } header: {
                    HStack {
                        Text(day.date.listTitle(today: today))
                        Spacer()
                        if !day.spending.isZero {
                            Text("spent \(MoneyFormatter.string(day.spending))").monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("day.\(day.date)")
                }
            }
        }
        .overlay { emptyState(hasRows: shown.hasRows) }
        .searchable(text: $session.activityFilter.text, prompt: "Payee, note or amount")
        .navigationTitle("Activity")
        .toolbar {
            // Top right is the profile icon on every tab, so this screen's buttons sit on the left.
            ToolbarItem(placement: .topBarLeading) {
                Button { session.openAdd(.transfer) } label: { Image(systemName: "arrow.left.arrow.right") }
                    .accessibilityLabel("New transfer")
                    .accessibilityIdentifier("activity.transfer")
            }
            ToolbarItem(placement: .topBarLeading) { filterMenu }
        }
        .sheet(isPresented: $showingRange) {
            DateRangeSheet(filter: $session.activityFilter)
        }
        // Worked out off the main thread, once per change: opening Activity and coming back from a row used to
        // redo the whole match each time and the screen hung (owner, 2026-10-15).
        .task(id: session.budgetRevision) { toReview = await session.ownMoneyReviewInBackground().count }
    }

    // MARK: Empty and no-result states (TXN-028)

    @ViewBuilder private func emptyState(hasRows: Bool) -> some View {
        if session.transactions.isEmpty {
            EmptyStateView("No transactions yet", systemImage: "list.bullet.rectangle",
                           description: "Everything you spend, earn and transfer will be listed here by day.",
                           actionTitle: "Add") { session.openAdd(.new) }
                // .contain keeps child identifiers visible to UI tests.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity.empty")
        } else if !hasRows {
            EmptyStateView(noResultsTitle, systemImage: "magnifyingglass",
                           description: "Try another word or amount, or clear the filters.",
                           actionTitle: "Clear filters") { clearFilters() }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity.noResults")
        }
    }

    private var noResultsTitle: String {
        let text = session.activityFilter.text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "No matching transactions" : "No results for \u{201C}\(text)\u{201D}"
    }

    private func clearFilters() {
        session.activityFilter = ActivityFilter()
    }

    // MARK: Filters (pull-down menu, DESIGN_SYSTEM §9)

    private var filterMenu: some View {
        Menu {
            Menu("Account") {
                ForEach(session.ledger.accounts) { account in
                    Toggle(account.name, isOn: member(account.id, in: \.accountIDs))
                }
            }
            Menu("Category") {
                ForEach(session.ledger.categories.filter { $0.parentID == nil && $0.type != .system }) { category in
                    Toggle(category.type == .income ? "Income · \(category.name)" : category.name,
                           isOn: member(category.id, in: \.categoryIDs))
                }
            }
            Menu("Type") {
                ForEach(Self.kindChoices, id: \.self) { kind in
                    Toggle(kind.name, isOn: member(kind, in: \.kinds))
                }
            }
            if !session.tags.isEmpty {
                Menu("Tag") {
                    ForEach(session.tags) { tag in
                        Toggle(tag.name, isOn: member(tag.id, in: \.tagIDs))
                    }
                }
            }
            Menu("Date") {
                Button("This month") { setRange(DatePresets.thisMonth(today)) }
                Button("Last month") { setRange(DatePresets.lastMonth(today)) }
                Button("Last 7 days") { setRange(DatePresets.lastDays(7, today)) }
                Button("Choose dates…") { showingRange = true }
                Button("Any date") { setRange(nil) }
            }
            if session.activityFilter.count > 0 {
                Button("Clear filters", role: .destructive) { clearFilters() }
            }
            Divider()
            // A plain button: a NavigationLink inside a Menu often doesn't navigate.
            Button {
                session.path(for: .activity).wrappedValue.append(.recentlyDeleted)
            } label: {
                Label("Recently Deleted", systemImage: "trash")
            }
        } label: {
            Image(systemName: session.activityFilter.count > 0
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(session.activityFilter.count > 0 ? "Filters, \(session.activityFilter.count) on" : "Filters")
        .accessibilityIdentifier("activity.filter")
    }

    static let kindChoices: [TransactionKind] = [.expense, .income, .transfer, .refund, .adjustment, .loanOut, .loanIn]

    private func member<T: Hashable>(_ value: T, in keyPath: WritableKeyPath<ActivityFilter, Set<T>>) -> Binding<Bool> {
        Binding(
            get: { session.activityFilter[keyPath: keyPath].contains(value) },
            set: { on in
                if on { session.activityFilter[keyPath: keyPath].insert(value) } else { session.activityFilter[keyPath: keyPath].remove(value) }
            }
        )
    }

    private func setRange(_ range: ClosedRange<LocalDate>?) {
        session.activityFilter.from = range?.lowerBound
        session.activityFilter.through = range?.upperBound
    }

    /// "HBL · Food · 1–31 Oct", read under Clear filters.
    private var filterSummary: String {
        let filter = session.activityFilter
        var parts: [String] = []
        parts += session.ledger.accounts.filter { filter.accountIDs.contains($0.id) }.map(\.name)
        parts += session.ledger.categories.filter { filter.categoryIDs.contains($0.id) }.map(\.name)
        parts += Self.kindChoices.filter { filter.kinds.contains($0) }.map(\.name)
        parts += session.tags.filter { filter.tagIDs.contains($0.id) }.map { "#" + $0.name }
        if filter.from != nil || filter.through != nil {
            parts.append(DatePresets.text(from: filter.from, through: filter.through))
        }
        return parts.joined(separator: " · ")
    }

    private var today: LocalDate { LocalDate(Date(), in: .current) }
}

extension AppSession {
    /// Activity's days for the current filter, kept until the data or the filter changes.
    func activityDays() -> (hasRows: Bool, days: [ActivityDay]) {
        let filter = activityFilter
        if let cache = activityCache, cache.revision == budgetRevision, cache.filter == filter { return (cache.hasRows, cache.days) }
        let rows = ActivityQuery.filter(transactions, filter, snapshot: ledger, tags: tagMap)
        let days = ActivityQuery.days(rows, snapshot: ledger)
        activityCache = (budgetRevision, filter, !rows.isEmpty, days)
        return (!rows.isEmpty, days)
    }
}

/// Date presets for the Activity filter, in the phone's calendar.
enum DatePresets {
    static func thisMonth(_ today: LocalDate) -> ClosedRange<LocalDate> {
        LocalDate(year: today.year, month: today.month, day: 1)...LocalDate(year: today.year, month: today.month, day: days(in: today))
    }

    static func lastMonth(_ today: LocalDate) -> ClosedRange<LocalDate> {
        let month = today.month == 1 ? 12 : today.month - 1
        let year = today.month == 1 ? today.year - 1 : today.year
        let first = LocalDate(year: year, month: month, day: 1)
        return first...LocalDate(year: year, month: month, day: days(in: first))
    }

    static func lastDays(_ count: Int, _ today: LocalDate) -> ClosedRange<LocalDate> {
        let start = Calendar.current.date(byAdding: .day, value: -(count - 1), to: today.startDate(in: .current)) ?? Date()
        return LocalDate(start, in: .current)...today
    }

    static func days(in date: LocalDate) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date.startDate(in: .current))?.count ?? 30
    }

    static func text(from: LocalDate?, through: LocalDate?) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let start = from.map { $0.startDate(in: .current).formatted(format) }
        let end = through.map { $0.startDate(in: .current).formatted(format) }
        switch (start, end) {
        case let (start?, end?): return start == end ? start : "\(start) – \(end)"
        case let (start?, nil): return "From \(start)"
        case let (nil, end?): return "Until \(end)"
        default: return ""
        }
    }
}

/// "Choose dates…": a from and to day for the Activity filter.
struct DateRangeSheet: View {
    @Binding var filter: ActivityFilter
    @State private var from = Date()
    @State private var through = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, displayedComponents: .date)
                    .accessibilityIdentifier("range.from")
                DatePicker("To", selection: $through, in: from..., displayedComponents: .date)
                    .accessibilityIdentifier("range.to")
            }
            .navigationTitle("Choose dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter.from = LocalDate(from, in: .current)
                        filter.through = LocalDate(max(from, through), in: .current)
                        dismiss()
                    }
                    .accessibilityIdentifier("range.apply")
                }
            }
            .onAppear {
                if let start = filter.from { from = start.startDate(in: .current) }
                if let end = filter.through { through = end.startDate(in: .current) }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Recently Deleted (DATA-010…014): tap an item to restore it or delete it for good; kept 30 days.
struct RecentlyDeletedView: View {
    @Bindable var session: AppSession
    @State private var rows: [MoneyTransaction] = []
    @State private var selected: MoneyTransaction?
    @State private var confirmPurgeAll = false

    var body: some View {
        List {
            Section {
                ForEach(rows) { transaction in
                    Button { selected = transaction } label: {
                        VStack(alignment: .leading, spacing: UZSpacing.xs) {
                            TransactionRow(transaction: transaction, ledger: session.ledger)
                            if let deletedAt = transaction.deletedAt {
                                Text(daysLeftText(deletedAt)).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                        }
                    }
                    .foregroundStyle(UZColor.label)
                    .accessibilityIdentifier("deleted.\(transaction.payeeName ?? transaction.kind.name)")
                    .swipeActions(edge: .leading) {
                        Button("Restore") { restore(transaction) }.tint(UZColor.tint)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete") { selected = transaction }.tint(UZColor.negative)
                    }
                }
            } footer: {
                if !rows.isEmpty {
                    Text("Items are removed for good 30 days after you delete them. They don't count in balances or totals.")
                }
            }
        }
        .overlay {
            if rows.isEmpty {
                EmptyStateView("Nothing deleted", systemImage: "trash",
                               description: "Transactions you delete stay here for 30 days so you can bring them back.")
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("deleted.empty")
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !rows.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete All", role: .destructive) { confirmPurgeAll = true }
                        .accessibilityIdentifier("deleted.purgeAll")
                }
            }
        }
        .onAppear(perform: load)
        .confirmationDialog(selected?.payeeName ?? "Deleted transaction", isPresented: selectedBinding,
                            titleVisibility: .visible, presenting: selected) { transaction in
            Button("Restore") { restore(transaction) }
                .accessibilityIdentifier("deleted.restore")
            Button("Delete for good", role: .destructive) { purge([transaction.id]) }
                .accessibilityIdentifier("deleted.purge")
        } message: { _ in
            Text("Restore puts it back in your lists and balances. Deleting for good can't be undone.")
        }
        .confirmationDialog("Delete all \(rows.count) for good?", isPresented: $confirmPurgeAll, titleVisibility: .visible) {
            Button("Delete all for good", role: .destructive) { purge(rows.map(\.id)) }
        } message: {
            Text("This can't be undone. Attached receipts are deleted too.")
        }
    }

    private var selectedBinding: Binding<Bool> {
        Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
    }

    private func daysLeftText(_ deletedAt: Date) -> String {
        let left = RecentlyDeleted.daysLeft(deletedAt: deletedAt, now: Date())
        return left == 1 ? "1 day left" : "\(left) days left"
    }

    private func load() {
        rows = (try? session.activity.deletedTransactions()) ?? []
    }

    private func restore(_ transaction: MoneyTransaction) {
        session.restore(transaction.id)
        load()
    }

    private func purge(_ ids: [UUID]) {
        if session.perform("Couldn't delete. Try again.", { try session.activity.purge(ids) }) {
            session.toasts.show(ids.count == 1 ? "Deleted for good" : "All deleted for good")
        }
        load()
    }
}
