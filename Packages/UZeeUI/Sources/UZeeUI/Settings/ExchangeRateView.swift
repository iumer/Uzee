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
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear {
            fillTexts()
            usesWise = session.usesWiseRates
            updated = session.wiseRatesUpdated
        }
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
