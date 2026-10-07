import Foundation
import UZeeCore

/// Answers questions from local data (VOX-03) with the same models the screens use, so voice and screens agree.
@MainActor
struct VoiceAnswerer {
    let session: AppSession

    private var today: LocalDate { session.today }
    private var base: Currency { session.ledger.base }

    func answer(_ question: VoiceQuestion) -> String {
        switch question {
        case .iOwe(let name): return owe(name, iOwe: true)
        case .owesMe(let name): return owe(name, iOwe: false)
        case .budgetLeft: return budgetLeft()
        case .spent(let category, let period): return spent(category, period)
        case .nextBill: return nextBill()
        case .subscriptions: return subscriptions()
        case .balance(let account): return balance(account)
        case .dueBeforeSalary: return dueBeforeSalary()
        case .upcoming: return upcoming()
        }
    }

    private func money(_ amount: Money) -> String {
        MoneyFormatter.string(Money(minorUnits: amount.minorUnits.magnitudeClamped, currency: amount.currency))
    }

    func person(named name: String) -> Person? {
        let key = NameKey.make(name)
        return session.people.others.first { NameKey.make($0.name) == key }
            ?? session.people.others.first { NameKey.make($0.name).hasPrefix(key) || key.hasPrefix(NameKey.make($0.name)) }
    }

    // MARK: People

    private func owe(_ name: String?, iOwe: Bool) -> String {
        if let name {
            guard let person = person(named: name) else { return "I couldn't find \(name) in People." }
            let net = session.balances.net(of: person.id)
            if net.isZero { return "You and \(person.name) are settled." }
            if net.isNegative {
                return iOwe ? "You owe \(person.name) \(money(net))." : "\(person.name) doesn't owe you. You owe \(person.name) \(money(net))."
            }
            return iOwe ? "You don't owe \(person.name). \(person.name) owes you \(money(net))." : "\(person.name) owes you \(money(net))."
        }
        let overall = session.balances.overall
        let total = iOwe ? overall.youOwe : overall.owedToYou
        guard !total.isZero else { return iOwe ? "You don't owe anyone." : "Nobody owes you anything." }
        let names = session.people.others
            .map { ($0.name, session.balances.net(of: $0.id)) }
            .filter { iOwe ? $0.1.isNegative : ($0.1.minorUnits > 0) }
            .sorted { $0.1.minorUnits.magnitudeClamped > $1.1.minorUnits.magnitudeClamped }
            .prefix(3)
            .map { "\($0.0) \(money($0.1))" }
        let start = iOwe ? "You owe \(money(total)) in total" : "People owe you \(money(total)) in total"
        return names.isEmpty ? start + "." : start + ": " + ListFormatter.localizedString(byJoining: names) + "."
    }

    // MARK: Budget and spending

    private func budgetLeft() -> String {
        let budget = BudgetModel(session: session)
        guard let summary = budget.summary(for: budget.current) else { return "You haven't set a budget for this month yet." }
        if summary.isOver { return "You're over budget by \(money(summary.left)) for \(BudgetModel.title(budget.current))." }
        return "You have \(money(summary.left)) left of \(money(summary.total)) for \(BudgetModel.title(budget.current))."
    }

    private func range(_ period: VoicePeriod) -> (LocalDate, LocalDate) {
        switch period {
        case .today: return (today, today)
        case .thisWeek:
            let offset = (today.weekday - Calendar.current.firstWeekday + 7) % 7
            return (today.addingDays(-offset), today)
        case .thisMonth: return (today.firstOfMonth, today)
        case .lastMonth: return (today.firstOfMonth.addingMonths(-1), today.firstOfMonth.addingDays(-1))
        }
    }

