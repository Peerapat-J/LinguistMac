import AppKit
import SwiftUI

struct WindowFrameObserver: NSViewRepresentable {
    let savedFrame: CGRect?
    let onFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowFrameObserverView()
        view.savedFrame = savedFrame
        view.onFrameChange = onFrameChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowFrameObserverView else {
            return
        }

        view.savedFrame = savedFrame
        view.onFrameChange = onFrameChange
        view.applySavedFrameIfNeeded()
    }
}

private final class WindowFrameObserverView: NSView {
    var savedFrame: CGRect?
    var onFrameChange: ((CGRect) -> Void)?

    private weak var observedWindow: NSWindow?
    private var didApplySavedFrame = false
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe(window)
        applySavedFrameIfNeeded()
        publishFrame()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopObserving()
        }
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
    }

    private func stopObserving() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        moveObserver = nil
        resizeObserver = nil
    }

    private func publishFrame() {
        guard let window else {
            return
        }

        onFrameChange?(window.frame)
    }

    private func clamped(_ frame: CGRect, for window: NSWindow) -> CGRect {
        guard let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return frame
        }

        let width = min(max(frame.width, 320), min(720, screenFrame.width))
        let height = min(max(frame.height, 240), min(640, screenFrame.height))
        let originX = min(max(frame.origin.x, screenFrame.minX), screenFrame.maxX - width)
        let originY = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - height)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}
