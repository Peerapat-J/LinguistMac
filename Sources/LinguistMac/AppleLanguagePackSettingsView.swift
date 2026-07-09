import AppKit
import LinguistMacCore
// swiftlint:disable:next unused_import
import OSLog
import SwiftUI
#if compiler(>=6.3)
    import _Translation_SwiftUI
#endif

private let appleLanguagePackTaskLogger = Logger(
    subsystem: AppIdentity.linguistMac.bundleIdentifier,
    category: "AppleLanguagePackTasks"
)
private let packVisibleRefreshNS: UInt64 = 30_000_000_000
private let packSettingsSyncAttempts = 60
private let packSettingsSyncNS: UInt64 = 2_000_000_000

struct AppleLanguagePackManagementView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppShellModel
    let searchText: String
    @State private var languagePackSearchText = ""
    @State private var systemSettingsSyncGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSearchHighlightedText(
                "Apple checks language pack status automatically. "
                    + "Use Manage to download or remove languages in macOS.",
                searchText: highlightText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            AppleLanguagePackSelectionView(
                selection: model.appleLanguagePackSelection,
                sourceLanguage: model.settings.sourceLanguage,
                targetLanguage: model.settings.targetLanguage,
                sourceStatus: selectedSourceStatus,
                targetStatus: selectedTargetStatus,
                searchText: highlightText,
                manage: manageTranslationLanguages
            )

            SettingsDivider()

            AppleLanguagePackSearchField(searchText: $languagePackSearchText)

            AppleLanguagePackLanguagesView(
                languages: filteredLanguageStatuses,
                searchText: highlightText,
                togglePin: { language in
                    model.togglePinnedAppleLanguagePackGroup(language)
                }
            )

            if filteredLanguageStatuses.isEmpty {
                Text("No language packs found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
            }

            SettingsSearchHighlightedText(
                "Downloaded Apple Translation assets are managed by macOS. "
                    + "Use Manage to download or remove system-managed languages.",
                searchText: highlightText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            #if compiler(>=6.3)
                if #available(macOS 26.0, *) {
                    AppleLanguagePackPreparationTasksView(model: model)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await pollAppleLanguagePackStatusWhileVisible()
        }
        .task(id: systemSettingsSyncGeneration) {
            guard systemSettingsSyncGeneration > 0 else {
                return
            }

            await pollAppleLanguagePackStatusAfterOpeningSystemSettings()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await refreshAppleLanguagePackStatus()
            }
        }
    }

    private var languagePackSearchQuery: String {
        languagePackSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var highlightText: String {
        [searchText, languagePackSearchQuery]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var languageStatuses: [AppleLanguagePackLanguageStatus] {
        model.appleLanguagePackGroups.map { group in
            AppleLanguagePackLanguageStatus(
                language: group.language,
                readiness: languageReadiness(for: group),
                isPinned: group.isPinned
            )
        }
    }

    private var languageStatusByID: [String: AppleLanguagePackLanguageStatus] {
        Dictionary(uniqueKeysWithValues: languageStatuses.map { ($0.language.id, $0) })
    }

    private var filteredLanguageStatuses: [AppleLanguagePackLanguageStatus] {
        let tokens = searchTokens(from: languagePackSearchQuery)
        guard !tokens.isEmpty else {
            return languageStatuses
        }

        return languageStatuses.filter { status in
            matches(
                tokens,
                in: [
                    status.language.displayName,
                    status.language.id,
                    status.readiness.displayText,
                    status.detailText
                ]
            )
        }
    }

    private var selectedSourceStatus: AppleLanguagePackLanguageStatus? {
        let language = model.settings.sourceLanguage
        guard !language.supportsAutoDetect else {
            return nil
        }

        return selectedStatus(for: language)
    }

    private var selectedTargetStatus: AppleLanguagePackLanguageStatus? {
        let language = model.settings.targetLanguage
        guard language.canBeTargetLanguage else {
            return nil
        }

        return selectedStatus(for: language)
    }

    private func selectedStatus(for language: TranslationLanguage) -> AppleLanguagePackLanguageStatus {
        let knownStatus = languageStatusByID[language.id]
        return AppleLanguagePackLanguageStatus(
            language: language,
            readiness: selectedLanguageReadiness(knownStatus?.readiness),
            isPinned: knownStatus?.isPinned ?? false
        )
    }

    private func selectedLanguageReadiness(_ knownReadiness: LanguagePackReadiness?) -> LanguagePackReadiness {
        let selectionReadiness = model.appleLanguagePackSelection.readiness
        if selectionReadiness == .ready || selectionReadiness == .unavailable {
            return selectionReadiness
        }

        guard let knownReadiness else {
            return selectionReadiness
        }

        if selectionReadiness == .needsDownload, knownReadiness == .unknown {
            return .needsDownload
        }

        return knownReadiness
    }

    private func languageReadiness(for group: AppleLanguagePackGroup) -> LanguagePackReadiness {
        let readinesses = group.rows.map(\.readiness)
        guard !readinesses.isEmpty else {
            return .unknown
        }

        if readinesses.contains(.ready) {
            return .ready
        }
        if readinesses.contains(.unknown) {
            return .unknown
        }
        if readinesses.contains(.needsDownload) {
            return .needsDownload
        }

        return .unavailable
    }

    private func manageTranslationLanguages() {
        if openTranslationLanguageSettings() {
            systemSettingsSyncGeneration += 1
        }
    }

    private func searchTokens(from query: String) -> [String] {
        query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func matches(_ tokens: [String], in values: [String]) -> Bool {
        tokens.allSatisfy { token in
            values.contains {
                $0.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private func refreshAppleLanguagePackStatus() async {
        await model.refreshAppleLanguagePackGroups(force: true)
    }

    private func pollAppleLanguagePackStatusWhileVisible() async {
        while !Task.isCancelled {
            await refreshAppleLanguagePackStatus()

            do {
                try await Task.sleep(nanoseconds: packVisibleRefreshNS)
            } catch {
                return
            }
        }
    }

    private func pollAppleLanguagePackStatusAfterOpeningSystemSettings() async {
        for attempt in 0..<packSettingsSyncAttempts {
            guard !Task.isCancelled else {
                return
            }

            await refreshAppleLanguagePackStatus()

            guard attempt < packSettingsSyncAttempts - 1 else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: packSettingsSyncNS)
            } catch {
                return
            }
        }
    }

    private func openTranslationLanguageSettings() -> Bool {
        guard let translationLanguagesURL = URL(
            string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation"
        ),
              let languageRegionURL = URL(
                  string: "x-apple.systempreferences:com.apple.Localization-Settings.extension"
              )
        else {
            return false
        }

        if !NSWorkspace.shared.open(translationLanguagesURL) {
            return NSWorkspace.shared.open(languageRegionURL)
        }

        return true
    }
}

#if compiler(>=6.3)
    @available(macOS 26.0, *)
    private struct AppleLanguagePackPreparationTasksView: View {
        @ObservedObject var model: AppShellModel

        var body: some View {
            ForEach(model.appleLanguagePackPreparationRequests) { request in
                AppleLanguagePackPreparationTaskView(model: model, request: request)
                    .id(request.id)
            }
        }
    }

    @available(macOS 26.0, *)
    private struct AppleLanguagePackPreparationTaskView: View {
        @ObservedObject var model: AppShellModel
        let request: AppleLanguagePackPreparationRequest
        @State private var configuration: TranslationSession.Configuration?

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    updateConfiguration()
                }
                .translationTask(configuration) { @Sendable session in
                    guard await model.noteAppleLanguagePackPreparationSessionStarted(for: request) else {
                        return
                    }

                    do {
                        try await session.prepareTranslation()
                        await model.finishAppleLanguagePackPreparation(
                            for: request.pair,
                            requestID: request.id,
                            result: .success(())
                        )
                    } catch {
                        let failure = AppleTranslationSessionAdapter.translationFailure(from: error)
                        let failureDescription = String(describing: failure)
                        appleLanguagePackTaskLogger.error(
                            "Translation task failed for \(request.pair.id, privacy: .public)"
                        )
                        appleLanguagePackTaskLogger.error(
                            "Translation failure: \(failureDescription, privacy: .public)"
                        )
                        await model.finishAppleLanguagePackPreparation(
                            for: request.pair,
                            requestID: request.id,
                            result: .failure(failure)
                        )
                    }

                    await MainActor.run {
                        configuration = nil
                    }
                }
        }

        @MainActor
        private func updateConfiguration() {
            guard let source = request.pair.sourceLanguage.localeLanguage,
                  let target = request.pair.targetLanguage.localeLanguage
            else {
                configuration = nil
                Task {
                    await model.finishAppleLanguagePackPreparation(
                        for: request.pair,
                        requestID: request.id,
                        result: .failure(.unsupportedLanguagePair)
                    )
                }
                return
            }

            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
#endif

private struct AppleLanguagePackSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search language packs", text: $searchText)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Language Pack Search")
                .help("Clear Language Pack Search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
    }
}

private struct AppleLanguagePackLanguageStatus: Identifiable, Equatable {
    let language: TranslationLanguage
    let readiness: LanguagePackReadiness
    let isPinned: Bool

    var id: String {
        language.id
    }

    var isChecking: Bool {
        readiness == .unknown
    }

    var statusText: String {
        readiness.displayText
    }

    var statusImage: String {
        readiness.settingsStatusImage
    }

    var statusTint: Color {
        readiness.settingsStatusTint
    }

    var detailText: String {
        switch readiness {
        case .unknown:
            "Checking Apple Translation language status."
        case .ready:
            "Ready for on-device Apple Translation."
        case .needsDownload:
            "Manage this language in macOS before translating offline."
        case .unavailable:
            "Apple Translation does not support this language."
        }
    }
}

private struct AppleLanguagePackSelectionView: View {
    let selection: AppleLanguagePackSelection
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
    let sourceStatus: AppleLanguagePackLanguageStatus?
    let targetStatus: AppleLanguagePackLanguageStatus?
    let searchText: String
    let manage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                if sourceLanguage.supportsAutoDetect {
                    HStack(spacing: 6) {
                        AppleLanguageSelectionLabelView(
                            title: sourceLanguage.displayName,
                            systemName: "circle.dashed",
                            tint: .secondary,
                            isChecking: false,
                            searchText: searchText
                        )

                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        if let targetStatus {
                            AppleLanguageSelectionLineView(
                                status: targetStatus,
                                searchText: searchText
                            )
                        } else {
                            AppleLanguageSelectionLabelView(
                                title: targetLanguage.displayName,
                                systemName: "circle.dashed",
                                tint: .secondary,
                                isChecking: false,
                                searchText: searchText
                            )
                        }
                    }
                    .lineLimit(1)
                } else if sourceLanguage == targetLanguage {
                    AppleLanguageSelectionLabelView(
                        title: sourceLanguage.displayName,
                        systemName: "checkmark.circle.fill",
                        tint: .green,
                        isChecking: false,
                        searchText: searchText
                    )
                } else if let sourceStatus, let targetStatus {
                    HStack(spacing: 6) {
                        AppleLanguageSelectionLineView(
                            status: sourceStatus,
                            searchText: searchText
                        )

                        Image(systemName: "arrow.left.arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        AppleLanguageSelectionLineView(
                            status: targetStatus,
                            searchText: searchText
                        )
                    }
                    .lineLimit(1)
                } else {
                    AppleLanguageSelectionLabelView(
                        title: sourceLanguage.displayName,
                        systemName: "circle.dashed",
                        tint: .secondary,
                        isChecking: false,
                        searchText: searchText
                    )
                }

                SettingsSearchHighlightedText(detailText, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)

                Button {
                    manage()
                } label: {
                    Label("Manage", systemImage: "gearshape")
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .help("Open Translation Languages in System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }

    private var detailText: String {
        if sourceLanguage.supportsAutoDetect {
            return "Select a concrete source language to check Apple Translation assets."
        }
        if sourceLanguage == targetLanguage {
            return "Source and target languages match, so no Apple language pack is needed."
        }

        guard selection.pair != nil else {
            return "Select concrete source and target languages to check Apple Translation assets."
        }

        switch selection.readiness {
        case .unknown:
            return "Checking selected languages for Apple Translation."
        case .ready:
            return "Ready for on-device Apple Translation."
        case .needsDownload:
            return "Manage the missing language in macOS before this pair is ready."
        case .unavailable:
            return "Apple Translation does not support this language pair."
        }
    }

    private var statusText: String {
        if sourceLanguage.supportsAutoDetect {
            return "Select Source"
        }
        if sourceLanguage == targetLanguage {
            return "Not Required"
        }

        return selection.settingsStatusText
    }

    private var statusTint: Color {
        if sourceLanguage.supportsAutoDetect || sourceLanguage == targetLanguage {
            return .secondary
        }

        return selection.settingsStatusTint
    }
}

private struct AppleLanguageSelectionLineView: View {
    let status: AppleLanguagePackLanguageStatus
    let searchText: String

    var body: some View {
        HStack(spacing: 6) {
            AppleLanguagePackStatusGlyph(
                systemName: status.statusImage,
                tint: status.statusTint,
                isProgressing: false,
                isChecking: status.isChecking
            )

            SettingsSearchHighlightedText(status.language.displayName, searchText: searchText)
                .font(.body.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct AppleLanguageSelectionLabelView: View {
    let title: String
    let systemName: String
    let tint: Color
    let isChecking: Bool
    let searchText: String

    var body: some View {
        HStack(spacing: 6) {
            AppleLanguagePackStatusGlyph(
                systemName: systemName,
                tint: tint,
                isProgressing: false,
                isChecking: isChecking
            )

            SettingsSearchHighlightedText(title, searchText: searchText)
                .font(.body.weight(.semibold))
                .lineLimit(1)
        }
    }
}

private struct AppleLanguagePackLanguagesView: View {
    let languages: [AppleLanguagePackLanguageStatus]
    let searchText: String
    let togglePin: (TranslationLanguage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSearchHighlightedText("Languages", searchText: searchText)
                .font(.caption.weight(.semibold))
                .padding(.bottom, 4)
            ForEach(Array(languages.enumerated()), id: \.element.id) { index, status in
                if index > 0 {
                    SettingsDivider()
                }
                AppleLanguagePackLanguageRowView(
                    status: status,
                    searchText: searchText,
                    togglePin: togglePin
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct AppleLanguagePackLanguageRowView: View {
    let status: AppleLanguagePackLanguageStatus
    let searchText: String
    let togglePin: (TranslationLanguage) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppleLanguagePackStatusGlyph(
                systemName: status.statusImage,
                tint: status.statusTint,
                isProgressing: false,
                isChecking: status.isChecking
            )
            SettingsSearchHighlightedText(status.language.displayName, searchText: searchText)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Button {
                togglePin(status.language)
            } label: {
                Image(systemName: status.isPinned ? "pin.fill" : "pin")
                    .font(.body)
                    .foregroundStyle(status.isPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(status.isPinned ? "Unpin language" : "Pin language")
            Spacer(minLength: 10)
            Text(status.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.statusTint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}
