import LinguistMacCore
import SwiftUI

struct PopupTextPanelAllocatedHeights {
    let sourcePanel: CGFloat
    let translationPanel: CGFloat
}

struct PopupNaturalPanelStackLayout: Layout {
    let showsOriginal: Bool

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let measurements = panelMeasurements(proposal: proposal, subviews: subviews)
        let allocation = PopupTextPanelLayout.naturalPanelAllocation(
            sourcePanelHeight: measurements.source.height,
            translationPanelHeight: measurements.translation.height,
            showsOriginal: showsOriginal
        )
        return CGSize(
            width: proposal.width ?? max(
                measurements.source.width,
                measurements.translation.width
            ),
            height: allocation.sourcePanel
                + PopupTextPanelLayout.spacing
                + allocation.translationPanel
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else {
            return
        }
        let measurements = panelMeasurements(
            proposal: ProposedViewSize(width: bounds.width, height: nil),
            subviews: subviews
        )
        let allocation = PopupTextPanelLayout.naturalPanelAllocation(
            sourcePanelHeight: measurements.source.height,
            translationPanelHeight: measurements.translation.height,
            showsOriginal: showsOriginal
        )
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: allocation.sourcePanel
            )
        )
        subviews[1].place(
            at: CGPoint(
                x: bounds.minX,
                y: bounds.minY
                    + allocation.sourcePanel
                    + PopupTextPanelLayout.spacing
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(
                width: bounds.width,
                height: allocation.translationPanel
            )
        )
    }

    private func panelMeasurements(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (source: CGSize, translation: CGSize) {
        guard subviews.count == 2 else {
            return (.zero, .zero)
        }
        let panelProposal = ProposedViewSize(width: proposal.width, height: nil)
        return (
            subviews[0].sizeThatFits(panelProposal),
            subviews[1].sizeThatFits(panelProposal)
        )
    }
}

struct PopupWindowAutomaticWidthState {
    private(set) var restoreWidth: CGFloat?

    var hasPendingRestore: Bool {
        restoreWidth != nil
    }

    mutating func preferredFrameWidth(
        requestedWidth: CGFloat?,
        currentWidth: CGFloat
    ) -> CGFloat? {
        guard let requestedWidth else {
            defer { restoreWidth = nil }
            return restoreWidth
        }
        if restoreWidth == nil {
            restoreWidth = currentWidth
        }
        return requestedWidth
    }

    mutating func reset() {
        restoreWidth = nil
    }
}

enum PopupTextPanelLayout {
    static let spacing: CGFloat = 12
    static let panelPadding: CGFloat = 12
    static let sectionHeaderHeight: CGFloat = 28
    static let minimumTextViewportHeight: CGFloat = 28
    static let minimumSourceTextViewportHeight = minimumTextViewportHeight
    static let minimumTranslationTextViewportHeight = minimumTextViewportHeight
    static let fixedContentChromeHeight: CGFloat = 164
    static let minimumCollapsedSourcePanelHeight = (panelPadding * 2)
        + sectionHeaderHeight
    static let minimumSourcePanelHeight = minimumCollapsedSourcePanelHeight
        + spacing
        + minimumSourceTextViewportHeight
    static let minimumTranslationPanelHeight = (panelPadding * 2)
        + sectionHeaderHeight
        + spacing
        + minimumTranslationTextViewportHeight
    static let minimumCollapsedContentHeight = fixedContentChromeHeight
        + minimumPanelStackHeight(showsOriginal: false)
    static let expandedContentHeightIncrement = spacing + minimumSourceTextViewportHeight
    static let minimumExpandedContentHeight = fixedContentChromeHeight
        + minimumPanelStackHeight(showsOriginal: true)

    static func minimumPanelStackHeight(showsOriginal: Bool) -> CGFloat {
        let sourcePanelHeight = showsOriginal
            ? minimumSourcePanelHeight
            : minimumCollapsedSourcePanelHeight
        return sourcePanelHeight + spacing + minimumTranslationPanelHeight
    }

