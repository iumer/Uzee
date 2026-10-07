import SwiftUI
import UZeeCore

/// Money actions never save in one tap (AUD-13): this sheet shows what will be saved,
/// then the caller shows "Saved · Undo". Amount, account and date become editable in M2.
public struct ConfirmSheet: View {
    public struct Row: Identifiable, Sendable {
        public let id = UUID()
        public let label: String
        public let value: String

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    let title: String
    let amount: Money
    let rows: [Row]
    let confirmTitle: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    public init(title: String, amount: Money, rows: [Row], confirmTitle: String, onConfirm: @escaping () -> Void) {
        self.title = title
        self.amount = amount
        self.rows = rows
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: UZSpacing.xxxl) {
                AmountText(amount, font: .system(.largeTitle, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, UZSpacing.m)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.label).foregroundStyle(UZColor.label2)
                            Spacer()
                            Text(row.value)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .combine)
                        if row.id != rows.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, UZSpacing.xxl)
                .background(UZColor.card, in: .rect(cornerRadius: UZRadius.card, style: .continuous))
                Spacer(minLength: 0)
                PrimaryButton(confirmTitle, isBusy: isSaving) {
                    isSaving = true
                    onConfirm()
                    dismiss()
                }
                .accessibilityIdentifier("confirm.primary")
            }
            .padding(UZSpacing.xxl)
            .background(UZColor.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: isSaving) { _, saving in saving }
    }
}
