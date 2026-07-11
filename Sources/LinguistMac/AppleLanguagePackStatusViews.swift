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

struct PopupLanguagePickerOption: View {
    let language: TranslationLanguage
    let readiness: LanguagePackReadiness?

    var body: some View {
        Group {
            if let readiness {
                Label {
                    Text(LocalizedStringKey(language.displayName))
                } icon: {
                    Image(systemName: readiness.settingsStatusImage)
                        .foregroundStyle(readiness.settingsStatusTint)
                }
            } else {
                Text(LocalizedStringKey(language.displayName))
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let readiness else {
            return language.displayName
        }

        return "\(language.displayName), Apple language pack \(readiness.displayText)"
    }
}

extension AppleLanguagePackSelection {
    var settingsStatusText: String {
        guard pair != nil else {
            return "Select Pair"
        }

        return readiness.displayText
    }

    var settingsStatusTint: Color {
        guard pair != nil else {
            return .secondary
        }

        return readiness.settingsStatusTint
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
