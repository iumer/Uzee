import SwiftUI
import UZeeCore

/// The UZee helper (SCR-03): talk to it like Siri, or type. It answers aloud from the data on this iPhone and
/// keeps listening until you're done; anything that would save shows a card first (VOX-01…08).
struct VoiceSheet: View {
    @Bindable var session: AppSession
    @State private var model: VoiceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool

    init(session: AppSession) {
        self.session = session
        _model = State(initialValue: VoiceModel(session: session))
    }

    static let suggestions = ["How am I doing this month?", "Spent 2,500 on groceries", "What did I spend on Foodpanda?",
                              "How much do I owe Ammi?", "I lent 20k to a friend", "What's my next bill?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                if !model.lines.isEmpty, model.handsFree || mood != .idle {
                    HStack(spacing: UZSpacing.m) {
                        HelperOrb(mood: mood, size: 30)
                            .frame(width: 48, height: 48)
                        Text(status).font(.subheadline).foregroundStyle(UZColor.label2).lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, UZSpacing.xxl)
                    .contentShape(.rect)
                    .onTapGesture { model.toggleListening() }
                    .accessibilityIdentifier("voice.statusBar")
                }
                inputBar
            }
            .background(UZColor.bg)
            .navigationTitle("UZee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        model.cancelListening()
                        dismiss()
                    }
                    .accessibilityIdentifier("voice.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.muted.toggle()
                        if model.muted { session.smart.stopSpeaking() }
                    } label: {
                        Image(systemName: model.muted ? "speaker.slash" : "speaker.wave.2")
                    }
                    .accessibilityLabel(model.muted ? "Speak replies" : "Mute replies")
                    .accessibilityIdentifier("voice.mute")
                }
            }
            .onAppear {
                if let request = session.voiceRequest {
                    session.voiceRequest = nil
                    model.submit(request)
                } else {
                    model.begin()
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
                    if model.isListening, !model.draft.isEmpty, !model.lines.isEmpty {
                        // What UZee is hearing, live.
                        HStack {
                            Spacer(minLength: 48)
                            Text(model.draft)
                                .padding(.horizontal, UZSpacing.l)
                                .padding(.vertical, UZSpacing.m)
                                .background(UZColor.tint.opacity(0.35), in: .rect(cornerRadius: UZRadius.chip, style: .continuous))
                                .foregroundStyle(Color.white)
                        }
                        .id("live")
                    }
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
            .onChange(of: model.card != nil) { _, shown in
                // Drop the keyboard so the whole card, Save included, is on screen.
                guard shown else { return }
                typing = false
                withAnimation { proxy.scrollTo("card", anchor: .bottom) }
            }
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

    private var mood: HelperOrb.Mood {
        model.isSpeaking ? .speaking : model.isThinking ? .thinking : model.isListening ? .listening : .idle
    }

    private var status: String {
        switch mood {
        case .listening: model.draft.isEmpty ? "Listening…" : model.draft
        case .thinking: "Thinking…"
        case .speaking: "Tap to interrupt"
        case .idle: "Tap the orb and talk, or type below"
        }
    }

    private var intro: some View {
        VStack(spacing: UZSpacing.l) {
            Button { model.toggleListening() } label: { HelperOrb(mood: mood, size: 120) }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isListening ? "Stop listening" : "Talk to UZee")
                .accessibilityIdentifier("voice.orb")
            Text(status)
                .font(model.isListening && !model.draft.isEmpty ? .title3.weight(.medium) : .headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(model.isListening && !model.draft.isEmpty ? UZColor.label : UZColor.label2)
                .animation(.easeOut(duration: 0.15), value: status)
                .accessibilityIdentifier("voice.status")
            Text("Ask about your money, log spending, loans or transfers, or find a transaction. Everything stays on this iPhone, and nothing is saved until you say yes.")
                .font(.subheadline).foregroundStyle(UZColor.label2).multilineTextAlignment(.center)
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
        .frame(maxWidth: .infinity)
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
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.78, blue: 0.55), Color(red: 0.25, green: 0.55, blue: 0.98)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                        .shadow(color: mood == .idle ? .clear : Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.6), radius: 10)
                    Image(systemName: model.isSpeaking ? "speaker.wave.2.fill" : model.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: model.isListening || model.isSpeaking)
                }
            }
            .accessibilityLabel(model.isSpeaking ? "Stop speaking" : model.isListening ? "Stop listening" : "Talk to UZee")
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
        if let current = model.card {
            // Not `Binding($model.card)`: that force-unwraps, and Save clears the card while these
            // fields are still on screen, which crashed the app.
            let binding = Binding<VoiceCard>(get: { model.card ?? current },
                                             set: { value in if model.card != nil { model.card = value } })
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
                      selection: card.accountID, identifier: "voiceCard.account",
                      none: action == .lend || action == .borrow ? "No account, just a record" : "Choose")
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

    private func accountPicker(_ label: String, selection: Binding<UUID?>, identifier: String, none: String = "Choose") -> some View {
        Picker(label, selection: selection) {
            Text(none).tag(UUID?.none)
            ForEach(ledger.activeAccounts) { account in
                Text(account.currency == ledger.base ? account.name : "\(account.name) (\(account.currency.code))")
                    .tag(UUID?.some(account.id))
            }
        }
        .accessibilityIdentifier(identifier)
    }
}
