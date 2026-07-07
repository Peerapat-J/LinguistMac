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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSearchHighlightedText(
                "Apple checks language pack status automatically and downloads assets for pairs you choose.",
                searchText: searchText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            AppleLanguagePackSelectionView(
                selection: model.appleLanguagePackSelection,
                searchText: searchText,
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

            AppleLanguagePackGroupsView(
                groups: model.appleLanguagePackGroups,
                searchText: searchText,
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

            SettingsSearchHighlightedText(
                "Downloaded Apple Translation assets are managed by macOS. "
                    + "LinguistMac can request downloads, but cannot remove system-managed assets.",
                searchText: searchText
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

private struct AppleLanguagePackSelectionView: View {
    let selection: AppleLanguagePackSelection
    let searchText: String
    let prepare: () -> Void
    let cancel: (AppleLanguagePackPair) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AppleLanguagePackStatusGlyph(
                systemName: selectionStatusImage,
                tint: selectionStatusTint,
                isAnimating: selection.isPreparing
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

                SettingsSearchHighlightedText(selectionMessage, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Text(selectionStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectionStatusTint)
                    .lineLimit(1)

                if selection.isPreparing, let pair = selection.pair {
                    Button {
                        cancel(pair)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
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

    private var selectionMessage: String {
        if let message = selection.message {
            return message
        }
        guard selection.pair != nil else {
            return "Auto Detect cannot be prepared ahead of time. Select a concrete source language first."
        }

        return selection.readiness.detailText
    }

    private var selectionStatusText: String {
        guard selection.pair != nil else {
            return "Select Pair"
        }

        return selection.isPreparing ? "Downloading" : selection.readiness.displayText
    }

    private var selectionStatusImage: String {
        guard selection.pair != nil else {
            return "circle.dashed"
        }

        return selection.isPreparing ? "circle.dotted" : selection.readiness.statusImage
    }

    private var selectionStatusTint: Color {
        guard selection.pair != nil else {
            return .secondary
        }

        if selection.isPreparing {
            return .orange
        }

        return selection.readiness.statusTint
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
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Button {
                    togglePin(group.language)
                } label: {
                    Image(systemName: group.isPinned ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundStyle(group.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(group.isPinned ? "Unpin language group" : "Pin language group")

                Spacer(minLength: 8)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }

    private var summaryText: String {
        guard !group.rows.contains(where: { $0.readiness == .unknown }) else {
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
                systemName: statusImage,
                tint: statusTint,
                isAnimating: row.isPreparing
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

                SettingsSearchHighlightedText(row.message ?? row.readiness.detailText, searchText: searchText)
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

                if row.isPreparing {
                    Button {
                        cancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .controlSize(.small)
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

    private var statusText: String {
        row.isPreparing ? "Downloading" : row.readiness.displayText
    }

    private var statusImage: String {
        row.isPreparing ? "circle.dotted" : row.readiness.statusImage
    }

    private var statusTint: Color {
        if row.isPreparing {
            return .orange
        }

        return row.readiness.statusTint
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

private struct AppleLanguagePackStatusGlyph: View {
    let systemName: String
    let tint: Color
    let isAnimating: Bool
    @State private var isRotating = false

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(tint)
            .frame(width: 20)
            .rotationEffect(.degrees(isAnimating && isRotating ? 360 : 0))
            .animation(
                isAnimating ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .default,
                value: isRotating
            )
            .onAppear {
                isRotating = isAnimating
            }
            .onChange(of: isAnimating) { _, newValue in
                isRotating = newValue
            }
    }
}

private extension LanguagePackReadiness {
    var statusImage: String {
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

    var statusTint: Color {
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

    var detailText: String {
        switch self {
        case .unknown:
            "Checking Apple Translation availability for this pair."
        case .ready:
            "Ready for on-device Apple Translation."
        case .needsDownload:
            "Download or verify the required Apple language assets."
        case .unavailable:
            "Apple Translation does not support this language pair."
        }
    }
}
