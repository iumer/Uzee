import SwiftUI
import UZeeCore

/// Settings → Exchange rate (owner, 2026-10-19). Add, Delete and Update at the top; then the rate UZee uses for
/// totals (Wise's live rate), then each money service (Google, NayaPay, Western Union…) with its rate for every
/// currency pair (USD → PKR, SAR → PKR, EUR → USD…). Add asks for a service's name and looks its rates up online;
/// a service that doesn't publish them keeps the rates you type for it.
struct ExchangeRateView: View {
    @Bindable var session: AppSession
    @State private var services: [RateService] = []
    @State private var pairs: [RatePair] = []
    /// Rates by "serviceID|pairID"; missing while loading, .some(nil) when it couldn't be read.
    @State private var values: [String: Decimal?] = [:]
    @State private var loading = false
    @State private var isFetchingWise = false
    @State private var updated: Date?
    @State private var problem: String?
    @State private var deleting = false
    @State private var addingService = false
    @State private var addingPair = false
    @State private var typing: TypedRate?

    private var base: Currency { session.ledger.base }

    var body: some View {
        List {
            Section {
                HStack(spacing: UZSpacing.m) {
                    Menu {
                        Button("Add a money service", systemImage: "building.columns") { addingService = true }
                            .accessibilityIdentifier("rate.addService")
                        Button("Add a currency pair", systemImage: "arrow.left.arrow.right") { addingPair = true }
                            .accessibilityIdentifier("rate.addPair")
                    } label: {
                        Label("Add", systemImage: "plus").frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("rate.add")
                    Button { withAnimation { deleting.toggle() } } label: {
                        Label(deleting ? "Done" : "Delete", systemImage: deleting ? "checkmark" : "trash").frame(maxWidth: .infinity)
                    }
                    .tint(deleting ? UZColor.tint : UZColor.negative)
                    .accessibilityIdentifier("rate.delete")
                    Button { Task { await updateAll() } } label: {
                        Label("Update", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .disabled(loading || isFetchingWise)
                    .accessibilityIdentifier("rate.update")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .font(.subheadline.weight(.semibold))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if deleting { Text("Tap the red button next to a service or a currency pair to delete it.") }
            }
            Section {
                ForEach(pairs) { pair in
                    HStack {
                        if deleting {
                            Button { delete(pair) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(UZColor.negative)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(pair.from) to \(pair.to)")
                            .accessibilityIdentifier("rate.deletePair.\(pair.id)")
                        }
                        Text("\(pair.from) → \(pair.to)")
                    }
                }
            } header: {
                Text("Currency pairs")
            } footer: {
                Text("Each service below shows these pairs. Add one with Add › Add a currency pair, like SAR → PKR or EUR → USD.")
            }
            // Wise's live rate, the one UZee uses for totals, shown per pair like the services below.
            Section {
                ForEach(pairs) { pair in row(Self.wise, pair) }
            } header: {
                Text("Wise")
            } footer: {
                Text((updated.map { "Updated \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? "")
                     + "Wise's live rate, refreshed when you open UZee. Entries for past days use that day's rate.")
            }
            ForEach(services.filter { $0.source != .wise }) { service in
                Section {
                    ForEach(pairs) { pair in row(service, pair) }
                } header: {
                    HStack {
                        if deleting {
                            Button { delete(service) } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(UZColor.negative)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(service.name)")
                            .accessibilityIdentifier("rate.deleteService.\(service.name)")
                        }
                        Text(service.name)
                    }
                } footer: {
                    Text(footer(service))
                }
            }
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear {
            // The Wise switch is gone (owner, 2026-10-19): totals always use Wise's live rate.
            if !session.usesWiseRates { session.usesWiseRates = true }
            services = session.rateServices
            pairs = session.ratePairs
            updated = session.wiseRatesUpdated
        }
        .task { await loadRates() }
        .sheet(isPresented: $addingService) {
            AddRateServiceSheet(session: session, pairs: pairs, existing: services.map(\.name)) { service in
                services.append(service)
                session.rateServices = services
                Task { await loadRates() }
            }
        }
        .sheet(isPresented: $addingPair) {
            AddRatePairSheet(existing: pairs) { pair in
                pairs.append(pair)
                session.ratePairs = pairs
                Task { await loadRates() }
            }
        }
        .alert(typing.map { "\($0.serviceName): 1 \($0.pair.from) in \($0.pair.to)" } ?? "", isPresented: Binding(
            get: { typing != nil }, set: { if !$0 { typing = nil } })) {
            TextField("Rate", text: Binding(get: { typing?.text ?? "" }, set: { typing?.text = $0 }))
                .keyboardType(.decimalPad)
            Button("Save") { saveTyped() }
            Button("Cancel", role: .cancel) { typing = nil }
        } message: {
            Text("Type the rate it shows in its app.")
        }
    }

    @ViewBuilder
    private func row(_ service: RateService, _ pair: RatePair) -> some View {
        let label = "\(pair.from) 1 → \(pair.to)"
        if service.source == .typed {
            // Plain text like the other rows (owner, 2026-10-19: no blue links); tap the row to type a rate.
            Button {
                typing = TypedRate(serviceID: service.id, serviceName: service.name, pair: pair,
                                   text: service.typed[pair.id].map(ExchangeRate.storageString) ?? "")
            } label: {
                LabeledContent {
                    HStack(spacing: UZSpacing.s) {
                        if let rate = service.typed[pair.id] {
                            Text(display(rate, pair)).monospacedDigit().foregroundStyle(UZColor.label)
                        } else {
                            // Nothing typed yet: Google's rate, said plainly, so the row is never empty.
                            Text(googleText(pair) + " (Google)").monospacedDigit().foregroundStyle(UZColor.label2)
                        }
                        Image(systemName: "pencil").font(.caption).foregroundStyle(UZColor.label3)
                    }
                } label: {
                    Text(label).foregroundStyle(UZColor.label)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rate.\(service.name).\(pair.id)")
        } else {
            LabeledContent(label) {
                if let value = values[key(service, pair)] {
                    if let rate = value { Text(display(rate, pair)).monospacedDigit() } else { Text("Couldn't load").foregroundStyle(UZColor.label2) }
                } else if loading {
                    ProgressView()
                } else {
                    Text("—")
                }
            }
            .accessibilityIdentifier("rate.\(service.name).\(pair.id)")
        }
    }

    private func footer(_ service: RateService) -> String {
        switch service.source {
        case .market: "The mid-market rate Google shows. For comparing; totals use Wise's rate above."
        case .wise: "Wise's live rate."
        case .westernUnion: "Western Union's live rate for sending money."
        case .typed: "\(service.name) doesn't publish its rates online. Tap a rate to type what its app shows; until then it shows Google's rate."
        }
    }

    private func key(_ service: RateService, _ pair: RatePair) -> String { service.id + "|" + pair.id }

    private func display(_ rate: Decimal, _ pair: RatePair) -> String {
        (pair.toCurrency?.symbol ?? pair.to) + " " + ExchangeRate.display(rate)
    }

    private static let google = RateService(id: "google", name: "Google", source: .market)
    private static let wise = RateService(id: "wise", name: "Wise", source: .wise)

    private func googleText(_ pair: RatePair) -> String {
        let google = services.first { $0.source == .market } ?? Self.google
        guard let value = values[key(google, pair)], let rate = value else { return loading ? "…" : "—" }
        return display(rate, pair)
    }

    private func one(_ currency: Currency) -> String {
        currency.symbol + (currency.symbolNeedsSpace ? " " : "") + "1"
    }

    /// Live rates for every service and pair; Google's are always fetched so typed services can fall back to them.
    private func loadRates() async {
        guard !loading else { return }
        loading = true
        values = [:]
        var targets = services.filter { $0.source != .typed && $0.source != .wise } + [Self.wise]
        if !targets.contains(where: { $0.source == .market }) { targets.append(Self.google) }
        for service in targets {
            for pair in pairs {
                values[key(service, pair)] = .some(await session.liveRate(service, pair))
            }
        }
        loading = false
    }

    private func updateAll() async {
        problem = nil
        isFetchingWise = true
        let got = await session.refreshWiseRates(force: true)
        isFetchingWise = false
        updated = session.wiseRatesUpdated
        if !got { problem = "Couldn't reach Wise. UZee keeps the last rate and tries again later." }
        await loadRates()
        if got { session.toasts.show("Rates updated") }
    }

    private func delete(_ service: RateService) {
        let before = services
        services.removeAll { $0.id == service.id }
        session.rateServices = services
        session.toasts.show("\(service.name) deleted") {
            services = before
            session.rateServices = before
        }
    }

    private func delete(_ pair: RatePair) {
        let before = pairs
        pairs.removeAll { $0.id == pair.id }
        session.ratePairs = pairs
        session.toasts.show("\(pair.from) → \(pair.to) deleted") {
            pairs = before
            session.ratePairs = before
        }
    }

    private func saveTyped() {
        guard let typing, let index = services.firstIndex(where: { $0.id == typing.serviceID }) else { return }
        let text = typing.text.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            services[index].typed[typing.pair.id] = nil
        } else if let rate = try? ExchangeRate.parseRate(text) {
            services[index].typed[typing.pair.id] = rate
        } else {
            problem = "Use numbers only for a rate, like 280 or 74.85."
            self.typing = nil
            return
        }
        problem = nil
        session.rateServices = services
        self.typing = nil
    }

    struct TypedRate {
        var serviceID: String
        var serviceName: String
        var pair: RatePair
        var text: String
    }
}

/// Add a money service by name: UZee looks its rates up online for every pair; when it can't, the rates can be
/// typed now or later.
struct AddRateServiceSheet: View {
    @Bindable var session: AppSession
    let pairs: [RatePair]
    let existing: [String]
    let onAdd: (RateService) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var searching = false
    @State private var searchedName: String?
    @State private var found: [String: Decimal] = [:]
    @State private var texts: [String: String] = [:]
    @State private var problem: String?

    private var clean: String { name.trimmingCharacters(in: .whitespaces) }
    private var searched: Bool { searchedName == clean && !clean.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like SadaPay or Western Union", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { afterTyping { Task { await search() } } }
                        .accessibilityIdentifier("rateService.name")
                    Button {
                        afterTyping { Task { await search() } }
                    } label: {
                        HStack {
                            Text("Find its rates")
                            if searching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(clean.isEmpty || searching)
                    .accessibilityIdentifier("rateService.find")
                } footer: {
                    Text("UZee looks for its live rates online. Only the name is sent.")
                }
                if searched {
                    if !found.isEmpty {
                        Section {
                            ForEach(pairs) { pair in
                                LabeledContent("\(pair.from) 1 → \(pair.to)",
                                               value: found[pair.id].map { (pair.toCurrency?.symbol ?? pair.to) + " " + ExchangeRate.display($0) } ?? "Couldn't load")
                                    .monospacedDigit()
                            }
                        } header: {
                            Label("Rates fetched", systemImage: "checkmark.circle.fill").foregroundStyle(UZColor.positive)
                                .accessibilityIdentifier("rateService.fetched")
                        }
                    } else {
                        Section {
                            ForEach(pairs) { pair in
                                HStack {
                                    Text("\(pair.from) 1 → \(pair.to)")
                                    TextField("Optional", text: Binding(get: { texts[pair.id] ?? "" }, set: { texts[pair.id] = $0 }))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                }
                            }
                        } header: {
                            Text("Type its rates")
                        } footer: {
                            Text("UZee couldn't find \(clean)'s rates online. Type what its app shows, now or later; until then it shows Google's rate.")
                                .accessibilityIdentifier("rateService.notFound")
                        }
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(UZColor.negative) }
                }
            }
            .navigationTitle("Add a money service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { afterTyping(add) }.fontWeight(.semibold)
                        .disabled(!searched)
                        .accessibilityIdentifier("rateService.add")
                }
            }
        }
    }

    private func search() async {
        guard !clean.isEmpty, !searching else { return }
        problem = nil
        if existing.contains(where: { NameKey.make($0) == NameKey.make(clean) }) {
            problem = "\(clean) is already on the list."
            return
        }
        searching = true
        found = [:]
        let service = RateService(name: clean)
        if service.source != .typed {
            for pair in pairs {
                if let rate = await session.liveRate(service, pair) { found[pair.id] = rate }
            }
        }
        searchedName = clean
        searching = false
    }

    private func add() {
        var typed: [String: Decimal] = [:]
        for pair in pairs {
            let text = (texts[pair.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard let rate = try? ExchangeRate.parseRate(text) else {
                problem = "\(pair.from) → \(pair.to): use numbers only, like 280 or 74.85."
                return
            }
            typed[pair.id] = rate
        }
        // A service whose live rates couldn't be read is kept as typed, so it still shows something.
        let service = RateService(name: clean, source: found.isEmpty ? .typed : RateService.source(for: clean), typed: typed)
        onAdd(service)
        session.toasts.show("\(clean) added")
        dismiss()
    }
}

/// Add a currency pair: 1 of one currency in another, like SAR → PKR or EUR → USD.
struct AddRatePairSheet: View {
    let existing: [RatePair]
    let onAdd: (RatePair) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var from: Currency = .sar
    @State private var to: Currency = .pkr

    private var problem: String? {
        if from == to { return "Pick two different currencies." }
        if existing.contains(RatePair(from: from, to: to)) { return "\(from.code) → \(to.code) is already on the list." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $from) {
                        ForEach(Currency.known, id: \.code) { Text("\($0.code) · \($0.symbol)").tag($0) }
                    }
                    .accessibilityIdentifier("ratePair.from")
                    Picker("To", selection: $to) {
                        ForEach(Currency.known, id: \.code) { Text("\($0.code) · \($0.symbol)").tag($0) }
                    }
                    .accessibilityIdentifier("ratePair.to")
                } footer: {
                    Text(problem ?? "Shows 1 \(from.code) in \(to.code) for every service.")
                        .foregroundStyle(problem == nil ? UZColor.label2 : UZColor.negative)
                }
            }
            .navigationTitle("Add a currency pair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(RatePair(from: from, to: to))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(problem != nil)
                    .accessibilityIdentifier("ratePair.add")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