    static func sourcePanelHeight(
        for availableHeight: CGFloat,
        minimumSourceHeight: CGFloat = minimumSourcePanelHeight,
        minimumTranslationHeight: CGFloat = minimumTranslationPanelHeight
    ) -> CGFloat {
        let panelHeight = max(availableHeight - spacing, 0)
        guard minimumSourceHeight + minimumTranslationHeight <= panelHeight else {
            let maximumSourceHeight = max(
                minimumSourcePanelHeight,
                panelHeight - minimumTranslationPanelHeight
            )
            return min(
                max(panelHeight / 2, minimumSourcePanelHeight),
                maximumSourceHeight
            )
        }
        let maximumSourceHeight = max(
            minimumSourceHeight,
            panelHeight - minimumTranslationHeight
        )
        let balancedHeight = panelHeight / 2
        return min(max(balancedHeight, minimumSourceHeight), maximumSourceHeight)
    }

    static func allocatedPanelHeights(
        availableHeight: CGFloat,
        showsOriginal: Bool
    ) -> PopupTextPanelAllocatedHeights {
        let panelHeight = max(availableHeight - spacing, 0)
        guard showsOriginal else {
            let sourcePanel = min(minimumCollapsedSourcePanelHeight, panelHeight)
            return PopupTextPanelAllocatedHeights(
                sourcePanel: sourcePanel,
                translationPanel: max(panelHeight - sourcePanel, 0)
            )
        }

        let sourcePanel = min(sourcePanelHeight(for: availableHeight), panelHeight)
        return PopupTextPanelAllocatedHeights(
            sourcePanel: sourcePanel,
            translationPanel: max(panelHeight - sourcePanel, 0)
        )
    }

    static func naturalPanelAllocation(
        sourcePanelHeight: CGFloat,
        translationPanelHeight: CGFloat,
        showsOriginal: Bool
    ) -> PopupTextPanelAllocatedHeights {
        let sourceRequiredHeight = max(
            ceil(sourcePanelHeight),
            showsOriginal ? minimumSourcePanelHeight : minimumCollapsedSourcePanelHeight
        )
        let translationRequiredHeight = max(
            ceil(translationPanelHeight),
            minimumTranslationPanelHeight
        )
        guard showsOriginal else {
            return PopupTextPanelAllocatedHeights(
                sourcePanel: sourceRequiredHeight,
                translationPanel: translationRequiredHeight
            )
        }

        let equalPanelHeight = max(sourceRequiredHeight, translationRequiredHeight)
        return PopupTextPanelAllocatedHeights(
            sourcePanel: equalPanelHeight,
            translationPanel: equalPanelHeight
        )
    }

    static func minimumContentHeight(showsOriginal: Bool) -> CGFloat {
        showsOriginal ? minimumExpandedContentHeight : minimumCollapsedContentHeight
    }
}

