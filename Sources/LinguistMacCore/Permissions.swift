public enum PermissionKind: String, CaseIterable, Sendable {
    case screenRecording
    case accessibility
    case keychain
    case network
}

public enum PermissionStatus: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable
}

public struct PermissionRequirement: Equatable, Sendable {
    public let kind: PermissionKind
    public let reason: String
    public let isRequiredForDefaultWorkflow: Bool

    public init(
        kind: PermissionKind,
        reason: String,
        isRequiredForDefaultWorkflow: Bool
    ) {
        self.kind = kind
        self.reason = reason
        self.isRequiredForDefaultWorkflow = isRequiredForDefaultWorkflow
    }
}

public enum PermissionBaseline {
    public static let defaultRequirements: [PermissionRequirement] = [
        PermissionRequirement(
            kind: .screenRecording,
            reason: "Capturing a selected screen region for OCR.",
            isRequiredForDefaultWorkflow: true
        ),
        PermissionRequirement(
            kind: .accessibility,
            reason: "Reading selected text, double-copy, and drag translation workflows.",
            isRequiredForDefaultWorkflow: false
        ),
        PermissionRequirement(
            kind: .keychain,
            reason: "Storing optional bring-your-own-key provider credentials.",
            isRequiredForDefaultWorkflow: false
        ),
        PermissionRequirement(
            kind: .network,
            reason: "Calling optional cloud translation providers selected by the user.",
            isRequiredForDefaultWorkflow: false
        )
    ]
}
