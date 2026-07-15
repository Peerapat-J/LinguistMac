import AppKit
import LinguistMacCore
import SwiftUI

struct WindowFrameObserver: NSViewRepresentable {
    let controller: PopupWindowFrameController
    let automaticResizeRequest: PopupWindowAutomaticResizeRequest?
    let automaticResizeEnabled: Bool
    let savedFrame: CGRect?
    let onFrameChange: (CGRect) -> Void
    let onManualResize: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowFrameObserverView()
        view.controller = controller
        update(controller)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowFrameObserverView else {
            return
        }

        view.controller = controller
        update(controller)
        view.attachControllerToCurrentWindow()
    }

    private func update(_ controller: PopupWindowFrameController) {
        controller.update(
            automaticResizeRequest: automaticResizeRequest,
            automaticResizeEnabled: automaticResizeEnabled,
            savedFrame: savedFrame,
            onFrameChange: onFrameChange,
            onManualResize: onManualResize
        )
    }
}

struct PopupWindowAutomaticResizeRequest: Equatable {
    let revision: PopupWindowContentRevision
    let preferredContentHeight: CGFloat
    let minimumContentHeight: CGFloat
}

struct PopupWindowContentRevision: Equatable {
    let resultID: UUID
    let showsOriginal: Bool
    let wordTranslations: [WordTranslation]
    let wordCard: TranslationPopupWordCardState?
}

enum PopupWindowSizingPolicy {
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 720
    static let minimumFrameHeight: CGFloat = 240
    static let maximumFrameHeight: CGFloat = 640
    static let automaticFrameComparisonTolerance: CGFloat = 1

    static func frame(
        bySettingHeight preferredHeight: CGFloat,
        from currentFrame: CGRect,
        visibleFrame: CGRect,
        minimumHeight: CGFloat = minimumFrameHeight
    ) -> CGRect {
        var frame = currentFrame
        frame.size.height = preferredHeight
        frame.origin.y = currentFrame.maxY - preferredHeight
        return clampedFrame(frame, visibleFrame: visibleFrame, minimumHeight: minimumHeight)
    }

    static func clampedFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        minimumHeight: CGFloat = minimumFrameHeight
    ) -> CGRect {
        let maximumWidth = min(Self.maximumWidth, visibleFrame.width)
        let maximumHeight = min(maximumFrameHeight, visibleFrame.height)
        let minimumWidth = min(Self.minimumWidth, maximumWidth)
        let minimumHeight = min(minimumHeight, maximumHeight)
        let width = min(max(frame.width, minimumWidth), maximumWidth)
        let height = min(max(frame.height, minimumHeight), maximumHeight)
        let originX = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        let originY = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= automaticFrameComparisonTolerance
            && abs(lhs.minY - rhs.minY) <= automaticFrameComparisonTolerance
            && abs(lhs.width - rhs.width) <= automaticFrameComparisonTolerance
            && abs(lhs.height - rhs.height) <= automaticFrameComparisonTolerance
    }

    static func preservesHeightWhenShowingOriginal(
        from previousRevision: PopupWindowContentRevision?,
        to nextRevision: PopupWindowContentRevision
    ) -> Bool {
        guard let previousRevision else {
            return false
        }

        return previousRevision.resultID == nextRevision.resultID
            && !previousRevision.showsOriginal
            && nextRevision.showsOriginal
    }

    static func preferredFrameHeight(
        measuredFrameHeight: CGFloat,
        currentFrameHeight: CGFloat,
        expandedContentHeightIncrement: CGFloat,
        isShowingOriginal: Bool
    ) -> CGFloat {
        guard isShowingOriginal else {
            return measuredFrameHeight
        }
        return max(
            measuredFrameHeight,
            currentFrameHeight + expandedContentHeightIncrement
        )
    }
}

@MainActor
final class PopupWindowFrameController: ObservableObject {
    private weak var window: NSWindow?
    private var automaticResizeRequest: PopupWindowAutomaticResizeRequest?
    private var automaticResizeEnabled = true
    private var savedFrame: CGRect?
    private var onFrameChange: ((CGRect) -> Void)?
    private var onManualResize: (() -> Void)?
    private var didApplySavedFrame = false
    private var appliedAutomaticResizeRevision: PopupWindowContentRevision?
    private var didObserveManualResize = false
    private var lastAutomaticFrame: CGRect?

    func update(
        automaticResizeRequest: PopupWindowAutomaticResizeRequest?,
        automaticResizeEnabled: Bool,
        savedFrame: CGRect?,
        onFrameChange: @escaping (CGRect) -> Void,
        onManualResize: @escaping () -> Void
    ) {
        self.automaticResizeRequest = automaticResizeRequest
        self.automaticResizeEnabled = automaticResizeEnabled
        self.savedFrame = savedFrame
        self.onFrameChange = onFrameChange
        self.onManualResize = onManualResize
        applySavedFrameIfNeeded()
        applyAutomaticResizeIfNeeded()
    }

    func attach(to window: NSWindow?) {
        guard let window else {
            return
        }

        if self.window !== window {
            self.window = window
            didApplySavedFrame = false
            appliedAutomaticResizeRevision = nil
            didObserveManualResize = false
            lastAutomaticFrame = nil
        }
        applySavedFrameIfNeeded()
        applyAutomaticResizeIfNeeded()
        publishFrame(window.frame)
    }

