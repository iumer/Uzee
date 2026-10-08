import AVFoundation
import Foundation

/// Speaks UZee's replies aloud with the system voice, on the device.
public final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = VoiceSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var onDone: (@Sendable () -> Void)?
    /// The utterance `onDone` belongs to; a late callback for an earlier one must not end this one early.
    private var current: AVSpeechUtterance?

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, then calls `done` (also when stopped).
    public func speak(_ text: String, done: @escaping @Sendable () -> Void) {
        speak(text, voiceID: nil, done: done)
    }

    func speak(_ text: String, voiceID: String?, done: @escaping @Sendable () -> Void) {
        // A new reply replaces the old one; the old one's "done" (start listening) would fire mid-sentence.
        lock.lock()
        onDone = nil
        current = nil
        lock.unlock()
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.bestVoice()
        // A touch slower and warmer than the default reads money more naturally.
        let speed = UserDefaults.standard.double(forKey: Self.speedKey)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed > 0 ? min(max(speed, 0.8), 1.2) : 0.98)
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.1
        lock.lock()
        onDone = done
        current = utterance
        lock.unlock()
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finish(nil)
    }

    /// The voice the owner picked in Settings › Siri & voice (an AVSpeechSynthesisVoice identifier).
    public static let chosenVoiceKey = "uzee.voice.id"
    /// Speaking speed, 0.8 (slower) … 1.2 (faster) of the normal rate; set in Settings › UZee's voice.
    public static let speedKey = "uzee.voice.speed"

    /// Installed English voices, best first: (identifier, name, accent and quality).
    public static func voices() -> [(id: String, name: String, detail: String, quality: String)] {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let rank: (AVSpeechSynthesisVoice) -> Int = { voice in
            switch voice.quality {
            case .premium: 0
            case .enhanced: 1
            default: 2
            }
        }
        return english
            // Novelty voices (Bells, Bubbles, Whisper…) aren't for reading money out.
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { (rank($0), $0.name) < (rank($1), $1.name) }
            .map { voice in
                let accent = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
                let quality = voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Standard"
                return (voice.identifier, voice.name, accent, quality)
            }
    }

    /// Says a sample sentence in a voice, for picking one.
    public func preview(_ identifier: String) {
        speak("Hi, I'm UZee. You spent 2,500 rupees on groceries this week.", voiceID: identifier) {}
    }

    /// The chosen voice, else the best installed English voice: premium, then enhanced, then the default.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: chosenVoiceKey), let chosen = AVSpeechSynthesisVoice(identifier: id) {
            return chosen
        }
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let preferred = ["en-US", "en-GB", "en-IN", "en-AU"]
        for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced] {
            for language in preferred {
                if let voice = english.first(where: { $0.quality == quality && $0.language == language }) { return voice }
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Calls `onDone` once; `utterance` nil means stopped by the app.
    private func finish(_ utterance: AVSpeechUtterance?) {
        lock.lock()
        if let utterance, utterance !== current { lock.unlock(); return }
        current = nil
        let done = onDone
        onDone = nil
        lock.unlock()
        done?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish(utterance) }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish(utterance) }
}
