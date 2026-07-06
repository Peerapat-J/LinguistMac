import LinguistMacCore
import SwiftUI

struct AppleLanguagePackManagementView: View {
    @ObservedObject var model: AppShellModel
    let searchText: String
    @State private var expandedGroupIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSearchHighlightedText(
                "Apple checks and prepares language assets for the selected pair and any language group you open.",
                searchText: searchText
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            AppleLanguagePackSelectionView(selection: model.appleLanguagePackSelection, searchText: searchText) {
                Task {
                    await model.prepareSelectedAppleLanguagePack()
                }
            }

            SettingsDivider()

            AppleLanguagePackGroupsView(
                groups: model.appleLanguagePackGroups,
                searchText: searchText,
                expandedBinding: groupExpansionBinding,
                preparePair: { pair in
                    Task {
                        await model.prepareAppleLanguagePack(for: pair)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupExpansionBinding(for group: AppleLanguagePackGroup) -> Binding<Bool> {
        Binding {
            expandedGroupIDs.contains(group.id)
        } set: { isExpanded in
            if isExpanded {
                let wasInserted = expandedGroupIDs.insert(group.id).inserted
                if wasInserted {
                    Task {
                        await model.refreshAppleLanguagePackGroup(for: group.language)
                    }
                }
            } else {
                expandedGroupIDs.remove(group.id)
            }
        }
    }
}

private struct AppleLanguagePackSelectionView: View {
    let selection: AppleLanguagePackSelection
    let searchText: String
    let prepare: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selectionStatusImage)
                .foregroundStyle(selectionStatusTint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                SettingsSearchHighlightedText(selectionTitle, searchText: searchText)
                    .lineLimit(1)

                SettingsSearchHighlightedText(selectionMessage, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 6) {
                Label(
                    selectionStatusText,
                    systemImage: selectionStatusImage
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectionStatusTint)
                .lineLimit(1)

                if selection.readiness == .needsDownload || selection.isPreparing {
                    Button {
                        prepare()
                    } label: {
                        Label(selection.isPreparing ? "Downloading" : "Download", systemImage: "arrow.down.circle")
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

    private var selectionTitle: String {
        selection.pair?.displayName ?? "Choose a Source Language"
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

        return selection.isPreparing ? "arrow.triangle.2.circlepath" : selection.readiness.statusImage
    }

    private var selectionStatusTint: Color {
        guard selection.pair != nil else {
            return .secondary
        }

        return selection.readiness.statusTint
    }
}

private struct AppleLanguagePackGroupsView: View {
    let groups: [AppleLanguagePackGroup]
    let searchText: String
    let expandedBinding: (AppleLanguagePackGroup) -> Binding<Bool>
    let preparePair: (AppleLanguagePackPair) -> Void

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
                    preparePair: preparePair
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
    let preparePair: (AppleLanguagePackPair) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SettingsDivider()
                            .padding(.leading, 28)
                    }

                    AppleLanguagePackPairRowView(row: row, searchText: searchText) {
                        preparePair(row.pair)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.leading, 18)
        } label: {
            HStack(spacing: 8) {
                SettingsSearchHighlightedText(group.language.displayName, searchText: searchText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

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
        let checkedRows = group.rows.filter { $0.readiness != .unknown }
        guard !checkedRows.isEmpty else {
            return "Not Checked"
        }

        let readyCount = group.rows.count(where: { $0.readiness == .ready })
        return "\(readyCount)/\(group.rows.count) Ready"
    }
}

private struct AppleLanguagePackPairRowView: View {
    let row: AppleLanguagePackReadinessRow
    let searchText: String
    let prepare: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusImage)
                .foregroundStyle(statusTint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    SettingsSearchHighlightedText(row.pair.displayName, searchText: searchText)
                        .lineLimit(1)

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
                Label(statusText, systemImage: statusImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)

                if row.readiness == .needsDownload || row.isPreparing {
                    Button {
                        prepare()
                    } label: {
                        Label(row.isPreparing ? "Downloading" : "Download", systemImage: "arrow.down.circle")
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
        row.isPreparing ? "arrow.triangle.2.circlepath" : row.readiness.statusImage
    }

    private var statusTint: Color {
        row.readiness.statusTint
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
