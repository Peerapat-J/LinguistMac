import AppKit
import KeyboardShortcuts
import LinguistMacCore
import SwiftUI

enum SettingsSectionID: String, CaseIterable, Identifiable, Hashable {
    case general
    case translation
    case appearance
    case notification
    case api
    case setup
    case privacy

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            "General"
        case .translation:
            "Translation"
        case .appearance:
            "Appearance"
        case .notification:
            "Notification"
        case .api:
            "API"
        case .setup:
            "Setup"
        case .privacy:
            "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .translation:
            "character.bubble"
        case .appearance:
            "paintbrush"
        case .notification:
            "bell"
        case .api:
            "key"
        case .setup:
            "checklist"
        case .privacy:
            "hand.raised"
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let searchText: String
    let content: Content

    init(_ title: String, searchText: String = "", @ViewBuilder content: () -> Content) {
        self.title = title
        self.searchText = searchText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardTitleSpacing) {
            SettingsSearchHighlightedText(title, searchText: searchText)
                .font(.headline)
                .padding(.leading, SettingsLayout.cardTitleInset)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, SettingsLayout.cardPadding)
            .padding(.vertical, SettingsLayout.cardVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
    }
}

struct SettingsDetailHeader: View {
    let title: String
    let canNavigateBack: Bool
    let canNavigateForward: Bool
    let navigateBack: () -> Void
    let navigateForward: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                headerButton(systemImage: "chevron.left", isEnabled: canNavigateBack, action: navigateBack)

                Divider()
                    .frame(height: 18)

                headerButton(systemImage: "chevron.right", isEnabled: canNavigateForward, action: navigateForward)
            }
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            }

            Text(title)
                .font(.headline)

            Spacer()
        }
        .padding(.leading, 18)
        .padding(.trailing, SettingsLayout.horizontalPadding)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
    }
}

enum SettingsLayout {
    static let contentWidth: CGFloat = 430, controlWidth: CGFloat = 150
    static let rowSpacing: CGFloat = 10, rowVerticalPadding: CGFloat = 7
    static let sectionSpacing: CGFloat = 20
    static let cardPadding: CGFloat = 14, cardVerticalPadding: CGFloat = 6
    static let cardCornerRadius: CGFloat = 14, cardTitleSpacing: CGFloat = 8, cardTitleInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 24, topPadding: CGFloat = 18, bottomPadding: CGFloat = 24
}

struct ProviderConfigurationRow: View {
    @ObservedObject var model: AppShellModel
    let provider: TranslationProviderDescriptor
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsSearchHighlightedText(provider.displayName, searchText: searchText)
                    SettingsSearchHighlightedText(provider.detail, searchText: searchText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                Label(provider.configurationStatus.displayText, systemImage: provider.statusImage)
                    .font(.caption)
                    .foregroundStyle(provider.statusTint)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                SecureField("API key", text: apiKeyDraftBinding)

                if provider.id == .microsoftAzure {
                    TextField("Region", text: apiRegionDraftBinding)
                }
            }

            HStack(spacing: 8) {
                Button("Save") {
                    Task {
                        await model.saveAPIKey(for: provider.id)
                    }
                }

                Button("Test") {
                    Task {
                        await model.testAPIKeyConfiguration(for: provider.id)
                    }
                }

                Button("Clear", role: .destructive) {
                    Task {
                        await model.clearAPIKey(for: provider.id)
                    }
                }

                Spacer()
            }
            .controlSize(.small)

            if let message = model.providerConfigurationMessages[provider.id] {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var apiKeyDraftBinding: Binding<String> {
        Binding {
            model.providerAPIKeyDrafts[provider.id, default: ""]
        } set: { value in
            model.providerAPIKeyDrafts[provider.id] = value
        }
    }

    private var apiRegionDraftBinding: Binding<String> {
        Binding {
            model.providerAPIRegionDrafts[provider.id, default: ""]
        } set: { value in
            model.providerAPIRegionDrafts[provider.id] = value
        }
    }
}

struct ShortcutRow: View {
    let title: String
    let searchText: String
    @Binding var shortcut: LinguistMacCore.KeyboardShortcut
    let defaultShortcut: LinguistMacCore.KeyboardShortcut
    let result: ShortcutRegistrationResult?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SettingsSearchHighlightedText(title, searchText: searchText)
                Spacer()
                KeyboardShortcuts.Recorder(shortcut: keyboardShortcutBinding)
                    .shortcutValidation { keyboardShortcut in
                        guard LinguistMacCore.KeyboardShortcut(keyboardShortcut) != nil else {
                            return .disallow(reason: "This key is not supported yet.")
                        }
                        return .allow
                    }
                    .fixedSize(horizontal: true, vertical: false)
            }

