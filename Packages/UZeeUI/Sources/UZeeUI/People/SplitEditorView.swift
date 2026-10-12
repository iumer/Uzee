import SwiftUI
import UZeeCore

/// Split from the Add screen, the same way as "Add an expense" in People (owner, 2026-10-12): who it's with,
/// then "Paid by you and split equally", where each part opens its own choice. Done keeps it on the entry.
struct SplitEditorView: View {
    @Bindable var session: AppSession
    let total: Money
    let isIncome: Bool
    let caption: String
    @Binding var draft: SplitDraft?
    @Environment(\.dismiss) private var dismiss
    @State private var working: SplitDraft

    init(session: AppSession, total: Money, isIncome: Bool, caption: String, draft: Binding<SplitDraft?>) {
        self.session = session
        self.total = total
        self.isIncome = isIncome
        self.caption = caption
        _draft = draft
        let me = session.people.selfID
        _working = State(initialValue: draft.wrappedValue ?? SplitDraft(participants: [me], payer: me))
    }

    private var me: UUID { session.people.selfID }
    private var hasPeople: Bool { working.members.contains { $0 != me } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Total") {
                    Text(MoneyFormatter.string(total)).font(.headline).monospacedDigit()
                }
                if !caption.isEmpty { Text(caption).font(.footnote).foregroundStyle(UZColor.label2) }
            }
            Section {
                WithPeopleField(session: session, draft: $working)
            }
            if hasPeople {
                Section {
                    SplitSentence(session: session, draft: $working, total: total, isIncome: isIncome)
                } footer: {
                    VStack(spacing: UZSpacing.s) {
                        SplitEffects(session: session, draft: working, total: total, isIncome: isIncome)
                        Text(isIncome ? "Only your share counts as your income." : "Only your share counts toward your budget.")
                    }
                }
            }
            if draft != nil {
                Section {
                    Button("Don't split", role: .destructive) {
                        draft = nil
                        dismiss()
                    }
                    .accessibilityIdentifier("split.remove")
                }
            }
        }
        .navigationTitle("Split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    draft = hasPeople ? working : nil
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(hasPeople && problem != nil)
                .accessibilityIdentifier("split.save")
            }
        }
    }

    private var problem: String? {
        do {
            _ = try working.build(total: total, transactionID: UUID())
            return nil
        } catch {
            return SplitText.problem(error)
        }
    }

    static func minor(_ text: String, _ currency: Currency) -> Int64 {
        (try? AmountParser.parse(text, currency: currency))?.minorUnits ?? 0
    }

    static func basisPoints(_ text: String) -> Int64 {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return 0 }
        return Rounding.int64(Rounding.halfUp(value * 100, scale: 0)) ?? 0
    }
}
