import LinguistMacCore
import SwiftUI

struct QuickTranslateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
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
            voiceControls

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
        .frame(width: 560, height: 520)
    }

    private var languageBar: some View {
        HStack(spacing: 12) {
            Picker("Source", selection: $model.quickDraft.sourceLanguage) {
                ForEach(model.availableLanguages, id: \.id) { language in
                    Text(LocalizedStringKey(language.displayName))
                        .tag(language)
                }
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Picker("Target", selection: $model.quickDraft.targetLanguage) {
                ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                    Text(LocalizedStringKey(language.displayName))
                        .tag(language)
                }
            }
        }
    }

    private var voiceControls: some View {
        HStack(spacing: 10) {
            Button {
                model.startQuickVoiceCapture()
            } label: {
                Label("Speak", systemImage: "mic.fill")
            }
            .disabled(model.isQuickVoiceCaptureActive)

            Button {
                model.cancelQuickVoiceCapture()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .disabled(!model.isQuickVoiceCaptureActive)

            Spacer()

            if let statusText = quickVoiceStatusText {
                Label(statusText, systemImage: quickVoiceStatusImage)
                    .font(.caption)
                    .foregroundStyle(quickVoiceStatusTint)
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
        case .capturing:
            ProgressView("Recording short phrase...")
                .frame(maxWidth: .infinity, minHeight: 96)
        case .recognizing:
            ProgressView("Recognizing speech...")
                .frame(maxWidth: .infinity, minHeight: 96)
        case let .requestingPermission(kind):
            ProgressView("Requesting \(kind.displayName)...")
                .frame(maxWidth: .infinity, minHeight: 96)
        case .translating:
            VStack(alignment: .leading, spacing: 8) {
                if let transcript = model.quickVoiceTranscript {
                    Text("Transcript")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                }

                ProgressView("Translating...")
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case let .completed(result):
            let presentedResult = quickPresentedResult(for: result)
            let wordCard = quickWordCard(for: result)
            let canSelectWords = quickResultMatchesPopup(result)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let transcript = voiceTranscript(for: presentedResult) {
                        Text("Transcript")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transcript)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }

                    Text("Result")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(presentedResult.translatedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    SpokenOutputControls(model: model, result: presentedResult)

                    if !presentedResult.wordTranslations.isEmpty || wordCard != nil {
                        Divider()
                        TranslationWordLookupSection(
                            wordTranslations: presentedResult.wordTranslations,
                            wordCard: wordCard,
                            isSelectionEnabled: canSelectWords,
                            onSelectWord: { wordTranslation, index in
                                Task {
                                    await model.selectPopupWord(
                                        wordTranslation,
                                        at: index,
                                        resultID: presentedResult.id
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
                                    resultID: presentedResult.id
                                )
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 190, alignment: .topLeading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case let .failed(failure):
            let presentation = failure.presentation
            VStack(alignment: .leading, spacing: 8) {
                Label(presentation.title, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let action = presentation.recoveryAction {
                    Button {
                        performRecoveryAction(action)
                    } label: {
                        Label(action.displayTitle, systemImage: action.systemImage)
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func quickPresentedResult(for result: TranslationResult) -> TranslationResult {
        guard case let .success(currentResult, _, _) = model.popupState,
              currentResult.id == result.id
        else {
            return result
        }

        return currentResult
    }

    private func quickWordCard(for result: TranslationResult) -> TranslationPopupWordCardState? {
        guard case let .success(currentResult, _, wordCard) = model.popupState,
              currentResult.id == result.id
        else {
            return nil
        }

        return wordCard
    }

    private func quickResultMatchesPopup(_ result: TranslationResult) -> Bool {
        guard case let .success(currentResult, _, _) = model.popupState else {
            return false
        }

        return currentResult.id == result.id
    }

    private func voiceTranscript(for result: TranslationResult) -> String? {
        guard let transcript = model.quickVoiceTranscript,
              transcript == result.originalText
        else {
            return nil
        }

        return transcript
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
}

private extension QuickTranslateView {
    var quickVoiceStatusText: String? {
        switch model.quickVoiceState {
        case .idle:
            nil
        case let .requestingPermission(kind):
            "Requesting \(kind.displayName)"
        case .capturing:
            "Recording"
        case .recognizing:
            "Recognizing"
        case let .completed(result):
            result.trimmedTranscript.isEmpty ? nil : "Transcript ready"
        case let .failed(failure):
            quickVoiceFailureText(failure)
        }
    }

    var quickVoiceStatusImage: String {
        switch model.quickVoiceState {
        case .idle:
            "mic"
        case .requestingPermission:
            "hand.raised"
        case .capturing:
            "mic.circle.fill"
        case .recognizing:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var quickVoiceStatusTint: AnyShapeStyle {
        switch model.quickVoiceState {
        case .idle, .completed:
            AnyShapeStyle(.secondary)
        case .requestingPermission, .capturing, .recognizing:
            AnyShapeStyle(.blue)
        case .failed:
            AnyShapeStyle(.orange)
        }
    }

    func quickVoiceFailureText(_ failure: SpeechRecognitionFailure) -> String {
        switch failure {
        case let .permissionDenied(kind):
            "\(kind.displayName) denied"
        case .sourceLanguageRequired:
            "Choose source language"
        case .onDeviceRecognitionUnavailable:
            "On-device speech unavailable"
        case .emptyTranscript:
            "No speech recognized"
        case .cancelled:
            "Voice capture cancelled"
        case .captureInProgress:
            "Voice capture running"
        case .recognitionFailed:
            "Speech recognition failed"
        }
    }
}
