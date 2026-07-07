import LinguistMacCore
import SwiftUI

struct AppleLanguagePackGroupSummaryView: View {
    let text: String
    let isChecking: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .tint(Color.secondary)
                    .frame(width: 12, height: 12)
            }

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 78, alignment: .trailing)
    }
}

struct AppleLanguagePackStatusGlyph: View {
    let systemName: String
    let tint: Color
    let isAnimating: Bool
    let isChecking: Bool

    var body: some View {
        Group {
            if isAnimating {
                RotatingAppleLanguagePackStatusGlyph(systemName: systemName)
            } else if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .tint(tint)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: systemName)
                    .id(systemName)
            }
        }
        .foregroundStyle(tint)
        .frame(width: 20)
    }
}

private struct RotatingAppleLanguagePackStatusGlyph: View {
    let systemName: String
    @State private var isRotating = false

    var body: some View {
        Image(systemName: systemName)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                isRotating = true
            }
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: isRotating)
    }
}

extension AppleLanguagePackSelection {
    var isChecking: Bool {
        readiness == .unknown && !isPreparing
    }
}

extension AppleLanguagePackReadinessRow {
    var isChecking: Bool {
        readiness == .unknown && !isPreparing
    }
}
