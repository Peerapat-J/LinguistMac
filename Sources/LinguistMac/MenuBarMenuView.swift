import AppKit
import LinguistMacCore
import SwiftUI

struct MenuBarMenuView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LinguistMac")
                    .font(.headline)
                Text(model.readiness.isScreenTranslationReady ? "Ready for translation" : "Setup needed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                model.presentScreenTranslationPreview()
                openWindow(id: AppWindow.translationPopup.rawValue)
                activateApp()
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
                openSettingsWindow()
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
                if model.recentMenuItems.isEmpty {
                    Text("No recent translations")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentMenuItems) { result in
                        Button {
                            model.popupState = .success(result, showsOriginal: false)
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
    }

    private func summary(for result: TranslationResult) -> String {
        let text = result.translatedText.replacingOccurrences(of: "\n", with: " ")
        if text.count <= 30 {
            return text
        }

        return String(text.prefix(27)) + "..."
    }

    private func openSettingsWindow() {
        model.record(.settings)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        activateApp()
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
