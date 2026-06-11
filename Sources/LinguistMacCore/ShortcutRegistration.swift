import Foundation

public enum ShortcutRegistrationIssue: Equatable, Sendable {
    case duplicate(ShortcutAction)
    case permissionDenied(PermissionKind)
    case unavailable(String)
}

public struct ShortcutRegistrationResult: Equatable, Sendable {
    public let action: ShortcutAction
    public let shortcut: KeyboardShortcut
    public let issue: ShortcutRegistrationIssue?

    public init(
        action: ShortcutAction,
        shortcut: KeyboardShortcut,
        issue: ShortcutRegistrationIssue? = nil
    ) {
        self.action = action
        self.shortcut = shortcut
        self.issue = issue
    }

    public var isRegistered: Bool {
        issue == nil
    }
}

public struct ShortcutRegistrationPlan: Equatable, Sendable {
    public let assignments: [ShortcutAction: KeyboardShortcut]
    private let actionOrder: [ShortcutAction] = [
        .screenTranslation,
        .textSelectionTranslation,
        .quickTranslate
    ]

    public init(settings: AppSettings) {
        assignments = [
            .screenTranslation: settings.screenTranslationShortcut,
            .textSelectionTranslation: settings.textSelectionShortcut,
            .quickTranslate: settings.quickTranslateShortcut
        ]
    }

    public func validated(accessibilityStatus: PermissionStatus) -> [ShortcutRegistrationResult] {
        let duplicates = duplicateOwners()

        return assignments
            .keys
            .sorted { lhs, rhs in
                actionSortIndex(lhs) < actionSortIndex(rhs)
            }
            .map { action in
                let shortcut = assignments[action] ?? .screenTranslationDefault
                if accessibilityStatus != .granted {
                    return ShortcutRegistrationResult(
                        action: action,
                        shortcut: shortcut,
                        issue: .permissionDenied(.accessibility)
                    )
                }
                if let duplicate = duplicates[action] {
                    return ShortcutRegistrationResult(
                        action: action,
                        shortcut: shortcut,
                        issue: .duplicate(duplicate)
                    )
                }

                return ShortcutRegistrationResult(action: action, shortcut: shortcut)
            }
    }

    private func duplicateOwners() -> [ShortcutAction: ShortcutAction] {
        var firstOwnerByShortcut: [KeyboardShortcut: ShortcutAction] = [:]
        var duplicates: [ShortcutAction: ShortcutAction] = [:]

        for action in assignments.keys.sorted(by: { actionSortIndex($0) < actionSortIndex($1) }) {
            guard let shortcut = assignments[action] else {
                continue
            }

            if let firstOwner = firstOwnerByShortcut[shortcut] {
                duplicates[action] = firstOwner
            } else {
                firstOwnerByShortcut[shortcut] = action
            }
        }

        return duplicates
    }

    private func actionSortIndex(_ action: ShortcutAction) -> Int {
        actionOrder.firstIndex(of: action) ?? Int.max
    }
}

public actor ShortcutRegistrationCoordinator {
    private let registry: any ShortcutRegistering
    private var registeredActions: Set<ShortcutAction> = []

    public init(registry: any ShortcutRegistering) {
        self.registry = registry
    }

    public func refresh(
        settings: AppSettings,
        accessibilityStatus: PermissionStatus
    ) async -> [ShortcutRegistrationResult] {
        let results = ShortcutRegistrationPlan(settings: settings)
            .validated(accessibilityStatus: accessibilityStatus)
        let validResults = results.filter(\.isRegistered)
        let validActions = Set(validResults.map(\.action))

        for action in registeredActions.subtracting(validActions) {
            await registry.unregister(action)
        }

        var finalResults: [ShortcutRegistrationResult] = []
        for result in results {
            guard result.isRegistered else {
                finalResults.append(result)
                continue
            }

            do {
                try await registry.register(result.shortcut, for: result.action)
                registeredActions.insert(result.action)
                finalResults.append(result)
            } catch {
                finalResults.append(
                    ShortcutRegistrationResult(
                        action: result.action,
                        shortcut: result.shortcut,
                        issue: .unavailable(error.localizedDescription)
                    )
                )
            }
        }

        registeredActions.formIntersection(validActions)
        return finalResults
    }
}

public struct DoubleCopyTriggerDetector: Equatable, Sendable {
    public var triggerWindow: TimeInterval
    private var lastCopyCommandAt: Date?

    public init(triggerWindow: TimeInterval = 0.7) {
        self.triggerWindow = triggerWindow
    }

    public mutating func recordCopyCommand(at date: Date) -> Bool {
        guard let lastCopyCommandAt,
              date.timeIntervalSince(lastCopyCommandAt) <= triggerWindow
        else {
            lastCopyCommandAt = date
            return false
        }

        self.lastCopyCommandAt = nil
        return true
    }

    public mutating func reset() {
        lastCopyCommandAt = nil
    }
}
