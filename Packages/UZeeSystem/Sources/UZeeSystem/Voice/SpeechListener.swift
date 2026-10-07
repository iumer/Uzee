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

    public init() {}

    /// Asks for speech recognition and microphone access; false if either is refused.
    public static func requestAccess() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// Starts listening. `onText` gets the transcript so far, then once more with `isFinal` true.
    public func start(_ onText: @escaping @Sendable (_ text: String, _ isFinal: Bool) -> Void) throws {
        stop()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw Failure.notAllowed }
        guard let recognizer, recognizer.isAvailable else { throw Failure.unavailable }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
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

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
