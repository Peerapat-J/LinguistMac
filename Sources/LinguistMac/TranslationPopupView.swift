import LinguistMacCore
import SwiftUI

struct TranslationPopupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            content

            Spacer(minLength: 0)

            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(
            minWidth: 320,
            idealWidth: model.settings.popupWidth,
            maxWidth: 760,
            minHeight: 240,
            idealHeight: model.settings.popupHeight,
            maxHeight: 680
        )
        .background {
            WindowFrameObserver(savedFrame: model.savedPopupWindowFrame) { frame in
                model.rememberPopupWindowFrame(frame)
            }
            .frame(width: 0, height: 0)
        }
    }

    private var header: some View {
        HStack {
            Label("Translation", systemImage: "text.bubble")
                .font(.headline)
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.translatedText)
                        .font(popupFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let translatedReading = result.translatedReading {
                        ReadingText(text: translatedReading, role: .translation)
                    }

                    PopupTextActions(model: model, result: result, role: .translation)

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

                    if showsOriginal {
                        Divider()
                        HStack {
                            Text("Original")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            PopupTextActions(model: model, result: result, role: .source)
                        }
                        Text(result.originalText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let sourceReading = result.sourceReading {
                            ReadingText(text: sourceReading, role: .source)
                        }
                    }
                }
            }
        case let .failed(failure, originalText):
            let presentation = failure.presentation
            VStack(alignment: .leading, spacing: 10) {
                Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(presentation.message)
                    .foregroundStyle(.secondary)

                if let originalText, !originalText.isEmpty {
                    Text(originalText)
                        .font(.callout)
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
    }

    private func handleWordLookupRecovery(
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
        case .openSystemSettings, .retry:
            model.performRecoveryAction(action)
        }
    }

    private var popupFont: Font {
        guard !model.settings.popupFontFamily.isEmpty else {
            return .system(size: model.settings.popupFontSize)
        }

        return .custom(model.settings.popupFontFamily, size: model.settings.popupFontSize)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Button {
                model.togglePopupOriginal()
            } label: {
                if model.popupState.showsOriginal {
                    Label("Hide Original", systemImage: "text.quote")
                } else {
                    Label("Show Original", systemImage: "text.quote")
                }
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

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.copyPopupText(role)
                }
            } label: {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
            .help(copyLabel)
            .accessibilityLabel(copyLabel)

            SpokenOutputControls(model: model, result: result, role: role)
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
}

struct SpokenOutputControls: View {
    @ObservedObject var model: AppShellModel
    let result: TranslationResult
    var role: TranslationTextRole = .translation

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
                    model.speakPopupText(role, result: result)
                } label: {
                    Label(speakLabel, systemImage: "speaker.wave.2.fill")
                }
                .help(speakLabel)
                .accessibilityLabel(speakLabel)
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
        model.spokenOutputRequest(for: role, result: result)
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
