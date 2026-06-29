import AppKit
import LinguistMacCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel
    @State private var selectedSection: SettingsSectionID? = .general
    @State private var sidebarSearchText = ""
    @State private var sectionHistory: [SettingsSectionID] = [.general]
    @State private var sectionHistoryIndex = 0
    @State private var readinessRefreshTrigger = 0

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            detailPane(for: selectedSection ?? .general)
        }
        .ignoresSafeArea(.container, edges: .top)
        .focusable(false)
        .frame(width: 680, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsWindowConfigurator())
        .onChange(of: selectedSection) { _, newValue in
            guard let newValue else {
                return
            }
            recordSectionSelection(newValue)
        }
        .task {
            await model.refreshProviderDescriptors()
            await model.refreshAppPreferences()
            await model.refreshScreenTranslationSoundNames()
        }
        .readinessRefreshMonitor(model: model, trigger: readinessRefreshTrigger)
    }
}

private extension SettingsView {
    var settingsSidebar: some View {
        VStack(spacing: 0) {
            SidebarTrafficLights()
                .padding(.top, 14)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search", text: $sidebarSearchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            VStack(spacing: 4) {
                ForEach(filteredSidebarSections) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        if selectedSection == section {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.accentColor)
                        }
                    }
                    .foregroundStyle(selectedSection == section ? .white : .primary)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }

                if filteredSidebarSections.isEmpty {
                    Text("No Results")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(width: 176)
        .background {
            SidebarMaterialBackground()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.7))
                .frame(width: 1)
        }
    }

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
        case .notification:
            settingsPane(section) {
                notificationSettings
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
            settingsSection("App") {
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
                settingsRow("Menu Bar Icon") {
                    Picker("", selection: $model.settings.menuBarIcon) {
                        ForEach(MenuBarIcon.allCases, id: \.rawValue) { icon in
                            Label(icon.displayName, systemImage: icon.systemImage)
                                .tag(icon)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
                }
                SettingsDivider()
                settingsSwitchRow("Launch at login", isOn: launchAtLoginBinding)
                SettingsDivider()
                settingsSwitchRow("Auto copy result to clipboard", isOn: $model.settings.autoCopyEnabled)
                SettingsDivider()
                settingsSwitchRow("Drag translation", isOn: $model.settings.dragTranslationEnabled)
                SettingsDivider()
                settingsSwitchRow("Selected text translation", isOn: $model.settings.doubleCopyTranslationEnabled)
                if let message = model.appPreferenceMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSection("Shortcut") {
                settingsSwitchRow("Enable Shortcut", isOn: shortcutsEnabledBinding)
                SettingsDivider()
                ShortcutRow(
                    title: "Screen translate",
                    shortcut: shortcutBinding(\.screenTranslationShortcut),
                    defaultShortcut: .screenTranslationDefault,
                    result: shortcutResult(for: .screenTranslation),
                    onChange: refreshShortcuts
                )
                .disabled(!model.settings.shortcutsEnabled)
                SettingsDivider()
                ShortcutRow(
                    title: "Quick translate",
                    shortcut: shortcutBinding(\.quickTranslateShortcut),
                    defaultShortcut: .quickTranslateDefault,
                    result: shortcutResult(for: .quickTranslate),
                    onChange: refreshShortcuts
                )
                .disabled(!model.settings.shortcutsEnabled)
                SettingsDivider()
                ShortcutRow(
                    title: "Selected text translate",
                    shortcut: shortcutBinding(\.textSelectionShortcut),
                    defaultShortcut: .textSelectionDefault,
                    result: shortcutResult(for: .textSelectionTranslation),
                    onChange: refreshShortcuts
                )
                .disabled(!model.settings.shortcutsEnabled)
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

    var notificationSettings: some View {
        NotificationSettingsSection(model: model)
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

    var canNavigateBack: Bool {
        sectionHistoryIndex > 0
    }

    var canNavigateForward: Bool {
        sectionHistoryIndex < sectionHistory.count - 1
    }

    func recordSectionSelection(_ section: SettingsSectionID) {
        guard sectionHistory.indices.contains(sectionHistoryIndex) else {
            sectionHistory = [section]
            sectionHistoryIndex = 0
            return
        }

        guard sectionHistory[sectionHistoryIndex] != section else {
            return
        }

        sectionHistory = Array(sectionHistory.prefix(sectionHistoryIndex + 1))
        sectionHistory.append(section)
        sectionHistoryIndex = sectionHistory.count - 1
    }

    func navigateBack() {
        guard canNavigateBack else {
            return
        }

        sectionHistoryIndex -= 1
        selectedSection = sectionHistory[sectionHistoryIndex]
    }

    func navigateForward() {
        guard canNavigateForward else {
            return
        }

        sectionHistoryIndex += 1
        selectedSection = sectionHistory[sectionHistoryIndex]
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
        VStack(spacing: 0) {
            SettingsDetailHeader(
                title: section.title,
                canNavigateBack: canNavigateBack,
                canNavigateForward: canNavigateForward,
                navigateBack: navigateBack,
                navigateForward: navigateForward
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: SettingsLayout.contentWidth, alignment: .topLeading)
                .padding(.horizontal, SettingsLayout.horizontalPadding)
                .padding(.top, SettingsLayout.topPadding)
                .padding(.bottom, SettingsLayout.bottomPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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

    var shortcutsEnabledBinding: Binding<Bool> {
        Binding {
            model.settings.shortcutsEnabled
        } set: { isEnabled in
            model.settings.shortcutsEnabled = isEnabled
            refreshShortcuts()
        }
    }

    func shortcutBinding(
        _ keyPath: WritableKeyPath<AppSettings, LinguistMacCore.KeyboardShortcut>
    ) -> Binding<LinguistMacCore.KeyboardShortcut> {
        Binding {
            model.settings[keyPath: keyPath]
        } set: { shortcut in
            var settings = model.settings
            settings[keyPath: keyPath] = shortcut
            model.settings = settings
        }
    }

    func refreshShortcuts() {
        Task {
            await model.refreshShortcutRegistrations()
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
