import LinguistMacCore
import SwiftUI

struct ContentView: View {
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
                Label("Recent translations stay in memory until history persistence lands.", systemImage: "clock")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.translatedText)
                        Text(result.originalText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
    }
}
