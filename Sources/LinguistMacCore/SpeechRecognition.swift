import Foundation

public struct SpeechRecognitionRequest: Equatable, Sendable {
    public let sourceLanguage: TranslationLanguage

    public init(sourceLanguage: TranslationLanguage = .autoDetect) {
        self.sourceLanguage = sourceLanguage
    }

    public var localeIdentifier: String? {
        sourceLanguage.supportsAutoDetect ? nil : sourceLanguage.id
    }
}

public struct SpeechRecognitionResult: Equatable, Sendable {
    public let transcript: String
    public let language: TranslationLanguage?

    public init(
        transcript: String,
        language: TranslationLanguage? = nil
    ) {
        self.transcript = transcript
        self.language = language
    }

    public var trimmedTranscript: String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SpeechRecognitionFailure: Error, Equatable, Sendable {
    case permissionDenied(PermissionKind)
    case sourceLanguageRequired
    case emptyTranscript
    case cancelled
    case captureInProgress
    case recognitionFailed
}

public enum SpeechRecognitionSessionState: Equatable, Sendable {
    case idle
    case requestingPermission(PermissionKind)
    case capturing
    case recognizing
    case completed(SpeechRecognitionResult)
    case failed(SpeechRecognitionFailure)
}

public enum SpeechRecognitionProgress: Equatable, Sendable {
    case recordingFinished
}

public typealias SpeechRecognitionProgressHandler = @Sendable (SpeechRecognitionProgress) async -> Void
public typealias SpeechRecognitionStateHandler = @Sendable (SpeechRecognitionSessionState) async -> Void

public protocol SpeechToTextServicing: Sendable {
    func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult
}

public struct UnavailableSpeechToTextService: SpeechToTextServicing {
    public init() {}

    public func transcribeShortPhrase(
        _ request: SpeechRecognitionRequest,
        progress: @escaping SpeechRecognitionProgressHandler
    ) async throws -> SpeechRecognitionResult {
        _ = request
        _ = progress
        throw SpeechRecognitionFailure.recognitionFailed
    }
}

public actor SpeechRecognitionCoordinator {
    public private(set) var state: SpeechRecognitionSessionState
    private var stateHistory: [SpeechRecognitionSessionState]
    private var isCaptureInProgress: Bool
    private let services: LinguistServices

    public init(services: LinguistServices) {
        self.services = services
        state = .idle
        stateHistory = [.idle]
        isCaptureInProgress = false
    }

    public func states() -> [SpeechRecognitionSessionState] {
        stateHistory
    }

    @discardableResult
    public func captureShortPhrase(
        sourceLanguage: TranslationLanguage = .autoDetect,
        onStateChange: SpeechRecognitionStateHandler? = nil
    ) async -> SpeechRecognitionSessionState {
        guard !isCaptureInProgress else {
            return .failed(.captureInProgress)
        }

        isCaptureInProgress = true
        defer {
            isCaptureInProgress = false
        }

        do {
            try Task.checkCancellation()
            guard try await requestPermissionIfNeeded(.microphone, onStateChange: onStateChange) == .granted else {
                return await fail(with: .permissionDenied(.microphone), onStateChange: onStateChange)
            }
            let speechRecognitionStatus = try await requestPermissionIfNeeded(
                .speechRecognition,
                onStateChange: onStateChange
            )
            guard speechRecognitionStatus == .granted else {
                return await fail(with: .permissionDenied(.speechRecognition), onStateChange: onStateChange)
            }

            let request = SpeechRecognitionRequest(sourceLanguage: sourceLanguage)
            await setState(.capturing, onStateChange: onStateChange)
            let result = try await services.speechToText.transcribeShortPhrase(request) { progress in
                await self.handleProgress(progress, onStateChange: onStateChange)
            }
            let transcript = result.trimmedTranscript
            guard !transcript.isEmpty else {
                return await fail(with: .emptyTranscript, onStateChange: onStateChange)
            }

            let completedResult = SpeechRecognitionResult(
                transcript: transcript,
                language: result.language
            )
            await setState(.completed(completedResult), onStateChange: onStateChange)
            return state
        } catch {
            return await fail(with: failure(from: error), onStateChange: onStateChange)
        }
    }

    private func requestPermissionIfNeeded(
        _ kind: PermissionKind,
        onStateChange: SpeechRecognitionStateHandler?
    ) async throws -> PermissionStatus {
        try Task.checkCancellation()
        let status = await services.permissionChecker.status(for: kind)
        try Task.checkCancellation()
        guard status != .granted else {
            return status
        }

        await setState(.requestingPermission(kind), onStateChange: onStateChange)
        try Task.checkCancellation()
        let requestedStatus = await services.permissionChecker.request(for: kind)
        try Task.checkCancellation()
        return requestedStatus
    }

    private func handleProgress(
        _ progress: SpeechRecognitionProgress,
        onStateChange: SpeechRecognitionStateHandler?
    ) async {
        switch progress {
        case .recordingFinished:
            guard state == .capturing else {
                return
            }

            await setState(.recognizing, onStateChange: onStateChange)
        }
    }

    private func failure(from error: Error) -> SpeechRecognitionFailure {
        if let failure = error as? SpeechRecognitionFailure {
            return failure
        }
        if isCancellation(error) {
            return .cancelled
        }

        return .recognitionFailed
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func fail(
        with failure: SpeechRecognitionFailure,
        onStateChange: SpeechRecognitionStateHandler?
    ) async -> SpeechRecognitionSessionState {
        await setState(.failed(failure), onStateChange: onStateChange)
        return state
    }

    private func setState(
        _ newState: SpeechRecognitionSessionState,
        onStateChange: SpeechRecognitionStateHandler?
    ) async {
        state = newState
        stateHistory.append(newState)
        if let onStateChange {
            await onStateChange(newState)
        }
    }
}
