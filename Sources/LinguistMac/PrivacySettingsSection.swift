import AppKit
import LinguistMacCore
import SwiftUI

struct PrivacySettingsSection: View {
    var body: some View {
        SettingsSectionCard("Privacy") {
            PrivacyInfoRow(
                title: "Default translation",
                detail: "Apple Translation and OCR run on this Mac by default. "
                    + "Text is sent to a cloud provider only after you choose a cloud engine and save a key."
            )

            SettingsDivider()

            PrivacyInfoRow(
                title: "Local data",
                detail: "Settings and shortcuts use macOS preferences for "
                    + "\(AppIdentity.linguistMac.bundleIdentifier). Recent translations use the history store below."
            )

            SettingsDivider()

            PrivacyInfoRow(
                title: "History store",
                detail: "Recent translation history keeps up to \(TranslationHistoryPolicy.defaultLimit) items.",
                footnote: Self.historyStoreDisplayPath
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
                detail: "API keys and Azure region are stored in macOS Keychain. Clear them from Provider Keys."
            )
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
    let title: LocalizedStringKey
    let detail: String
    let footnote: String?
    let accessory: Accessory

    init(
        title: LocalizedStringKey,
        detail: String,
        footnote: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.detail = detail
        self.footnote = footnote
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote {
                    Text(footnote)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
