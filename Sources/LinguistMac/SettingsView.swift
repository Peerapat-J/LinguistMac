import AppKit
import LinguistMacCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel
    @State private var selectedSection: SettingsSectionID? = .general
    @State private var sidebarSearchText = ""
    @State private var readinessRefreshTrigger = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(filteredSidebarSections) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }

                if filteredSidebarSections.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $sidebarSearchText, placement: .sidebar, prompt: "Search")
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 128, ideal: 144, max: 176)
        } detail: {
            detailPane(for: selectedSection ?? .general)
        }
        .focusable(false)
        .frame(width: 760, height: 560)
        .task {
            await model.refreshProviderDescriptors()
            await model.refreshAppPreferences()
        }
        .readinessRefreshMonitor(model: model, trigger: readinessRefreshTrigger)
    }
}

private extension SettingsView {
    @ViewBuilder
    func detailPane(for section: SettingsSectionID) -> some View {
        switch section {
        case .general:
            settingsPane(section) {
                generalSettings
            }
        case .translation:
            settingsPane(section) {
                translationSettings
            }
        case .appearance:
            settingsPane(section) {
                appearanceSettings
            }
        case .api:
            settingsPane(section) {
                apiSettings
            }
        case .setup:
            settingsPane(section) {
                setupSettings
            }
        case .privacy:
            settingsPane(section) {
                privacySettings
            }
        }
    }

