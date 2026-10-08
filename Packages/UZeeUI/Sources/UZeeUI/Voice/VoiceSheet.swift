import SwiftUI
import UZeeCore

/// The UZee helper (SCR-03): type, or tap the singing mic for voice mode, where a big orb at the bottom glows
/// while you talk, spins while UZee thinks and pulses while it answers aloud. Anything that would save shows a
/// card first (VOX-01…08). Chats are kept, with earlier ones under Past chats.
struct VoiceSheet: View {
    @Bindable var session: AppSession
    @State private var model: VoiceModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var showsPast = false
    /// UZee dozes for a moment when the sheet opens, then wakes up to listen.
    @State private var asleep = true

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
                if model.voiceMode {
                    voicePanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    inputBar
                }
            }
            .animation(.spring(duration: 0.4), value: model.voiceMode)
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
                    Menu {
                        Button("New chat", systemImage: "square.and.pencil") { model.newChat() }
                            .disabled(model.lines.isEmpty)
                            .accessibilityIdentifier("voice.newChat")
                        Button("Past chats", systemImage: "clock.arrow.circlepath") { showsPast = true }
                            .accessibilityIdentifier("voice.pastChats")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Chats")
                    .accessibilityIdentifier("voice.menu")
                }
            }
            .sheet(isPresented: $showsPast) {
                PastChatsView(model: model)
            }
            .onAppear {
                if let request = session.voiceRequest {
                    session.voiceRequest = nil
                    asleep = false
                    model.submit(request)
                } else {
                    wakeUp()
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
                    if model.isThinking, !model.voiceMode {
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

    /// The caption under the voice orb.
    private var status: String {
        switch mood {
        case .listening: model.liveText.isEmpty ? "Listening…" : model.liveText
        case .thinking: "Thinking…"
        case .speaking: model.lines.last { $0.speaker == .uzee }?.text ?? "Tap to interrupt"
        case .idle: model.card != nil ? "Say yes to save, or tap the orb to talk" : "Tap UZee to talk"
        }
    }

    private var intro: some View {
        VStack(spacing: UZSpacing.l) {
            if !model.voiceMode {
                Button { model.startVoice() } label: { HelperOrb(mood: mood, size: 110) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Talk to UZee")
                    .accessibilityIdentifier("voice.orb")
                Text("Hi, I'm UZee")
                    .font(.title2.bold())
                    .accessibilityIdentifier("voice.status")
            }
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
            TextField("Ask or log something", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { model.submit(model.draft) }
                .padding(.horizontal, UZSpacing.l)
                .padding(.vertical, UZSpacing.m)
                .background(UZColor.card, in: .rect(cornerRadius: UZRadius.field, style: .continuous))
                .accessibilityIdentifier("voice.input")
            if !model.draft.isEmpty {
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
                model.startVoice()
            } label: {
                SingingMic(size: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk instead")
            .accessibilityIdentifier("voice.mic")
        }
        .padding(.horizontal, UZSpacing.xxl)
        .padding(.vertical, UZSpacing.m)
        .background(.bar)
    }

    // MARK: Voice mode

    /// Replaces the typing bar while talking: a caption of what's heard or said, the big orb, mute and close.
    private var voicePanel: some View {
        VStack(spacing: UZSpacing.m) {
            Text(status)
                .font(mood == .listening && !model.liveText.isEmpty ? .title3.weight(.medium) : .headline)
                .foregroundStyle(mood == .idle || mood == .thinking ? UZColor.label2 : UZColor.label)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, UZSpacing.xxl)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: status)
                .opacity(asleep ? 0 : 1)
                .accessibilityIdentifier("voice.caption")
            if model.isThinking {
                // Kept for UI tests and VoiceOver.
                Text("Thinking…").font(.caption2).opacity(0.01).accessibilityIdentifier("voice.thinking")
            }
            HStack {
                roundButton("keyboard", label: "Type instead", identifier: "voice.keyboard") {
                    asleep = false
                    model.endVoice()
                }
                Spacer()
                Button {
                    if asleep {
                        withAnimation(.spring(duration: 0.5, bounce: 0.45)) { asleep = false }
                        model.startVoice()
                    } else {
                        model.toggleListening()
                    }
                } label: {
                    VoiceBlob(mood: mood, size: 130, level: session.smart.listeningLevel, asleep: asleep)
                        .offset(y: asleep ? 24 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isSpeaking ? "Stop speaking" : model.isListening ? "Done talking" : "Talk")
                .accessibilityIdentifier("voice.blob")
                Spacer()
                roundButton(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            label: model.muted ? "Speak replies" : "Mute replies", identifier: "voice.mute") {
                    model.muted.toggle()
                    if model.muted { session.smart.stopSpeaking() }
                }
            }
            .padding(.horizontal, UZSpacing.xxl)
        }
        .padding(.bottom, UZSpacing.m)
        .background(alignment: .bottom) {
            LinearGradient(colors: [UZColor.bg.opacity(0), Color(red: 0.25, green: 0.55, blue: 0.98).opacity(0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// Opening Ask UZee: the dozing UZee wakes up with a bounce, then listens (when the mic is already allowed;
    /// otherwise the first tap asks for it).
    private func wakeUp() {
        guard model.voiceMode, asleep else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.spring(duration: 0.55, bounce: 0.5)) { asleep = false }
            try? await Task.sleep(for: .milliseconds(300))
            if session.smart.canListen(), model.voiceMode, !model.isListening, !model.isThinking { model.startVoice() }
        }
    }

    private func roundButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(UZColor.card, in: .circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(UZColor.label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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
                      none: action.isLoan ? "No account, just a record" : "Choose")
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

/// Earlier Ask UZee chats, newest first; open one to read it, swipe to delete.
struct PastChatsView: View {
    @Bindable var model: VoiceModel
    @Environment(\.dismiss) private var dismiss
    @State private var chats: [VoiceHistory.Chat] = []

    var body: some View {
        NavigationStack {
            List {
                if chats.isEmpty {
                    Text("No earlier chats yet. When you start a new chat, or come back the next day, the last one is kept here.")
                        .foregroundStyle(UZColor.label2)
                }
                ForEach(chats) { chat in
                    NavigationLink {
                        PastChatView(chat: chat)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title).lineLimit(1)
                            Text(chat.started.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote).foregroundStyle(UZColor.label2)
                        }
                    }
                    .accessibilityIdentifier("voice.pastChat")
                }
                .onDelete { offsets in
                    for index in offsets { model.deleteChat(chats[index].id) }
                    chats.remove(atOffsets: offsets)
                }
            }
            .navigationTitle("Past chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { chats = model.pastChats }
        }
    }
}

/// One earlier chat, read-only.
struct PastChatView: View {
    let chat: VoiceHistory.Chat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UZSpacing.l) {
                ForEach(chat.lines) { line in
                    HStack {
                        if line.speaker == .me { Spacer(minLength: 48) }
                        Text(line.text)
                            .padding(.horizontal, UZSpacing.l)
                            .padding(.vertical, UZSpacing.m)
                            .background(line.speaker == .me ? UZColor.tint : UZColor.card,
                                        in: .rect(cornerRadius: UZRadius.chip, style: .continuous))
                            .foregroundStyle(line.speaker == .me ? Color.white : UZColor.label)
                            .textSelection(.enabled)
                        if line.speaker == .uzee { Spacer(minLength: 48) }
                    }
                }
            }
            .padding(UZSpacing.xxl)
        }
        .background(UZColor.bg)
        .navigationTitle(chat.started.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
