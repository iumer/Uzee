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

    /// Receipt photo → text lines, top to bottom.
    public var readReceipt: @Sendable (Data) throws -> [String]
    /// Statement file (PDF, CSV) → text. Throws `StatementFileProblem`.
    public var readStatement: @Sendable (URL, _ password: String?) throws -> StatementText
    public var understand: @Sendable (String, VoiceVocabulary, LocalDate) async -> VoiceCommand
    /// nil when Apple's on-device model is available; otherwise the explanation to show (VOX-08).
    public var voiceModelProblem: @Sendable () -> String?
    public var requestSpeechAccess: @Sendable () async -> Bool
    public var startListening: @Sendable (@escaping @Sendable (String, Bool) -> Void) throws -> Void
    public var stopListening: @Sendable () -> Void
    public var cancelListening: @Sendable () -> Void

    public init(readReceipt: @escaping @Sendable (Data) throws -> [String],
                readStatement: @escaping @Sendable (URL, String?) throws -> StatementText,
                understand: @escaping @Sendable (String, VoiceVocabulary, LocalDate) async -> VoiceCommand,
                voiceModelProblem: @escaping @Sendable () -> String?,
                requestSpeechAccess: @escaping @Sendable () async -> Bool,
                startListening: @escaping @Sendable (@escaping @Sendable (String, Bool) -> Void) throws -> Void,
                stopListening: @escaping @Sendable () -> Void,
                cancelListening: @escaping @Sendable () -> Void) {
        self.readReceipt = readReceipt
        self.readStatement = readStatement
        self.understand = understand
        self.voiceModelProblem = voiceModelProblem
        self.requestSpeechAccess = requestSpeechAccess
        self.startListening = startListening
        self.stopListening = stopListening
        self.cancelListening = cancelListening
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
