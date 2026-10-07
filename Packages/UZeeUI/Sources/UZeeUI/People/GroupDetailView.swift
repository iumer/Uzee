import SwiftUI
import UZeeCore

/// Group (SCR-21): who owes whom in the group, Simplify debts suggestions, the month's group spend and
/// your share, and the group's activity (SPL-07, SPL-09, SPL-12).
struct GroupDetailView: View {
    @Bindable var session: AppSession
    let groupID: UUID
    @State private var month: LocalDate?
    @State private var settling: UUID?
    @State private var reminding: UUID?
    @State private var isEditing = false

    var body: some View {
        let model = PeopleModel(session: session)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                if let group = session.people.group(groupID) {
                    header(group, model: model)
                    balanceCard(group, model: model)
                    activitySection(group, model: model)
                } else {
                    EmptyStateView("Not found", systemImage: "person.3", description: "This group was removed.")
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle(session.people.group(groupID)?.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add expense", systemImage: "plus") { session.openAdd(.shared(group: groupID, person: nil)) }
                    Button("Edit group", systemImage: "pencil") { isEditing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("group.more")
            }
        }
        .sheet(isPresented: $isEditing) { GroupFormSheet(session: session, editing: session.people.group(groupID)) }
        .sheet(item: Binding(get: { settling.map { IdentifiedID(id: $0) } }, set: { settling = $0?.id })) { item in
            SettleUpSheet(session: session, personID: item.id, groupID: groupID,
                          suggested: model.toBase(session.balances.group(groupID).withMe[item.id] ?? MoneyBag()))
        }
        .sheet(item: Binding(get: { reminding.map { IdentifiedID(id: $0) } }, set: { reminding = $0?.id })) { item in
            RemindSheet(name: model.name(item.id), balance: model.toBase(session.balances.group(groupID).withMe[item.id] ?? MoneyBag()),
                        groupName: session.people.group(groupID)?.name)
        }
    }

    private func header(_ group: SplitGroup, model: PeopleModel) -> some View {
        HStack(spacing: UZSpacing.l) {
            GroupTile(icon: group.icon, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.title2.bold())
                Text("\(group.memberIDs.count) members · split \(group.defaultMethod.name.lowercased())")
                    .font(.subheadline).foregroundStyle(UZColor.label2)
            }
        }
    }

