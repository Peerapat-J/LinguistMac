import AppKit
import LinguistMacCore
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LinguistMac Status")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Screen translation is wired through capture, OCR, and the default translation provider.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Label("Menu bar commands route through app state.", systemImage: "menubar.rectangle")
                Label("Selected-region translation uses ScreenCaptureKit and Vision OCR.", systemImage: "viewfinder")
                Label("Recent translations persist locally and trim to the latest 50 records.", systemImage: "clock")
            }

            if let historyLoadError = model.historyLoadError {
                HStack(alignment: .top, spacing: 10) {
                    Label(historyLoadError.message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Button {
                        Task {
                            await model.refreshRecentTranslations()
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
            }

            if model.recentTranslations.isEmpty {
                ContentUnavailableView(
                    "No Recent Translations",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Run Screen Translate or Quick Translate from the menu bar.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(model.recentTranslations) { result in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.translatedText)
                                .lineLimit(2)
                            Text(result.originalText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(relativeDateString(for: result.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            model.showHistoryResult(result)
                            openWindow(id: AppWindow.translationPopup.rawValue)
                            NSApp.activate(ignoringOtherApps: true)
                        } label: {
                            Label("Reopen", systemImage: "arrow.up.forward.app")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            Task {
                                await model.copyHistoryResult(result)
                            }
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .task {
            await model.refreshRecentTranslations()
        }
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
