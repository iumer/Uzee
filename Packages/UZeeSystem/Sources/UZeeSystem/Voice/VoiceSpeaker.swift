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
        utterance.voice = Self.bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
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