    func windowDidMove(_ window: NSWindow) {
        guard self.window === window else {
            return
        }
        publishFrame(window.frame)
    }

    func windowDidResize(_ window: NSWindow) {
        guard self.window === window,
              didObserveManualResize || window.inLiveResize
        else {
            return
        }
        publishFrame(window.frame)
    }

    func windowWillStartLiveResize(_ window: NSWindow) {
        guard self.window === window,
              !didObserveManualResize
        else {
            return
        }
        didObserveManualResize = true
        onManualResize?()
    }

    private func applySavedFrameIfNeeded() {
        guard !didApplySavedFrame,
              let savedFrame,
              let window
        else {
            return
        }

        let frame = clamped(savedFrame, for: window)
        didApplySavedFrame = true
        lastAutomaticFrame = frame
        guard !PopupWindowSizingPolicy.framesMatch(frame, window.frame) else {
            return
        }
        window.setFrame(frame, display: true)
    }

    private func applyAutomaticResizeIfNeeded() {
        guard let request = automaticResizeRequest,
              let window,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else {
            return
        }

        configureSizeLimits(for: window, request: request, visibleFrame: visibleFrame)
        guard request.revision != appliedAutomaticResizeRevision else {
            return
        }

        let previousRevision = appliedAutomaticResizeRevision
        appliedAutomaticResizeRevision = request.revision
        let isShowingOriginal = PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
            from: previousRevision,
            to: request.revision
        )
        guard (automaticResizeEnabled && !didObserveManualResize) || isShowingOriginal else {
            return
        }

        let measuredFrameHeight = frameHeight(
            forContentHeight: request.preferredContentHeight,
            window: window
        )
        let preferredFrameHeight = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: measuredFrameHeight,
            currentFrameHeight: window.frame.height,
            expandedContentHeightIncrement: PopupTextPanelLayout.expandedContentHeightIncrement,
            isShowingOriginal: isShowingOriginal
        )
        let minimumFrameHeight = frameHeight(
            forContentHeight: request.minimumContentHeight,
            window: window
        )
        let frame = PopupWindowSizingPolicy.frame(
            bySettingHeight: preferredFrameHeight,
            from: window.frame,
            visibleFrame: visibleFrame,
            minimumHeight: minimumFrameHeight
        )

        lastAutomaticFrame = frame
        guard !PopupWindowSizingPolicy.framesMatch(frame, window.frame) else {
            return
        }
        window.setFrame(frame, display: true)
    }

    private func publishFrame(_ frame: CGRect) {
        if let lastAutomaticFrame {
            guard !PopupWindowSizingPolicy.framesMatch(frame, lastAutomaticFrame) else {
                return
            }
        }
        lastAutomaticFrame = nil
        onFrameChange?(frame)
    }

    private func configureSizeLimits(
        for window: NSWindow,
        request: PopupWindowAutomaticResizeRequest,
        visibleFrame: CGRect
    ) {
        let minimumHeight = frameHeight(
            forContentHeight: request.minimumContentHeight,
            window: window
        )
        window.minSize = NSSize(
            width: min(PopupWindowSizingPolicy.minimumWidth, visibleFrame.width),
            height: min(minimumHeight, visibleFrame.height)
        )
        window.maxSize = NSSize(
            width: min(PopupWindowSizingPolicy.maximumWidth, visibleFrame.width),
            height: min(PopupWindowSizingPolicy.maximumFrameHeight, visibleFrame.height)
        )
    }

    private func frameHeight(forContentHeight contentHeight: CGFloat, window: NSWindow) -> CGFloat {
        let contentRect = CGRect(
            x: 0,
            y: 0,
            width: window.contentLayoutRect.width,
            height: contentHeight
        )
        return window.frameRect(forContentRect: contentRect).height
    }

    private func clamped(_ frame: CGRect, for window: NSWindow) -> CGRect {
        guard let screenFrame = visibleFrame(containing: frame)
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        else {
            return frame
        }

        return PopupWindowSizingPolicy.clampedFrame(frame, visibleFrame: screenFrame)
    }

    private func visibleFrame(containing frame: CGRect) -> CGRect? {
        NSScreen.screens
            .map { screen in
                (frame: screen.visibleFrame, area: screen.visibleFrame.intersection(frame).area)
            }
            .filter { $0.area > 0 }
            .max { $0.area < $1.area }?
            .frame
    }
}

private final class WindowFrameObserverView: NSView {
    weak var controller: PopupWindowFrameController?

    private weak var observedWindow: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        attachControllerToCurrentWindow()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        guard newWindow !== observedWindow else {
            return
        }
        stopObserving()
        observedWindow = nil
    }

    func attachControllerToCurrentWindow() {
        controller?.attach(to: window)
    }

    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }
        stopObserving()
        observedWindow = window

        guard let window else {
            return
        }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowDidMove(window)
            }
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowDidResize(window)
            }
        }
        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.controller?.windowWillStartLiveResize(window)
            }
        }
    }

    private func stopObserving() {
        for observer in [moveObserver, resizeObserver, liveResizeObserver].compactMap(\.self) {
            NotificationCenter.default.removeObserver(observer)
        }
        moveObserver = nil
        resizeObserver = nil
        liveResizeObserver = nil
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }
        return width * height
    }
}
