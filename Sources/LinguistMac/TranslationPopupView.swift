import LinguistMacCore
import SwiftUI

struct TranslationPopupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            content

            Spacer(minLength: 0)

            footer
        }
        .padding(20)
        .frame(
            minWidth: 320,
            idealWidth: model.settings.popupWidth,
            maxWidth: 760,
            minHeight: 240,
            idealHeight: 320
        )
    }

    private var header: some View {
        HStack {
            Label("Translation", systemImage: "text.bubble")
                .font(.headline)

            Spacer()

            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.popupState {
        case .empty:
            ContentUnavailableView(
                "No Translation",
                systemImage: "text.bubble",
                description: Text("Run Screen Translate or Quick Translate to preview this popup.")
            )
        case .loading:
            ProgressView("Translating...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .success(result, showsOriginal):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.translatedText)
                        .font(.system(size: model.settings.popupFontSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsOriginal {
                        Divider()
                        Text("Original")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.originalText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case let .failed(failure, originalText):
            VStack(alignment: .leading, spacing: 8) {
                Label("Translation Failed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(failure.displayText)
                    .foregroundStyle(.secondary)

                if let originalText, !originalText.isEmpty {
                    Text(originalText)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task {
                    await model.copyPopupText()
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(model.popupState.copyableText == nil)

            Button {
                model.togglePopupOriginal()
            } label: {
                Label(model.popupState.showsOriginal ? "Hide Original" : "Show Original", systemImage: "text.quote")
            }
            .disabled(model.popupState.copyableText == nil)

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

extension TranslationFailure {
    var displayText: String {
        switch self {
        case let .permissionDenied(kind):
            "Permission required: \(kind.rawValue)."
        case .captureCancelled:
            "Screen capture was cancelled."
        case .noTextRecognized:
            "No text was recognized."
        case .emptyInput:
            "Enter text before translating."
        case .unsupportedLanguagePair:
            "This language pair is not available yet."
        case let .missingLanguagePack(providerID):
            "Language pack required for \(providerID.rawValue)."
        case let .providerUnavailable(providerID):
            "Provider is unavailable: \(providerID.rawValue)."
        case let .missingAPIKey(providerID):
            "API key required for \(providerID.rawValue)."
        case let .inputModeDisabled(inputMode):
            "\(inputMode.displayName) is disabled in Settings."
        case let .providerFailed(message):
            message
        }
    }
}
