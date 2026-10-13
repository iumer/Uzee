import SwiftUI
import UZeeCore

/// Imported rows that aren't really spending or income (BUG-022, F3, F4):
/// - money moved between your own accounts, seen on both statements: becomes one transfer;
/// - cash taken out at an ATM: becomes a transfer into Cash, spending only once you spend it;
/// - money sent to your own account whose other side isn't in UZee: a transfer when the account is known, else a
///   balance change marked "Moved to my own account".
/// Balances stay the same in every case; only spending and income change.
struct OwnMoneyReview {
    var pairs: [TransferMatcher.Pair] = []
    var cash: [TransferMatcher.Entry] = []
    var moves: [TransferMatcher.Move] = []

    var isEmpty: Bool { pairs.isEmpty && cash.isEmpty && moves.isEmpty }
    var count: Int { pairs.count + cash.count + moves.count }

    /// Ticked to start with: pairs and moves that name you or your accounts on both sides, and every ATM withdrawal.
    var sure: Set<UUID> {
        Set(pairs.filter(\.isSure).map(\.out.id) + cash.map(\.id) + moves.filter(\.isSure).map(\.entry.id))
    }
}

extension AppSession {
    /// Imported spending and income only; rows shared with people or groups are left alone.
    func ownMoneyReview() -> OwnMoneyReview {
        let entries: [TransferMatcher.Entry] = transactions.compactMap { transaction in
            guard transaction.deletedAt == nil, transaction.source == .import, transaction.counterpartyID == nil,
                  transaction.groupID == nil, transaction.kind == .expense || transaction.kind == .income,
                  transaction.legs.count == 1, let leg = transaction.legs.first else { return nil }
            let text = [transaction.payeeName, transaction.note].compactMap { $0 }.joined(separator: " ")
            return TransferMatcher.Entry(id: transaction.id, accountID: leg.accountID, date: transaction.localDate,
                                         amount: leg.amount, text: text)
        }
        let names = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0.name) })
        let owner = TransferMatcher.likelyOwnerWords(entries, accountNames: names)
        let pairs = TransferMatcher.pairs(entries, accountNames: names, ownerWords: owner)
        let used = Set(pairs.flatMap { [$0.out.id, $0.into.id] })
        let cash = TransferMatcher.cashWithdrawals(entries)
        let moves = TransferMatcher.moves(entries, excluding: used, accountNames: names, ownerWords: owner)
        return OwnMoneyReview(pairs: pairs, cash: cash, moves: moves)
    }

    /// Saves the ticked rows as transfers (or "moved to my own account") and moves the originals to Recently
    /// Deleted. Nothing changes when any of them fails. Returns what Undo needs.
    func applyOwnMoney(_ review: OwnMoneyReview, chosen: Set<UUID>) -> (made: [UUID], replaced: [UUID])? {
        var made: [UUID] = []
        var replaced: [UUID] = []
        do {
            for pair in review.pairs where chosen.contains(pair.out.id) {
                try save(transferFrom: pair.out, to: pair.into.accountID, made: &made)
                try client.delete(pair.out.id)
                replaced.append(pair.out.id)
                try client.delete(pair.into.id)
                replaced.append(pair.into.id)
            }
            let cash = review.cash.filter { chosen.contains($0.id) }
            for entry in cash {
                let cashAccount = try cashAccount(entry.amount.currency, since: cash.map(\.date).min() ?? entry.date)
                try save(transferFrom: entry, to: cashAccount, made: &made)
                try client.delete(entry.id)
                replaced.append(entry.id)
            }
            for move in review.moves where chosen.contains(move.entry.id) {
                if let target = move.toAccountID {
                    try save(transferFrom: move.entry, to: target, made: &made)
                } else {
                    try saveMovedOut(move.entry, made: &made)
                }
                try client.delete(move.entry.id)
                replaced.append(move.entry.id)
            }
        } catch {
            undoTransfers(made: made, replaced: replaced)
            errorMessage = "Couldn't change them. Nothing was changed."
            return nil
        }
        reload()
        return (made, replaced)
    }

    /// Puts the spending and income back and removes what replaced them.
    func undoTransfers(made: [UUID], replaced: [UUID]) {
        for id in made { try? client.discard(id) }
        for id in replaced { try? activity.restore(id) }
        reload()
    }

    private func save(transferFrom entry: TransferMatcher.Entry, to account: UUID, made: inout [UUID]) throws {
        let magnitude = try entry.amount.magnitude()
        let row = transactions.first { $0.id == entry.id }
        let draft = TransactionDraft(kind: .transfer, amount: magnitude, accountID: entry.accountID, toAccountID: account,
                                     note: note(row), occurredAt: occurred(row, entry), source: .import)
        let transfer = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base)
        try client.save(transfer)
        made.append(transfer.id)
    }

    /// Out of the account to one of yours that isn't in UZee: the balance goes down, but it isn't spending.
    private func saveMovedOut(_ entry: TransferMatcher.Entry, made: inout [UUID]) throws {
        let magnitude = try entry.amount.magnitude()
        let row = transactions.first { $0.id == entry.id }
        let text = "Moved to my own account" + (note(row).map { ": \($0)" } ?? "")
        let draft = TransactionDraft(kind: .adjustment, amount: magnitude, accountID: entry.accountID, adjustmentIncreases: false,
                                     note: String(text.prefix(TransactionValidator.maxNoteLength)),
                                     occurredAt: occurred(row, entry), source: .import)
        let adjustment = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base)
        try client.save(adjustment)
        made.append(adjustment.id)
    }

    /// Your Cash account in that currency, added (empty) when there isn't one.
    private func cashAccount(_ currency: Currency, since day: LocalDate) throws -> UUID {
        if let existing = ledger.activeAccounts.first(where: { $0.kind == .cash && $0.currency == currency }) { return existing.id }
        let name = currency == ledger.base ? "Cash" : "Cash \(currency.code)"
        let account = try client.createAccount(.init(name: name, kind: .cash, currency: currency,
                                                     openingBalance: Money(minorUnits: 0, currency: currency),
                                                     openingDate: day.addingDays(-1), includeInTotals: true))
        reload()
        return account.id
    }

    private func note(_ row: MoneyTransaction?) -> String? {
        [row?.payeeName, row?.note].compactMap { $0 }.first { !$0.isEmpty }.map { String($0.prefix(TransactionValidator.maxNoteLength)) }
    }

    private func occurred(_ row: MoneyTransaction?, _ entry: TransferMatcher.Entry) -> Date {
        row?.occurredAt ?? entry.date.startDate(in: .current).addingTimeInterval(12 * 3_600)
    }
}

