import SwiftUI
import UZeeCore

/// Ask UZee (SCR-03): speak or type; answers come from the data on this iPhone, and anything that would
/// save shows a card first (VOX-01…08).
struct VoiceSheet: View {
    @Bindable var session: AppSession
    @State private var model: VoiceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: VoiceModel(session: session))
    }

    static let suggestions = ["How much do I owe Ammi?", "What's my next bill?", "How much budget is left?",
                              "Spent 2,500 on groceries", "I lent 20k to a friend"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                inputBar
            }
            .background(UZColor.bg)
            .navigationTitle("Ask UZee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.cancelListening()
                        dismiss()
                    }
                    .accessibilityIdentifier("voice.close")
                }
            }
            .onAppear {
                if let request = session.voiceRequest {
                    session.voiceRequest = nil
                    model.submit(request)
                }
            }
            .onChange(of: session.voiceRequest) { _, request in
                guard let request else { return }
                session.voiceRequest = nil
                model.submit(request)
            }
            .onDisappear { model.cancelListening() }
        }
        .presentationDetents([.large])
        // .contain keeps child identifiers visible to UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.sheet")
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: UZSpacing.l) {
                    if model.lines.isEmpty && model.card == nil { intro }
                    ForEach(model.lines) { line in bubble(line).id(line.id) }
                    if model.isThinking {
                        HStack(spacing: UZSpacing.m) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(UZColor.label2)
                        }
                        .accessibilityIdentifier("voice.thinking")
                    }
                    if model.card != nil {
                        VoiceCardView(session: session, model: model).id("card")
                    }
                }
                .padding(UZSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.lines.count) {
                withAnimation {
                    if model.card != nil {
                        proxy.scrollTo("card", anchor: .bottom)
                    } else if let last = model.lines.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: UZSpacing.l) {
            UZeeLogo(size: 64, tile: true)
                .accessibilityHidden(true)
            Text("Ask about your money, or log something").font(.title3.weight(.semibold))
            Text("Everything stays on this iPhone. Nothing is saved until you check it and tap Save.")
                .font(.subheadline).foregroundStyle(UZColor.label2)
            if let problem = model.modelProblem {
                Label(problem, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(UZColor.label2)
                    .accessibilityIdentifier("voice.modelProblem")
            }
            FlowLayout(spacing: UZSpacing.m) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { model.submit(suggestion) }
                        .font(.subheadline)
                        .padding(.horizontal, UZSpacing.l)
                        .padding(.vertical, UZSpacing.s)
                        .background(UZColor.card, in: .capsule)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("voice.suggestion")
                }
            }
        }
        .padding(.top, UZSpacing.xl)
    }

    private func bubble(_ line: VoiceModel.Line) -> some View {
        HStack {
            if line.speaker == .me { Spacer(minLength: 48) }
            Text(line.text)
                .padding(.horizontal, UZSpacing.l)
                .padding(.vertical, UZSpacing.m)
                .background(line.speaker == .me ? UZColor.tint : UZColor.card,
                            in: .rect(cornerRadius: UZRadius.chip, style: .continuous))
                .foregroundStyle(line.speaker == .me ? Color.white : UZColor.label)
                .textSelection(.enabled)
                .accessibilityIdentifier(line.speaker == .me ? "voice.you" : "voice.answer")
            if line.speaker == .uzee { Spacer(minLength: 48) }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: UZSpacing.m) {
            TextField(model.isListening ? "Listening…" : "Ask or log something", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { model.submit(model.draft) }
                .padding(.horizontal, UZSpacing.l)
                .padding(.vertical, UZSpacing.m)
                .background(UZColor.card, in: .rect(cornerRadius: UZRadius.field, style: .continuous))
                .disabled(model.isListening)
                .accessibilityIdentifier("voice.input")
            if !model.draft.isEmpty && !model.isListening {
                Button {
                    model.submit(model.draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                }
                .accessibilityLabel("Send")
                .accessibilityIdentifier("voice.send")
            }
            Button {
                typing = false
                model.toggleListening()
            } label: {
                Image(systemName: model.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(model.isListening ? UZColor.negative : UZColor.tint)
                    .symbolEffect(.pulse, isActive: model.isListening)
            }
            .accessibilityLabel(model.isListening ? "Stop listening" : "Speak")
            .accessibilityIdentifier("voice.mic")
        }
        .padding(.horizontal, UZSpacing.xxl)
        .padding(.vertical, UZSpacing.m)
        .background(.bar)
    }
}

/// The confirmation card: every row can be changed before Save (VOX-07, VOX-010).
struct VoiceCardView: View {
    @Bindable var session: AppSession
    @Bindable var model: VoiceModel

    private var ledger: LedgerSnapshot { session.ledger }

    var body: some View {
        if let binding = Binding($model.card) {
            UZCard {
                VStack(alignment: .leading, spacing: UZSpacing.l) {
                    Text("Check and save").font(.headline)
                    Picker("Type", selection: binding.action) {
                        ForEach(VoiceCard.actions, id: \.self) { Text(VoiceCard.title($0)).tag($0) }
                    }
                    .accessibilityIdentifier("voiceCard.type")
                    HStack {
                        Text(ledger.account(binding.wrappedValue.accountID)?.currency.symbol ?? ledger.base.symbol)
                            .foregroundStyle(UZColor.label2)
                        TextField("0", text: binding.amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold())
                            .monospacedDigit()
                            .accessibilityLabel("Amount")
                            .accessibilityIdentifier("voiceCard.amount")
                    }
                    fields(binding)
                    DatePicker("Date", selection: binding.date, displayedComponents: .date)
                        .accessibilityIdentifier("voiceCard.date")
                    if let problem = binding.wrappedValue.problem {
                        Text(problem).font(.footnote).foregroundStyle(UZColor.negative)
                            .accessibilityIdentifier("voiceCard.problem")
                    }
                    HStack {
                        Button("Cancel", role: .cancel) { model.cancelCard() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("voiceCard.cancel")
                        Spacer()
                        Button("Save") { model.save() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("voiceCard.save")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voice.card")
        }
    }

    @ViewBuilder
    private func fields(_ card: Binding<VoiceCard>) -> some View {
        let action = card.wrappedValue.action
        if action.isLoan {
            Picker("Person", selection: personSelection(card)) {
                if let name = card.wrappedValue.newPersonName { Text("\(name) (new)").tag(UUID?.none) } else { Text("Choose").tag(UUID?.none) }
                ForEach(session.people.others) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .accessibilityIdentifier("voiceCard.person")
        }
        accountPicker(action == .transfer ? "From" : action == .income || action == .repaidToMe || action == .borrow ? "Into" : "From",
                      selection: card.accountID, identifier: "voiceCard.account")
        if action == .transfer {
            accountPicker("To", selection: card.toAccountID, identifier: "voiceCard.to")
        }
        if action == .expense || action == .income {
            NavigationLink {
                CategoryPicker(categories: ledger.categories, type: action == .income ? .income : .expense, selection: card.categoryID)
            } label: {
                LabeledContent("Category") {
                    Text(ledger.categoryPath(card.wrappedValue.categoryID) ?? "Choose")
                        .foregroundStyle(card.wrappedValue.categoryID == nil ? UZColor.label2 : UZColor.label)
                }
            }
            .accessibilityIdentifier("voiceCard.category")
            TextField(action == .income ? "From (payer)" : "Paid to (payee)", text: card.payee)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("voiceCard.payee")
        }
    }

    /// Picking someone from the list replaces a new name.
    private func personSelection(_ card: Binding<VoiceCard>) -> Binding<UUID?> {
        Binding(get: { card.wrappedValue.personID },
                set: { value in
                    card.wrappedValue.personID = value
                    if value != nil { card.wrappedValue.newPersonName = nil }
                })
    }

    private func accountPicker(_ label: String, selection: Binding<UUID?>, identifier: String) -> some View {
        Picker(label, selection: selection) {
            Text("Choose").tag(UUID?.none)
            ForEach(ledger.activeAccounts) { account in
                Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                    .tag(UUID?.some(account.id))
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
