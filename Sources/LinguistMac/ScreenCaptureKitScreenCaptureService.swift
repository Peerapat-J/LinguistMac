import AppKit
import CoreGraphics
import ImageIO
import LinguistMacCore
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenCaptureKitScreenCaptureService: ScreenCaptureServicing {
    private static let overlayDismissalDelay: Duration = .milliseconds(120)

    func captureSelection() async throws -> CapturedScreenRegion {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw TranslationFailure.permissionDenied(.screenRecording)
        }

        let rect = try await requestRegionSelection()
        guard rect.width >= 4, rect.height >= 4 else {
            throw TranslationFailure.captureCancelled
        }

        // Give the selection overlay a frame to leave the WindowServer before capturing underlying content.
        try await Task.sleep(for: Self.overlayDismissalDelay)

        let image = try await captureImage(in: rect)
        let imageData = try pngData(from: image)
        return CapturedScreenRegion(
            imageData: imageData,
            scale: Double(image.width) / max(rect.width, 1)
        )
    }

    private func captureImage(in rect: CGRect) async throws -> CGImage {
        guard #available(macOS 15.2, *) else {
            throw TranslationFailure.providerFailed("Selected-region capture requires macOS 15.2 or newer.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, error in
                if let error {
                    continuation.resume(throwing: TranslationFailure.providerFailed(error.localizedDescription))
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: TranslationFailure.providerFailed("Screen capture returned no image.")
                    )
                }
            }
        }
    }

    private func pngData(from image: CGImage) throws -> Data {
        guard let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  data,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else {
            throw TranslationFailure.providerFailed("Could not prepare captured image data.")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TranslationFailure.providerFailed("Could not encode captured image.")
        }

        return data as Data
    }
}

@MainActor
private func requestRegionSelection() async throws -> CGRect {
    try await RegionSelectionOverlayController.shared.selectRegion()
}

@MainActor
private final class RegionSelectionOverlayController {
    static let shared = RegionSelectionOverlayController()

    private var continuation: CheckedContinuation<CGRect, Error>?
    private var windows: [NSWindow] = []

    func selectRegion() async throws -> CGRect {
        guard continuation == nil else {
            throw TranslationFailure.providerFailed("A screen selection is already active.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            showOverlayWindows()
        }
    }

    private func showOverlayWindows() {
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            let view = RegionSelectionOverlayView(
                screenFrame: screen.frame,
                onComplete: { [weak self] rect in
                    self?.complete(with: rect)
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )

            window.contentView = view
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            return window
        }
    }

    private func complete(with rect: CGRect) {
        let continuation = finishOverlay()
        continuation?.resume(returning: rect)
    }

    private func cancel() {
        let continuation = finishOverlay()
        continuation?.resume(throwing: TranslationFailure.captureCancelled)
    }

    private func finishOverlay() -> CheckedContinuation<CGRect, Error>? {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

private final class RegionSelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(
        screenFrame: CGRect,
        onComplete: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        _ = event
        onCancel()
    }

    override func mouseDown(with event: NSEvent) {
        let point = screenPoint(from: event)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = screenPoint(from: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = screenPoint(from: event)
        guard let selection = selectionRect, selection.width >= 4, selection.height >= 4 else {
            onCancel()
            return
        }

        onComplete(selection)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let selection = selectionRect else {
            return
        }

        let localSelection = localRect(fromScreenRect: selection)
        NSColor.clear.setFill()
        localSelection.fill(using: .clear)

        let path = NSBezierPath(rect: localSelection)
        path.lineWidth = 2
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.14).setFill()
        localSelection.fill()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func screenPoint(from event: NSEvent) -> CGPoint {
        guard let window else {
            return event.locationInWindow
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func localRect(fromScreenRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - screenFrame.minX,
            y: rect.minY - screenFrame.minY,
            width: rect.width,
            height: rect.height
        )
    }
}
