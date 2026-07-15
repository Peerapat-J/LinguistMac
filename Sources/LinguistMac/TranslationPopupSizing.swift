import LinguistMacCore
import SwiftUI

enum PopupTextPanelLayout {
    static let spacing: CGFloat = 12
    static let minimumCollapsedContentHeight: CGFloat = 240
    static let minimumExpandedContentHeight: CGFloat = 380
    static let minimumSourcePanelHeight: CGFloat = 138
    static let minimumTranslationPanelHeight: CGFloat = 88
    static func sourcePanelHeight(for availableHeight: CGFloat) -> CGFloat {
        let panelHeight = max(availableHeight - spacing, 0)
        let maximumSourceHeight = max(
            minimumSourcePanelHeight,
            panelHeight - minimumTranslationPanelHeight
        )
        let balancedHeight = panelHeight / 2
        return min(max(balancedHeight, minimumSourcePanelHeight), maximumSourceHeight)
    }
}

extension TranslationPopupView {
    func flexibleSuccessContent(
        result: TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        GeometryReader { geometry in
            let sourceHeight = PopupTextPanelLayout.sourcePanelHeight(
                for: geometry.size.height
            )

            VStack(alignment: .leading, spacing: PopupTextPanelLayout.spacing) {
                PopupTextPanel(fillsHeight: showsOriginal) {
                    sourcePanelContent(
                        result: result,
                        showsOriginal: showsOriginal,
                        usesFlexibleEditorHeight: true
                    )
                }
                .frame(height: showsOriginal ? sourceHeight : nil)

                PopupTextPanel(fillsHeight: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            translationTextContent(result: result, wordCard: wordCard)
                        }
                        .frame(maxHeight: .infinity)

                        Divider()
                        PopupTextActionBar(model: model, result: result, role: .translation)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    func naturalSuccessContent(
        result: TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        VStack(alignment: .leading, spacing: PopupTextPanelLayout.spacing) {
            PopupTextPanel {
                sourcePanelContent(
                    result: result,
                    showsOriginal: showsOriginal,
                    usesFlexibleEditorHeight: false
                )
            }

            PopupTextPanel {
                VStack(alignment: .leading, spacing: 12) {
                    translationTextContent(result: result, wordCard: wordCard)
                    Divider()
                    PopupTextActionBar(model: model, result: result, role: .translation)
                }
            }
        }
    }

    private func sourcePanelContent(
        result: TranslationResult,
        showsOriginal: Bool,
        usesFlexibleEditorHeight: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    model.togglePopupOriginal()
                    model.preparePopupSourceEditorIfNeeded()
                } label: {
                    Label(
                        showsOriginal ? "Hide Original" : "Show Original",
                        systemImage: showsOriginal ? "chevron.down" : "chevron.right"
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()

                Spacer()
            }

            if showsOriginal {
                if usesFlexibleEditorHeight {
                    TextEditor(text: popupSourceDraftBinding)
                        .scrollContentBackground(.hidden)
                        .font(popupFont)
                        .frame(minHeight: 80, maxHeight: .infinity)
                        .accessibilityLabel("Original Text")
                } else {
                    Text(model.popupSourceDraft)
                        .font(popupFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 80, maxHeight: 160, alignment: .topLeading)
                }

                if let sourceReading = result.sourceReading, !model.isPopupSourceDirty {
                    ReadingText(text: sourceReading, role: .source)
                }
            }

            Divider()
            PopupTextActionBar(
                model: model,
                result: result,
                role: .source,
                textOverride: model.popupSourceDraft
            )
        }
    }

    private func translationTextContent(
        result: TranslationResult,
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.translatedText)
                .font(popupFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let translatedReading = result.translatedReading {
                ReadingText(text: translatedReading, role: .translation)
            }

            if !result.wordTranslations.isEmpty || wordCard != nil {
                Divider()
                TranslationWordLookupSection(
                    wordTranslations: result.wordTranslations,
                    wordCard: wordCard,
                    isSelectionEnabled: true,
                    onSelectWord: { wordTranslation, index in
                        Task {
                            await model.selectPopupWord(
                                wordTranslation,
                                at: index,
                                resultID: result.id
                            )
                        }
                    },
                    onDismissWordCard: {
                        model.dismissPopupWordCard()
                    },
                    onRecoveryAction: { action, card in
                        handleWordLookupRecovery(
                            action,
                            card: card,
                            resultID: result.id
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PopupNaturalHeightMeasurement: Equatable {
    let revision: PopupWindowContentRevision
    let height: CGFloat
}

struct PopupNaturalHeightPreferenceKey: PreferenceKey {
    static let defaultValue: PopupNaturalHeightMeasurement? = nil

    static func reduce(
        value: inout PopupNaturalHeightMeasurement?,
        nextValue: () -> PopupNaturalHeightMeasurement?
    ) {
        value = nextValue() ?? value
    }
}

struct PopupNaturalHeightReader: View {
    let revision: PopupWindowContentRevision

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: PopupNaturalHeightPreferenceKey.self,
                value: PopupNaturalHeightMeasurement(
                    revision: revision,
                    height: geometry.size.height
                )
            )
        }
    }
}

struct PopupTextPanel<Content: View>: View {
    let fillsHeight: Bool
    @ViewBuilder let content: Content

    init(
        fillsHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.fillsHeight = fillsHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                Color(nsColor: .underPageBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            }
    }
}

private struct ReadingText: View {
    let text: String
    let role: TranslationTextRole

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(accessibilityPrefix) reading: \(text)")
    }

    private var accessibilityPrefix: String {
        switch role {
        case .source:
            "Original"
        case .translation:
            "Translation"
        }
    }
}

private struct PopupTextActionBar: View {
    @ObservedObject var model: AppShellModel
    let result: TranslationResult
    let role: TranslationTextRole
    var textOverride: String?

    var body: some View {
        HStack {
            Spacer()

            PopupTextActions(
                model: model,
                result: result,
                role: role,
                textOverride: textOverride
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PopupTextActions: View {
    @ObservedObject var model: AppShellModel
    let result: TranslationResult
    let role: TranslationTextRole
    var textOverride: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.copyPopupText(role, textOverride: textOverride)
                }
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
            .help(copyLabel)
            .accessibilityLabel(copyLabel)
            .disabled(effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            SpokenOutputControls(
                model: model,
                result: result,
                role: role,
                textOverride: textOverride
            )
        }
        .controlSize(.small)
    }

    private var copyLabel: String {
        switch role {
        case .source:
            "Copy Original"
        case .translation:
            "Copy Translation"
        }
    }

    private var effectiveText: String {
        if let textOverride {
            return textOverride
        }

        return switch role {
        case .source:
            result.originalText
        case .translation:
            result.translatedText
        }
    }
}