extension TranslationPopupView {
    func flexibleSuccessContent(
        result: TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        GeometryReader { geometry in
            let allocatedHeights = PopupTextPanelLayout.allocatedPanelHeights(
                availableHeight: geometry.size.height,
                showsOriginal: showsOriginal
            )

            VStack(alignment: .leading, spacing: PopupTextPanelLayout.spacing) {
                PopupTextPanel(fillsHeight: showsOriginal) {
                    sourcePanelContent(
                        result: result,
                        showsOriginal: showsOriginal,
                        usesFlexibleEditorHeight: true
                    )
                }
                .frame(height: allocatedHeights.sourcePanel)

                PopupTextPanel(fillsHeight: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        translationPanelHeader(result: result)

                        ScrollView {
                            translationTextContent(result: result, wordCard: wordCard)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: allocatedHeights.translationPanel)
            }
        }
        .frame(
            minHeight: PopupTextPanelLayout.minimumPanelStackHeight(
                showsOriginal: showsOriginal
            )
        )
    }

    func naturalSuccessContent(
        result: TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        PopupNaturalPanelStackLayout(showsOriginal: showsOriginal) {
            PopupTextPanel {
                sourcePanelContent(
                    result: result,
                    showsOriginal: showsOriginal,
                    usesFlexibleEditorHeight: false
                )
            }

            PopupTextPanel {
                VStack(alignment: .leading, spacing: 12) {
                    translationPanelHeader(result: result)
                    translationTextContent(result: result, wordCard: wordCard)
                }
            }
        }
        .frame(
            minHeight: PopupTextPanelLayout.minimumPanelStackHeight(
                showsOriginal: showsOriginal
            )
        )
    }

    private func sourcePanelContent(
        result: TranslationResult,
        showsOriginal: Bool,
        usesFlexibleEditorHeight: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sourcePanelHeader(result: result, showsOriginal: showsOriginal)

            if showsOriginal {
                if usesFlexibleEditorHeight {
                    TextEditor(text: popupSourceDraftBinding)
                        .scrollContentBackground(.hidden)
                        .font(popupFont)
                        .frame(
                            minHeight: PopupTextPanelLayout.minimumSourceTextViewportHeight,
                            maxHeight: .infinity
                        )
                        .accessibilityLabel("Original Text")
                } else {
                    Text(model.popupSourceDraft)
                        .font(popupFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(
                            minHeight: PopupTextPanelLayout.minimumSourceTextViewportHeight,
                            alignment: .topLeading
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let sourceReading = result.sourceReading, !model.isPopupSourceDirty {
                    ReadingText(text: sourceReading, role: .source)
                }
            }
        }
    }

    func automaticResizeMinimumContentHeight() -> CGFloat {
        switch model.popupState {
        case let .success(_, showsOriginal, _):
            PopupTextPanelLayout.minimumContentHeight(showsOriginal: showsOriginal)
        case .failed, .empty, .loading:
            PopupWindowSizingPolicy.minimumFrameHeight
        }
    }

    private func sourcePanelHeader(
        result: TranslationResult,
        showsOriginal: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                model.togglePopupOriginal()
                model.preparePopupSourceEditorIfNeeded()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showsOriginal ? "chevron.down" : "chevron.right")
                    Text(LocalizedStringKey(result.request.sourceLanguage.displayName))
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel(
                PopupTextPanelAccessibility.disclosureLabel(
                    languageName: result.request.sourceLanguage.displayName,
                    showsOriginal: showsOriginal
                )
            )

            Spacer(minLength: 8)

            PopupTextActions(
                model: model,
                result: result,
                role: .source,
                languageName: result.request.sourceLanguage.displayName,
                textOverride: model.popupSourceDraft
            )
        }
        .frame(minHeight: PopupTextPanelLayout.sectionHeaderHeight)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
        .accessibilityElement(children: .contain)
    }

    private func translationPanelHeader(result: TranslationResult) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(result.request.targetLanguage.displayName))
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            PopupTextActions(
                model: model,
                result: result,
                role: .translation,
                languageName: result.request.targetLanguage.displayName
            )
        }
        .frame(minHeight: PopupTextPanelLayout.sectionHeaderHeight)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
        .accessibilityElement(children: .contain)
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
                .fixedSize(horizontal: false, vertical: true)

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
        .fixedSize(horizontal: false, vertical: true)
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
            .padding(PopupTextPanelLayout.panelPadding)
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

private struct PopupTextActions: View {
    @ObservedObject var model: AppShellModel
    let result: TranslationResult
    let role: TranslationTextRole
    let languageName: String
    var textOverride: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.copyPopupText(role, textOverride: textOverride)
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help(copyLabel)
            .accessibilityLabel(copyLabel)
            .disabled(effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            SpokenOutputControls(
                model: model,
                result: result,
                role: role,
                textOverride: textOverride,
                actionTitle: "Speak",
                actionAccessibilityLabel: speakLabel
            )
        }
        .controlSize(.small)
    }

    private var copyLabel: String {
        "Copy \(languageName) text"
    }

    private var speakLabel: String {
        "Speak \(languageName) text"
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

enum PopupTextPanelAccessibility {
    static func disclosureLabel(languageName: String, showsOriginal: Bool) -> String {
        "\(showsOriginal ? "Hide" : "Show") original text in \(languageName)"
    }
}
