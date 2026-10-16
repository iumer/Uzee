import SwiftUI

/// Settings › UZee's voice: every English voice on this iPhone, natural ones first, each with a sample, plus
/// the speaking speed. The nicest voices (Premium, Enhanced) must be downloaded in the iPhone's settings first.
struct UZeeVoiceView: View {
    @Bindable var session: AppSession
    @AppStorage(SmartClient.chosenVoiceKey) private var chosenVoice = ""
    @AppStorage(SmartClient.speedKey) private var speed = 0.98
    @State private var voices: [SmartClient.VoiceChoice] = []

    private var natural: [SmartClient.VoiceChoice] { voices.filter(\.isNatural) }
    /// A short list, not 30 (owner, 2026-10-15): Gordon (the owner's favourite), then the natural voices, at most six.
    private var shortList: [SmartClient.VoiceChoice] {
        let gordon = voices.filter { $0.name.lowercased().hasPrefix("gordon") }
        let picked = voices.filter { $0.id == chosenVoice }
        var seen = Set<String>()
        return (gordon + natural + picked).filter { seen.insert($0.id).inserted }.prefix(6).map { $0 }
    }
    /// What UZee speaks with when nothing is picked: the first (best) voice.
    private var current: String { chosenVoice.isEmpty || !voices.contains { $0.id == chosenVoice } ? voices.first?.id ?? "" : chosenVoice }

    var body: some View {
        List {
            if !shortList.isEmpty {
                Section {
                    ForEach(shortList) { row($0) }
                } header: {
                    Text("Favourites")
                } footer: {
                    Text("Tap a voice to hear it and use it.")
                }
            }
            // Every English voice on this iPhone, the ones downloaded in iPhone Settings included (owner, 2026-10-16).
            ForEach(["Premium", "Enhanced", "Standard"], id: \.self) { quality in
                let group = voices.filter { $0.quality == quality }
                if !group.isEmpty {
                    Section {
                        ForEach(group) { row($0) }
                    } header: {
                        Text("\(quality) · \(group.count)")
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: UZSpacing.s) {
                    Label(natural.count < 3 ? "Get better voices" : "More voices", systemImage: "sparkles").font(.headline)
                    Text("Apps can't download voices themselves; iPhone does it, free. In iPhone Settings › Accessibility › Read & Speak › Voices › English, download a voice marked Premium (Ava, Zoe or Evan sound the most natural), then come back here. It shows up in this list.")
                        .font(.subheadline).foregroundStyle(UZColor.label2)
                }
                .padding(.vertical, UZSpacing.xs)
                .accessibilityIdentifier("voice.getNatural")
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
