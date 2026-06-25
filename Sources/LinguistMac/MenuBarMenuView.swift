import AppKit
import LinguistMacCore
import SwiftUI

struct MenuBarMenuView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LinguistMac")
                    .font(.headline)
                if model.readiness.isScreenTranslationReady {
                    Text("Ready for translation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Setup needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button {
                dismissWindow(id: AppWindow.translationPopup.rawValue)
                Task {
                    await model.runScreenTranslation()
                    openWindow(id: AppWindow.translationPopup.rawValue)
                    activateApp()
                }
            } label: {
                Label("Screen Translate", systemImage: "viewfinder")
            }

            Button {
                model.prepareQuickTranslate()
                openWindow(id: AppWindow.quickTranslate.rawValue)
                activateApp()
            } label: {
                Label("Quick Translate", systemImage: "text.cursor")
            }

            Button {
                dismissWindow(id: AppWindow.translationPopup.rawValue)
                Task {
                    await model.runSelectedTextTranslation()
                    openWindow(id: AppWindow.translationPopup.rawValue)
                    activateApp()
                }
            } label: {
                Label("Selected Text", systemImage: "selection.pin.in.out")
            }

            Button {
                dismissWindow(id: AppWindow.translationPopup.rawValue)
                Task {
                    await model.runDragTranslation()
                    openWindow(id: AppWindow.translationPopup.rawValue)
                    activateApp()
                }
            } label: {
                Label("Drag Translate", systemImage: "cursorarrow.motionlines")
            }
            .disabled(!model.settings.dragTranslationEnabled)

            Button {
                openLinguistSettings(model: model, using: openSettings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Button {
                model.record(.history)
                openWindow(id: AppWindow.status.rawValue)
                activateApp()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Divider()

            Menu {
                if model.historyLoadError != nil {
                    Text("History unavailable")
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await model.refreshRecentTranslations()
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                } else if model.recentMenuItems.isEmpty {
                    Text("No recent translations")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentMenuItems) { result in
                        Button {
                            model.showHistoryResult(result)
                            openWindow(id: AppWindow.translationPopup.rawValue)
                            activateApp()
                        } label: {
                            Text(summary(for: result))
                        }
                    }
                }
            } label: {
                Label("Recent", systemImage: "list.bullet")
            }

            Button {
                model.reopenOnboarding()
                openWindow(id: AppWindow.onboarding.rawValue)
                activateApp()
            } label: {
                Label("Setup Guide", systemImage: "checklist")
            }

            Button {
                model.record(.about)
                NSApp.orderFrontStandardAboutPanel(nil)
                activateApp()
            } label: {
                Label("About", systemImage: "info.circle")
            }

            Divider()

            Button {
                model.record(.quit)
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .frame(minWidth: 240, alignment: .leading)
        .task {
            await model.refreshRecentTranslations()
            await model.refreshReadiness()
            await model.refreshShortcutRegistrations()
        }
    }

    private func summary(for result: TranslationResult) -> String {
        let text = result.translatedText.replacingOccurrences(of: "\n", with: " ")
        if text.count <= 27 {
            return text
        }

        return String(text.prefix(27)) + "..."
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension View {
    @MainActor
    func openLinguistSettings(model: AppShellModel, using openSettings: OpenSettingsAction) {
        model.record(.settings)
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }
}
