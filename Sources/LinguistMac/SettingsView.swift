import AppKit
import LinguistMacCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppShellModel

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }

            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .padding(24)
        .frame(width: 620, height: 520)
        .task {
            await model.refreshProviderDescriptors()
            await model.refreshAppPreferences()
            await model.refreshReadiness()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Languages") {
                Picker("Source", selection: sourceLanguageBinding) {
                    ForEach(model.availableLanguages, id: \.id) { language in
                        Text(LocalizedStringKey(language.displayName))
                            .tag(language)
                    }
                }

                Picker("Target", selection: targetLanguageBinding) {
                    ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                        Text(LocalizedStringKey(language.displayName))
                            .tag(language)
                    }
                }

                Picker("App language", selection: appLanguageBinding) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        Text(LocalizedStringKey(language.displayName))
                            .tag(language)
                    }
                }
            }

            Section("Translation") {
                Picker("Engine", selection: $model.settings.selectedProviderID) {
                    ForEach(model.selectableProviders, id: \.id) { provider in
                        Text(provider.pickerTitle)
                            .tag(provider.id)
                    }
                }

                Toggle("Auto-copy result", isOn: $model.settings.autoCopyEnabled)
                Toggle("Cmd+C+C translation", isOn: $model.settings.doubleCopyTranslationEnabled)
                Toggle("Drag translation", isOn: $model.settings.dragTranslationEnabled)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let message = model.appPreferenceMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Provider Keys") {
                ForEach(model.availableProviders.filter(\.requiresAPIKey), id: \.id) { provider in
                    ProviderConfigurationRow(model: model, provider: provider)
                }
            }

            Section("Shortcuts") {
                ShortcutRow(title: "Screen Translate", shortcut: model.settings.screenTranslationShortcut)
                ShortcutRow(title: "Selected Text", shortcut: model.settings.textSelectionShortcut)
                ShortcutRow(title: "Quick Translate", shortcut: model.settings.quickTranslateShortcut)
                shortcutStatus
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            Section("Popup") {
                Stepper(
                    "Font size: \(Int(model.settings.popupFontSize)) pt",
                    value: $model.settings.popupFontSize,
                    in: 12 ... 22,
                    step: 1
                )

                Picker("Font", selection: $model.settings.popupFontFamily) {
                    ForEach(PopupFontOption.allCases) { option in
                        Text(option.displayName)
                            .tag(option.fontFamily)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Width: \(Int(model.settings.popupWidth)) px")
                    Slider(value: $model.settings.popupWidth, in: 320 ... 720, step: 20)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Height: \(Int(model.settings.popupHeight)) px")
                    Slider(value: $model.settings.popupHeight, in: 240 ... 640, step: 20)
                }

                Toggle("Match selection width", isOn: $model.settings.matchPopupWidthToSelection)
            }

            Section("Setup") {
                Toggle("Setup guide completed", isOn: onboardingCompletedBinding)

                ForEach(model.readiness.items) { item in
                    ReadinessRow(item: item) {
                        switch item.kind {
                        case .screenTranslation:
                            model.openSystemSettings(for: .screenRecording)
                        case .accessibility:
                            model.openSystemSettings(for: .accessibility)
                        case .voiceMicrophone:
                            model.openSystemSettings(for: .microphone)
                        case .speechRecognition:
                            model.openSystemSettings(for: .speechRecognition)
                        case .appleTranslation, .cloudProvider:
                            openSettingsWindow()
                        }
                    }
                }
            }

            Section("Privacy") {
                Text("The default path is on-device. Cloud providers stay optional and require explicit configuration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var onboardingCompletedBinding: Binding<Bool> {
        Binding {
            model.settings.hasCompletedOnboarding
        } set: { isCompleted in
            model.setOnboardingCompleted(isCompleted)
        }
    }

    private var sourceLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.settings.sourceLanguage
        } set: { language in
            model.setSourceLanguage(language)
        }
    }

    private var targetLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.settings.targetLanguage
        } set: { language in
            model.setTargetLanguage(language)
        }
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding {
            model.settings.appLanguage
        } set: { language in
            model.settings.appLanguage = language
            AppLanguagePreferenceApplier.apply(language)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.settings.launchAtLoginEnabled
        } set: { isEnabled in
            Task {
                await model.setLaunchAtLoginEnabled(isEnabled)
            }
        }
    }

    private func openSettingsWindow() {
        model.record(.settings)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        if model.shortcutRegistrationResults.isEmpty {
            Text("Shortcuts will register after Accessibility is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.shortcutRegistrationResults, id: \.action) { result in
                HStack {
                    Image(systemName: result.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isRegistered ? .green : .orange)
                    Text(result.action.settingsTitle)
                    Spacer()
                    Text(result.statusText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private enum PopupFontOption: String, CaseIterable, Identifiable {
    case system
    case notoSans
    case notoSansThai
    case notoSansCJK
    case thonburi
    case hiragino
    case pingFang

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .notoSans:
            "Noto Sans"
        case .notoSansThai:
            "Noto Sans Thai"
        case .notoSansCJK:
            "Noto Sans CJK"
        case .thonburi:
            "Thonburi"
        case .hiragino:
            "Hiragino Sans"
        case .pingFang:
            "PingFang SC"
        }
    }

    var fontFamily: String {
        switch self {
        case .system:
            ""
        case .notoSans:
            "Noto Sans"
        case .notoSansThai:
            "Noto Sans Thai"
        case .notoSansCJK:
            "Noto Sans CJK KR"
        case .thonburi:
            "Thonburi"
        case .hiragino:
            "Hiragino Sans"
        case .pingFang:
            "PingFang SC"
        }
    }
}

private struct ProviderConfigurationRow: View {
    @ObservedObject var model: AppShellModel
    let provider: TranslationProviderDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                    Text(provider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Label(provider.configurationStatus.displayText, systemImage: provider.statusImage)
                    .font(.caption)
                    .foregroundStyle(provider.statusTint)
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
            }
        }
        .padding(.vertical, 4)
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

private struct ShortcutRow: View {
    let title: String
    let shortcut: LinguistMacCore.KeyboardShortcut

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var displayText: String {
        let modifiers = shortcut.modifiers
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displaySymbol)
            .joined()
        return modifiers + shortcut.key.uppercased()
    }
}

private extension TranslationProviderDescriptor {
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

private extension LinguistMacCore.KeyboardModifier {
    var displaySymbol: String {
        switch self {
        case .command:
            "Cmd+"
        case .control:
            "Ctrl+"
        case .option:
            "Opt+"
        case .shift:
            "Shift+"
        }
    }
}

private extension ShortcutAction {
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

private extension ShortcutRegistrationResult {
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

private struct ReadinessRow: View {
    let item: OnboardingReadinessItem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.showsRecoveryAction {
                Button("Open") {
                    action()
                }
                .controlSize(.small)
            }
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
