import LinguistMacCore
import SwiftUI

struct AppleLanguagePackStatusGlyph: View {
    let systemName: String
    let tint: Color
    let isProgressing: Bool
    let isChecking: Bool

    var body: some View {
        Group {
            if isProgressing || isChecking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .tint(tint)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: systemName)
                    .id(systemName)
            }
        }
        .foregroundStyle(tint)
        .frame(width: 20)
    }
}

extension AppleLanguagePackSelection {
    var settingsStatusText: String {
        guard pair != nil else {
            return "Select Pair"
        }

        return preparationStatusText
    }

    var settingsStatusTint: Color {
        guard pair != nil else {
            return .secondary
        }

        return preparationStatusTint
    }
}

private extension AppleLanguagePackSelection {
    var preparationStatusText: String {
        if hasPreparationFailure {
            return "Download Failed"
        }
        if hasIncompletePreparation {
            return "Downloading"
        }
        if wasPreparationCanceled {
            return "Canceled"
        }

        return isPreparing ? "Downloading" : readiness.displayText
    }

    var preparationStatusTint: Color {
        AppleLanguagePackPreparationPresentation.tint(
            isPreparing: isPreparing,
            hasFailure: hasPreparationFailure,
            hasIncompletePreparation: hasIncompletePreparation,
            wasCanceled: wasPreparationCanceled,
            fallback: readiness.settingsStatusTint
        )
    }
}

private enum AppleLanguagePackPreparationPresentation {
    static func tint(
        isPreparing: Bool,
        hasFailure: Bool,
        hasIncompletePreparation: Bool,
        wasCanceled: Bool,
        fallback: Color
    ) -> Color {
        if isPreparing {
            return .orange
        }
        if hasFailure {
            return .red
        }
        if hasIncompletePreparation {
            return .orange
        }
        if wasCanceled {
            return .secondary
        }

        return fallback
    }
}

extension LanguagePackReadiness {
    var settingsStatusImage: String {
        switch self {
        case .unknown:
            "circle.dashed"
        case .ready:
            "checkmark.circle.fill"
        case .needsDownload:
            "arrow.down.circle.fill"
        case .unavailable:
            "minus.circle.fill"
        }
    }

    var settingsStatusTint: Color {
        switch self {
        case .unknown:
            .secondary
        case .ready:
            .green
        case .needsDownload:
            .orange
        case .unavailable:
            .red
        }
    }
}

extension AppShellModel {
    func preferredAppleLanguagePackMessage(
        _ messages: [AppleLanguagePackPreparationMessage]
    ) -> AppleLanguagePackPreparationMessage? {
        messages.first { $0.kind == .failure }
            ?? messages.first { $0.kind == .canceled }
            ?? messages.first { $0.kind == .notCompleted }
            ?? messages.first
    }

    func preparationMessage(for readiness: LanguagePackReadiness) -> AppleLanguagePackPreparationMessage {
        switch readiness {
        case .ready:
            AppleLanguagePackPreparationMessage(text: "Language pack is ready.")
        case .needsDownload:
            AppleLanguagePackPreparationMessage(
                text: "macOS is still preparing this language pack.",
                kind: .notCompleted
            )
        case .unavailable:
            AppleLanguagePackPreparationMessage(
                text: "This language pair is not supported by Apple Translation.",
                kind: .failure
            )
        case .unknown:
            AppleLanguagePackPreparationMessage(text: "Language pack status could not be checked.")
        }
    }

    func preparationContinuingMessage() -> AppleLanguagePackPreparationMessage {
        AppleLanguagePackPreparationMessage(
            text: "macOS is still preparing this language pack."
        )
    }

    func preparationNeedsDownloadMessage() -> AppleLanguagePackPreparationMessage {
        AppleLanguagePackPreparationMessage(
            text: "Download was not started or has not completed."
        )
    }

    func preparationFailureMessage(from error: Error) -> AppleLanguagePackPreparationMessage {
        guard let failure = error as? TranslationFailure else {
            return AppleLanguagePackPreparationMessage(
                text: "Apple Translation could not prepare this language pair.",
                kind: .failure
            )
        }

        switch failure {
        case .unsupportedLanguagePair:
            return AppleLanguagePackPreparationMessage(
                text: "This language pair is not supported by Apple Translation.",
                kind: .failure
            )
        case .missingLanguagePack:
            return AppleLanguagePackPreparationMessage(
                text: "macOS is still preparing this language pack.",
                kind: .notCompleted
            )
        case .providerUnavailable:
            return AppleLanguagePackPreparationMessage(
                text: "Apple Translation is not available on this Mac.",
                kind: .failure
            )
        default:
            return AppleLanguagePackPreparationMessage(
                text: "Apple Translation could not prepare this language pair.",
                kind: .failure
            )
        }
    }
}
