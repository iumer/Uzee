import SwiftUI

/// Siri & voice (SCR-40): what to say, where else Ask UZee lives, and whether Apple Intelligence is on (VOX-01, VOX-08).
struct SiriVoiceView: View {
    @Bindable var session: AppSession
    @AppStorage(SmartClient.chosenVoiceKey) private var chosenVoice = ""
    @State private var voices: [SmartClient.VoiceChoice] = []

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
                ForEach(voices) { voice in
                    Button {
                        chosenVoice = voice.id
                        session.smart.previewVoice(voice.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name).foregroundStyle(UZColor.label)
                                Text(voice.detail).font(.footnote).foregroundStyle(UZColor.label2)
                            }
                            Spacer()
                            if voice.id == chosenVoice || (chosenVoice.isEmpty && voice.id == voices.first?.id) {
                                Image(systemName: "checkmark").foregroundStyle(UZColor.tint)
                            }
                        }
                    }
                    .accessibilityIdentifier("siri.voice")
                }
            } header: {
                Text("UZee's voice")
            } footer: {
                Text("Tap to hear it. For a more natural voice, download a Premium or Enhanced one (such as Ava, Zoe or Evan) in the iPhone's Settings › Accessibility › Read & Speak › Voices › English, then pick it here.")
            }
            Section {
                Button("Try Ask UZee") { session.openVoice() }
                    .accessibilityIdentifier("siri.try")
            }
        }
        .task { voices = session.smart.voices() }
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
