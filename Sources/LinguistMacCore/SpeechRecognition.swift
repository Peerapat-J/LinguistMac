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
    case onDeviceRecognitionUnavailable
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

public struct SpokenOutputRequest: Equatable, Sendable {
    public let text: String
    public let language: TranslationLanguage

    public init(
        text: String,
        language: TranslationLanguage
    ) {
        self.text = text
        self.language = language
    }

    public init(result: TranslationResult) {
        self.init(
            text: result.translatedText,
            language: result.request.targetLanguage
        )
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalized: SpokenOutputRequest {
        SpokenOutputRequest(text: trimmedText, language: language)
    }
}

public enum SpokenOutputFailure: Error, Equatable, Sendable {
    case emptyText
    case unsupportedLanguage(TranslationLanguage)
    case cancelled
    case playbackFailed
}

public extension SpokenOutputFailure {
    var displayText: String {
        switch self {
        case .emptyText:
            "No translated text to speak"
        case let .unsupportedLanguage(language):
            "Spoken output unavailable for \(language.displayName)"
        case .cancelled:
            "Spoken output stopped"
        case .playbackFailed:
            "Spoken output failed"
        }
    }
}

public enum SpokenOutputSessionState: Equatable, Sendable {
    case idle
    case preparing(SpokenOutputRequest)
    case speaking(SpokenOutputRequest)
    case completed(SpokenOutputRequest)
    case failed(SpokenOutputFailure, request: SpokenOutputRequest?)
}

public typealias SpokenOutputStateHandler = @Sendable (SpokenOutputSessionState) async -> Void

public protocol SpokenOutputServicing: Sendable {
    func canSpeak(language: TranslationLanguage) async -> Bool
    func speak(_ request: SpokenOutputRequest) async throws
    func stop() async
}

public struct UnavailableSpokenOutputService: SpokenOutputServicing {
    public init() {}

    public func canSpeak(language: TranslationLanguage) async -> Bool {
        _ = language
        return false
    }

    public func speak(_ request: SpokenOutputRequest) async throws {
        throw SpokenOutputFailure.unsupportedLanguage(request.language)
    }

    public func stop() async {}
}

public actor SpokenOutputCoordinator {
    public private(set) var state: SpokenOutputSessionState
    private var stateHistory: [SpokenOutputSessionState]
    private let spokenOutput: any SpokenOutputServicing

    public init(services: LinguistServices) {
        spokenOutput = services.spokenOutput
        state = .idle
        stateHistory = [.idle]
    }

    public func states() -> [SpokenOutputSessionState] {
        stateHistory
    }

    @discardableResult
    public func speak(
        _ request: SpokenOutputRequest,
        onStateChange: SpokenOutputStateHandler? = nil
    ) async -> SpokenOutputSessionState {
        let normalizedRequest = request.normalized
        guard !normalizedRequest.trimmedText.isEmpty else {
            return await fail(with: .emptyText, request: normalizedRequest, onStateChange: onStateChange)
        }

        await setState(.preparing(normalizedRequest), onStateChange: onStateChange)
        guard await spokenOutput.canSpeak(language: normalizedRequest.language) else {
            return await fail(
                with: .unsupportedLanguage(normalizedRequest.language),
                request: normalizedRequest,
                onStateChange: onStateChange
            )
        }

        do {
            try Task.checkCancellation()
            await setState(.speaking(normalizedRequest), onStateChange: onStateChange)
            let output = spokenOutput
            try await withTaskCancellationHandler {
                try await output.speak(normalizedRequest)
            } onCancel: {
                Task {
                    await output.stop()
                }
            }
            try Task.checkCancellation()
            await setState(.completed(normalizedRequest), onStateChange: onStateChange)
            return state
        } catch {
            return await fail(
                with: failure(from: error),
                request: normalizedRequest,
                onStateChange: onStateChange
            )
        }
    }

    private func failure(from error: Error) -> SpokenOutputFailure {
        if let failure = error as? SpokenOutputFailure {
            return failure
        }
        if isCancellation(error) {
            return .cancelled
        }

        return .playbackFailed
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
        with failure: SpokenOutputFailure,
        request: SpokenOutputRequest?,
        onStateChange: SpokenOutputStateHandler?
    ) async -> SpokenOutputSessionState {
        await setState(.failed(failure, request: request), onStateChange: onStateChange)
        return state
    }

    private func setState(
        _ newState: SpokenOutputSessionState,
        onStateChange: SpokenOutputStateHandler?
    ) async {
        state = newState
        stateHistory.append(newState)
        if let onStateChange {
            await onStateChange(newState)
        }
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