    private func balanceCard(_ group: SplitGroup, model: PeopleModel) -> some View {
        let balance = session.balances.group(group.id)
        let others = group.memberIDs.filter { $0 != model.me }
        let nets = Dictionary(uniqueKeysWithValues: group.memberIDs.map { ($0, model.toBase(balance.nets[$0] ?? MoneyBag())) })
        let suggestions = group.simplifyDebts && group.memberIDs.count >= 3
            ? DebtSimplifier.simplify(nets: nets, order: group.memberIDs) : []
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Balance now")
            UZCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(others, id: \.self) { person in
                        let amount = model.toBase(balance.withMe[person] ?? MoneyBag())
                        HStack(spacing: UZSpacing.l) {
                            PersonAvatar(name: model.name(person))
                            Text(model.name(person)).font(.body.weight(.semibold))
                            Spacer()
                            BalanceLabel(balance: amount)
                        }
                        .padding(.vertical, UZSpacing.m)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("groupBalance.\(model.name(person))")
                        if !amount.isZero {
                            HStack {
                                Button("Remind") { reminding = person }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("group.remind.\(model.name(person))")
                                Button("Settle up") { settling = person }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("group.settle.\(model.name(person))")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.bottom, UZSpacing.m)
                        }
                        if person != others.last { Divider() }
                    }
                    if others.allSatisfy({ (balance.withMe[$0].map(model.toBase) ?? .zero(session.ledger.base)).isZero }) {
                        Label("All settled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(UZColor.positive)
                            .padding(.top, UZSpacing.s)
                            .accessibilityIdentifier("group.settled")
                    }
                }
            }
            if !suggestions.isEmpty {
                UZCard {
                    VStack(alignment: .leading, spacing: UZSpacing.s) {
                        Text("Simplify debts").font(.subheadline.weight(.semibold))
                        ForEach(suggestions, id: \.self) { debt in
                            Text("\(model.name(debt.debtor)) pays \(model.name(debt.creditor)) \(MoneyFormatter.string(debt.amount))")
                                .font(.subheadline).monospacedDigit()
                        }
                        Text("Balances are netted so fewer payments are needed.").font(.footnote).foregroundStyle(UZColor.label2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("group.simplify")
            }
        }
    }

    private struct Entry: Identifiable {
        let id: UUID
        let transaction: MoneyTransaction
        let split: Split?
    }

    private func activitySection(_ group: SplitGroup, model: PeopleModel) -> some View {
        let splits = Dictionary(session.people.splits.filter { $0.groupID == group.id }.map { ($0.transactionID, $0) },
                                uniquingKeysWith: { a, _ in a })
        let entries = session.transactions.compactMap { transaction -> Entry? in
            if let split = splits[transaction.id] { return Entry(id: transaction.id, transaction: transaction, split: split) }
            if transaction.kind == .settlement && transaction.groupID == group.id { return Entry(id: transaction.id, transaction: transaction, split: nil) }
            return nil
        }
        let months = Array(Set(entries.map { $0.transaction.localDate.firstOfMonth })).sorted(by: >)
        let today = LocalDate(Date(), in: .current).firstOfMonth
        let selected = month ?? (months.contains(today) ? today : months.first ?? today)
        let shown = entries.filter { $0.transaction.localDate.firstOfMonth == selected }
        let base = session.ledger.base
        let rates = session.ledger.rates
        var spend: Int64 = 0
        var mine: Int64 = 0
        for entry in shown where entry.split != nil && SpendingRules.spendingSign(entry.transaction.kind) != 0 {
            let sign = SpendingRules.spendingSign(entry.transaction.kind)
            spend += sign * ((try? RateTable.toBase(entry.transaction.amount, base: base, rates: rates))?.minorUnits ?? 0)
            mine += sign * ((try? RateTable.toBase(entry.transaction.myShare, base: base, rates: rates))?.minorUnits ?? 0)
        }
        let monthName = selected.startDate(in: .current).formatted(.dateTime.month(.wide))
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            HStack {
                SectionHeader("Activity")
                Menu {
                    ForEach(months, id: \.self) { start in
                        Button(start.startDate(in: .current).formatted(.dateTime.month(.wide).year())) { month = start }
                    }
                } label: {
                    Label(selected.startDate(in: .current).formatted(.dateTime.month(.abbreviated).year()), systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("group.month")
            }
            UZCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Group spend in \(monthName)").font(.footnote).foregroundStyle(UZColor.label2)
                        Text(MoneyFormatter.string(Money(minorUnits: spend, currency: base))).font(.title3.bold()).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("group.spend")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Your share").font(.footnote).foregroundStyle(UZColor.label2)
                        Text(MoneyFormatter.string(Money(minorUnits: mine, currency: base))).font(.title3.bold()).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("group.yourShare")
                }
            }
            UZCard {
                if shown.isEmpty {
                    Text("Nothing in \(monthName).").foregroundStyle(UZColor.label2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(shown) { entry in
                            NavigationLink(value: Route.transaction(entry.id)) {
                                activityRow(entry, model: model)
                            }
                            .buttonStyle(.plain)
                            if entry.id != shown.last?.id { Divider() }
                        }
                    }
                }
            }
            if let note = RateTable.footnote(for: Set(shown.map(\.transaction.amount.currency)), base: base, rates: rates) {
                Text(note).font(.footnote).foregroundStyle(UZColor.label2)
            }
        }
    }

    private func activityRow(_ entry: Entry, model: PeopleModel) -> some View {
        let transaction = entry.transaction
        let isIncome = SpendingRules.countsAsIncome(transaction.kind)
        var paidLine = ""
        var effectWord = ""
        var effectAmount = ""
        var effectColor = UZColor.label2
        if let split = entry.split {
            let payers = split.payers.map { model.name($0.personID) }
            let verb = isIncome ? "received" : "paid"
            paidLine = payers.count == 1 ? "\(payers[0]) \(verb) \(MoneyFormatter.string(transaction.amount))" : "Several people \(verb)"
            if let effect = model.effect(of: split, isIncome: isIncome) {
                effectWord = effect.isZero ? "not involved" : effect.isNegative ? "you owe" : "you lent"
                effectAmount = effect.isZero ? "" : MoneyFormatter.string(SplitText.magnitude(effect))
                effectColor = SplitText.color(effect)
            }
        } else if let settlement = Settlement.from(transaction) {
            let other = model.name(settlement.personID)
            paidLine = settlement.amount.isNegative ? "\(other) paid you \(MoneyFormatter.string(SplitText.magnitude(settlement.amount)))"
                                                    : "You paid \(other) \(MoneyFormatter.string(settlement.amount))"
            effectWord = "✓ settled"
        }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.split == nil ? "Settled up" : transaction.payeeName ?? "Shared expense").foregroundStyle(UZColor.label)
                Text(model.dateLine(transaction)).font(.footnote).foregroundStyle(UZColor.label2)
                Text(paidLine).font(.footnote).foregroundStyle(UZColor.label2).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(effectWord).font(.caption).foregroundStyle(UZColor.label2)
                if !effectAmount.isEmpty { Text(effectAmount).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(effectColor) }
            }
        }
        .padding(.vertical, UZSpacing.m)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("groupTxn.\(transaction.payeeName ?? "")")
    }
}

/// Wraps an id for `.sheet(item:)`.
struct IdentifiedID: Identifiable {
    let id: UUID
}
