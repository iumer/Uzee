import SwiftUI
import UZeeCore

/// Short date words used across Bills and Calendar.
enum DateText {
    /// "Mon 5 Oct".
    static func short(_ date: LocalDate) -> String {
        date.startDate(in: .current).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "5 Oct 2026".
    static func long(_ date: LocalDate) -> String {
        date.startDate(in: .current).formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "Jul 2028".
    static func monthYear(_ date: LocalDate) -> String {
        date.startDate(in: .current).formatted(.dateTime.month(.abbreviated).year())
    }

    /// "Today", "Tomorrow", "in 3 days", "2 days late".
    static func relative(_ date: LocalDate, today: LocalDate) -> String {
        let days = today.days(to: date)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let n where n > 1: return "in \(n) days"
        default: return "\(-days) days late"
        }
    }

    /// "12th".
    static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}

/// One item's occurrence, for lists.
struct DueItem: Identifiable {
    let item: RecurringItem
    let occurrence: Occurrence
    var id: String { occurrence.id }
}

/// One slice of the monthly mix.
struct MixPart: Identifiable {
    let bucket: RecurringModel.Bucket
    let amount: Money
    var id: RecurringModel.Bucket { bucket }
}

/// Recurring figures for the Bills hub, detail screens, Calendar and Home, read fresh from the session.
@MainActor
struct RecurringModel {
    let session: AppSession
    var today: LocalDate { session.today }
    var snapshot: RecurringSnapshot { session.recurring }
    var base: Currency { session.ledger.base }

    var active: [RecurringItem] { snapshot.items.filter(\.isActive) }

    func records(_ item: RecurringItem) -> [OccurrenceRecord] { snapshot.records(for: item.id) }

    func next(_ item: RecurringItem) -> Occurrence? { snapshot.next(item, today: today) }

    /// Group members split a group bill equally, so my share is the amount ÷ members.
    func divisor(_ item: RecurringItem) -> Int64 {
        guard let group = session.people.group(item.groupID) else { return 1 }
        return Int64(max(1, group.memberIDs.count))
    }

    /// My share of one amount in its own currency.
    func myShare(_ item: RecurringItem, _ amount: Money) -> Money {
        let divisor = divisor(item)
        guard divisor > 1 else { return amount }
        let value = amount.decimalValue / Decimal(divisor)
        return (try? Money.fromMajor(value, amount.currency)) ?? amount
    }

    /// My share converted to base.
    func baseShare(_ item: RecurringItem, _ amount: Money) -> Money {
        let share = myShare(item, amount)
        return (try? RateTable.toBase(share, base: base, rates: session.ledger.rates)) ?? .zero(base)
    }

    func monthly(_ item: RecurringItem) -> Money {
        RecurringTotals.monthly(item, myShareDivisor: divisor(item), base: base, rates: session.ledger.rates)
    }

    /// Sum of monthly equivalents in base.
    func monthlyTotal(_ items: [RecurringItem]) -> Money {
        (try? Money.sum(items.map(monthly), in: base)) ?? .zero(base)
    }

    /// A year at the rounded monthly figure, so "Rs 14,065 / month" reads "Rs 168,780 / year".
    func yearly(fromMonthly monthly: Money) -> Money {
        let scale = Money.scale(monthly.currency.minorUnits)
        let whole = (monthly.minorUnits + scale / 2) / scale
        return Money(major: whole * 12, monthly.currency)
    }

    /// Spending items (not income) still active.
    var spendingItems: [RecurringItem] { active.filter { !$0.type.isIncome } }

    /// Which bucket of the monthly mix an item falls in (Bills hub mix bar).
    enum Bucket: Hashable {
        case group(UUID), plans, subscriptions, bills
    }

    func bucket(_ item: RecurringItem) -> Bucket {
        if let group = item.groupID, session.people.group(group) != nil { return .group(group) }
        if item.type.isPlan { return .plans }
        if item.type == .subscription { return .subscriptions }
        return .bills
    }

    func bucketName(_ bucket: Bucket) -> String {
        switch bucket {
        case .group(let id): "\(session.people.group(id)?.name ?? "Group") group (your share)"
        case .plans: "Plans"
        case .subscriptions: "Subscriptions"
        case .bills: "Bills"
        }
    }

    func bucketColor(_ bucket: Bucket) -> Color {
        switch bucket {
        case .group: Color(hex: "#5856D6")
        case .plans: Color(hex: "#00C7BE")
        case .subscriptions: Color(hex: "#FF2D55")
        case .bills: Color(hex: "#FFCC00")
        }
    }

    /// The monthly mix, largest first.
    var mix: [MixPart] {
        var totals: [Bucket: Money] = [:]
        for item in spendingItems {
            let value = monthly(item)
            totals[bucket(item)] = (try? (totals[bucket(item)] ?? .zero(base)).adding(value)) ?? value
        }
        return totals.map { MixPart(bucket: $0.key, amount: $0.value) }.sorted { $0.amount.minorUnits > $1.amount.minorUnits }
    }

