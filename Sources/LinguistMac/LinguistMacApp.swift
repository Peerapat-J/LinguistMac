import AppKit
import SwiftUI

@main
struct LinguistMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppShellModel()
    @State private var keyboardInputMonitor = KeyboardInputMonitor()

    var body: some Scene {
        MenuBarExtra("LinguistMac", systemImage: "character.book.closed") {
            MenuBarMenuView(model: model)
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: scenePhase, initial: true) { _, _ in
            startKeyboardInputMonitor()
        }

        WindowGroup("LinguistMac", id: AppWindow.status.rawValue) {
            ZStack {
                if model.settings.hasCompletedOnboarding {
                    ContentView(model: model)
                } else {
                    OnboardingView(model: model)
                }
            }
        }
        .defaultSize(width: 620, height: 520)

        Window("Quick Translate", id: AppWindow.quickTranslate.rawValue) {
            QuickTranslateView(model: model)
        }
        .defaultSize(width: 560, height: 460)

        Window("Translation", id: AppWindow.translationPopup.rawValue) {
            TranslationPopupView(model: model)
        }
        .defaultSize(width: 460, height: 320)

        Window("Setup Guide", id: AppWindow.onboarding.rawValue) {
            OnboardingView(model: model)
        }
        .defaultSize(width: 620, height: 560)

        Settings {
            SettingsView(model: model)
        }
    }

    private func startKeyboardInputMonitor() {
        let didStart = keyboardInputMonitor.start(model: model) { window in
            openWindow(id: window.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
        if didStart {
            Task {
                await model.refreshShortcutRegistrations()
            }
        }
    }
}
