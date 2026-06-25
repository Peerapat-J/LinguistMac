import AppKit
import LinguistMacCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppShellModel
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsPane {
                generalSettings
            }
            .tabItem {
                Label("General", systemImage: "slider.horizontal.3")
            }
            .tag(SettingsTab.general)

            settingsPane {
                advancedSettings
            }
            .tabItem {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
            }
            .tag(SettingsTab.advanced)
        }
        .focusable(false)
        .frame(width: 620, height: 520)
        .task {
            await model.refreshProviderDescriptors()
            await model.refreshAppPreferences()
            await model.refreshReadiness()
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            settingsSection("Languages") {
                settingsRow("Source") {
                    Picker("", selection: sourceLanguageBinding) {
                        ForEach(model.availableLanguages, id: \.id) { language in
                            Text(LocalizedStringKey(language.displayName))
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.compactControlWidth)
                }

                settingsRow("Target") {
                    Picker("", selection: targetLanguageBinding) {
                        ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                            Text(LocalizedStringKey(language.displayName))
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.compactControlWidth)
                }

                settingsRow("App language") {
                    Picker("", selection: appLanguageBinding) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(LocalizedStringKey(language.displayName))
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.compactControlWidth)
                }
            }

            settingsSection("Translation") {
                settingsRow("Engine") {
                    Picker("", selection: $model.settings.selectedProviderID) {
                        ForEach(model.selectableProviders, id: \.id) { provider in
                            Text(provider.pickerTitle)
                                .tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.compactControlWidth)
                }

                indentedSetting {
                    Toggle("Auto-copy result", isOn: $model.settings.autoCopyEnabled)
                }
                indentedSetting {
                    Toggle("Cmd+C+C translation", isOn: $model.settings.doubleCopyTranslationEnabled)
                }
                indentedSetting {
                    Toggle("Drag translation", isOn: $model.settings.dragTranslationEnabled)
                }
                indentedSetting {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                }
                if let message = model.appPreferenceMessage {
                    indentedSetting {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            settingsSection("Provider Keys") {
                ForEach(Array(apiKeyProviders.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        SettingsDivider()
                    }
                    ProviderConfigurationRow(model: model, provider: provider)
                }
            }

            settingsSection("Shortcuts") {
                ShortcutRow(title: "Screen Translate", shortcut: model.settings.screenTranslationShortcut)
                SettingsDivider()
                ShortcutRow(title: "Selected Text", shortcut: model.settings.textSelectionShortcut)
                SettingsDivider()
                ShortcutRow(title: "Quick Translate", shortcut: model.settings.quickTranslateShortcut)
                SettingsDivider()
                shortcutStatus
            }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            settingsSection("Popup") {
                settingsRow("Font size") {
                    Stepper(
                        "\(Int(model.settings.popupFontSize)) pt",
                        value: $model.settings.popupFontSize,
                        in: 12 ... 22,
                        step: 1
                    )
                    .frame(maxWidth: 140, alignment: .leading)
                }

                settingsRow("Font") {
                    Picker("", selection: $model.settings.popupFontFamily) {
                        ForEach(PopupFontOption.allCases) { option in
                            Text(option.displayName)
                                .tag(option.fontFamily)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsLayout.compactControlWidth)
                }

                settingsRow("Width") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(model.settings.popupWidth)) px")
                            .foregroundStyle(.secondary)
                        Slider(value: $model.settings.popupWidth, in: 320 ... 720, step: 20)
                            .frame(maxWidth: .infinity)
                    }
                }

                settingsRow("Height") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(model.settings.popupHeight)) px")
                            .foregroundStyle(.secondary)
                        Slider(value: $model.settings.popupHeight, in: 240 ... 640, step: 20)
                            .frame(maxWidth: .infinity)
                    }
                }

                indentedSetting {
                    Toggle("Match selection width", isOn: $model.settings.matchPopupWidthToSelection)
                }
            }

            settingsSection("Setup") {
                indentedSetting {
                    Toggle("Setup guide completed", isOn: onboardingCompletedBinding)
                }

                ForEach(model.readiness.items) { item in
                    SettingsDivider()
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
                            model.record(.settings)
                            selectedTab = .general
                        }
                    }
                }
            }

            settingsSection("Privacy") {
                Text("The default path is on-device. Cloud providers stay optional and require explicit configuration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var apiKeyProviders: [TranslationProviderDescriptor] {
        model.availableProviders.filter(\.requiresAPIKey)
    }

    private func settingsPane(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: SettingsLayout.contentWidth, alignment: .leading)
                .padding(.horizontal, SettingsLayout.horizontalPadding)
                .padding(.top, SettingsLayout.topPadding)
                .padding(.bottom, SettingsLayout.bottomPadding)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.visible)
    }

    private func settingsSection(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        SettingsSectionCard(title) {
            content()
        }
    }

    private func settingsRow(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.rowLabelSpacing) {
            Text(title)
                .frame(width: SettingsLayout.labelWidth, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func indentedSetting(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.leading, SettingsLayout.labelWidth + SettingsLayout.rowLabelSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    private var shortcutStatus: some View {
        if model.shortcutRegistrationResults.isEmpty {
            Text("Shortcuts will register after Accessibility is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(model.shortcutRegistrationResults, id: \.action) { result in
                HStack {
                    Image(systemName: result.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isRegistered ? .green : .orange)
                    Text(result.action.settingsTitle)
                    Spacer()
                    Text(result.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
    }
}

private struct SettingsSectionCard<Content: View>: View {
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

            VStack(alignment: .leading, spacing: SettingsLayout.rowSpacing) {
                content
            }
            .padding(SettingsLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
    }
}

private enum SettingsLayout {
    static let contentWidth: CGFloat = 520
    static let compactControlWidth: CGFloat = 360
    static let labelWidth: CGFloat = 112
    static let rowLabelSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 10
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 14
    static let cardCornerRadius: CGFloat = 14
    static let cardTitleSpacing: CGFloat = 8
    static let cardTitleInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 28
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 24
}

private enum SettingsTab: Hashable {
    case general
    case advanced
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
                .lineLimit(1)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            if item.showsRecoveryAction {
                Button("Open") {
                    action()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
