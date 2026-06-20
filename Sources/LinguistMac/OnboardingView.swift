import AppKit
import LinguistMacCore
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppShellModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LinguistMac Setup")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Check the pieces needed before screen translation starts.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.readiness.items) { item in
                        SetupStatusCard(item: item) {
                            switch item.kind {
                            case .screenTranslation:
                                model.openSystemSettings(for: .screenRecording)
                            case .accessibility:
                                model.openSystemSettings(for: .accessibility)
                            case .voiceMicrophone:
                                model.openSystemSettings(for: .microphone)
                            case .speechRecognition:
                                model.openSystemSettings(for: .speechRecognition)
                            case .appleTranslation:
                                openSettingsWindow()
                            case .cloudProvider:
                                openSettingsWindow()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Text(
                "Default translation stays on-device. "
                    + "Cloud providers are optional and only run after you select and configure them."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button("Open Settings") {
                    openSettingsWindow()
                }

                Spacer()

                Button("Skip for Now") {
                    model.markOnboardingComplete()
                    dismiss()
                }

                Button("Done") {
                    model.markOnboardingComplete()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .task {
            await model.refreshReadiness()
        }
    }

    private func openSettingsWindow() {
        model.record(.settings)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SetupStatusCard: View {
    let item: OnboardingReadinessItem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.tint)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                    if item.isRequiredForDefaultWorkflow {
                        Text("Required")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.showsRecoveryAction {
                Button("Open") {
                    action()
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
