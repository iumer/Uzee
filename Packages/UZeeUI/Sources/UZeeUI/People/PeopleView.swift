import SwiftUI
import UZeeCore

/// People (SCR-20): one balance per person from loans and shared groups (SPL-01/07, LOAN-04).
/// Groups sit behind the top button; "+" adds a person, existing balances or a group.
struct PeopleView: View {
    @Bindable var session: AppSession
    @State private var sheet: PeopleSheet?

    var body: some View {
        let model = PeopleModel(session: session)
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                summaryCard(model)
                Button {
                    session.openAdd(.shared(group: nil, person: nil))
                } label: {
                    Label("Add shared expense", systemImage: "person.2.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("people.addShared")
                let people = model.rows
                if people.isEmpty {
                    UZCard {
                        EmptyStateView("No people yet", systemImage: "person.2",
                                       description: "Add someone you lend to, borrow from or split bills with. Each person gets one balance.")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("people.empty")
                } else {
                    UZCard(padding: UZSpacing.xxl) {
                        VStack(spacing: 0) {
                            ForEach(people) { row in
                                NavigationLink(value: Route.person(row.id)) {
                                    PersonRow(row: row)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("person.\(row.name)")
                                if row.id != people.last?.id { Divider().padding(.leading, 48) }
                            }
                        }
                    }
                }
                Text("Each person shows one balance from loans and shared groups. Only your share of a split counts as your spending.")
                    .font(.footnote)
                    .foregroundStyle(UZColor.label2)
                if let footnote = model.footnote {
                    Text(footnote).font(.footnote).foregroundStyle(UZColor.label2)
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle("People")
        .accessibilityIdentifier("screen.people")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.groups) {
                    Label("Groups", systemImage: "person.3")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("people.groups")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add person", systemImage: "person.badge.plus") { sheet = .addPerson }
                        .accessibilityIdentifier("people.addPerson")
                    Button("Add existing balances", systemImage: "list.bullet.rectangle") { sheet = .existingBalances }
                        .accessibilityIdentifier("people.existing")
                    Button("New group", systemImage: "person.3") { sheet = .newGroup }
                        .accessibilityIdentifier("people.newGroup")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                .accessibilityIdentifier("people.add")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .addPerson: PersonFormSheet(session: session, editing: nil)
            case .existingBalances: ExistingBalancesSheet(session: session)
            case .newGroup: GroupFormSheet(session: session, editing: nil)
            }
        }
    }

    private func summaryCard(_ model: PeopleModel) -> some View {
        UZCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    Text("Owed to you").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                    Text(MoneyFormatter.string(model.overall.owedToYou))
                        .font(.title2.bold()).monospacedDigit().foregroundStyle(UZColor.positive)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("people.owed")
                Spacer()
                VStack(alignment: .trailing, spacing: UZSpacing.xs) {
                    Text("You owe").font(.subheadline.weight(.semibold)).foregroundStyle(UZColor.label2)
                    Text(MoneyFormatter.string(model.overall.youOwe))
                        .font(.title2.bold()).monospacedDigit().foregroundStyle(model.overall.youOwe.isZero ? UZColor.label : UZColor.negative)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("people.owe")
            }
        }
    }
}

enum PeopleSheet: String, Identifiable {
    case addPerson, existingBalances, newGroup
    var id: String { rawValue }
}

/// Figures for the People screens, computed fresh from the session.
@MainActor
struct PeopleModel {
    let session: AppSession

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let meta: String
        let balance: Money
    }

    var me: UUID { session.people.selfID }
    var overall: (owedToYou: Money, youOwe: Money) { session.balances.overall }

    /// People with a balance first (largest first), then settled ones by name; archived ones are hidden.
    var rows: [Row] {
        session.people.others.filter { $0.archivedAt == nil }.map { person in
            Row(id: person.id, name: person.name, meta: meta(person.id), balance: session.balances.net(of: person.id))
        }
        .sorted {
            let a = $0.balance.minorUnits.magnitudeClamped, b = $1.balance.minorUnits.magnitudeClamped
            return a != b ? a > b : $0.name.localizedCompare($1.name) == .orderedAscending
        }
    }

    /// "Loans · Office" — where the balance comes from.
    func meta(_ person: UUID) -> String {
        var parts: [String] = []
        let loans = session.people.loans.filter { $0.personID == person && LoanCalculator.status($0) != .settled }
        if !loans.isEmpty { parts.append(loans.count == 1 ? "Loan" : "\(loans.count) loans") }
        let groups = session.people.groups.filter { $0.memberIDs.contains(person) && $0.archivedAt == nil }.map(\.name)
        parts += groups.prefix(2)
        if parts.isEmpty { return session.balances.net(of: person).isZero ? "All settled" : "Shared expenses" }
        return parts.joined(separator: " · ")
    }

    /// "USD at $1 = Rs 280" when a balance mixes currencies.
    var footnote: String? {
        var currencies = Set<Currency>()
        for balance in session.balances.people.values { currencies.formUnion(balance.net.currencies) }
        return RateTable.footnote(for: currencies, base: session.ledger.base, rates: session.ledger.rates)
    }

    func name(_ id: UUID) -> String {
        id == me ? "You" : session.people.person(id)?.name ?? "Someone"
    }

    /// My net effect from one split with everyone (+ others owe me) or with one person.
    func effect(of split: Split, isIncome: Bool, with person: UUID? = nil) -> Money? {
        guard let currency = split.payers.first?.amount.currency else { return nil }
        var total: Int64 = 0
        for debt in SplitCalculator.debts(split, isIncome: isIncome) {
            if debt.creditor == me && (person == nil || debt.debtor == person) { total += debt.amount.minorUnits }
            if debt.debtor == me && (person == nil || debt.creditor == person) { total -= debt.amount.minorUnits }
        }
        return Money(minorUnits: total, currency: currency)
    }

    func accountName(_ transaction: MoneyTransaction) -> String? {
        transaction.legs.first.flatMap { session.ledger.account($0.accountID)?.name }
    }

    func dateLine(_ transaction: MoneyTransaction) -> String {
        let today = LocalDate(Date(), in: .current)
        return ([transaction.localDate.listTitle(today: today)] + [accountName(transaction)].compactMap { $0 }).joined(separator: " · ")
    }

    func toBase(_ bag: MoneyBag) -> Money { bag.total(in: session.ledger.base, rates: session.ledger.rates) }
}

struct PersonRow: View {
    let row: PeopleModel.Row

