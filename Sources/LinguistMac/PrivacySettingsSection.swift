import AppKit
import LinguistMacCore
import SwiftUI

struct PrivacySettingsSection: View {
    let searchText: String
    let openAPISettings: () -> Void

    var body: some View {
        SettingsSectionCard("Privacy", searchText: searchText) {
            PrivacyInfoRow(
                title: "History store",
                detail: "Recent translation history keeps up to \(TranslationHistoryPolicy.defaultLimit) items.",
                warningDetail: "Avoid editing this file directly.",
                footnote: Self.historyStoreDisplayPath,
                searchText: searchText
            ) {
                Button("Show") {
                    revealHistoryStore()
                }
                .controlSize(.small)
                .accessibilityLabel("Show translation history store in Finder")
                .help("Show translation history store in Finder")
            }

            SettingsDivider()

            PrivacyInfoRow(
                title: "Provider keys",
                detail: "API keys and Azure region are stored in macOS Keychain. Manage or clear them in API settings.",
                searchText: searchText
            ) {
                Button("Open API Settings", action: openAPISettings)
                    .controlSize(.small)
                    .accessibilityLabel("Open API settings")
                    .help("Open API settings")
            }
        }
    }

    private func revealHistoryStore() {
        guard let applicationSupportURL = Self.applicationSupportURL else {
            return
        }

        let storeURL = Self.historyStoreURL(in: applicationSupportURL)
        if FileManager.default.fileExists(atPath: storeURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        } else {
            NSWorkspace.shared.open(applicationSupportURL)
        }
    }

    private static func historyStoreURL(in applicationSupportURL: URL) -> URL {
        applicationSupportURL.appendingPathComponent(historyStoreFileName)
    }

    private static var applicationSupportURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    private static let historyStoreFileName = "LinguistMacTranslationHistory.store"
    private static let historyStoreDisplayPath = "~/Library/Application Support/\(historyStoreFileName)"
}

private struct PrivacyInfoRow<Accessory: View>: View {
    let title: String
    let detail: String
    let warningDetail: String?
    let footnote: String?
    let searchText: String
    let accessory: Accessory

    init(
        title: String,
        detail: String,
        warningDetail: String? = nil,
        footnote: String? = nil,
        searchText: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.warningDetail = warningDetail
        self.footnote = footnote
        self.searchText = searchText
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SettingsSearchHighlightedText(title, searchText: searchText)
                    .font(.callout.weight(.semibold))

                Spacer(minLength: 12)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
            }

            SettingsSearchHighlightedText(detail, searchText: searchText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let warningDetail {
                SettingsSearchHighlightedText(warningDetail, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote {
                SettingsSearchHighlightedText(footnote, searchText: searchText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
