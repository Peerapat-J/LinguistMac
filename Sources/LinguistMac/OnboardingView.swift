import LinguistMacCore
import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppShellModel
    @State private var readinessRefreshTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LinguistMac Setup")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Check the pieces needed before screen translation starts.")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(model.readiness.items) { item in
                        SetupStatusCard(item: item) {
                            handleReadinessAction(for: item)
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
                    openLinguistSettings(model: model, using: openSettings)
                    readinessRefreshTrigger += 1
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
        .readinessRefreshMonitor(model: model, trigger: readinessRefreshTrigger)
    }

    private func handleReadinessAction(for item: OnboardingReadinessItem) {
        switch item.kind {
        case .screenTranslation:
            model.openSystemSettings(for: .screenRecording)
        case .accessibility:
            model.openSystemSettings(for: .accessibility)
        case .voiceMicrophone:
            model.openSystemSettings(for: .microphone)
        case .speechRecognition:
            model.openSystemSettings(for: .speechRecognition)
        case .appleTranslation, .cloudProvider:
            openLinguistSettings(model: model, using: openSettings)
        }

        readinessRefreshTrigger += 1
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
                    Text(item.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.tint)
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
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func readinessRefreshMonitor(model: AppShellModel, trigger: Int) -> some View {
        modifier(ReadinessRefreshMonitor(model: model, trigger: trigger))
    }
}

private struct ReadinessRefreshMonitor: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let model: AppShellModel
    let trigger: Int
    @State private var monitorTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .task {
                startMonitoring()
            }
            .onChange(of: trigger) { _, _ in
                startMonitoring()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else {
                    return
                }
                startMonitoring()
            }
            .onDisappear {
                monitorTask?.cancel()
                monitorTask = nil
            }
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [model] in
            await refreshUntilTimeout(model: model)
        }
    }

    private func refreshUntilTimeout(model: AppShellModel) async {
        for attempt in 0 ... ReadinessRefreshSchedule.maxRefreshAttempts {
            guard !Task.isCancelled else {
                return
            }

            await model.refreshReadiness()

            guard attempt < ReadinessRefreshSchedule.maxRefreshAttempts else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: ReadinessRefreshSchedule.intervalNanoseconds)
            } catch {
                return
            }
        }
    }
}

private enum ReadinessRefreshSchedule {
    static let intervalNanoseconds: UInt64 = 2_000_000_000
    static let maxRefreshAttempts = 45
}
