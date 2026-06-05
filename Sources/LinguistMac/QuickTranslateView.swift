import LinguistMacCore
import SwiftUI

struct QuickTranslateView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Translate", systemImage: "text.cursor")
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

            languageBar

            TextEditor(text: $model.quickDraft.sourceText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay {
                    if model.quickDraft.sourceText.isEmpty {
                        Text("Type text to translate")
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }

            resultPanel

            HStack {
                Button {
                    model.swapQuickDraftLanguages()
                } label: {
                    Label("Swap", systemImage: "arrow.left.arrow.right")
                }
                .disabled(!LanguageSelection(
                    source: model.quickDraft.sourceLanguage,
                    target: model.quickDraft.targetLanguage
                ).canSwap)

                Spacer()

                Button("Close") {
                    dismiss()
                }

                Button {
                    Task {
                        await model.runQuickTranslate()
                    }
                } label: {
                    Label("Translate", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.quickDraft.canTranslate)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private var languageBar: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $model.quickDraft.sourceLanguage) {
                ForEach(model.availableLanguages, id: \.id) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Picker("Target", selection: $model.quickDraft.targetLanguage) {
                ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                    Text(language.displayName)
                        .tag(language)
                }
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        switch model.quickSessionState {
        case .idle:
            VStack(alignment: .leading, spacing: 6) {
                Text("Result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Preview translation will appear here.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .capturing, .recognizing, .requestingPermission:
            ProgressView("Preparing...")
                .frame(maxWidth: .infinity, minHeight: 96)
        case .translating:
            ProgressView("Translating...")
                .frame(maxWidth: .infinity, minHeight: 96)
        case let .completed(result):
            VStack(alignment: .leading, spacing: 8) {
                Text("Result")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.translatedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case let .failed(failure):
            Label(failure.displayText, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

}
