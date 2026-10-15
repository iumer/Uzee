import SwiftUI
import UZeeCore

/// Settings → Exchange rate (CUR-03, CUR-012): Wise's live rate by default, or a typed rate for each foreign
/// currency your accounts use (USD, and EUR once a Wise EUR account exists); transfers keep their own.
struct ExchangeRateView: View {
    @Bindable var session: AppSession
    @State private var texts: [String: String] = [:]
    @State private var problem: String?
    @State private var usesWise = true
    @State private var isFetching = false
    @State private var updated: Date?
    /// Other rates by "market.USD" or "westernUnion.USD"; nil while loading, .none when it couldn't be read.
    @State private var others: [String: Decimal?] = [:]
    @State private var loadingOthers = false
    @State private var providers: [RateProvider] = []

    private var base: Currency { session.ledger.base }

    /// USD always, plus every other currency an account uses (BUG-021: EUR had no way to get a rate).
    private var currencies: [Currency] {
        var set = Set(session.ledger.activeAccounts.map(\.currency))
        set.insert(.usd)
        set.remove(base)
        return set.sorted { $0 == .usd ? true : $1 == .usd ? false : $0.code < $1.code }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Live rate from Wise", isOn: Binding(get: { usesWise }, set: { on in
                    usesWise = on
                    session.usesWiseRates = on
                    if on { update() }
                }))
                .accessibilityIdentifier("rate.wise")
                if usesWise {
                    ForEach(currencies, id: \.code) { currency in
                        LabeledContent(one(currency), value: shown(currency))
                            .monospacedDigit()
                            .accessibilityIdentifier("rate.value.\(currency.code)")
                    }
                    Button {
                        update()
                    } label: {
                        HStack {
                            Text("Update now")
                            if isFetching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isFetching)
                    .accessibilityIdentifier("rate.update")
                }
            } footer: {
                if usesWise {
                    Text((updated.map { "Updated \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? "")
                         + "The mid-market rate Wise shows, refreshed when you open UZee. Entries for past days use that day's Wise rate.")
                }
            }
            if !usesWise {
                Section {
                    ForEach(currencies, id: \.code) { currency in
                        HStack {
                            Text("\(one(currency)) = \(base.symbol)")
                            TextField(currency == .usd ? "280" : "Rate", text: binding(currency))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .accessibilityIdentifier(currency == .usd ? "rate.field" : "rate.field.\(currency.code)")
                        }
                    }
                } footer: {
                    Text("Used to show other currencies in rupees and for totals. Transfers keep the rate they actually got.")
                }
                Section {
                    Button("Save rates", action: save).accessibilityIdentifier("rate.save")
                }
            }
            otherRatesSection
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear {
            fillTexts()
            usesWise = session.usesWiseRates
            updated = session.wiseRatesUpdated
            providers = session.rateProviders
        }
        .task { await loadOthers() }
    }

    // MARK: Other rates (owner, 2026-10-15)

    /// USD and EUR always, plus the other currencies your accounts use.
    private var otherCurrencies: [Currency] {
        var list = currencies
        if !list.contains(.eur), base != .eur { list.insert(.eur, at: min(1, list.count)) }
        return list
    }

    @ViewBuilder private var otherRatesSection: some View {
        Section {
            ForEach(otherCurrencies, id: \.code) { currency in
                LabeledContent(one(currency), value: otherText("market", currency))
                    .monospacedDigit()
                    .accessibilityIdentifier("rate.market.\(currency.code)")
            }
        } header: {
            Text("Google (market rate)")
        } footer: {
            Text("The mid-market rate Google shows. For comparing only; totals use the rate at the top.")
        }
        ForEach(providers) { provider in
            Section {
                ForEach(otherCurrencies, id: \.code) { currency in
                    LabeledContent(one(currency)) {
                        if let rate = others[key(provider.rawValue, currency)] ?? nil {
                            Text("\(base.symbol) " + ExchangeRate.display(rate)).monospacedDigit()
                        } else if others[key(provider.rawValue, currency)] == nil, loadingOthers {
                            ProgressView()
                        } else {
                            // Couldn't read the service's rate: the market rate, said plainly.
                            Text(otherText("market", currency) + " (Google)").monospacedDigit().foregroundStyle(UZColor.label2)
                        }
                    }
                    .accessibilityIdentifier("rate.\(provider.rawValue).\(currency.code)")
                }
            } header: {
                HStack {
                    Text(provider.name)
                    Spacer()
                    Button("Remove") { remove(provider) }.font(.caption).textCase(nil)
                }
            } footer: {
                if provider != .westernUnion {
                    Text("\(provider.name) doesn't share its rate online, so this shows Google's rate.")
                }
            }
        }
        Section {
            let missing = RateProvider.allCases.filter { !providers.contains($0) }
            if !missing.isEmpty {
                Menu {
                    ForEach(missing) { provider in Button(provider.name) { add(provider) } }
                } label: {
                    Label("Add a money service", systemImage: "plus")
                }
                .accessibilityIdentifier("rate.addProvider")
            }
            Button {
                Task { await loadOthers() }
            } label: {
                HStack {
                    Text("Refresh these rates")
                    if loadingOthers { Spacer(); ProgressView() }
                }
            }
            .disabled(loadingOthers)
        } footer: {
            Text("Services in your account names, like Western Union or Payoneer, are added here by themselves.")
        }
    }

    private func key(_ source: String, _ currency: Currency) -> String { source + "." + currency.code }

    private func otherText(_ source: String, _ currency: Currency) -> String {
        guard let value = others[key(source, currency)] else { return loadingOthers ? "Loading…" : "—" }
        guard let rate = value else { return "Couldn't load" }
        return "\(base.symbol) " + ExchangeRate.display(rate)
    }

    private func loadOthers() async {
        guard !loadingOthers else { return }
        loadingOthers = true
        others = [:]
        let base = self.base
        for currency in otherCurrencies {
            others[key("market", currency)] = .some(await session.smart.marketRate(currency, base))
            for provider in providers {
                others[key(provider.rawValue, currency)] = .some(await session.smart.providerRate(provider, currency, base))
            }
        }
        loadingOthers = false
    }

    private func add(_ provider: RateProvider) {
        session.setRateProvider(provider, shown: true)
        providers = session.rateProviders
        Task { await loadOthers() }
    }

    private func remove(_ provider: RateProvider) {
        session.setRateProvider(provider, shown: false)
        providers = session.rateProviders
    }

    private func one(_ currency: Currency) -> String {
        currency.symbol + (currency.symbolNeedsSpace ? " " : "") + "1"
    }

    private func shown(_ currency: Currency) -> String {
        guard let rate = session.ledger.rates[currency.code] else { return "No rate yet" }
        return "\(base.symbol) " + ExchangeRate.display(rate)
    }

    private func binding(_ currency: Currency) -> Binding<String> {
        Binding(get: { texts[currency.code] ?? "" }, set: { texts[currency.code] = $0 })
    }

    private func fillTexts() {
        for currency in currencies {
            texts[currency.code] = session.ledger.rates[currency.code].map(ExchangeRate.storageString) ?? ""
        }
    }

    private func update() {
        isFetching = true
        problem = nil
        Task {
            let got = await session.refreshWiseRates(force: true)
            isFetching = false
            updated = session.wiseRatesUpdated
            fillTexts()
            if !got { problem = "Couldn't reach Wise. UZee keeps the last rate and tries again later." }
        }
    }

    private func save() {
        var parsed: [(Currency, Decimal)] = []
        for currency in currencies {
            let text = (texts[currency.code] ?? "").trimmingCharacters(in: .whitespaces)
            // A currency left empty keeps the rate it has; USD must always have one.
            if text.isEmpty, currency != .usd { continue }
            do {
                parsed.append((currency, try ExchangeRate.parseRate(text)))
            } catch {
                let reason: String = switch error {
                case .empty: "enter a rate."
                case .notANumber: "use numbers only, like 280 or 278.70."
                case .notPositive: "the rate must be more than zero."
                }
                problem = "\(currency.code): " + reason
                return
            }
        }
        problem = nil
        if session.perform("Couldn't save the rate. Try again.", {
            for (currency, rate) in parsed { try session.client.setRate(rate, currency) }
        }) {
            session.toasts.show(parsed.count == 1 ? "Rate saved" : "Rates saved")
        }
    }
}
