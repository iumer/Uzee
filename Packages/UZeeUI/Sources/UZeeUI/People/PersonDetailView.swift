import SwiftUI
import UZeeCore

/// Person, the Splitwise way (owner, 2026-10-12): one balance at the top, Settle up and Add expense under it,
/// then every expense, loan and payment with this person, newest first, each saying "you lent" or "you borrowed".
/// Lending, borrowing and editing sit in the ••• menu.
struct PersonDetailView: View {
    @Bindable var session: AppSession
    let personID: UUID
    @State private var sheet: PersonSheet?
    @State private var askingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = PeopleModel(session: session)
        let balance = session.balances.balance(of: personID)
        let net = model.toBase(balance.net)
        let loans = session.people.loans.filter { $0.personID == personID }
        // One list: the balance, the buttons, then History with loans in it (owner, 2026-10-19: no separate Loans
        // section). A List so every entry can be swiped left to delete.
        List {
            if let person = session.people.person(personID), session.people.isListed(personID) {
                Section {
                    header(person, net: net, balance: balance, model: model)
                    actions(person, net: net, loans: loans)
                }
                .listRowInsets(EdgeInsets(top: UZSpacing.m, leading: 0, bottom: UZSpacing.m, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                historySection(model, person: person)
            } else {
                EmptyStateView("Not found", systemImage: "person.crop.circle.badge.questionmark", description: "This person was removed.")
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
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
                        Button("Delete \(person.name)", systemImage: "trash", role: .destructive) { askingDelete = true }
                            .accessibilityIdentifier("person.delete")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("person.more")
            }
        }
        // Settled people can be deleted; anyone with money still between you is settled up first (owner, 2026-10-19).
        .confirmationDialog(deleteTitle(net), isPresented: Binding(get: { askingDelete && net.isZero }, set: { askingDelete = $0 }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let person = session.people.person(personID), session.deletePerson(person) { dismiss() }
            }
            .accessibilityIdentifier("person.confirmDelete")
        } message: {
            Text("They're removed from People. Their past entries stay in Activity. You can undo it.")
        }
        .alert(deleteTitle(net), isPresented: Binding(get: { askingDelete && !net.isZero }, set: { askingDelete = $0 })) {
            Button("Settle up") { sheet = .settle }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(unsettledMessage(net))
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
                        // White, or the tick takes the list's blue and disappears on the blue button.
                        Label("Settle up", systemImage: "checkmark.circle").frame(maxWidth: .infinity).foregroundStyle(.white)
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

    private func deleteTitle(_ net: Money) -> String {
        let name = session.people.person(personID)?.name ?? "this person"
        return net.isZero ? "Delete \(name)?" : "Settle up with \(name) first"
    }

    private func unsettledMessage(_ net: Money) -> String {
        let name = session.people.person(personID)?.name ?? "They"
        let amount = MoneyFormatter.string(SplitText.magnitude(net))
        return net.minorUnits > 0 ? "\(name) still owes you \(amount). Settle up, then you can delete them."
                                  : "You still owe \(name) \(amount). Settle up, then you can delete them."
    }

    /// Every expense, loan and payment with this person, newest first. Swipe left to delete one (with Undo).
    @ViewBuilder
    private func historySection(_ model: PeopleModel, person: Person) -> some View {
        let items = history(model)
        Section {
            if items.isEmpty {
                Text("Nothing yet.").foregroundStyle(UZColor.label2)
            }
            ForEach(items) { item in
                Group {
                    if let loan = item.loanID {
                        NavigationLink(value: Route.loan(loan)) { historyRow(item) }
                    } else if item.opensTransaction {
                        NavigationLink(value: Route.transaction(item.id)) { historyRow(item) }
                    } else {
                        historyRow(item)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                        .accessibilityIdentifier("history.delete")
                }
                .accessibilityIdentifier("history.\(item.title)")
            }
        } header: {
            Text("History")
        } footer: {
            Text("Loans and shared expenses with \(person.name) add up into the balance above. Swipe left on an entry to delete it.")
        }
    }

    private func delete(_ item: HistoryItem) {
        switch item.target {
        case .transaction(let id):
            if let transaction = session.transactions.first(where: { $0.id == id }) { session.delete(transaction) }
        case .loanRecord(let id):
            if let loan = session.people.loans.first(where: { $0.id == id }) { session.deleteLoan(loan) }
        case .paymentRecord(let id):
            session.deleteLoanPayment(id)
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
        /// A loan opens its own page, with notes.
        var loanID: UUID?
        /// What a swipe-left Delete removes: the transaction unless it's a record kept without one.
        var record: DeleteTarget?
        var target: DeleteTarget { record ?? .transaction(id) }

        enum DeleteTarget { case transaction(UUID), loanRecord(UUID), paymentRecord(UUID) }
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
                    return HistoryItem(id: transaction.id, title: "You lent \(name)", meta: loanMeta(meta, loanByTransaction[transaction.id]),
                                       amount: MoneyFormatter.string(transaction.amount), theyOwe: true, caption: "you lent", date: when,
                                       loanID: loanByTransaction[transaction.id]?.id)
                case .loanIn:
                    return HistoryItem(id: transaction.id, title: "\(name) lent you", meta: loanMeta(meta, loanByTransaction[transaction.id]),
                                       amount: MoneyFormatter.string(transaction.amount), theyOwe: false, caption: "you borrowed", date: when,
                                       loanID: loanByTransaction[transaction.id]?.id)
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
                                         meta: loanMeta(loan.startDate.listTitle(today: today) + " · record", loan),
                                         amount: MoneyFormatter.string(loan.principal), theyOwe: lent,
                                         date: loan.startDate.startDate(in: .current), opensTransaction: false, loanID: loan.id,
                                         record: .loanRecord(loan.id)))
            }
            for payment in loan.payments where payment.transactionID == nil {
                items.append(HistoryItem(id: payment.id, title: lent ? "\(name) paid you" : "You paid back",
                                         meta: payment.paidOn.listTitle(today: today) + " · record",
                                         amount: "−" + MoneyFormatter.string(payment.amount), theyOwe: lent,
                                         date: payment.paidOn.startDate(in: .current), opensTransaction: false, loanID: loan.id,
                                         record: .paymentRecord(payment.id)))
            }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// "Oct 6 · Easypaisa · Rs 15,000 left" while part of a loan is still open.
    private func loanMeta(_ meta: String, _ loan: Loan?) -> String {
        guard let loan, LoanCalculator.status(loan) == .partiallyPaid else { return meta }
        return meta + " · \(MoneyFormatter.string(LoanCalculator.outstanding(loan))) left"
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
