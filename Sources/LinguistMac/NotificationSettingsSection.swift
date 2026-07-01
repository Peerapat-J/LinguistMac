import SwiftUI

struct NotificationSettingsSection: View {
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
            SettingsSectionCard("Sound") {
                switchRow(
                    "Play completion sound",
                    detail: "Play sound when translation completes",
                    isOn: $model.settings.screenTranslationSoundEnabled
                )
                SettingsDivider()
                notificationRow(
                    "Screen Translate Sound",
                    detail: "Choose the sound played after Screen Translate completes."
                ) {
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.playSelectedScreenTranslationSound() }
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.settings.screenTranslationSoundEnabled)
                        .accessibilityLabel("Preview Screen Translate sound")

                        Picker("", selection: $model.settings.screenTranslationSoundName) {
                            ForEach(soundOptions, id: \.self) { soundName in
                                Text(soundName)
                                    .tag(soundName)
                            }
                        }
                        .labelsHidden()
                        .disabled(!model.settings.screenTranslationSoundEnabled)
                        .onChange(of: model.settings.screenTranslationSoundName) {
                            Task { await model.playSelectedScreenTranslationSound() }
                        }
                    }
                }
            }

            SettingsSectionCard("System Notification") {
                switchRow(
                    "Show completion notification",
                    detail: "Show notification when translation completes",
                    isOn: notificationEnabledBinding
                )

                if let message = model.screenTranslationNotificationMessage {
                    SettingsDivider()
                    HStack(alignment: .center, spacing: 12) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button("Open Settings") {
                            Task {
                                await model.openScreenTranslationNotificationSettings()
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, SettingsLayout.rowVerticalPadding)
                }
            }
        }
    }

    private var soundOptions: [String] {
        let soundNames = model.screenTranslationSoundNames
        guard !soundNames.isEmpty else {
            return [model.settings.screenTranslationSoundName]
        }

        return soundNames.contains(model.settings.screenTranslationSoundName)
            ? soundNames
            : [model.settings.screenTranslationSoundName] + soundNames
    }

    private var notificationEnabledBinding: Binding<Bool> {
        Binding {
            model.settings.screenTranslationNotificationsEnabled
        } set: { isEnabled in
            Task {
                await model.setScreenTranslationNotificationsEnabled(isEnabled)
            }
        }
    }

    private func switchRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        notificationRow(title, detail: detail) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }

    private func notificationRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: SettingsLayout.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .frame(width: SettingsLayout.controlWidth, alignment: .trailing)
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}