    private func spent(_ categoryName: String?, _ period: VoicePeriod) -> String {
        let (start, end) = range(period)
        var transactions = session.transactions
        var label = ""
        if let categoryName {
            let key = NameKey.make(categoryName)
            guard let category = session.ledger.categories.first(where: { NameKey.make($0.name) == key && $0.type == .expense }) else {
                return "I couldn't find a category called \(categoryName)."
            }
            let ids = Set([category.id] + session.ledger.categories.filter { $0.parentID == category.id }.map(\.id))
            transactions = transactions.filter { transaction in transaction.categoryID.map { ids.contains($0) } ?? false }
            label = " on \(category.name)"
        }
        let totals = ReportCalculator.totals(transactions, from: start, through: end, base: base, rates: session.ledger.rates)
        return "You spent \(money(totals.spending))\(label) \(period.name). Only your shares count."
    }

    // MARK: Bills

    private func nextBill() -> String {
        let model = RecurringModel(session: session)
        let rows = model.due(from: today, through: today.addingDays(62), includeOverdue: true).filter { !$0.item.type.isIncome }
        let overdue = rows.filter { $0.occurrence.dueDate < today }
        var parts: [String] = []
        if let next = rows.first(where: { $0.occurrence.dueDate >= today }) {
            let date = next.occurrence.dueDate.startDate(in: .current).formatted(.dateTime.weekday(.wide).day().month(.wide))
            parts.append("\(next.item.name), \(money(model.baseShare(next.item, next.occurrence.amount))), \(date).")
        } else {
            parts.append("Nothing is due in the next two months.")
        }
        if let first = overdue.first {
            parts.append(overdue.count == 1 ? "\(first.item.name) is overdue." : "\(overdue.count) bills are overdue, starting with \(first.item.name).")
        }
        return parts.joined(separator: " ")
    }

    private func subscriptions() -> String {
        let model = RecurringModel(session: session)
        let items = model.active.filter { $0.type == .subscription && $0.groupID == nil }
        guard !items.isEmpty else { return "You have no active subscriptions." }
        let monthly = model.monthlyTotal(items)
        return "Your \(items.count) subscriptions cost \(money(monthly)) a month, about \(money(model.yearly(fromMonthly: monthly))) a year."
    }

    private func dueBeforeSalary() -> String {
        let model = RecurringModel(session: session)
        guard let salary = model.nextSalary, salary.dueDate > today else { return "I don't know your next salary date. Add your salary in Bills & subscriptions." }
        let rows = model.due(from: today, through: salary.dueDate.addingDays(-1), includeOverdue: true).filter { !$0.item.type.isIncome }
        let due = model.total(rows)
        let left = (try? session.ledger.available.subtracting(due)) ?? session.ledger.available
        let days = today.days(to: salary.dueDate)
        return "\(money(due)) is due in the \(days) days before your salary on \(DateText.short(salary.dueDate)). "
            + (left.isNegative ? "That's \(money(left)) more than you have." : "You'll have \(money(left)) left after bills.")
    }

    private func upcoming() -> String {
        let model = RecurringModel(session: session)
        let rows = model.due(from: today, through: today.addingDays(7), includeOverdue: true).filter { !$0.item.type.isIncome }
        guard !rows.isEmpty else { return "Nothing is due in the next 7 days." }
        let names = rows.prefix(3).map { "\($0.item.name) \(DateText.short($0.occurrence.dueDate))" }
        return "\(money(model.total(rows))) is due in the next 7 days: " + ListFormatter.localizedString(byJoining: names)
            + (rows.count > 3 ? " and \(rows.count - 3) more." : ".")
    }

    // MARK: Accounts

    private func balance(_ name: String?) -> String {
        if let name {
            let key = NameKey.make(name)
            guard let account = session.ledger.activeAccounts.first(where: { NameKey.make($0.name) == key }) else {
                return "I couldn't find an account called \(name)."
            }
            return "\(account.name) has \(MoneyFormatter.string(session.ledger.balance(of: account)))."
        }
        return "You have \(MoneyFormatter.string(session.ledger.available)) across your accounts."
    }
}
