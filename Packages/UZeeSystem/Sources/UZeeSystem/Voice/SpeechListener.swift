import AVFoundation
import Foundation
import Speech

/// Turns the microphone into text for Ask UZee (VOX-01, VOX-02), on the device when it supports it.
public final class SpeechListener: @unchecked Sendable {
    public enum Failure: Error, Sendable {
        case notAllowed
        case unavailable
    }

    public static let shared = SpeechListener()

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var currentLevel: Float = 0

    /// How loud the microphone is, 0 (quiet) … 1 (loud speech), smoothed. 0 when not listening.
    public var level: Float { lock.withLock { currentLevel } }

    public init() {}

    /// Asks for speech recognition and microphone access; false if either is refused.
    public static func requestAccess() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// True when speech recognition and the microphone are already allowed.
    public static var hasAccess: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioApplication.shared.recordPermission == .granted
    }

    /// Starts listening. `onText` gets the transcript so far, then once more with `isFinal` true.
    public func start(_ onText: @escaping @Sendable (_ text: String, _ isFinal: Bool) -> Void) throws {
        stop()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw Failure.notAllowed }
        guard let recognizer, recognizer.isAvailable else { throw Failure.unavailable }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // Play and record, so UZee can answer aloud right after listening.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.measure(buffer)
        }
        engine.prepare()
        try engine.start()
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onText(result.bestTranscription.formattedString, result.isFinal)
            } else if error != nil {
                onText("", true)
            }
            if error != nil || result?.isFinal == true { self?.stopAudio() }
        }
        lock.lock()
        self.request = request
        self.task = task
        lock.unlock()
    }

    /// Stops the microphone; the recogniser then delivers its final text.
    public func stop() {
        lock.lock()
        let request = self.request
        self.request = nil
        lock.unlock()
        stopAudio()
        request?.endAudio()
    }

    /// Stops and throws away anything not yet delivered.
    public func cancel() {
        lock.lock()
        let task = self.task
        self.task = nil
        self.request = nil
        lock.unlock()
        stopAudio()
        task?.cancel()
    }

    /// Loudness of one buffer, as a smoothed 0…1 level (about -55 dB is 0, -10 dB is 1).
    private func measure(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_001))
        let value = max(0, min(1, (decibels + 55) / 45))
        lock.withLock { currentLevel = currentLevel * 0.4 + value * 0.6 }
    }

    private func stopAudio() {
        lock.withLock { currentLevel = 0 }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
