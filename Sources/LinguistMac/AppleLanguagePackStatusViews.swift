import AppKit
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
                    Image(nsImage: popupLanguagePackStatusMenuImage(for: readiness))
                        .renderingMode(.original)
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

func popupLanguagePackStatusMenuImage(for readiness: LanguagePackReadiness) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [readiness.settingsStatusNSColor]))
    let image = NSImage(
        systemSymbolName: readiness.settingsStatusImage,
        accessibilityDescription: readiness.displayText
    )?
        .withSymbolConfiguration(configuration) ?? NSImage(size: NSSize(width: 12, height: 12))
    image.isTemplate = false
    return image
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

    var settingsStatusNSColor: NSColor {
        switch self {
        case .unknown:
            .secondaryLabelColor
        case .ready:
            .systemGreen
        case .needsDownload:
            .systemOrange
        case .unavailable:
            .systemRed
        }
    }
}