    var generalSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            settingsSection("General") {
                settingsRow("App language") {
                    Picker("", selection: appLanguageBinding) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(LocalizedStringKey(language.displayName))
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }
                SettingsDivider()
                settingsSwitchRow("Auto-copy result", isOn: $model.settings.autoCopyEnabled)
                SettingsDivider()
                settingsSwitchRow("Cmd+C+C translation", isOn: $model.settings.doubleCopyTranslationEnabled)
                SettingsDivider()
                settingsSwitchRow("Drag translation", isOn: $model.settings.dragTranslationEnabled)
                SettingsDivider()
                settingsSwitchRow("Launch at login", isOn: launchAtLoginBinding)
                if let message = model.appPreferenceMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSection("Shortcuts") {
                ShortcutRow(
                    title: "Screen Translate",
                    shortcut: model.settings.screenTranslationShortcut,
                    result: shortcutResult(for: .screenTranslation)
                )
                SettingsDivider()
                ShortcutRow(
                    title: "Selected Text",
                    shortcut: model.settings.textSelectionShortcut,
                    result: shortcutResult(for: .textSelectionTranslation)
                )
                SettingsDivider()
                ShortcutRow(
                    title: "Quick Translate",
                    shortcut: model.settings.quickTranslateShortcut,
                    result: shortcutResult(for: .quickTranslate)
                )
            }
        }
    }

    var translationSettings: some View {
        settingsSection("Translation") {
            settingsRow("Engine") {
                Picker("", selection: $model.settings.selectedProviderID) {
                    ForEach(model.selectableProviders, id: \.id) { provider in
                        Text(provider.pickerTitle)
                            .tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
            SettingsDivider()
            settingsRow("Source language") {
                Picker("", selection: sourceLanguageBinding) {
                    ForEach(model.availableLanguages, id: \.id) { language in
                        Text(LocalizedStringKey(language.displayName))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
            SettingsDivider()
            settingsRow("Target language") {
                Picker("", selection: targetLanguageBinding) {
                    ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                        Text(LocalizedStringKey(language.displayName))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
        }
    }

    var appearanceSettings: some View {
        settingsSection("Appearance") {
            settingsRow("Font family") {
                Picker("", selection: $model.settings.popupFontFamily) {
                    ForEach(PopupFontOption.allCases) { option in
                        Text(option.displayName)
                            .tag(option.fontFamily)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
            SettingsDivider()
            settingsRow("Font size") {
                Stepper(
                    "\(Int(model.settings.popupFontSize)) pt",
                    value: $model.settings.popupFontSize,
                    in: 12 ... 22,
                    step: 1
                )
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
            }
            SettingsDivider()
            settingsRow("Width") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int(model.settings.popupWidth)) px")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.settings.popupWidth, in: 320 ... 720, step: 20)
                        .frame(maxWidth: .infinity)
                }
            }
            SettingsDivider()
            settingsRow("Height") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(Int(model.settings.popupHeight)) px")
                        .foregroundStyle(.secondary)
                    Slider(value: $model.settings.popupHeight, in: 240 ... 640, step: 20)
                        .frame(maxWidth: .infinity)
                }
            }
            SettingsDivider()
            settingsSwitchRow("Match selection width", isOn: $model.settings.matchPopupWidthToSelection)
        }
    }

    var apiSettings: some View {
        settingsSection("Provider Keys") {
            ForEach(Array(apiKeyProviders.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    SettingsDivider()
                }
                ProviderConfigurationRow(model: model, provider: provider)
            }
        }
    }

    var setupSettings: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardTitleSpacing) {
            settingsSection("Setup") {
                ForEach(Array(model.readiness.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { SettingsDivider() }
                    ReadinessRow(item: item) {
                        handleReadinessAction(for: item)
                    }
                }
            }

            Button {
                openSetupGuide()
            } label: {
                Label("Open Setup Guide", systemImage: "checklist")
            }
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    var privacySettings: some View {
        PrivacySettingsSection()
    }

    var apiKeyProviders: [TranslationProviderDescriptor] {
        model.availableProviders.filter(\.requiresAPIKey)
    }

    var filteredSidebarSections: [SettingsSectionID] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SettingsSectionID.allCases
        }
        return SettingsSectionID.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    func handleReadinessAction(for item: OnboardingReadinessItem) {
        switch item.kind {
        case .screenTranslation:
            model.openSystemSettings(for: .screenRecording)
        case .accessibility:
            model.openSystemSettings(for: .accessibility)
        case .voiceMicrophone:
            model.openSystemSettings(for: .microphone)
        case .speechRecognition:
            model.openSystemSettings(for: .speechRecognition)
        case .appleTranslation:
            model.record(.settings)
            selectedSection = .translation
        case .cloudProvider:
            model.record(.settings)
            selectedSection = .api
        }

        readinessRefreshTrigger += 1
    }

    func openSetupGuide() {
        model.reopenOnboarding()
        openWindow(id: AppWindow.onboarding.rawValue)
        NSApp.activate(ignoringOtherApps: true)
        readinessRefreshTrigger += 1
    }

    func settingsPane(
        _ section: SettingsSectionID,
        @ViewBuilder content: () -> some View
    ) -> some View {
        ScrollView {
            content()
                .frame(maxWidth: SettingsLayout.contentWidth, alignment: .leading)
                .padding(.horizontal, SettingsLayout.horizontalPadding)
                .padding(.top, SettingsLayout.topPadding)
                .padding(.bottom, SettingsLayout.bottomPadding)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.visible)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(section.title)
    }

    func settingsSection(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        SettingsSectionCard(title) {
            content()
        }
    }

    func settingsRow(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsLayout.rowSpacing) {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    func settingsSwitchRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        settingsRow(title) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    var sourceLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.settings.sourceLanguage
        } set: { language in
            model.setSourceLanguage(language)
        }
    }

    var targetLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.settings.targetLanguage
        } set: { language in
            model.setTargetLanguage(language)
        }
    }

    var appLanguageBinding: Binding<AppLanguage> {
        Binding {
            model.settings.appLanguage
        } set: { language in
            model.settings.appLanguage = language
            AppLanguagePreferenceApplier.apply(language)
        }
    }

    var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.settings.launchAtLoginEnabled
        } set: { isEnabled in
            Task {
                await model.setLaunchAtLoginEnabled(isEnabled)
            }
        }
    }

    func shortcutResult(for action: ShortcutAction) -> ShortcutRegistrationResult? {
        model.shortcutRegistrationResults.first { $0.action == action }
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
