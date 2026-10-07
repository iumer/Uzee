import SwiftUI

/// Add transaction (SCR-05). M1 shows the sheet frame; keypad, categories and accounts arrive in M2.
struct AddSheet: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView("Adding comes next", systemImage: "plus.circle",
                           description: "The amount keypad, categories and accounts arrive in the next update.")
                .background(UZColor.bg)
                .navigationTitle("New expense")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityIdentifier("add.close")
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.form)
        .accessibilityIdentifier("add.sheet")
    }
}

/// Ask UZee (SCR-03). Voice arrives in M9.
struct VoiceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EmptyStateView("Ask UZee", systemImage: "waveform",
                           description: "Soon you'll ask about your money or log something by voice. Speech stays on this iPhone.")
                .background(UZColor.bg)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityIdentifier("voice.close")
                    }
                }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("voice.sheet")
    }
}
