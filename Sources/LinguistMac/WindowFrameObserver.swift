import AppKit
import SwiftUI

struct WindowFrameObserver: NSViewRepresentable {
    let automaticResizeRequest: PopupWindowAutomaticResizeRequest?
    let automaticResizeEnabled: Bool
    let savedFrame: CGRect?
    let onFrameChange: (CGRect) -> Void
    let onManualResize: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowFrameObserverView()
        view.automaticResizeRequest = automaticResizeRequest
        view.automaticResizeEnabled = automaticResizeEnabled
        view.savedFrame = savedFrame
        view.onFrameChange = onFrameChange
        view.onManualResize = onManualResize
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowFrameObserverView else {
            return
        }

        view.automaticResizeRequest = automaticResizeRequest
        view.automaticResizeEnabled = automaticResizeEnabled
        view.savedFrame = savedFrame
        view.onFrameChange = onFrameChange
        view.onManualResize = onManualResize
        view.applySavedFrameIfNeeded()
        view.applyAutomaticResizeIfNeeded()
    }
}

struct PopupWindowAutomaticResizeRequest: Equatable {
    let revision: String
    let preferredContentHeight: CGFloat
    let minimumContentHeight: CGFloat
}

enum PopupWindowSizingPolicy {
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 720
    static let minimumFrameHeight: CGFloat = 240
    static let maximumFrameHeight: CGFloat = 640

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
}

private final class WindowFrameObserverView: NSView {
    var automaticResizeRequest: PopupWindowAutomaticResizeRequest?
    var automaticResizeEnabled = true
    var savedFrame: CGRect?
    var onFrameChange: ((CGRect) -> Void)?
    var onManualResize: (() -> Void)?

    private weak var observedWindow: NSWindow?
    private var didApplySavedFrame = false
    private var appliedAutomaticResizeRevision: String?
    private var didObserveManualResize = false
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        applySavedFrameIfNeeded()
        applyAutomaticResizeIfNeeded()
        publishFrame()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        guard newWindow !== observedWindow else {
            return
        }

        resetObservedWindow()
    }

    func applySavedFrameIfNeeded() {
        guard !didApplySavedFrame,
              let savedFrame,
              let window
        else {
            return
        }

        window.setFrame(clamped(savedFrame, for: window), display: true)
        didApplySavedFrame = true
    }

    func applyAutomaticResizeIfNeeded() {
        guard let request = automaticResizeRequest,
              let window,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else {
            return
        }

        configureSizeLimits(for: window, request: request, visibleFrame: visibleFrame)
        guard automaticResizeEnabled,
              !didObserveManualResize,
              request.revision != appliedAutomaticResizeRevision
        else {
            return
        }

        let preferredFrameHeight = frameHeight(
            forContentHeight: request.preferredContentHeight,
            window: window
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

        appliedAutomaticResizeRevision = request.revision
        guard frame != window.frame else {
            return
        }
        window.setFrame(frame, display: true)
    }

    private func observe(_ window: NSWindow?) {
        guard observedWindow !== window else {
            return
        }

        resetObservedWindow()
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
                self?.clampWindowToVisibleFrameIfNeeded()
                self?.publishFrame()
            }
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.publishFrame()
            }
        }

        liveResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.observeManualResizeIfNeeded()
            }
        }
    }

    private func resetObservedWindow() {
        stopObserving()
        observedWindow = nil
        didApplySavedFrame = false
        appliedAutomaticResizeRevision = nil
        didObserveManualResize = false
    }

    private func stopObserving() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        if let liveResizeObserver {
            NotificationCenter.default.removeObserver(liveResizeObserver)
        }
        moveObserver = nil
        resizeObserver = nil
        liveResizeObserver = nil
    }

    private func publishFrame() {
        guard let window else {
            return
        }

        onFrameChange?(window.frame)
    }

    private func observeManualResizeIfNeeded() {
        guard !didObserveManualResize else {
            return
        }
        didObserveManualResize = true
        onManualResize?()
    }

    private func clampWindowToVisibleFrameIfNeeded() {
        guard let window,
              let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        else {
            return
        }

        if let automaticResizeRequest {
            configureSizeLimits(
                for: window,
                request: automaticResizeRequest,
                visibleFrame: visibleFrame
            )
        }
        let minimumHeight = automaticResizeRequest.map {
            frameHeight(forContentHeight: $0.minimumContentHeight, window: window)
        } ?? PopupWindowSizingPolicy.minimumFrameHeight
        let frame = PopupWindowSizingPolicy.clampedFrame(
            window.frame,
            visibleFrame: visibleFrame,
            minimumHeight: minimumHeight
        )
        guard frame != window.frame else {
            return
        }
        window.setFrame(frame, display: true)
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

private extension CGRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }
        return width * height
    }
}
