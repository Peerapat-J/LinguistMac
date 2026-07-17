import AppKit
import LinguistMacCore
import SwiftUI

struct TranslationPopupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel
    @State private var measuredNaturalHeight: PopupNaturalHeightMeasurement?
    @State private var shouldRetryAfterDismiss = false
    @StateObject private var windowFrameController = PopupWindowFrameController()

    var body: some View {
        popupLayout {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: PopupWindowSizingPolicy.minimumWidth,
            idealWidth: model.settings.popupWidth,
            maxWidth: PopupWindowSizingPolicy.maximumWidth,
            minHeight: PopupWindowSizingPolicy.minimumFrameHeight,
            idealHeight: model.settings.popupHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .background(alignment: .topLeading) {
            naturalHeightMeasurement
        }
        .onPreferenceChange(PopupNaturalHeightPreferenceKey.self) { measurement in
            guard let measurement, measurement.height > 0 else {
                measuredNaturalHeight = nil
                return
            }

            let roundedMeasurement = PopupNaturalHeightMeasurement(
                revision: measurement.revision,
                height: ceil(measurement.height)
            )
            if measuredNaturalHeight != roundedMeasurement {
                measuredNaturalHeight = roundedMeasurement
            }
        }
        .background {
            WindowFrameObserver(
                controller: windowFrameController,
                automaticResizeRequest: automaticResizeRequest,
                automaticResizeEnabled: !model.hasManuallyResizedPopup,
                savedFrame: model.savedPopupWindowFrame,
                onFrameChange: { frame in
                    model.rememberPopupWindowFrame(frame)
                },
                onManualResize: {
                    model.notePopupManualResize()
                }
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            model.preparePopupSourceEditorIfNeeded()
            Task {
                await model.refreshAppleLanguagePackGroupsIfNeeded()
            }
        }
        .onDisappear {
            retryAfterDismissIfNeeded()
        }
    }
}

extension TranslationPopupView {
    func popupLayout(
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            languageBar
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
            Divider()
                .fixedSize(horizontal: false, vertical: true)
            content()
                .layoutPriority(0)
            footer
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private var automaticResizeRequest: PopupWindowAutomaticResizeRequest? {
        guard let revision = automaticResizeRevision else {
            return nil
        }
        guard let measuredNaturalHeight,
              measuredNaturalHeight.revision == revision
        else {
            return nil
        }

        let minimumContentHeight = automaticResizeMinimumContentHeight()
        return PopupWindowAutomaticResizeRequest(
            revision: revision,
            preferredContentHeight: max(measuredNaturalHeight.height, minimumContentHeight),
            minimumContentHeight: minimumContentHeight,
            preferredFrameWidth: automaticResizePreferredFrameWidth(for: revision)
        )
    }

    private func automaticResizePreferredFrameWidth(
        for revision: PopupWindowContentRevision
    ) -> CGFloat? {
        if revision.isSuccess {
            return model.settings.popupWidth
        }
        return PopupWindowSizingPolicy.preferredFrameWidth(for: revision)
    }

    @ViewBuilder
    private var naturalHeightMeasurement: some View {
        if let revision = automaticResizeRevision {
            GeometryReader { geometry in
                popupLayout {
                    naturalContentMeasurement
                }
                .frame(width: geometry.size.width)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    PopupNaturalHeightReader(revision: revision)
                }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var naturalContentMeasurement: some View {
        switch model.popupState {
        case let .success(result, showsOriginal, wordCard):
            naturalSuccessContent(
                result: result,
                showsOriginal: showsOriginal,
                wordCard: wordCard
            )
        case let .failed(failure, originalText):
            failureContent(failure: failure, originalText: originalText)
        case .empty, .loading:
            EmptyView()
        }
    }

    private var automaticResizeRevision: PopupWindowContentRevision? {
        switch model.popupState {
        case let .success(result, showsOriginal, wordCard):
            automaticResizeRevision(
                result: result,
                showsOriginal: showsOriginal,
                wordCard: wordCard
            )
        case let .failed(failure, originalText):
            .failure(failure, originalText: originalText)
        case .empty, .loading:
            nil
        }
    }

    private func automaticResizeRevision(
        result: TranslationResult,
        showsOriginal: Bool,
        wordCard: TranslationPopupWordCardState?
    ) -> PopupWindowContentRevision {
        PopupWindowContentRevision(
            resultID: result.id,
            showsOriginal: showsOriginal,
            wordTranslations: result.wordTranslations,
            wordCard: wordCard
        )
    }

    private var languageBar: some View {
        HStack(spacing: 10) {
            Picker("Source Language", selection: popupSourceLanguageBinding) {
                ForEach(model.availableLanguages, id: \.id) { language in
                    PopupLanguagePickerOption(
                        language: language,
                        readiness: model.popupLanguagePackReadiness(for: language)
                    )
                    .tag(language)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Source Language")

            Button {
                model.swapPopupLanguages()
            } label: {
                Label("Swap Languages", systemImage: "arrow.left.arrow.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Swap Languages")
            .accessibilityLabel("Swap Languages")
            .disabled(!model.canSwapPopupLanguages)

            Picker("Target Language", selection: popupTargetLanguageBinding) {
                ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                    PopupLanguagePickerOption(
                        language: language,
                        readiness: model.popupLanguagePackReadiness(for: language)
                    )
                    .tag(language)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Target Language")
        }
        .disabled(!model.canRetranslatePopup)
    }

    private var popupSourceLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.popupSourceLanguage
        } set: { language in
            model.selectPopupSourceLanguage(language)
        }
    }

    private var popupTargetLanguageBinding: Binding<TranslationLanguage> {
        Binding {
            model.popupTargetLanguage
        } set: { language in
            model.selectPopupTargetLanguage(language)
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
        case let .success(result, showsOriginal, wordCard):
            flexibleSuccessContent(
                result: result,
                showsOriginal: showsOriginal,
                wordCard: wordCard
            )
        case let .failed(failure, originalText):
            failureContent(failure: failure, originalText: originalText)
        }
    }

    private func failureContent(
        failure: TranslationFailure,
        originalText: String?
    ) -> some View {
        let presentation = failure.presentation
        return VStack(alignment: .leading, spacing: 10) {
            Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(presentation.message)
                .foregroundStyle(.secondary)

            if let originalText, !originalText.isEmpty {
                Text(originalText)
                    .font(popupFont)
                    .textSelection(.enabled)
            }

            if let action = presentation.recoveryAction {
                Button {
                    performRecoveryAction(action)
                } label: {
                    Label(action.displayTitle, systemImage: action.systemImage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func handleWordLookupRecovery(
        _ action: TranslationRecoveryAction,
        card: TranslationPopupWordCardState,
        resultID: UUID
    ) {
        switch action {
        case .retry:
            Task {
                await model.selectPopupWord(
                    card.wordTranslation,
                    at: card.wordIndex,
                    resultID: resultID
                )
            }
        case .openSettings:
            openLinguistSettings(model: model, using: openSettings)
        case .openSystemSettings:
            model.performRecoveryAction(action)
        }
    }

    private func performRecoveryAction(_ action: TranslationRecoveryAction) {
        switch action {
        case .openSettings:
            openLinguistSettings(model: model, using: openSettings)
        case .openSystemSettings:
            model.performRecoveryAction(action)
        case .retry:
            shouldRetryAfterDismiss = true
            dismissWindow(id: AppWindow.translationPopup.rawValue)
        }
    }

    private func retryAfterDismissIfNeeded() {
        guard shouldRetryAfterDismiss else {
            return
        }

        shouldRetryAfterDismiss = false
        Task {
            await model.retryLastTranslationCommand()
            openWindow(id: AppWindow.translationPopup.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var popupFont: Font {
        guard !model.settings.popupFontFamily.isEmpty else {
            return .system(size: model.settings.popupFontSize)
        }

        return .custom(model.settings.popupFontFamily, size: model.settings.popupFontSize)
    }

    var popupSourceDraftBinding: Binding<String> {
        Binding {
            model.popupSourceDraft
        } set: { text in
            model.updatePopupSourceDraft(text)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                model.translatePopupDraft()
            } label: {
                Label("Translate", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canTranslatePopupDraft)
        }
    }
}

struct SpokenOutputControls: View {
    @ObservedObject var model: AppShellModel
    let result: TranslationResult
    var role: TranslationTextRole = .translation
    var textOverride: String?
    var actionTitle: String?
    var actionAccessibilityLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            if model.isSpokenOutputActive(context: context) {
                Button {
                    model.stopSpokenOutput()
                } label: {
                    Label("Stop", systemImage: "speaker.slash.fill")
                }
                .help("Stop Speaking")
                .accessibilityLabel("Stop Speaking")
            } else {
                Button {
                    model.speakPopupText(
                        role,
                        result: result,
                        textOverride: textOverride
                    )
                } label: {
                    Label(actionTitle ?? speakLabel, systemImage: "speaker.wave.2.fill")
                }
                .help(actionAccessibilityLabel ?? speakLabel)
                .accessibilityLabel(actionAccessibilityLabel ?? speakLabel)
                .disabled(request.trimmedText.isEmpty)
            }

            if let statusText {
                Label(statusText, systemImage: statusImage)
                    .font(.caption)
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
        }
    }

    private var statusText: String? {
        guard model.activeSpokenOutputContext == context else {
            return nil
        }

        switch model.spokenOutputState {
        case .idle:
            return nil
        case .preparing:
            return "Preparing speech"
        case .speaking:
            return "Speaking"
        case .completed:
            return "Spoken"
        case let .failed(failure, _):
            return failure.displayText
        }
    }

    private var context: SpokenOutputContext {
        SpokenOutputContext(resultID: result.id, role: role)
    }

    private var request: SpokenOutputRequest {
        model.spokenOutputRequest(
            for: role,
            result: result,
            textOverride: textOverride
        )
    }

    private var speakLabel: String {
        switch role {
        case .source:
            "Speak Original"
        case .translation:
            "Speak Translation"
        }
    }

    private var statusImage: String {
        switch model.spokenOutputState {
        case .failed:
            "exclamationmark.triangle"
        case .completed:
            "checkmark.circle"
        case .idle, .preparing, .speaking:
            "speaker.wave.2"
        }
    }

    private var statusTint: Color {
        switch model.spokenOutputState {
        case .failed:
            .orange
        case .preparing, .speaking:
            .blue
        case .idle, .completed:
            .secondary
        }
    }
}

struct TranslationWordLookupSection: View {
    let wordTranslations: [WordTranslation]
    let wordCard: TranslationPopupWordCardState?
    let isSelectionEnabled: Bool
    let onSelectWord: (WordTranslation, Int) -> Void
    let onDismissWordCard: () -> Void
    let onRecoveryAction: (TranslationRecoveryAction, TranslationPopupWordCardState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !wordTranslations.isEmpty {
                wordTranslationList
            }

            if let wordCard {
                wordLookupCard(wordCard)
            }
        }
    }

    private var wordTranslationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(wordTranslations.enumerated()), id: \.offset) { index, wordTranslation in
                    Button {
                        onSelectWord(wordTranslation, index)
                    } label: {
                        wordTranslationRow(
                            wordTranslation,
                            isSelected: wordCard?.matches(wordTranslation, at: index) == true
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isSelectionEnabled)
                    .accessibilityLabel("Look up \(wordTranslation.sourceText)")
                }
            }
        }
    }

    private func wordTranslationRow(
        _ wordTranslation: WordTranslation,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(wordTranslation.sourceText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(minWidth: 88, alignment: .leading)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(wordTranslation.translatedText)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private func wordLookupCard(_ card: TranslationPopupWordCardState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(card.wordTranslation.sourceText, systemImage: "text.magnifyingglass")
                    .font(.callout.weight(.semibold))

                Text(card.wordTranslation.translatedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onDismissWordCard()
                } label: {
                    Label("Dismiss word card", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            wordLookupContent(card)
        }
        .padding(10)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func wordLookupContent(_ card: TranslationPopupWordCardState) -> some View {
        switch card.lookupState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Looking up word...")
                .controlSize(.small)
        case let .completed(result):
            VStack(alignment: .leading, spacing: 6) {
                Text(result.translatedText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sentenceContext = result.sentenceContextDisplayText {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Context")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(sentenceContext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let definition = result.definition, !definition.isEmpty {
                    Text(definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let example = result.example, !example.isEmpty {
                    Text(example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        case .empty:
            Label("No extra word details available.", systemImage: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .failed(failure):
            wordLookupFailureContent(failure, card: card)
        }
    }

    @ViewBuilder
    private func wordLookupFailureContent(
        _ failure: WordLookupFailure,
        card: TranslationPopupWordCardState
    ) -> some View {
        let presentation = failure.presentation
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.title, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(presentation.message)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let action = presentation.recoveryAction {
                Button {
                    onRecoveryAction(action, card)
                } label: {
                    Label(action.displayTitle, systemImage: action.systemImage)
                }
                .controlSize(.small)
            }
        }
    }
}

extension TranslationRecoveryAction {
    var displayTitle: String {
        switch self {
        case .openSystemSettings:
            "Open System Settings"
        case .openSettings:
            "Open Settings"
        case .retry:
            "Try Again"
        }
    }

    var systemImage: String {
        switch self {
        case .openSystemSettings:
            "gearshape"
        case .openSettings:
            "slider.horizontal.3"
        case .retry:
            "arrow.clockwise"
        }
    }
}
