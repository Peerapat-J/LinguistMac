import LinguistMacCore
import OSLog
import SwiftUI
#if compiler(>=6.3)
    import _Translation_SwiftUI
#endif

private let appleLanguagePackTaskLogger = Logger(
    subsystem: AppIdentity.linguistMac.bundleIdentifier,
    category: "AppleLanguagePackTasks"
)

struct AppleLanguagePackManagementView: View {
    @ObservedObject var model: AppShellModel
    let searchText: String
    @State private var expandedGroupIDs: Set<String> = []
    @State private var languagePackSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSearchHighlightedText(
                "Apple checks language pack status automatically and downloads assets for pairs you choose.",
                searchText: highlightText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            AppleLanguagePackSelectionView(
                selection: model.appleLanguagePackSelection,
                searchText: highlightText,
                prepare: {
                    Task {
                        await model.prepareSelectedAppleLanguagePack()
                    }
                },
                cancel: { pair in
                    Task {
                        await model.cancelAppleLanguagePackPreparation(for: pair)
                    }
                }
            )

            SettingsDivider()

            AppleLanguagePackSearchField(searchText: $languagePackSearchText)

            AppleLanguagePackGroupsView(
                groups: filteredLanguagePackGroups,
                searchText: highlightText,
                expandedBinding: groupExpansionBinding,
                togglePin: { language in
                    model.togglePinnedAppleLanguagePackGroup(language)
                },
                preparePairs: { pairs in
                    Task {
                        await model.prepareAppleLanguagePacks(for: pairs)
                    }
                },
                cancelPairs: { pairs in
                    Task {
                        await model.cancelAppleLanguagePackPreparations(for: pairs)
                    }
                }
            )

            if filteredLanguagePackGroups.isEmpty {
                Text("No language packs found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
            }

            SettingsSearchHighlightedText(
                "Downloaded Apple Translation assets are managed by macOS. "
                    + "LinguistMac can request downloads, but cannot remove system-managed assets.",
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
            await model.clearStaleAppleLanguagePackPreparationIfNeeded()
            await model.refreshAppleLanguagePackGroupsIfNeeded()
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

    private var filteredLanguagePackGroups: [AppleLanguagePackGroup] {
        let tokens = searchTokens(from: languagePackSearchQuery)
        guard !tokens.isEmpty else {
            return model.appleLanguagePackGroups
        }

        return model.appleLanguagePackGroups.compactMap { group in
            if matches(tokens, in: [group.language.displayName, group.language.id]) {
                return group
            }

            let rows = group.rows.filter { row in
                matches(
                    tokens,
                    in: [
                        row.language.displayName,
                        row.language.id,
                        row.pairedLanguage.displayName,
                        row.pairedLanguage.id,
                        row.displayName
                    ]
                )
            }
            guard !rows.isEmpty else {
                return nil
            }

            return AppleLanguagePackGroup(
                language: group.language,
                rows: rows,
                isPinned: group.isPinned
            )
        }
    }

    private func groupExpansionBinding(for group: AppleLanguagePackGroup) -> Binding<Bool> {
        Binding {
            expandedGroupIDs.contains(group.id)
        } set: { isExpanded in
            if isExpanded {
                expandedGroupIDs.insert(group.id)
            } else {
                expandedGroupIDs.remove(group.id)
            }
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

private struct AppleLanguagePackSelectionView: View {
    let selection: AppleLanguagePackSelection
    let searchText: String
    let prepare: () -> Void
    let cancel: (AppleLanguagePackPair) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppleLanguagePackStatusGlyph(
                systemName: selection.settingsStatusImage,
                tint: selection.settingsStatusTint,
                isAnimating: selection.showsDownloadingControl,
                isChecking: selection.isChecking
            )

            VStack(alignment: .leading, spacing: 3) {
                if let pair = selection.pair {
                    AppleLanguagePackPairTitleView(
                        leadingLanguage: pair.sourceLanguage,
                        trailingLanguage: pair.targetLanguage,
                        searchText: searchText
                    )
                } else {
                    SettingsSearchHighlightedText("Choose a Source Language", searchText: searchText)
                        .lineLimit(1)
                }

                SettingsSearchHighlightedText(selection.settingsMessage, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Text(selection.settingsStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selection.settingsStatusTint)
                    .lineLimit(1)

                if selection.showsDownloadingControl {
                    Button {} label: {
                        Label("Downloading", systemImage: "circle.dotted")
                    }
                    .controlSize(.small)
                    .disabled(true)
                    .fixedSize(horizontal: true, vertical: false)
                } else if selection.readiness == .needsDownload {
                    Button {
                        prepare()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                    .disabled(!selection.canPrepare)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct AppleLanguagePackGroupsView: View {
    let groups: [AppleLanguagePackGroup]
    let searchText: String
    let expandedBinding: (AppleLanguagePackGroup) -> Binding<Bool>
    let togglePin: (TranslationLanguage) -> Void
    let preparePairs: ([AppleLanguagePackPair]) -> Void
    let cancelPairs: ([AppleLanguagePackPair]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSearchHighlightedText("Language Groups", searchText: searchText)
                .font(.caption.weight(.semibold))
                .padding(.bottom, 4)

            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    SettingsDivider()
                }

                AppleLanguagePackGroupView(
                    group: group,
                    searchText: searchText,
                    isExpanded: expandedBinding(group),
                    togglePin: togglePin,
                    preparePairs: preparePairs,
                    cancelPairs: cancelPairs
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct AppleLanguagePackGroupView: View {
    let group: AppleLanguagePackGroup
    let searchText: String
    @Binding var isExpanded: Bool
    let togglePin: (TranslationLanguage) -> Void
    let preparePairs: ([AppleLanguagePackPair]) -> Void
    let cancelPairs: ([AppleLanguagePackPair]) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SettingsDivider()
                            .padding(.leading, 28)
                    }

                    AppleLanguagePackPairRowView(
                        row: row,
                        searchText: searchText,
                        prepare: {
                            preparePairs(row.pairs)
                        },
                        cancel: {
                            cancelPairs(row.pairs)
                        }
                    )
                }
            }
            .padding(.top, 6)
            .padding(.leading, 18)
        } label: {
            HStack(spacing: 8) {
                SettingsSearchHighlightedText(group.language.displayName, searchText: searchText)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Button {
                    togglePin(group.language)
                } label: {
                    Image(systemName: group.isPinned ? "pin.fill" : "pin")
                        .font(.body)
                        .foregroundStyle(group.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(group.isPinned ? "Unpin language group" : "Pin language group")

                Spacer(minLength: 8)

                AppleLanguagePackGroupSummaryView(
                    text: summaryText,
                    isChecking: isChecking
                )
            }
        }
        .padding(.vertical, 8)
    }

    private var isChecking: Bool {
        group.rows.contains(where: { $0.readiness == .unknown })
    }

    private var summaryText: String {
        guard !isChecking else {
            return "Checking"
        }

        let readyCount = group.rows.count(where: { $0.readiness == .ready })
        return "\(readyCount)/\(group.rows.count) Ready"
    }
}

private struct AppleLanguagePackPairRowView: View {
    let row: AppleLanguagePackReadinessRow
    let searchText: String
    let prepare: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppleLanguagePackStatusGlyph(
                systemName: row.settingsStatusImage,
                tint: row.settingsStatusTint,
                isAnimating: row.showsDownloadingControl,
                isChecking: row.isChecking
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    AppleLanguagePackPairTitleView(
                        leadingLanguage: row.language,
                        trailingLanguage: row.pairedLanguage,
                        searchText: searchText
                    )

                    if row.isCurrentPair {
                        Label("Current", systemImage: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }

                SettingsSearchHighlightedText(row.settingsMessage, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Text(row.settingsStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.settingsStatusTint)
                    .lineLimit(1)

                if row.showsDownloadingControl {
                    Button {} label: {
                        Label("Downloading", systemImage: "circle.dotted")
                    }
                    .controlSize(.small)
                    .disabled(true)
                    .fixedSize(horizontal: true, vertical: false)
                } else if row.readiness == .needsDownload {
                    Button {
                        prepare()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                    .disabled(!row.canPrepare)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct AppleLanguagePackPairTitleView: View {
    let leadingLanguage: TranslationLanguage
    let trailingLanguage: TranslationLanguage
    let searchText: String

    var body: some View {
        HStack(spacing: 6) {
            SettingsSearchHighlightedText(leadingLanguage.displayName, searchText: searchText)
                .lineLimit(1)

            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            SettingsSearchHighlightedText(trailingLanguage.displayName, searchText: searchText)
                .lineLimit(1)
        }
    }
}
