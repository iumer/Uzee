import SwiftUI

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
        // .contain keeps child identifiers visible to UI tests.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.sheet")
    }
}
