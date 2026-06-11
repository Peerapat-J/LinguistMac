import LinguistMacCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }

            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
        }
        .padding(24)
        .frame(width: 620, height: 520)
        .task {
            await model.refreshReadiness()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Languages") {
                Picker("Source", selection: $model.settings.sourceLanguage) {
                    ForEach(model.availableLanguages, id: \.id) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }

                Picker("Target", selection: $model.settings.targetLanguage) {
                    ForEach(model.availableLanguages.filter(\.canBeTargetLanguage), id: \.id) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            }

            Section("Translation") {
                Picker("Engine", selection: $model.settings.selectedProviderID) {
                    ForEach(model.availableProviders, id: \.id) { provider in
                        Text(provider.displayName)
                            .tag(provider.id)
                    }
                }

                Toggle("Auto-copy result", isOn: $model.settings.autoCopyEnabled)
                Toggle("Cmd+C+C translation", isOn: $model.settings.doubleCopyTranslationEnabled)
                Toggle("Drag translation", isOn: $model.settings.dragTranslationEnabled)
                Toggle("Launch at login", isOn: $model.settings.launchAtLoginEnabled)
                    .disabled(true)
                Text("Launch-at-login wiring lands with the app preferences milestone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                ShortcutRow(title: "Screen Translate", shortcut: model.settings.screenTranslationShortcut)
                ShortcutRow(title: "Selected Text", shortcut: model.settings.textSelectionShortcut)
                ShortcutRow(title: "Quick Translate", shortcut: model.settings.quickTranslateShortcut)
                shortcutStatus
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            Section("Popup") {
                Stepper(
                    "Font size: \(Int(model.settings.popupFontSize)) pt",
                    value: $model.settings.popupFontSize,
                    in: 12 ... 22,
                    step: 1
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Width: \(Int(model.settings.popupWidth)) px")
                    Slider(value: $model.settings.popupWidth, in: 320 ... 720, step: 20)
                }

                Toggle("Match selection width", isOn: $model.settings.matchPopupWidthToSelection)
            }

            Section("Setup") {
                Toggle("Setup guide completed", isOn: onboardingCompletedBinding)

                ForEach(model.readiness.items) { item in
                    ReadinessRow(item: item) {
                        switch item.kind {
                        case .screenTranslation:
                            model.openSystemSettings(for: .screenRecording)
                        case .accessibility:
                            model.openSystemSettings(for: .accessibility)
                        case .appleTranslation, .cloudProvider:
                            model.openSettingsWindow()
                            model.record(.settings)
                        }
                    }
                }
            }

            Section("Privacy") {
                Text("The default path is on-device. Cloud providers stay optional and require explicit configuration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var onboardingCompletedBinding: Binding<Bool> {
        Binding {
            model.settings.hasCompletedOnboarding
        } set: { isCompleted in
            model.setOnboardingCompleted(isCompleted)
        }
    }

    @ViewBuilder
    private var shortcutStatus: some View {
        if model.shortcutRegistrationResults.isEmpty {
            Text("Shortcuts will register after Accessibility is available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(model.shortcutRegistrationResults, id: \.action) { result in
                HStack {
                    Image(systemName: result.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isRegistered ? .green : .orange)
                    Text(result.action.settingsTitle)
                    Spacer()
                    Text(result.statusText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: LinguistMacCore.KeyboardShortcut

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var displayText: String {
        let modifiers = shortcut.modifiers
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displaySymbol)
            .joined()
        return modifiers + shortcut.key.uppercased()
    }
}

private extension LinguistMacCore.KeyboardModifier {
    var displaySymbol: String {
        switch self {
        case .command:
            "Cmd+"
        case .control:
            "Ctrl+"
        case .option:
            "Opt+"
        case .shift:
            "Shift+"
        }
    }
}

private extension ShortcutAction {
    var settingsTitle: String {
        switch self {
        case .screenTranslation:
            "Screen Translate"
        case .textSelectionTranslation:
            "Selected Text"
        case .quickTranslate:
            "Quick Translate"
        case .clipboardDoubleCopy:
            "Cmd+C+C"
        case .dragTranslation:
            "Drag Translation"
        }
    }
}

private extension ShortcutRegistrationResult {
    var statusText: String {
        switch issue {
        case nil:
            "Registered"
        case .permissionDenied:
            "Needs Accessibility"
        case let .duplicate(action):
            "Conflicts with \(action.settingsTitle)"
        case .unavailable:
            "Unavailable"
        }
    }
}

private struct ReadinessRow: View {
    let item: OnboardingReadinessItem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.status != .granted {
                Button("Open") {
                    action()
                }
                .controlSize(.small)
            }
        }
    }
}

extension PermissionStatus {
    var systemImage: String {
        switch self {
        case .granted:
            "checkmark.circle.fill"
        case .notDetermined:
            "circle.dashed"
        case .denied:
            "xmark.circle.fill"
        case .restricted:
            "lock.circle.fill"
        case .unavailable:
            "minus.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .granted:
            .green
        case .notDetermined:
            .secondary
        case .denied, .restricted:
            .red
        case .unavailable:
            .orange
        }
    }
}
