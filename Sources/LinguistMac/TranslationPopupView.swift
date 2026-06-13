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
        case let .success(result, showsOriginal):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.translatedText)
                        .font(popupFont)
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
