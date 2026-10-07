import SwiftUI
import UZeeCore

/// Settings → Exchange rate (CUR-03, CUR-012): one table rate for USD; transfers keep their own.
struct ExchangeRateView: View {
    @Bindable var session: AppSession
    @State private var text = ""
    @State private var problem: String?

    var body: some View {
        Form {
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
            if let problem {
                Section { Text(problem).foregroundStyle(UZColor.negative).accessibilityIdentifier("rate.problem") }
            }
            Section {
                Button("Save rate", action: save).accessibilityIdentifier("rate.save")
            }
        }
        .navigationTitle("Exchange rate")
        .onAppear { text = ExchangeRate.storageString(session.ledger.rate(for: .usd)) }
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
