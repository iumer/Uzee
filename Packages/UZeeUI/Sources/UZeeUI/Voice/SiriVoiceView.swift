import SwiftUI

/// Siri & voice (SCR-40): what to say, where else Ask UZee lives, and whether Apple Intelligence is on (VOX-01, VOX-08).
struct SiriVoiceView: View {
    @Bindable var session: AppSession

    var body: some View {
        List {
            Section {
                phrase("Hey Siri, ask UZee", "Then ask: how much do I owe Ammi? What's my next bill? How much budget is left?")
                phrase("Hey Siri, add to UZee", "Then say it: spent 2,500 on groceries. UZee opens so you can check and save.")
            } header: {
                Text("Say to Siri")
            } footer: {
                Text("Answers come from the data on this iPhone. Nothing is saved without your Save.")
            }
            Section {
                Label("Home › mic button", systemImage: "mic")
                Label("Action Button: Settings › Action Button › Shortcut › UZee", systemImage: "button.horizontal.top.press")
                Label("Shortcuts app: Ask UZee and Add to UZee", systemImage: "square.2.layers.3d")
            } header: {
                Text("Other ways in")
            }
            Section {
                if let problem = session.smart.voiceModelProblem() {
                    Label(problem, systemImage: "info.circle").foregroundStyle(UZColor.label2)
                } else {
                    Label("Apple Intelligence is on. UZee uses it on this iPhone for sentences the built-in rules don't understand.",
                          systemImage: "checkmark.circle")
                }
            } header: {
                Text("Apple Intelligence")
            }
            Section {
                NavigationLink {
                    UZeeVoiceView(session: session)
                } label: {
                    Label("UZee's voice", systemImage: "person.wave.2")
                }
                .accessibilityIdentifier("siri.voice")
            }
            Section {
                Button("Try Ask UZee") { session.openVoice() }
                    .accessibilityIdentifier("siri.try")
            }
        }
        .navigationTitle("Siri & voice")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen.siriVoice")
    }

    private func phrase(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: UZSpacing.xs) {
            Text("“\(title)”").font(.body.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(UZColor.label2)
        }
        .accessibilityElement(children: .combine)
    }
}
