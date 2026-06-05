import SwiftUI

@main
struct LinguistMacApp: App {
    @StateObject private var model = AppShellModel()

    var body: some Scene {
        MenuBarExtra("LinguistMac", systemImage: "character.book.closed") {
            MenuBarMenuView(model: model)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("LinguistMac", id: AppWindow.status.rawValue) {
            if model.settings.hasCompletedOnboarding {
                ContentView(model: model)
            } else {
                OnboardingView(model: model)
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
}
