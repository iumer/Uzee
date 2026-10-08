import AVFoundation
import Foundation

/// Speaks UZee's replies aloud with the system voice, on the device.
public final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public static let shared = VoiceSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var onDone: (@Sendable () -> Void)?

    override public init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, then calls `done` (also when stopped).
    public func speak(_ text: String, done: @escaping @Sendable () -> Void) {
        stop()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
        try? session.setActive(true)
        #endif
        lock.lock()
        onDone = done
        lock.unlock()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finish()
    }

    /// The best installed English voice: premium, then enhanced, then the default.
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        let preferred = ["en-US", "en-GB", "en-IN", "en-AU"]
        for quality in [AVSpeechSynthesisVoiceQuality.premium, .enhanced] {
            for language in preferred {
                if let voice = english.first(where: { $0.quality == quality && $0.language == language }) { return voice }
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private func finish() {
        lock.lock()
        let done = onDone
        onDone = nil
        lock.unlock()
        done?()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish() }
}
