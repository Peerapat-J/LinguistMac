import KeyboardShortcuts
import LinguistMacCore
import SwiftUI

enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case general
    case translation
    case appearance
    case api
    case setup
    case privacy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "General"
        case .translation:
            "Translation"
        case .appearance:
            "Appearance"
        case .api:
            "API"
        case .setup:
            "Setup"
        case .privacy:
            "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .translation:
            "character.bubble"
        case .appearance:
            "paintbrush"
        case .api:
            "key"
        case .setup:
            "checklist"
        case .privacy:
            "hand.raised"
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardTitleSpacing) {
            Text(title)
                .font(.headline)
                .padding(.leading, SettingsLayout.cardTitleInset)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsLayout.cardPadding)
            .padding(.vertical, SettingsLayout.cardVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
    }
}

struct SettingsDetailHeader: View {
    let title: String
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let navigateBack: () -> Void
    let navigateForward: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                headerButton(systemImage: "chevron.left", isEnabled: canNavigateBack, action: navigateBack)

                Divider()
                    .frame(height: 18)

                headerButton(systemImage: "chevron.right", isEnabled: canNavigateForward, action: navigateForward)
            }
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            }

            Text(title)
                .font(.headline)

            Spacer()
        }
        .padding(.leading, 18)
        .padding(.trailing, SettingsLayout.horizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
    }
}

enum SettingsLayout {
    static let contentWidth: CGFloat = 430
    static let controlWidth: CGFloat = 150
    static let rowSpacing: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 7
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let cardVerticalPadding: CGFloat = 6
    static let cardCornerRadius: CGFloat = 14
    static let cardTitleSpacing: CGFloat = 8
    static let cardTitleInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 24
    static let topPadding: CGFloat = 18
    static let bottomPadding: CGFloat = 24
}

struct ProviderConfigurationRow: View {
    @ObservedObject var model: AppShellModel
    let provider: TranslationProviderDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                    Text(provider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                Label(provider.configurationStatus.displayText, systemImage: provider.statusImage)
                    .font(.caption)
                    .foregroundStyle(provider.statusTint)
                    .lineLimit(1)
            }

            SecureField("API key", text: apiKeyDraftBinding)

            if provider.id == .microsoftAzure {
                TextField("Region", text: apiRegionDraftBinding)
            }

            HStack {
                Button("Save") {
                    Task {
                        await model.saveAPIKey(for: provider.id)
                    }
                }

                Button("Test") {
                    Task {
                        await model.testAPIKeyConfiguration(for: provider.id)
                    }
                }

                Button("Clear", role: .destructive) {
                    Task {
                        await model.clearAPIKey(for: provider.id)
                    }
                }

                Spacer()
            }
            .controlSize(.small)

            if let message = model.providerConfigurationMessages[provider.id] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var apiKeyDraftBinding: Binding<String> {
        Binding {
            model.providerAPIKeyDrafts[provider.id, default: ""]
        } set: { value in
            model.providerAPIKeyDrafts[provider.id] = value
        }
    }

    private var apiRegionDraftBinding: Binding<String> {
        Binding {
            model.providerAPIRegionDrafts[provider.id, default: ""]
        } set: { value in
            model.providerAPIRegionDrafts[provider.id] = value
        }
    }
}

struct ShortcutRow: View {
    let title: String
    @Binding var shortcut: LinguistMacCore.KeyboardShortcut
    let defaultShortcut: LinguistMacCore.KeyboardShortcut
    let result: ShortcutRegistrationResult?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                KeyboardShortcuts.Recorder(shortcut: keyboardShortcutBinding)
                    .shortcutValidation { keyboardShortcut in
                        guard LinguistMacCore.KeyboardShortcut(keyboardShortcut) != nil else {
                            return .disallow(reason: "This key is not supported yet.")
                        }
                        return .allow
                    }
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let result, result.issue != nil {
                HStack(spacing: 6) {
                    Image(systemName: result.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isRegistered ? .green : .orange)
                    Text(result.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }

    private var keyboardShortcutBinding: Binding<KeyboardShortcuts.Shortcut?> {
        Binding {
            shortcut.keyboardShortcutsShortcut
        } set: { newValue in
            guard let newValue else {
                shortcut = defaultShortcut
                onChange()
                return
            }

            if let appShortcut = LinguistMacCore.KeyboardShortcut(newValue) {
                shortcut = appShortcut
            } else {
                shortcut = defaultShortcut
            }
            onChange()
        }
    }
}

struct ReadinessRow: View {
    let item: OnboardingReadinessItem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                    Text(item.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.tint)
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if item.showsRecoveryAction {
                Button("Open") {
                    action()
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

extension TranslationProviderDescriptor {
    var pickerTitle: String {
        isConfigured || !requiresAPIKey
            ? displayName
            : "\(displayName) - API key required"
    }

    var statusImage: String {
        switch configurationStatus {
        case .ready:
            "checkmark.circle.fill"
        case .needsAPIKey:
            "key.fill"
        case .unavailable:
            "exclamationmark.triangle.fill"
        }
    }

    var statusTint: Color {
        switch configurationStatus {
        case .ready:
            .green
        case .needsAPIKey:
            .orange
        case .unavailable:
            .red
        }
    }
}

extension ShortcutAction {
    var settingsTitle: String {
        switch self {
        case .screenTranslation:
            "Screen Translate"
        case .textSelectionTranslation:
            "Selected Text"
        case .quickTranslate:
            "Quick Translate"
        case .clipboardDoubleCopy:
            "Cmd+C+C"
        case .dragTranslation:
            "Drag Translation"
        }
    }
}

extension ShortcutRegistrationResult {
    var statusText: String {
        switch issue {
        case nil:
            "Registered"
        case .permissionDenied:
            "Needs Accessibility"
        case let .duplicate(action):
            "Conflicts with \(action.settingsTitle)"
        case .unavailable:
            "Unavailable"
        }
    }
}

extension PermissionStatus {
    var systemImage: String {
        switch self {
        case .granted:
            "checkmark.circle.fill"
        case .notDetermined:
            "circle.dashed"
        case .denied:
            "xmark.circle.fill"
        case .restricted:
            "lock.circle.fill"
        case .unavailable:
            "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .granted:
            .green
        case .notDetermined:
            .secondary
        case .denied, .restricted:
            .red
        case .unavailable:
            .orange
        }
    }
}
