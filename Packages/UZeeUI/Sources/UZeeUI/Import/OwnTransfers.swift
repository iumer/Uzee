import SwiftUI
import UZeeCore

/// Money moved between your own accounts, imported from both statements as spending in one and income in the other
/// (BUG-022). UZee finds the pairs, you tick them, and each becomes one transfer: balances stay the same, but it no
/// longer counts as spending or income.
extension AppSession {
    /// Imported spending and income that look like the two sides of one transfer. Rows shared with people or groups
    /// are left alone.
    func ownTransferPairs() -> [TransferMatcher.Pair] {
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
        return TransferMatcher.pairs(entries, accountNames: names, ownerWords: owner)
    }

    /// Turns each pair into one transfer and moves the two rows to Recently Deleted. Nothing changes when any of
    /// them fails. Returns what Undo needs: the transfers made and the rows they replaced.
    func makeTransfers(_ pairs: [TransferMatcher.Pair]) -> (made: [UUID], replaced: [UUID])? {
        var made: [UUID] = []
        var replaced: [UUID] = []
        do {
            for pair in pairs {
                guard let magnitude = try? pair.into.amount.magnitude() else { continue }
                let outRow = transactions.first { $0.id == pair.out.id }
                let note = [outRow?.payeeName, outRow?.note].compactMap { $0 }.first { !$0.isEmpty }
                let draft = TransactionDraft(kind: .transfer, amount: magnitude, accountID: pair.out.accountID,
                                             toAccountID: pair.into.accountID,
                                             note: note.map { String($0.prefix(TransactionValidator.maxNoteLength)) },
                                             occurredAt: outRow?.occurredAt ?? pair.out.date.startDate(in: .current).addingTimeInterval(12 * 3_600),
                                             source: .import)
                let transfer = try TransactionValidator.build(draft, accounts: ledger.accounts, base: ledger.base)
                try client.save(transfer)
                made.append(transfer.id)
                try client.delete(pair.out.id)
                replaced.append(pair.out.id)
                try client.delete(pair.into.id)
                replaced.append(pair.into.id)
            }
        } catch {
            undoTransfers(made: made, replaced: replaced)
            errorMessage = "Couldn't change them to transfers. Nothing was changed."
            return nil
        }
        reload()
        return (made, replaced)
    }

    /// Puts the spending and income back and removes the transfers.
    func undoTransfers(made: [UUID], replaced: [UUID]) {
        for id in made { try? client.discard(id) }
        for id in replaced { try? activity.restore(id) }
        reload()
    }
}

/// The pairs to tick: "HBL → NayaPay · Rs 5,000 · 3 Oct", with both statement lines.
struct OwnTransferRows: View {
    let session: AppSession
    let pairs: [TransferMatcher.Pair]
    @Binding var chosen: Set<UUID>

    var body: some View {
        ForEach(pairs, id: \.out.id) { pair in
            let isOn = chosen.contains(pair.out.id)
            Button {
                if isOn { chosen.remove(pair.out.id) } else { chosen.insert(pair.out.id) }
            } label: {
                HStack(alignment: .top, spacing: UZSpacing.l) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(isOn ? UZColor.tint : UZColor.label3)
                    VStack(alignment: .leading, spacing: UZSpacing.xxs) {
                        HStack {
                            Text("\(name(pair.out.accountID)) → \(name(pair.into.accountID))")
                                .font(.body.weight(.medium)).foregroundStyle(UZColor.label).lineLimit(1)
                            Spacer()
                            Text(MoneyFormatter.string((try? pair.into.amount.magnitude()) ?? pair.into.amount))
                                .font(.body.weight(.medium)).monospacedDigit().foregroundStyle(UZColor.label)
                        }
                        Text(pair.out.date == pair.into.date ? DateText.short(pair.out.date)
                             : "\(DateText.short(pair.out.date)) → \(DateText.short(pair.into.date))")
                            .font(.caption).foregroundStyle(UZColor.label2)
                        Text("Out: \(pair.out.text)").font(.caption).foregroundStyle(UZColor.label2).lineLimit(2)
                        Text("In: \(pair.into.text)").font(.caption).foregroundStyle(UZColor.label2).lineLimit(2)
                        if !pair.isSure {
                            Text("Only one side says it's yours. Tick it if it is.").font(.caption).foregroundStyle(UZColor.warning)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
            .accessibilityIdentifier("transfers.row")
        }
    }

    private func name(_ id: UUID) -> String { session.ledger.account(id)?.name ?? "Account" }
}

/// Settings › Transfers between my accounts: the same check over everything imported so far.
struct OwnTransfersView: View {
    @Bindable var session: AppSession
    @State private var pairs: [TransferMatcher.Pair] = []
    @State private var chosen: Set<UUID> = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && pairs.isEmpty {
                ContentUnavailableView("No transfers to fix", systemImage: "checkmark.circle",
                                       description: Text("Money moved between your own accounts is already saved as transfers."))
                    .accessibilityIdentifier("transfers.none")
            } else if !pairs.isEmpty {
                Section {
                    OwnTransferRows(session: session, pairs: pairs, chosen: $chosen)
                } footer: {
                    Text("These were imported from both statements, so they count as spending and income. Tick the ones that are yours and tap Make at the top. As transfers, balances stay the same but they leave your spending.")
                }
            }
        }
        // The button sits in the top bar: this screen is pushed inside a tab, so a bottom button would sit under
        // the floating +, tab bar and UZee and taps would go to them (BUG-024).
        .toolbar {
            if !pairs.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.isEmpty ? "Make" : "Make \(chosen.count)", action: convert)
                        .disabled(chosen.isEmpty)
                        .accessibilityIdentifier("transfers.make")
                }
            }
        }
        // Room under the last row to scroll it clear of the floating bar.
        .contentMargins(.bottom, 140, for: .scrollContent)
        .navigationTitle("Transfers between my accounts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        pairs = session.ownTransferPairs()
        chosen = Set(pairs.filter(\.isSure).map(\.out.id))
        loaded = true
    }

    private func convert() {
        let picked = pairs.filter { chosen.contains($0.out.id) }
        guard let result = session.makeTransfers(picked) else { return }
        session.toasts.show(result.made.count == 1 ? "Made 1 transfer" : "Made \(result.made.count) transfers") { [session] in
            session.undoTransfers(made: result.made, replaced: result.replaced)
        }
        load()
    }
}
