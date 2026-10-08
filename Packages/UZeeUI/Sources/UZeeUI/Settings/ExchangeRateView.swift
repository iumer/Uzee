import SwiftUI
import UZeeCore

/// Settings → Exchange rate (CUR-03, CUR-012): Wise's live rate by default, or one typed rate for USD;
/// transfers keep their own.
struct ExchangeRateView: View {
    @Bindable var session: AppSession
    @State private var text = ""
    @State private var problem: String?
    @State private var usesWise = true
    @State private var isFetching = false
    @State private var updated: Date?

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
                    LabeledContent("$1", value: "Rs " + ExchangeRate.display(session.ledger.rate(for: .usd)))
                        .monospacedDigit()
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
                HStack {
                    Text("$1 = Rs")
                    TextField("280", text: $text)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                        .accessibilityIdentifier("rate.field")
                }
            } footer: {
                Text("Used to show USD in rupees and for totals. Transfers keep the rate they actually got.")
            }
            Section {
                Button("Save rate", action: save).accessibilityIdentifier("rate.save")
            }
            }
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear {
            text = ExchangeRate.storageString(session.ledger.rate(for: .usd))
            usesWise = session.usesWiseRates
            updated = session.wiseRatesUpdated
        }
    }

    private func update() {
        isFetching = true
        problem = nil
        Task {
            let got = await session.refreshWiseRates(force: true)
            isFetching = false
            updated = session.wiseRatesUpdated
            text = ExchangeRate.storageString(session.ledger.rate(for: .usd))
            if !got { problem = "Couldn't reach Wise. UZee keeps the last rate and tries again later." }
        }
    }

    private func save() {
        do {
            let rate = try ExchangeRate.parseRate(text)
            problem = nil
            if session.perform("Couldn't save the rate. Try again.", { try session.client.setRate(rate, .usd) }) {
                session.toasts.show("Rate saved")
            }
        } catch {
            problem = switch error {
            case .empty: "Enter a rate."
            case .notANumber: "Use numbers only, like 280 or 278.70."
            case .notPositive: "The rate must be more than zero."
            }
        }
    }
}