    var body: some View {
        HStack(spacing: UZSpacing.l) {
            PersonAvatar(name: row.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(UZColor.label)
                Text(row.meta).font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer()
            BalanceLabel(balance: row.balance)
        }
        .padding(.vertical, UZSpacing.m)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// "owes you / Rs 25,000" stacked, coloured by direction; "settled" when zero.
struct BalanceLabel: View {
    let balance: Money
    var large = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(SplitText.word(balance)).font(large ? .subheadline : .caption).foregroundStyle(UZColor.label2)
            if !balance.isZero {
                Text(MoneyFormatter.string(SplitText.magnitude(balance)))
                    .font(large ? .title.bold() : .body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(SplitText.color(balance))
            }
        }
    }
}

/// Groups (SCR-21): each group with my balance in it.
struct GroupsView: View {
    @Bindable var session: AppSession
    @State private var isAdding = false

    var body: some View {
        let model = PeopleModel(session: session)
        let groups = session.people.groups.filter { $0.archivedAt == nil }
        List {
            if groups.isEmpty {
                EmptyStateView("No groups yet", systemImage: "person.3",
                               description: "Make a group for the office, a trip or home, and split expenses with everyone in it.")
            }
            ForEach(groups) { group in
                NavigationLink(value: Route.group(group.id)) {
                    HStack(spacing: UZSpacing.l) {
                        GroupTile(icon: group.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.body.weight(.semibold))
                            Text(group.memberIDs.map { model.name($0) }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(UZColor.label2).lineLimit(1)
                        }
                        Spacer()
                        BalanceLabel(balance: model.toBase(session.balances.group(group.id).myNet))
                    }
                    .accessibilityElement(children: .combine)
                }
                .accessibilityIdentifier("group.\(group.name)")
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New group", systemImage: "plus") { isAdding = true }
                    .accessibilityIdentifier("groups.add")
            }
        }
        .sheet(isPresented: $isAdding) { GroupFormSheet(session: session, editing: nil) }
    }
}
