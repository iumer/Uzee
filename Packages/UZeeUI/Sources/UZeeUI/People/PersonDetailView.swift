import SwiftUI
import UZeeCore

/// Person, the Splitwise way (owner, 2026-10-12): one balance at the top, Settle up and Add expense under it,
/// then every expense, loan and payment with this person, newest first, each saying "you lent" or "you borrowed".
/// Lending, borrowing and editing sit in the ••• menu.
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
                    historyCard(model)
                    let open = loans.filter { LoanCalculator.status($0) == .open || LoanCalculator.status($0) == .partiallyPaid }
                    if !open.isEmpty { loansCard(open) }
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
                    Button("Lend money", systemImage: "arrow.up.circle") { sheet = .lend(.lent) }
                        .accessibilityIdentifier("person.lend")
                    Button("Borrow money", systemImage: "arrow.down.circle") { sheet = .lend(.borrowed) }
                        .accessibilityIdentifier("person.borrow")
                    if !net.isZero {
                        Button("Remind", systemImage: "bell") { sheet = .remind }
                            .accessibilityIdentifier("person.remind")
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
                    if net.isZero {
                        Text("All settled up").font(.subheadline).foregroundStyle(UZColor.label2)
                    } else {
                        Text(net.minorUnits > 0 ? "owes you" : "you owe").font(.subheadline).foregroundStyle(UZColor.label2)
                        Text(MoneyFormatter.string(SplitText.magnitude(net)))
                            .font(.largeTitle.bold()).monospacedDigit().foregroundStyle(SplitText.color(net))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("person.balance")
    }

    /// Settle up and Add expense, as in Splitwise; "Paid you back" too while a loan is open.
    private func actions(_ person: Person, net: Money, loans: [Loan]) -> some View {
        let open = loans.filter { LoanCalculator.status($0) == .open || LoanCalculator.status($0) == .partiallyPaid }
        return VStack(spacing: UZSpacing.m) {
            HStack(spacing: UZSpacing.m) {
                if !net.isZero {
                    Button { sheet = .settle } label: {
                        Label("Settle up", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("person.settle")
                }
                Button { session.openAdd(.shared(group: nil, person: personID)) } label: {
                    Label("Add expense", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("person.addExpense")
            }
            .controlSize(.large)
            .font(.subheadline.weight(.semibold))
            if let loan = open.first {
                Button(loan.direction == .lent ? "\(person.name) paid you back" : "You paid \(person.name) back") { sheet = .repay(loan.id) }
                    .font(.subheadline)
                    .accessibilityIdentifier("person.repay")
            }
        }
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
        HStack(spacing: UZSpacing.l) {
            VStack(spacing: 0) {
                Text(item.date.formatted(.dateTime.month(.abbreviated))).font(.caption2).foregroundStyle(UZColor.label2)
                Text(item.date.formatted(.dateTime.day())).font(.headline).monospacedDigit()
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(UZColor.label).lineLimit(1)
                Text(item.meta).font(.footnote).foregroundStyle(UZColor.label2).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                if !item.caption.isEmpty {
                    Text(item.caption).font(.caption2).foregroundStyle(item.theyOwe ? UZColor.positive : UZColor.negative)
                }
                Text(item.amount).monospacedDigit().fontWeight(.semibold)
                    .foregroundStyle(item.theyOwe ? UZColor.positive : UZColor.negative)
            }
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
        /// "you lent" / "you borrowed" above the amount, as in Splitwise.
        var caption = ""
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
                    return HistoryItem(id: transaction.id, title: "You lent \(name)", meta: meta,
                                       amount: MoneyFormatter.string(transaction.amount), theyOwe: true, caption: "you lent", date: when)
                case .loanIn:
                    return HistoryItem(id: transaction.id, title: "\(name) lent you", meta: meta,
                                       amount: MoneyFormatter.string(transaction.amount), theyOwe: false, caption: "you borrowed", date: when)
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
            let payer = split.payers.count == 1
                ? (split.payers[0].personID == model.me ? "You" : session.people.person(split.payers[0].personID)?.name ?? "Someone")
                : "\(split.payers.count) people"
            return HistoryItem(id: transaction.id, title: transaction.payeeName ?? "Shared expense",
                               meta: "\(payer) paid \(MoneyFormatter.string(transaction.amount))",
                               amount: MoneyFormatter.string(SplitText.magnitude(effect)),
                               theyOwe: !effect.isNegative, caption: effect.isNegative ? "you borrowed" : "you lent", date: when)
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
