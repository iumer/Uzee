import SwiftUI

/// Settings › UZee's voice: every English voice on this iPhone, natural ones first, each with a sample, plus
/// the speaking speed. The nicest voices (Premium, Enhanced) must be downloaded in the iPhone's settings first.
struct UZeeVoiceView: View {
    @Bindable var session: AppSession
    @AppStorage(SmartClient.chosenVoiceKey) private var chosenVoice = ""
    @AppStorage(SmartClient.speedKey) private var speed = 0.98
    @State private var voices: [SmartClient.VoiceChoice] = []
    @State private var showsBasic = false

    private var natural: [SmartClient.VoiceChoice] { voices.filter(\.isNatural) }
    private var basic: [SmartClient.VoiceChoice] { voices.filter { !$0.isNatural } }
    /// What UZee speaks with when nothing is picked: the first (best) voice.
    private var current: String { chosenVoice.isEmpty || !voices.contains { $0.id == chosenVoice } ? voices.first?.id ?? "" : chosenVoice }

    var body: some View {
        List {
            if natural.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: UZSpacing.s) {
                        Label("Get a natural voice", systemImage: "sparkles").font(.headline)
                        Text("The voices on this iPhone right now are the basic ones. Download a nicer one, then pick it here:")
                            .font(.subheadline).foregroundStyle(UZColor.label2)
                        Text("iPhone Settings › Accessibility › Read & Speak › Voices › English › tap a voice marked Premium or Enhanced (Ava, Zoe, Evan or Nathan).")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.vertical, UZSpacing.xs)
                    .accessibilityIdentifier("voice.getNatural")
                }
            }
            if !natural.isEmpty {
                Section {
                    ForEach(natural) { row($0) }
                } header: {
                    Text("Natural voices")
                } footer: {
                    Text("Tap a voice to hear it and use it. More: iPhone Settings › Accessibility › Read & Speak › Voices › English.")
                }
            }
            Section {
                DisclosureGroup("Basic voices (\(basic.count))", isExpanded: $showsBasic) {
                    ForEach(basic) { row($0) }
                }
                .accessibilityIdentifier("voice.basic")
            }
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Text("Speaking speed")
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(UZColor.label2)
                        Slider(value: $speed, in: 0.8...1.2, step: 0.02) { editing in
                            if !editing, !current.isEmpty { session.smart.previewVoice(current) }
                        }
                        .accessibilityIdentifier("voice.speed")
                        Image(systemName: "hare").foregroundStyle(UZColor.label2)
                    }
                }
            }
        }
        .navigationTitle("UZee's voice")
        .navigationBarTitleDisplayMode(.inline)
        .task { voices = session.smart.voices() }
        .onDisappear { session.smart.stopSpeaking() }
    }

    private func row(_ voice: SmartClient.VoiceChoice) -> some View {
        Button {
            chosenVoice = voice.id
            session.smart.previewVoice(voice.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: UZSpacing.s) {
                        Text(voice.name).foregroundStyle(UZColor.label)
                        if voice.isNatural {
                            Text(voice.quality).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(UZColor.tint.opacity(0.15), in: .capsule)
                                .foregroundStyle(UZColor.tint)
                        }
                    }
                    Text(voice.detail).font(.footnote).foregroundStyle(UZColor.label2)
                }
                Spacer()
                Image(systemName: voice.id == current ? "checkmark.circle.fill" : "play.circle")
                    .font(.title3)
                    .foregroundStyle(voice.id == current ? UZColor.tint : UZColor.label2)
            }
        }
        .accessibilityLabel("\(voice.name), \(voice.quality)\(voice.id == current ? ", selected" : "")")
    }
}
