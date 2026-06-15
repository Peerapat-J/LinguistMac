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
        case let .success(result, showsOriginal, wordCard):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.translatedText)
                        .font(popupFont)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !result.wordTranslations.isEmpty {
                        Divider()
                        wordTranslationList(result.wordTranslations, wordCard: wordCard)
                    }

                    if let wordCard {
                        wordLookupCard(wordCard)
                    }

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
                        model.performRecoveryAction(action)
                    } label: {
                        Label(action.displayTitle, systemImage: action.systemImage)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func wordTranslationList(
        _ wordTranslations: [WordTranslation],
        wordCard: TranslationPopupWordCardState?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(wordTranslations.enumerated()), id: \.offset) { index, wordTranslation in
                    Button {
                        Task {
                            await model.selectPopupWord(wordTranslation, at: index)
                        }
                    } label: {
                        wordTranslationRow(
                            wordTranslation,
                            isSelected: wordCard?.matches(wordTranslation, at: index) == true
                        )
                    }
                    .buttonStyle(.plain)
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
                    model.dismissPopupWordCard()
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
                    if action == .retry {
                        Task {
                            await model.selectPopupWord(card.wordTranslation, at: card.wordIndex)
                        }
                    } else {
                        model.performRecoveryAction(action)
                    }
                } label: {
                    Label(action.displayTitle, systemImage: action.systemImage)
                }
                .controlSize(.small)
            }
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

            PopupResizeGrip { widthDelta, heightDelta in
                model.resizePopup(widthDelta: widthDelta, heightDelta: heightDelta)
            }
        }
    }
}

extension TranslationFailure {
    var displayText: String {
        presentation.message
    }
}

private struct PopupResizeGrip: View {
    @State private var previousTranslation: CGSize = .zero
    let onResize: (Double, Double) -> Void

    var body: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel("Resize translation popup")
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let widthDelta = value.translation.width - previousTranslation.width
                        let heightDelta = value.translation.height - previousTranslation.height
                        previousTranslation = value.translation
                        onResize(widthDelta, heightDelta)
                    }
                    .onEnded { _ in
                        previousTranslation = .zero
                    }
            )
    }
}

private extension TranslationRecoveryAction {
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
