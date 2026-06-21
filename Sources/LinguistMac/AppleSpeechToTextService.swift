import Foundation
import LinguistMacCore
@preconcurrency import Speech

actor AppleSpeechToTextService: SpeechToTextServicing {
    private let maxPhraseDuration: TimeInterval
    private let recognitionGraceDuration: TimeInterval
    private var activeAudioEngine: AVAudioEngine?
    private var activeRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var activeContinuation: SpeechRecognitionContinuationBox?
    private var activeSessionID: UUID?
    private var activeShortPhraseLimitTask: Task<Void, Never>?
    private var activeRecognitionTimeoutTask: Task<Void, Never>?

    init(
        maxPhraseDuration: TimeInterval = 8,
        recognitionGraceDuration: TimeInterval = 5
    ) {
        self.maxPhraseDuration = maxPhraseDuration
        self.recognitionGraceDuration = recognitionGraceDuration
    }

    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        try Task.checkCancellation()
        let recognizer = try makeRecognizer(for: request)
        let language = request.sourceLanguage.supportsAutoDetect ? nil : request.sourceLanguage
        let sessionID = UUID()

        return try await withTaskCancellationHandler {
            try await startTranscription(
                recognizer: recognizer,
                language: language,
                progress: progress,
                sessionID: sessionID
            )
        } onCancel: {
            Task {
                await self.cancelActiveRecognition(sessionID: sessionID)
            }
        }
    }

    private func makeRecognizer(for request: SpeechRecognitionRequest) throws -> SFSpeechRecognizer {
        guard let localeIdentifier = request.localeIdentifier else {
            throw SpeechRecognitionFailure.sourceLanguageRequired
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable
        else {
            throw SpeechRecognitionFailure.recognitionFailed
        }

        return recognizer
    }

    private func startTranscription(
        recognizer: SFSpeechRecognizer,
        language: TranslationLanguage?,
        progress: @escaping SpeechRecognitionProgressHandler,
        sessionID: UUID
    ) async throws -> SpeechRecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = SpeechRecognitionContinuationBox(continuation)
            activeSessionID = sessionID
            activeContinuation = continuationBox

            do {
                let audioEngine = AVAudioEngine()
                let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                recognitionRequest.shouldReportPartialResults = false
                recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

                let inputNode = audioEngine.inputNode
                let recordingFormat = inputNode.outputFormat(forBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                    recognitionRequest.append(buffer)
                }

                activeAudioEngine = audioEngine
                activeRecognitionRequest = recognitionRequest
                activeRecognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                    let transcript = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    let isFinal = result?.isFinal == true
                    let failure = error.map(Self.speechRecognitionFailure(from:))
                    Task {
                        self.handleRecognitionResult(
                            transcript: transcript,
                            isFinal: isFinal,
                            failure: failure,
                            language: language,
                            sessionID: sessionID
                        )
                    }
                }

                audioEngine.prepare()
                try audioEngine.start()
                scheduleShortPhraseLimit(sessionID: sessionID, progress: progress)
                scheduleRecognitionTimeout(sessionID: sessionID)
            } catch {
                cleanupActiveRecognition(cancelTask: true)
                continuationBox.resume(throwing: Self.speechRecognitionFailure(from: error))
            }
        }
    }

    private func scheduleShortPhraseLimit(
        sessionID: UUID,
        progress: @escaping SpeechRecognitionProgressHandler
    ) {
        activeShortPhraseLimitTask = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds(for: maxPhraseDuration))
                await finishRecordingIfNeeded(sessionID: sessionID, progress: progress)
            } catch {}
        }
    }

    private func scheduleRecognitionTimeout(sessionID: UUID) {
        activeRecognitionTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds(for: maxPhraseDuration + recognitionGraceDuration))
                failActiveRecognitionIfNeeded(.recognitionFailed, sessionID: sessionID)
            } catch {}
        }
    }

    private func finishRecordingIfNeeded(
        sessionID: UUID,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async {
        guard activeSessionID == sessionID,
              activeContinuation?.isResolved == false,
              activeRecognitionRequest != nil
        else {
            return
        }

        await progress(.recordingFinished)
        guard activeSessionID == sessionID,
              activeContinuation?.isResolved == false
        else {
            return
        }

        stopAudioInput()
    }

    private func handleRecognitionResult(
        transcript: String?,
        isFinal: Bool,
        failure: SpeechRecognitionFailure?,
        language: TranslationLanguage?,
        sessionID: UUID
    ) {
        guard activeSessionID == sessionID,
              let continuation = activeContinuation,
              !continuation.isResolved
        else {
            return
        }

        if let failure {
            cleanupActiveRecognition(cancelTask: false)
            continuation.resume(throwing: failure)
            return
        }

        guard isFinal,
              let transcript
        else {
            return
        }

        cleanupActiveRecognition(cancelTask: false)
        continuation.resume(
            returning: SpeechRecognitionResult(
                transcript: transcript,
                language: language
            )
        )
    }

    private func failActiveRecognitionIfNeeded(
        _ failure: SpeechRecognitionFailure,
        sessionID: UUID? = nil
    ) {
        guard let continuation = activeContinuation,
              sessionID == nil || activeSessionID == sessionID,
              !continuation.isResolved
        else {
            return
        }

        cleanupActiveRecognition(cancelTask: true)
        continuation.resume(throwing: failure)
    }

    private func cancelActiveRecognition(sessionID: UUID? = nil) {
        failActiveRecognitionIfNeeded(.cancelled, sessionID: sessionID)
    }

    private func stopAudioInput() {
        activeAudioEngine?.inputNode.removeTap(onBus: 0)
        activeAudioEngine?.stop()
        activeAudioEngine = nil
        activeRecognitionRequest?.endAudio()
        activeRecognitionRequest = nil
    }

    private func cleanupActiveRecognition(cancelTask: Bool) {
        stopAudioInput()
        activeShortPhraseLimitTask?.cancel()
        activeShortPhraseLimitTask = nil
        activeRecognitionTimeoutTask?.cancel()
        activeRecognitionTimeoutTask = nil
        if cancelTask {
            activeRecognitionTask?.cancel()
        }
        activeRecognitionTask = nil
        activeContinuation = nil
        activeSessionID = nil
    }

    private nonisolated func nanoseconds(for duration: TimeInterval) -> UInt64 {
        UInt64(duration * 1_000_000_000)
    }

    private nonisolated static func speechRecognitionFailure(from error: Error) -> SpeechRecognitionFailure {
        if let failure = error as? SpeechRecognitionFailure {
            return failure
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return .cancelled
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled
        }

        return .recognitionFailed
    }
}

private final class SpeechRecognitionContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SpeechRecognitionResult, Error>?

    init(_ continuation: CheckedContinuation<SpeechRecognitionResult, Error>) {
        self.continuation = continuation
    }

    var isResolved: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }

        return continuation == nil
    }

    func resume(returning result: SpeechRecognitionResult) {
        resume { continuation in
            continuation.resume(returning: result)
        }
    }

    func resume(throwing error: Error) {
        resume { continuation in
            continuation.resume(throwing: error)
        }
    }

    private func resume(_ body: (CheckedContinuation<SpeechRecognitionResult, Error>) -> Void) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }

        self.continuation = nil
        lock.unlock()
        body(continuation)
    }
}
