import AppKit
import SwiftUI

@main
struct LinguistMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppShellModel
    @State private var keyboardInputMonitor = KeyboardInputMonitor()
    private let shortcutRegistry: SystemShortcutRegistry

    init() {
        let shortcutRegistry = SystemShortcutRegistry()
        let initialSettings = UserDefaultsAppSettingsStore.loadInitialSettings()
        AppLanguagePreferenceApplier.apply(initialSettings.appLanguage)
        self.shortcutRegistry = shortcutRegistry
        _model = StateObject(
            wrappedValue: AppShellModel(
                settings: initialSettings,
                services: LiveLinguistServices.make(shortcutRegistry: shortcutRegistry)
            )
        )
    }

    var body: some Scene {
        MenuBarExtra("LinguistMac", systemImage: "character.book.closed") {
            MenuBarMenuView(model: model)
                .environment(\.locale, model.settings.appLanguage.locale)
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
            .environment(\.locale, model.settings.appLanguage.locale)
        }
        .defaultSize(width: 620, height: 520)

        Window("Quick Translate", id: AppWindow.quickTranslate.rawValue) {
            QuickTranslateView(model: model)
                .environment(\.locale, model.settings.appLanguage.locale)
        }
        .defaultSize(width: 560, height: 460)

        Window("Translation", id: AppWindow.translationPopup.rawValue) {
            TranslationPopupView(model: model)
                .environment(\.locale, model.settings.appLanguage.locale)
        }
        .defaultSize(width: 460, height: 320)

        Window("Setup Guide", id: AppWindow.onboarding.rawValue) {
            OnboardingView(model: model)
                .environment(\.locale, model.settings.appLanguage.locale)
        }
        .defaultSize(width: 620, height: 560)

        Settings {
            SettingsView(model: model)
                .environment(\.locale, model.settings.appLanguage.locale)
        }
    }

    private func startKeyboardInputMonitor() {
        let didStart = keyboardInputMonitor.start(model: model, shortcutRegistry: shortcutRegistry) { window in
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
