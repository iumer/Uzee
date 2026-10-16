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
        case .dueThisMonth: return dueThisMonth()
        case .afford(let amount): return afford(amount)
        case .biggest(let period): return biggest(period)
        case .compare: return compare()
        }
    }

    /// "Can I afford a 30,000 phone?": weighed against this month's budget left, then the money in the accounts.
    private func afford(_ said: SpokenAmount?) -> String {
        let budget = BudgetModel(session: session)
        let summary = budget.summary(for: budget.current)
        guard let said, said.currency == nil || said.currency == base,
              let price = try? Money.fromMajor(said.value, base) else {
            return [budgetLeft(), balance(nil)].joined(separator: " ")
        }
        let available = session.ledger.available
        if let summary {
            let left = summary.isOver ? -summary.left.minorUnits.magnitudeClamped : summary.left.minorUnits.magnitudeClamped
            let after = Money(minorUnits: left - price.minorUnits, currency: base)
            if after.minorUnits >= 0 {
                return "Yes. \(money(price)) fits your budget, with \(money(after)) still left for \(BudgetModel.title(budget.current))."
            }
            let short = "It would put you \(money(after)) over budget for \(BudgetModel.title(budget.current))"
            return available.minorUnits >= price.minorUnits
                ? short + ", though your accounts have \(MoneyFormatter.string(available)). Maybe wait until next month."
                : short + ", and your accounts only have \(MoneyFormatter.string(available))."
        }
        return available.minorUnits >= price.minorUnits
            ? "You have \(MoneyFormatter.string(available)) across your accounts, so yes, but there's no budget this month to check it against."
            : "Not right now. Your accounts have \(MoneyFormatter.string(available)), less than \(money(price))."
    }

    /// "4 transactions for Foodpanda this month, Rs 6,200 spent. Latest: …" (UZee helper's search).
    func search(_ text: String, period: VoicePeriod?) -> String {
        var filter = ActivityFilter(text: text)
        if let period { (filter.from, filter.through) = range(period) }
        var found = ActivityQuery.filter(session.transactions, filter, snapshot: session.ledger, tags: session.tagMap)
        if found.isEmpty {
            // Search by category name too ("fuel", "groceries").
            let key = NameKey.make(text)
            let ids = Set(session.ledger.categories.filter { NameKey.make($0.name).contains(key) && !key.isEmpty }.map(\.id))
            if !ids.isEmpty {
                filter.text = ""
                filter.categoryIDs = ids
                found = ActivityQuery.filter(session.transactions, filter, snapshot: session.ledger, tags: session.tagMap)
            }
        }
        let when = period.map { " " + $0.name } ?? ""
        guard !found.isEmpty else { return "No transactions for \(text)\(when)." }
        // Only spending counts toward the total, my share in base, as on the Budget and Reports screens (owner, 2026-10-16).
        let spending = found.filter { $0.isEffective && SpendingRules.spendingSign($0.kind) != 0 }
        let spent = spending.reduce(Int64(0)) { $0 + SpendingRules.spendingSign($1.kind) * baseShare($1) }
        var reply = "\(found.count) transaction\(found.count == 1 ? "" : "s") for \(text)\(when)"
        if spending.isEmpty {
            let received = found.filter { $0.isEffective && SpendingRules.countsAsIncome($0.kind) }.reduce(Int64(0)) { $0 + baseShare($1) }
            reply += received != 0 ? ", \(money(Money(minorUnits: received, currency: base))) received." : ", none of it spending."
        } else {
            reply += ", \(money(Money(minorUnits: spent, currency: base))) \(spent < 0 ? "refunded" : "spent")"
            reply += spending.count < found.count ? " (transfers, loans and pending ones aren't counted)." : "."
        }
        let latest = found.prefix(5).map { row in
            "\(row.payeeName ?? session.ledger.categoryPath(row.categoryID) ?? "a transaction") \(money(row.amount)) on \(DateText.short(row.localDate))"
        }
        return reply + " Latest: " + latest.joined(separator: "; ") + "."
    }

    /// My share of a transaction in base minor units; 0 when there's no rate, as the totals skip it.
    private func baseShare(_ transaction: MoneyTransaction) -> Int64 {
        (try? RateTable.toBase(transaction.myShare, base: base, rates: session.ledger.rates))?.minorUnits ?? 0
    }

    /// Total balance, this month's spending, budget left and the next bill, in one breath.
    func overview() -> String {
        [balance(nil), spent(nil, .thisMonth), budgetLeft(), nextBill()].joined(separator: " ")
    }

    private func money(_ amount: Money) -> String {
        MoneyFormatter.string(Money(minorUnits: amount.minorUnits.magnitudeClamped, currency: amount.currency))
    }

    func person(named name: String) -> Person? {
        let key = NameKey.make(name)
        return session.people.others.first { NameKey.make($0.name) == key }
            ?? onlyOne(session.people.others.filter { person in
                // "Ali" is "Ali Raza" but never "Alina"; with two Alis, ask rather than guess.
                let words = NameKey.make(person.name).split(separator: " ")
                return words.first.map(String.init) == key || key.split(separator: " ").first.map(String.init) == NameKey.make(person.name)
            })
    }

    private func onlyOne(_ people: [Person]) -> Person? {
        people.count == 1 ? people[0] : nil
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

    func range(_ period: VoicePeriod) -> (LocalDate, LocalDate) {
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
            let expense = session.ledger.categories.filter { $0.type == .expense }
            // "food" finds "Food & Dining"; whole words first, then any part of a name.
            func wordMatch(_ name: String) -> Bool {
                let words: [String] = NameKey.make(name).split(separator: " ").map(String.init)
                return words.contains(key) || words.contains(key + "s") || words.contains { $0 + "s" == key }
            }
            var found: SpendCategory? = expense.first { NameKey.make($0.name) == key }
            if found == nil { found = expense.first { wordMatch($0.name) } }
            if found == nil, key.count >= 4 { found = expense.first { NameKey.make($0.name).contains(key) } }
            guard let category = found else {
                return "I couldn't find a category called \(categoryName)."
            }
            let ids = Set([category.id] + session.ledger.categories.filter { $0.parentID == category.id }.map(\.id))
            transactions = transactions.filter { transaction in transaction.categoryID.map { ids.contains($0) } ?? false }
            label = " on \(category.name)"
        }
        let totals = ReportCalculator.totals(transactions, from: start, through: end, base: base, rates: session.ledger.rates)
        return "You spent \(money(totals.spending))\(label) \(period.name). Only your shares count."
    }

    /// "Your biggest expense this month is Office, Rs 37,000 (48%). Then Transport Rs 16,000 and Food Rs 15,500.
    /// The largest single payment was Office rent, Rs 30,000 on Oct 1."
    private func biggest(_ period: VoicePeriod) -> String {
        let (start, end) = range(period)
        let shares = ReportCalculator.byGroup(session.transactions, from: start, through: end, categories: session.ledger.categories,
                                              base: base, rates: session.ledger.rates)
        guard let top = shares.first else { return "You haven't spent anything \(period.name)." }
        func name(_ id: UUID) -> String { session.ledger.category(id)?.name ?? "Other" }
        var parts = ["Your biggest expense \(period.name) is \(name(top.categoryID)), \(money(top.amount)) (\(top.percent)% of your spending)."]
        let next = shares.dropFirst().prefix(2).map { "\(name($0.categoryID)) \(money($0.amount))" }
        if !next.isEmpty { parts.append("Then " + ListFormatter.localizedString(byJoining: next) + ".") }
        // Every kind that counts as spending, my share in base, so the payment matches the totals (owner, 2026-10-16).
        let rows = session.transactions.filter {
            $0.isEffective && SpendingRules.spendingSign($0.kind) > 0 && $0.localDate >= start && $0.localDate <= end
        }
        let largest = rows.max { baseShare($0) < baseShare($1) }
        if let largest {
            let what = largest.payeeName ?? session.ledger.categoryPath(largest.categoryID) ?? "a payment"
            let share = (try? RateTable.toBase(largest.myShare, base: base, rates: session.ledger.rates)) ?? largest.myShare
            parts.append("The largest single payment was \(what), \(money(share)) on \(DateText.short(largest.localDate)).")
            if LoanWords.looksLikeLoan(largest.payeeName, largest.note) {
                parts.append("\(largest.payeeName ?? "That payment") is saved as spending. If it was a loan or a repayment, "
                    + "change it so it stops counting as spending.")
            }
        }
        if name(top.categoryID) == "Other", top.percent >= 40 {
            // "Other" is a real category: spending with no category isn't counted at all.
            let ids = Set([top.categoryID] + session.ledger.categories.filter { $0.parentID == top.categoryID }.map(\.id))
            var byPayee: [String: Int64] = [:]
            for row in rows where row.categoryID.map({ ids.contains($0) }) ?? false {
                byPayee[row.payeeName ?? "no name", default: 0] += baseShare(row)
            }
            let payees: [String] = byPayee.sorted { $0.value > $1.value }.prefix(3)
                .map { "\($0.key) \(money(Money(minorUnits: $0.value, currency: base)))" }
            if payees.isEmpty {
                parts.append("Moving payments out of Other into a real category would make this clearer.")
            } else {
                parts.append("Most of it is filed under Other, mainly " + ListFormatter.localizedString(byJoining: payees)
                    + ". Moving those to a real category would make this clearer.")
            }
        }
        return parts.joined(separator: " ")
    }

    /// This month so far against the same days of last month.
    private func compare() -> String {
        let start = today.firstOfMonth
        let lastStart = start.addingMonths(-1)
        let lastEnd = min(lastStart.addingDays(today.day - 1), lastStart.lastOfMonth)
        let now = ReportCalculator.totals(session.transactions, from: start, through: today, base: base, rates: session.ledger.rates).spending
        let then = ReportCalculator.totals(session.transactions, from: lastStart, through: lastEnd, base: base, rates: session.ledger.rates).spending
        let difference = Money(minorUnits: (now.minorUnits - then.minorUnits).magnitudeClamped, currency: base)
        let days = "the first \(today.day) days"
        if then.isZero { return "You've spent \(money(now)) this month. There's nothing from \(days) of last month to compare with." }
        if now.minorUnits == then.minorUnits { return "You've spent \(money(now)) this month, the same as \(days) of last month." }
        return "You've spent \(money(now)) this month, \(money(difference)) \(now.minorUnits > then.minorUnits ? "more" : "less") than \(days) of last month (\(money(then)))."
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

    /// The total and every subscription in one answer, so "how much" and "breakdown" can never disagree; the same items
    /// as the Bills hub (owner, 2026-10-16).
    func subscriptions() -> String {
        let model = RecurringModel(session: session)
        let items = model.active.filter { model.isSubscription($0) && $0.groupID == nil }
        let extra = untrackedSubscriptionPayments(model)
        guard !items.isEmpty else {
            return "You have no active subscriptions." + (extra.isEmpty ? "" : " " + untrackedText(extra))
        }
        let monthly = model.monthlyTotal(items)
        let sorted = items.sorted { a, b in
            let x = model.monthly(a).minorUnits, y = model.monthly(b).minorUnits
            return x != y ? x > y : a.name < b.name
        }
        let named: [String] = sorted.map { item in
            let perMonth = money(model.monthly(item))
            guard item.rule.unit != .month || item.rule.interval != 1 else { return "\(item.name) \(perMonth)" }
            return "\(item.name) \(perMonth) a month (\(money(item.amount)) \(item.rule.text.lowercased()))"
        }
        var text = "You have \(items.count) subscription\(items.count == 1 ? "" : "s"), \(money(monthly)) a month "
            + "(\(money(model.yearly(fromMonthly: monthly))) a year): " + ListFormatter.localizedString(byJoining: named) + "."
        if !extra.isEmpty { text += " " + untrackedText(extra) }
        return text
    }

    /// This month's payments filed under Subscriptions that no saved bill covers, so the Budget line can differ.
    private func untrackedSubscriptionPayments(_ model: RecurringModel) -> [MoneyTransaction] {
        session.transactions.filter { transaction in
            transaction.isEffective && SpendingRules.spendingSign(transaction.kind) > 0
                && transaction.localDate >= today.firstOfMonth && transaction.localDate <= today
                && session.ledger.category(transaction.categoryID)?.group == .subscriptions && !model.isTracked(transaction)
        }
    }

    private func untrackedText(_ payments: [MoneyTransaction]) -> String {
        let shown = payments.prefix(3).map { payment in
            "\(payment.payeeName ?? session.ledger.categoryPath(payment.categoryID) ?? "a payment") "
                + money(Money(minorUnits: baseShare(payment), currency: base))
        }
        return "Also filed under Subscriptions this month but not saved as a subscription: "
            + ListFormatter.localizedString(byJoining: Array(shown)) + (payments.count > 3 ? " and \(payments.count - 3) more." : ".")
    }

    /// Bills and subscriptions falling due this calendar month (and any still overdue), paid and still to pay.
    func dueThisMonth() -> String {
        let model = RecurringModel(session: session)
        // Skipped bills were never paid, so they count neither as due nor as paid.
        let rows = model.due(from: today.firstOfMonth, through: today.lastOfMonth, includeOverdue: true)
            .filter { !$0.item.type.isIncome && $0.occurrence.state != .skipped }
        guard !rows.isEmpty else { return "Nothing is due this month." }
        let open = rows.filter { !$0.occurrence.isResolved }
        let paid = rows.filter { $0.occurrence.state == .paid }
        guard !open.isEmpty else { return "Everything due this month is paid: \(money(model.total(rows)))." }
        let named = open.map { "\($0.item.name) \(money(model.baseShare($0.item, $0.occurrence.amount))) \(DateText.short($0.occurrence.dueDate))" }
        var text = "\(money(model.total(rows))) of bills and subscriptions fall due this month. "
        if !paid.isEmpty { text += "\(money(model.total(paid))) is paid and " }
        text += "\(money(model.total(open))) is still to pay: " + ListFormatter.localizedString(byJoining: named) + "."
        return text
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
