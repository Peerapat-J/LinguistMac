public enum CaptureSelectionState: Equatable, Sendable {
    case idle
    case selecting
    case completed(CapturedScreenRegion)
    case cancelled
    case failed(TranslationFailure)
}

public struct CaptureSelectionStateMachine: Equatable, Sendable {
    public private(set) var state: CaptureSelectionState

    public init(state: CaptureSelectionState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func start() -> Bool {
        guard state != .selecting else {
            return false
        }

        state = .selecting
        return true
    }

    public mutating func complete(with region: CapturedScreenRegion) {
        guard state == .selecting else {
            return
        }

        state = .completed(region)
    }

    public mutating func cancel() {
        guard state == .selecting else {
            return
        }

        state = .cancelled
    }

    public mutating func fail(with failure: TranslationFailure) {
        state = .failed(failure)
    }

    public mutating func reset() {
        state = .idle
    }
}
