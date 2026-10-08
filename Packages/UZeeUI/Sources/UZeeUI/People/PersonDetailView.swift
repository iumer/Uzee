import SwiftUI
import UZeeCore

/// Person (SCR-22): one balance made of loans and shared expenses, the loans with their status, and the
/// history behind the balance. Lend, repay, settle up and remind from here (LOAN-02…05, SPL-08).
struct PersonDetailView: View {
    @Bindable var session: AppSession
    let personID: UUID
    @State private var sheet: PersonSheet?

    var body: some View {
        let model = PeopleModel(session: session)
        let balance = session.balances.balance(of: personID)
        let net = model.toBase(balance.net)
        let loans = session.people.loans.filter { $0.personID == personID }
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.xl) {
                if let person = session.people.person(personID) {
                    header(person, net: net, balance: balance, model: model)
                    actions(person, net: net, loans: loans)
                    if !loans.isEmpty { loansCard(loans) }
                    historyCard(model)
                    Text("Loans and shared expenses with \(person.name) add up into this one balance.")
                        .font(.footnote).foregroundStyle(UZColor.label2)
                } else {
                    EmptyStateView("Not found", systemImage: "person.crop.circle.badge.questionmark", description: "This person was removed.")
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
            .padding(.bottom, UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle(session.people.person(personID)?.name ?? "Person")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add shared expense", systemImage: "person.2.badge.plus") {
                        session.openAdd(.shared(group: nil, person: personID))
                    }
                    Button("Edit", systemImage: "pencil") { sheet = .edit }
                    if let person = session.people.person(personID) {
                        Button(person.archivedAt == nil ? "Archive" : "Unarchive", systemImage: "archivebox") { toggleArchive(person) }
                            .disabled(person.archivedAt == nil && !net.isZero)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("person.more")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: PersonFormSheet(session: session, editing: session.people.person(personID))
            case .lend(let direction): LoanSheet(session: session, personID: personID, direction: direction)
            case .repay(let loan): RepaymentSheet(session: session, loanID: loan)
            case .settle: SettleUpSheet(session: session, personID: personID, groupID: nil, suggested: net)
            case .remind: RemindSheet(name: session.people.person(personID)?.name ?? "", balance: net)
            case .due(let loan): LoanTermsSheet(session: session, loanID: loan)
            }
        }
    }

