import Foundation
import UZeeCore

/// On-device reading and listening (AI-02, IMP-01, VOX-01…08), injected like the other clients so UZeeUI
/// doesn't depend on Vision, PDFKit, Speech or Foundation Models directly.
public struct SmartClient: Sendable {
    public enum StatementText: Sendable {
        /// A PDF's text, read one or more ways (see `StatementParser.read(versions:)`).
        case pdf([[String]])
        case csv(String)
    }

    /// Receipt photo → the text on it and where each piece sits.
    public var readReceipt: @Sendable (Data) throws -> [ReceiptPiece]
    /// Statement file (PDF, CSV) → text. Throws `StatementFileProblem`.
    public var readStatement: @Sendable (URL, _ password: String?) throws -> StatementText
    public var understand: @Sendable (String, VoiceVocabulary, LocalDate) async -> VoiceCommand
    /// nil when Apple's on-device model is available; otherwise the explanation to show (VOX-08).
    public var voiceModelProblem: @Sendable () -> String?
    public var requestSpeechAccess: @Sendable () async -> Bool
    public var startListening: @Sendable (@escaping @Sendable (String, Bool) -> Void) throws -> Void
    public var stopListening: @Sendable () -> Void
    public var cancelListening: @Sendable () -> Void
    /// True when the microphone and speech recognition are already allowed (so listening won't show a prompt).
    public var canListen: @Sendable () -> Bool
    /// A conversation with Apple's on-device model, or nil when it isn't available (rules are used then).
    public var startAssistant: @Sendable (AssistantActions, VoiceVocabulary, LocalDate) -> (any AssistantChat)?
    /// Says a reply aloud, then calls back.
    public var speak: @Sendable (String, @escaping @Sendable () -> Void) -> Void
    public var stopSpeaking: @Sendable () -> Void
    /// Installed English voices for UZee to speak with, best first.
    public var voices: @Sendable () -> [VoiceChoice]
    public var previewVoice: @Sendable (String) -> Void

    public struct VoiceChoice: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let detail: String

        public init(id: String, name: String, detail: String) {
            self.id = id
            self.name = name
            self.detail = detail
        }
    }

    /// Where the chosen voice is kept (read by the speaker in UZeeSystem too).
    public static let chosenVoiceKey = "uzee.voice.id"

    public init(readReceipt: @escaping @Sendable (Data) throws -> [ReceiptPiece],
                readStatement: @escaping @Sendable (URL, String?) throws -> StatementText,
                understand: @escaping @Sendable (String, VoiceVocabulary, LocalDate) async -> VoiceCommand,
                voiceModelProblem: @escaping @Sendable () -> String?,
                requestSpeechAccess: @escaping @Sendable () async -> Bool,
                startListening: @escaping @Sendable (@escaping @Sendable (String, Bool) -> Void) throws -> Void,
                stopListening: @escaping @Sendable () -> Void,
                cancelListening: @escaping @Sendable () -> Void,
                canListen: @escaping @Sendable () -> Bool = { false },
                startAssistant: @escaping @Sendable (AssistantActions, VoiceVocabulary, LocalDate) -> (any AssistantChat)? = { _, _, _ in nil },
                speak: @escaping @Sendable (String, @escaping @Sendable () -> Void) -> Void = { _, done in done() },
                stopSpeaking: @escaping @Sendable () -> Void = {},
                voices: @escaping @Sendable () -> [VoiceChoice] = { [] },
                previewVoice: @escaping @Sendable (String) -> Void = { _ in }) {
        self.readReceipt = readReceipt
        self.readStatement = readStatement
        self.understand = understand
        self.voiceModelProblem = voiceModelProblem
        self.requestSpeechAccess = requestSpeechAccess
        self.startListening = startListening
        self.stopListening = stopListening
        self.cancelListening = cancelListening
        self.canListen = canListen
        self.startAssistant = startAssistant
        self.speak = speak
        self.stopSpeaking = stopSpeaking
        self.voices = voices
        self.previewVoice = previewVoice
    }

    /// Previews and tests: rules only, no camera text, no microphone.
    public static let unavailable = SmartClient(
        readReceipt: { _ in [] },
        readStatement: { _, _ in throw StatementFileProblem.unreadable },
        understand: { text, vocabulary, today in VoiceRuleParser.parse(text, vocabulary: vocabulary, today: today) },
        voiceModelProblem: { "Apple Intelligence isn't available, so UZee understands common sentences only." },
        requestSpeechAccess: { false },
        startListening: { _ in throw StatementFileProblem.unreadable },
        stopListening: {},
        cancelListening: {})
}