    /// Next occurrence of every active item, soonest first (overdue first).
    var nextOccurrences: [DueItem] {
        active.compactMap { item in next(item).map { DueItem(item: item, occurrence: $0) } }.sorted(by: Self.order)
    }

    /// Every unresolved occurrence due in a range, plus overdue ones when the range starts today or earlier.
    func due(from start: LocalDate, through end: LocalDate, includeOverdue: Bool = false) -> [DueItem] {
        var rows: [DueItem] = []
        for item in active {
            for occurrence in OccurrenceGenerator.occurrences(item, records: records(item), from: start, through: end, today: today,
                                                              includeOverdue: includeOverdue) {
                rows.append(DueItem(item: item, occurrence: occurrence))
            }
        }
        return rows.sorted(by: Self.order)
    }

    static func order(_ a: DueItem, _ b: DueItem) -> Bool {
        a.occurrence.dueDate != b.occurrence.dueDate ? a.occurrence.dueDate < b.occurrence.dueDate : a.item.name < b.item.name
    }

    /// The next salary or income date, for "Due before salary".
    var nextSalary: Occurrence? {
        active.filter { $0.type == .salary }.compactMap { next($0) }.min { $0.dueDate < $1.dueDate }
    }

    /// Sum of my shares in base for these occurrences.
    func total(_ rows: [DueItem]) -> Money {
        (try? Money.sum(rows.map { baseShare($0.item, $0.occurrence.amount) }, in: base)) ?? .zero(base)
    }

    /// "12th · HBL" style meta line.
    func meta(_ item: RecurringItem) -> String {
        var parts: [String] = []
        switch item.rule.unit {
        case .month where item.rule.interval == 1: parts.append(DateText.ordinal(item.rule.anchor.day))
        default: parts.append(item.rule.text)
        }
        if let payer = item.paidByID, payer != session.people.selfID, let name = session.people.person(payer)?.name {
            parts.append("\(name) pays")
        } else if let account = session.ledger.account(item.accountID) {
            parts.append(account.name)
        }
        return parts.joined(separator: " · ")
    }

    func badge(_ state: OccurrenceState) -> StatusBadge.Status {
        switch state {
        case .paid: .paid
        case .skipped: .skipped
        case .overdue: .overdue
        case .dueToday: .dueToday
        case .upcoming: .dueSoon
        }
    }
}

/// Monogram tile in the item's colour; UZee never uses brand logos.
struct RecurringTile: View {
    let item: RecurringItem
    var size: CGFloat = 36

    var body: some View {
        Text(monogram)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: item.colorHex).gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    private var monogram: String {
        switch item.type {
        case .kameti: return "◆"
        default:
            let letters = item.name.split(separator: " ").prefix(1).compactMap(\.first)
            return letters.isEmpty ? "?" : String(letters).uppercased()
        }
    }
}

/// One recurring item in a list: tile, name, meta, amount, and the next due state.
struct RecurringRow: View {
    let model: RecurringModel
    let item: RecurringItem
    var occurrence: Occurrence?
    var showsDate = false

    var body: some View {
        let amount = occurrence?.amount ?? item.amount
        HStack(spacing: UZSpacing.l) {
            RecurringTile(item: item)
            VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                Text(item.name).font(.body).foregroundStyle(UZColor.label).lineLimit(1)
                Text(metaLine).font(.footnote).foregroundStyle(UZColor.label2).lineLimit(1)
            }
            Spacer(minLength: UZSpacing.m)
            VStack(alignment: .trailing, spacing: UZSpacing.xxs) {
                Text((item.isEstimated ? "~" : "") + MoneyFormatter.string(amount))
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(item.type.isIncome ? UZColor.positive : UZColor.label)
                if let line = secondLine(amount) {
                    Text(line).font(.caption).foregroundStyle(UZColor.label2).monospacedDigit()
                }
                if let occurrence, occurrence.state == .overdue || occurrence.state == .dueToday {
                    StatusBadge(model.badge(occurrence.state))
                } else if !item.isActive {
                    StatusBadge(item.status == .paused ? .paused : .cancelled)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var metaLine: String {
        guard let occurrence, showsDate else {
            if !item.isActive, let changed = item.statusChangedAt {
                return "\(item.status.name) in \(DateText.monthYear(changed))"
            }
            return model.meta(item)
        }
        var parts = [DateText.short(occurrence.dueDate)]
        if item.type == .installment || item.type == .kameti, let total = item.rule.limit {
            parts.append("\(occurrence.sequence) of \(total)")
        } else {
            parts.append(model.meta(item))
        }
        return parts.joined(separator: " · ")
    }

    private func secondLine(_ amount: Money) -> String? {
        if model.divisor(item) > 1 {
            return "your share \(MoneyFormatter.string(model.myShare(item, amount)))"
        }
        if amount.currency != model.base {
            return MoneyFormatter.approximate(amount, in: model.base, rate: model.session.ledger.rate(for: amount.currency))
        }
        return nil
    }
}