            if let result, result.issue != nil {
                HStack(spacing: 6) {
                    Image(systemName: result.isRegistered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.isRegistered ? .green : .orange)
                    Text(result.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }

    private var keyboardShortcutBinding: Binding<KeyboardShortcuts.Shortcut?> {
        Binding {
            shortcut.keyboardShortcutsShortcut
        } set: { newValue in
            guard let newValue else {
                shortcut = defaultShortcut
                onChange()
                return
            }

            if let appShortcut = LinguistMacCore.KeyboardShortcut(newValue) {
                shortcut = appShortcut
            } else {
                shortcut = defaultShortcut
            }
            onChange()
        }
    }
}

struct ReadinessRow: View {
    let item: OnboardingReadinessItem
    let searchText: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SettingsSearchHighlightedText(item.title, searchText: searchText)
                    SettingsSearchHighlightedText(item.statusText, searchText: searchText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.tint)
                }
                SettingsSearchHighlightedText(item.detail, searchText: searchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if item.showsRecoveryAction {
                Button("Open") {
                    action()
                }
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

extension TranslationProviderDescriptor {
    var pickerTitle: String {
        isConfigured || !requiresAPIKey
            ? displayName
            : "\(displayName) - API key required"
    }

    var statusImage: String {
        switch configurationStatus {
        case .ready:
            "checkmark.circle.fill"
        case .needsAPIKey:
            "key.fill"
        case .unavailable:
            "exclamationmark.triangle.fill"
        }
    }

    var statusTint: Color {
        switch configurationStatus {
        case .ready:
            .green
        case .needsAPIKey:
            .orange
        case .unavailable:
            .red
        }
    }
}

extension ShortcutAction {
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

extension ShortcutRegistrationResult {
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

struct SidebarTrafficLights: View {
    @State private var isHovering = false
    private let buttonHitSize: CGFloat = 18
    private let trafficLightSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 8) {
            trafficLight(
                .red,
                symbolName: "xmark",
                accessibilityLabel: "Close",
                isEnabled: true
            ) {
                NSApp.keyWindow?.close()
            }

            trafficLight(
                .yellow,
                symbolName: "minus",
                accessibilityLabel: "Minimize",
                isEnabled: false
            ) {}

            trafficLight(
                .green,
                symbolName: "plus",
                accessibilityLabel: "Zoom",
                isEnabled: false
            ) {}
        }
        .onHover { isHovering = $0 }
    }

    private func trafficLight(
        _ color: Color,
        symbolName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isEnabled ? color : disabledTrafficLightColor)
                    .frame(width: trafficLightSize, height: trafficLightSize)

                Image(systemName: symbolName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black.opacity(isEnabled ? 0.58 : 0.28))
                    .opacity(isHovering ? 1 : 0)
            }
            .frame(width: buttonHitSize, height: buttonHitSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var disabledTrafficLightColor: Color {
        Color(nsColor: .tertiaryLabelColor)
    }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowConfiguratorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SettingsWindowConfiguratorView else {
            return
        }

        view.configureWindowIfNeeded()
    }
}

struct SidebarTranslucentBackground: View {
    var body: some View {
        SidebarVisualEffectBackground()
            .overlay(Color.black.opacity(0.16))
            .overlay(Color.white.opacity(0.06))
    }
}

private struct SidebarVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
    }
}

private final class SettingsWindowConfiguratorView: NSView {
    private weak var configuredWindow: NSWindow?
    private var cursorTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindowIfNeeded()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        resetStaleTextCursorIfNeeded(for: event)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resetStaleTextCursorIfNeeded(for: event)
        super.mouseExited(with: event)
    }

    func configureWindowIfNeeded() {
        guard let window else {
            return
        }

        if configuredWindow !== window {
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.remove(.titled)
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            configuredWindow = window
        }

        window.title = ""
        window.toolbar = nil
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        hideStandardWindowButtons(in: window)

        DispatchQueue.main.async { [weak self, weak window] in
            window?.toolbar = nil
            window?.isOpaque = false
            window?.backgroundColor = .clear
            window?.isMovableByWindowBackground = true
            window?.acceptsMouseMovedEvents = true
            if let window {
                self?.hideStandardWindowButtons(in: window)
            }
        }
    }

    private func resetStaleTextCursorIfNeeded(for event: NSEvent) {
        guard let contentView = window?.contentView else {
            return
        }

        guard !contentView.containsTextInput(atWindowPoint: event.locationInWindow) else {
            return
        }

        if NSCursor.current.isEqual(NSCursor.iBeam) {
            NSCursor.arrow.set()
        }
    }

    private func hideStandardWindowButtons(in window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ]
        .compactMap(\.self)

        for button in buttons {
            button.isHidden = true
        }
    }
}

private extension NSView {
    func containsTextInput(atWindowPoint point: NSPoint) -> Bool {
        let localPoint = convert(point, from: nil)
        guard bounds.contains(localPoint) else {
            return false
        }

        if self is NSTextField || self is NSTextView {
            return true
        }

        return subviews.contains { $0.containsTextInput(atWindowPoint: point) }
    }
}
