import LinguistMacCore
import SwiftUI

struct ContentView: View {
    private let features = AppFeature.starterFeatures

    var body: some View {
        NavigationSplitView {
            List(features) { feature in
                Label(feature.title, systemImage: feature.systemImage)
                    .tag(feature.id)
            }
            .navigationTitle("LinguistMac")
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                Text("LinguistMac")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text("Fresh macOS scaffold for a clean-room screen translation app.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features) { feature in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                Text(feature.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: feature.systemImage)
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
            .frame(minWidth: 420, minHeight: 300, alignment: .topLeading)
        }
    }
}