/// The rows to tick, in three groups.
struct OwnMoneyRows: View {
    let session: AppSession
    let review: OwnMoneyReview
    @Binding var chosen: Set<UUID>

    var body: some View {
        if !review.pairs.isEmpty {
            Section("Between your accounts") {
                ForEach(review.pairs, id: \.out.id) { pair in
                    row(id: pair.out.id, title: "\(name(pair.out.accountID)) → \(name(pair.into.accountID))", amount: pair.into.amount,
                        date: pair.out.date == pair.into.date ? DateText.short(pair.out.date)
                            : "\(DateText.short(pair.out.date)) → \(DateText.short(pair.into.date))",
                        lines: ["Out: \(pair.out.text)", "In: \(pair.into.text)"],
                        warning: pair.isSure ? nil : "Only one side says it's yours. Tick it if it is.")
                }
            }
        }
        if !review.cash.isEmpty {
            Section {
                ForEach(review.cash, id: \.id) { entry in
                    row(id: entry.id, title: "\(name(entry.accountID)) → Cash", amount: entry.amount,
                        date: DateText.short(entry.date), lines: [entry.text], warning: nil)
                }
            } header: {
                Text("Cash from ATMs")
            } footer: {
                Text("Moved into your Cash account. It counts as spending when you add what you spent it on.")
            }
        }
        if !review.moves.isEmpty {
            Section {
                ForEach(review.moves, id: \.entry.id) { move in
                    row(id: move.entry.id, title: "\(name(move.entry.accountID)) → \(move.toAccountID.map(name) ?? "your other account")",
                        amount: move.entry.amount, date: DateText.short(move.entry.date), lines: [move.entry.text],
                        warning: move.isSure ? nil : "Doesn't name you. Tick it if this account is yours.")
                }
            } header: {
                Text("To your other accounts")
            } footer: {
                Text("The other side isn't in UZee yet. Left out of spending; the balance stays the same.")
            }
        }
    }

    private func row(id: UUID, title: String, amount: Money, date: String, lines: [String], warning: String?) -> some View {
        let isOn = chosen.contains(id)
        return Button {
            if isOn { chosen.remove(id) } else { chosen.insert(id) }
        } label: {
            HStack(alignment: .top, spacing: UZSpacing.l) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isOn ? UZColor.tint : UZColor.label3)
                VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                    HStack {
                        Text(title).font(.body.weight(.medium)).foregroundStyle(UZColor.label).lineLimit(1)
                        Spacer()
                        Text(MoneyFormatter.string((try? amount.magnitude()) ?? amount))
                            .font(.body.weight(.medium)).monospacedDigit().foregroundStyle(UZColor.label)
                    }
                    Text(date).font(.caption).foregroundStyle(UZColor.label2)
                    ForEach(lines, id: \.self) { Text($0).font(.caption).foregroundStyle(UZColor.label2).lineLimit(2) }
                    if let warning {
                        Text(warning).font(.caption).foregroundStyle(UZColor.warning)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("transfers.row")
    }

    private func name(_ id: UUID) -> String { session.ledger.account(id)?.name ?? "Account" }
}

/// Settings › Transfers & ATM cash: the same check over everything imported so far.
struct OwnTransfersView: View {
    @Bindable var session: AppSession
    @State private var review = OwnMoneyReview()
    @State private var chosen: Set<UUID> = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && review.isEmpty {
                ContentUnavailableView("Nothing to fix", systemImage: "checkmark.circle",
                                       description: Text("Moves between your accounts and ATM cash are already left out of spending."))
                    .accessibilityIdentifier("transfers.none")
            } else if !review.isEmpty {
                Section {
                    Text("These were imported as spending or income, but the money stayed yours. Tick them and tap Make at the top. Balances stay the same; they leave your spending.")
                        .font(.footnote).foregroundStyle(UZColor.label2)
                }
                OwnMoneyRows(session: session, review: review, chosen: $chosen)
            }
        }
        // The button sits in the top bar: this screen is pushed inside a tab, so a bottom button would sit under
        // the floating +, tab bar and UZee and taps would go to them (BUG-024).
        .toolbar {
            if !review.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Make" : "Make \(chosen.count)", action: convert)
                        .disabled(chosen.isEmpty)
                        .accessibilityIdentifier("transfers.make")
                }
            }
        }
        // Room under the last row to scroll it clear of the floating bar.
        .contentMargins(.bottom, 140, for: .scrollContent)
        .navigationTitle("Transfers & ATM cash")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        review = session.ownMoneyReview()
        chosen = review.sure
        loaded = true
    }

    private func convert() {
        guard let result = session.applyOwnMoney(review, chosen: chosen) else { return }
        let count = chosen.count
        session.toasts.show(count == 1 ? "Changed 1 row" : "Changed \(count) rows") { [session] in
            session.undoTransfers(made: result.made, replaced: result.replaced)
        }
        load()
    }
}
