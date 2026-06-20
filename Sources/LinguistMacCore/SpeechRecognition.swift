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
    case emptyTranscript
    case cancelled
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

public protocol SpeechToTextServicing: Sendable {
    func transcribeShortPhrase(_ request: SpeechRecognitionRequest) async throws -> SpeechRecognitionResult
}

public struct UnavailableSpeechToTextService: SpeechToTextServicing {
    public init() {}

    public func transcribeShortPhrase(_ request: SpeechRecognitionRequest) async throws -> SpeechRecognitionResult {
        _ = request
        throw SpeechRecognitionFailure.recognitionFailed
    }
}

public actor SpeechRecognitionCoordinator {
    public private(set) var state: SpeechRecognitionSessionState
    private var stateHistory: [SpeechRecognitionSessionState]
    private let services: LinguistServices

    public init(services: LinguistServices) {
        self.services = services
        state = .idle
        stateHistory = [.idle]
    }

    public func states() -> [SpeechRecognitionSessionState] {
        stateHistory
    }

    @discardableResult
    public func captureShortPhrase(
        sourceLanguage: TranslationLanguage = .autoDetect
    ) async -> SpeechRecognitionSessionState {
        guard await requestPermissionIfNeeded(.microphone) == .granted else {
            return fail(with: .permissionDenied(.microphone))
        }
        guard await requestPermissionIfNeeded(.speechRecognition) == .granted else {
            return fail(with: .permissionDenied(.speechRecognition))
        }

        let request = SpeechRecognitionRequest(sourceLanguage: sourceLanguage)

        do {
            try Task.checkCancellation()
            setState(.capturing)
            setState(.recognizing)
            let result = try await services.speechToText.transcribeShortPhrase(request)
            let transcript = result.trimmedTranscript
            guard !transcript.isEmpty else {
                return fail(with: .emptyTranscript)
            }

            let completedResult = SpeechRecognitionResult(
                transcript: transcript,
                language: result.language
            )
            setState(.completed(completedResult))
            return state
        } catch {
            return fail(with: failure(from: error))
        }
    }

    private func requestPermissionIfNeeded(_ kind: PermissionKind) async -> PermissionStatus {
        let status = await services.permissionChecker.status(for: kind)
        guard status != .granted else {
            return status
        }

        setState(.requestingPermission(kind))
        return await services.permissionChecker.request(for: kind)
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

    private func fail(with failure: SpeechRecognitionFailure) -> SpeechRecognitionSessionState {
        setState(.failed(failure))
        return state
    }

    private func setState(_ newState: SpeechRecognitionSessionState) {
        state = newState
        stateHistory.append(newState)
    }
}