    private func header(_ person: Person, net: Money, balance: PersonBalance, model: PeopleModel) -> some View {
        UZCard(tint: net.isZero ? nil : SplitText.color(net)) {
            HStack(spacing: UZSpacing.xl) {
                PersonAvatar(name: person.name, size: 56)
                VStack(alignment: .leading, spacing: UZSpacing.xs) {
                    Text(person.name).font(.title3.bold())
                    Text(SplitText.word(net)).font(.subheadline).foregroundStyle(UZColor.label2)
                    if !net.isZero {
                        Text(MoneyFormatter.string(SplitText.magnitude(net)))
                            .font(.largeTitle.bold()).monospacedDigit().foregroundStyle(SplitText.color(net))
                    }
                    Text("Loans \(MoneyFormatter.string(model.toBase(balance.loans))) · Shared \(MoneyFormatter.string(model.toBase(balance.shared)))")
                        .font(.footnote).foregroundStyle(UZColor.label2).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("person.balance")
    }

    private func actions(_ person: Person, net: Money, loans: [Loan]) -> some View {
        let open = loans.filter { LoanCalculator.status($0) == .open || LoanCalculator.status($0) == .partiallyPaid }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: UZSpacing.m) {
                if let loan = open.first {
                    actionButton(loan.direction == .lent ? "They paid you" : "You paid back", "arrow.uturn.backward.circle",
                                 id: "person.repay") { sheet = .repay(loan.id) }
                }
                actionButton("Lend", "arrow.up.circle", id: "person.lend") { sheet = .lend(.lent) }
                actionButton("Borrow", "arrow.down.circle", id: "person.borrow") { sheet = .lend(.borrowed) }
                if !net.isZero {
                    actionButton("Settle up", "checkmark.circle", id: "person.settle") { sheet = .settle }
                    actionButton("Remind", "bell", id: "person.remind") { sheet = .remind }
                }
            }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    private func loansCard(_ loans: [Loan]) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("Loans")
            UZCard {
                VStack(spacing: 0) {
                    ForEach(loans) { loan in
                        loanRow(loan)
                        if loan.id != loans.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func loanRow(_ loan: Loan) -> some View {
        let status = LoanCalculator.status(loan)
        let today = LocalDate(Date(), in: .current)
        var meta = [loan.startDate.listTitle(today: today)]
        if let due = loan.dueDate { meta.append("due \(due.listTitle(today: today))") }
        if loan.isOpeningBalance { meta.append("existing balance") }
        let interest = LoanCalculator.interest(loan, asOf: today)
        if !interest.isZero { meta.append("interest so far \(MoneyFormatter.string(interest))") }
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(loan.direction == .lent ? "Lent" : "Borrowed") \(MoneyFormatter.string(loan.principal))").font(.body.weight(.semibold))
                Text(meta.joined(separator: " · ")).font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(status.name).font(.caption.weight(.semibold))
                    .foregroundStyle(status == .settled || status == .writtenOff ? UZColor.label2 : UZColor.warning)
                if status == .open || status == .partiallyPaid {
                    // Red: money you owe them. Green: money they owe you.
                    Text("\(MoneyFormatter.string(LoanCalculator.outstanding(loan))) left").font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(loan.direction == .lent ? UZColor.positive : UZColor.negative)
                }
            }
        }
        .padding(.vertical, UZSpacing.m)
        .contentShape(.rect)
        .onTapGesture {
            if status == .open || status == .partiallyPaid { sheet = .repay(loan.id) }
        }
        .contextMenu {
            if status == .open || status == .partiallyPaid {
                Button(loan.direction == .lent ? "They paid you" : "You paid back", systemImage: "arrow.uturn.backward") { sheet = .repay(loan.id) }
            }
            Button("Due date and interest", systemImage: "calendar") { sheet = .due(loan.id) }
            Button(loan.writtenOffAt == nil ? "Write off" : "Undo write-off", systemImage: "xmark.seal") {
                let writeOff = loan.writtenOffAt == nil
                if session.perform("Couldn't change the loan. Try again.", { try session.peopleClient.setWrittenOff(writeOff, loan.id) }) {
                    session.toasts.show(writeOff ? "Written off" : "Write-off undone")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loan.\(loan.direction.rawValue).\(MoneyFormatter.string(loan.principal))")
    }

    private func historyCard(_ model: PeopleModel) -> some View {
        let items = history(model)
        return VStack(alignment: .leading, spacing: UZSpacing.m) {
            SectionHeader("History")
            UZCard {
                if items.isEmpty {
                    Text("Nothing yet.").foregroundStyle(UZColor.label2)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            if item.opensTransaction {
                                NavigationLink(value: Route.transaction(item.id)) { historyRow(item) }
                                    .buttonStyle(.plain)
                            } else {
                                historyRow(item)
                            }
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ item: HistoryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(UZColor.label)
                Text(item.meta).font(.footnote).foregroundStyle(UZColor.label2)
            }
            Spacer()
            Text(item.amount).monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(item.theyOwe ? UZColor.positive : UZColor.negative)
        }
        .padding(.vertical, UZSpacing.m)
        .contentShape(.rect)
    }

    /// One line of history. Green when it is about money they owe you, red when it is about money you owe them.
    struct HistoryItem: Identifiable {
        let id: UUID
        let title: String
        let meta: String
        let amount: String
        var theyOwe = true
        var date = Date.distantPast
        /// Records kept without an account have no transaction to open.
        var opensTransaction = true
    }

    /// Everything that moved this balance, newest first, including debts and payments kept as records only.
    private func history(_ model: PeopleModel) -> [HistoryItem] {
        let name = session.people.person(personID)?.name ?? "They"
        let loanByTransaction = Dictionary(session.people.loans.compactMap { loan in loan.transactionID.map { ($0, loan) } },
                                           uniquingKeysWith: { a, _ in a })
        var paymentLoans: [UUID: Loan] = [:]
        for loan in session.people.loans { for payment in loan.payments { if let id = payment.transactionID { paymentLoans[id] = loan } } }
        func negated(_ money: Money) -> Money { Money(minorUnits: -money.minorUnits, currency: money.currency) }
        var items = session.transactions.compactMap { (transaction: MoneyTransaction) -> HistoryItem? in
            let meta = model.dateLine(transaction)
            let when = transaction.occurredAt
            if transaction.counterpartyID == personID || loanByTransaction[transaction.id]?.personID == personID {
                switch transaction.kind {
                case .loanOut:
                    return HistoryItem(id: transaction.id, title: "You lent", meta: meta,
                                       amount: MoneyFormatter.string(transaction.amount, sign: .always), theyOwe: true, date: when)
                case .loanIn:
                    return HistoryItem(id: transaction.id, title: "You borrowed", meta: meta,
                                       amount: MoneyFormatter.string(negated(transaction.amount)), theyOwe: false, date: when)
                case .repayment:
                    let lent = paymentLoans[transaction.id]?.direction != .borrowed
                    return HistoryItem(id: transaction.id, title: lent ? "\(name) paid you" : "You paid back", meta: meta,
                                       amount: MoneyFormatter.string(lent ? negated(transaction.amount) : transaction.amount, sign: .always),
                                       theyOwe: lent, date: when)
                case .settlement:
                    guard let settlement = Settlement.from(transaction) else { return nil }
                    return HistoryItem(id: transaction.id, title: settlement.amount.isNegative ? "\(name) paid you" : "You paid \(name)",
                                       meta: meta, amount: "✓ " + MoneyFormatter.string(SplitText.magnitude(settlement.amount)),
                                       theyOwe: settlement.amount.isNegative, date: when)
                default: break
                }
            }
            guard let split = session.people.split(for: transaction.id), split.people.contains(personID),
                  let effect = model.effect(of: split, isIncome: SpendingRules.countsAsIncome(transaction.kind), with: personID),
                  !effect.isZero else { return nil }
            return HistoryItem(id: transaction.id, title: transaction.payeeName ?? "Shared expense", meta: meta,
                               amount: (effect.isNegative ? "you owe " : "owes you ") + MoneyFormatter.string(SplitText.magnitude(effect)),
                               theyOwe: !effect.isNegative, date: when)
        }
        // "I owe Ammi Rs 250,000" and "paid Rs 50,000 in cash" have no transaction: show them from the loan.
        let today = LocalDate(Date(), in: .current)
        for loan in session.people.loans where loan.personID == personID {
            let lent = loan.direction == .lent
            if loan.transactionID == nil {
                items.append(HistoryItem(id: loan.id, title: lent ? "\(name) owes you" : "You owe \(name)",
                                         meta: loan.startDate.listTitle(today: today) + " · record",
                                         amount: MoneyFormatter.string(loan.principal), theyOwe: lent,
                                         date: loan.startDate.startDate(in: .current), opensTransaction: false))
            }
            for payment in loan.payments where payment.transactionID == nil {
                items.append(HistoryItem(id: payment.id, title: lent ? "\(name) paid you" : "You paid back",
                                         meta: payment.paidOn.listTitle(today: today) + " · record",
                                         amount: "−" + MoneyFormatter.string(payment.amount), theyOwe: lent,
                                         date: payment.paidOn.startDate(in: .current), opensTransaction: false))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    private func toggleArchive(_ person: Person) {
        var changed = person
        changed.archivedAt = person.archivedAt == nil ? Date() : nil
        if session.perform("Couldn't change \(person.name). Try again.", { try session.peopleClient.updatePerson(changed) }) {
            session.toasts.show(changed.archivedAt == nil ? "Unarchived" : "Archived")
        }
    }
}

enum PersonSheet: Identifiable {
    case edit, settle, remind
    case lend(LoanDirection)
    case repay(UUID)
    case due(UUID)

    var id: String {
        switch self {
        case .edit: "edit"
        case .settle: "settle"
        case .remind: "remind"
        case .lend(let direction): "lend.\(direction.rawValue)"
        case .repay(let id): "repay.\(id)"
        case .due(let id): "due.\(id)"
        }
    }
}
