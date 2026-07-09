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

        let selection = try await requestRegionSelection()
        guard selection.rect.width >= 4, selection.rect.height >= 4 else {
            throw TranslationFailure.captureCancelled
        }

        // Give the selection overlay a frame to leave the WindowServer before capturing underlying content.
        try await Task.sleep(for: Self.overlayDismissalDelay)

        let captureRect = try await displaySpaceRect(for: selection)
        let image = try await captureImage(in: captureRect)
        let imageData = try pngData(from: image)
        return CapturedScreenRegion(
            imageData: imageData,
            scale: Double(image.width) / max(captureRect.width, 1)
        )
    }

    private func displaySpaceRect(for selection: ScreenSelection) async throws -> CGRect {
        guard let displayFrame = await displayFrame(for: selection.displayID) else {
            throw TranslationFailure.providerFailed("Could not resolve selected display bounds.")
        }

        return ScreenCaptureDisplaySpaceRectMapper.displaySpaceRect(
            appKitRect: selection.rect,
            appKitScreenFrame: selection.screenFrame,
            displayFrame: displayFrame
        )
    }

    private func displayFrame(for displayID: CGDirectDisplayID?) async -> CGRect? {
        guard let displayID else {
            return nil
        }

        do {
            let shareableContent = try await SCShareableContent.current
            if let displayFrame = shareableContent.displays.first(where: { $0.displayID == displayID })?.frame {
                return displayFrame
            }
        } catch {
            // Fall back to CoreGraphics bounds below. AppKit NSScreen frames are not display-space rects.
        }

        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.width > 0, displayBounds.height > 0 else {
            return nil
        }

        return displayBounds
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
private func requestRegionSelection() async throws -> ScreenSelection {
    try await RegionSelectionOverlayController.shared.selectRegion()
}

struct ScreenSelection: Equatable {
    let rect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID?
}

enum ScreenCaptureDisplaySpaceRectMapper {
    static func displaySpaceRect(
        appKitRect: CGRect,
        appKitScreenFrame: CGRect,
        displayFrame: CGRect
    ) -> CGRect {
        guard appKitScreenFrame.width > 0, appKitScreenFrame.height > 0 else {
            return appKitRect
        }

        let xScale = displayFrame.width / appKitScreenFrame.width
        let yScale = displayFrame.height / appKitScreenFrame.height
        return CGRect(
            x: displayFrame.minX + ((appKitRect.minX - appKitScreenFrame.minX) * xScale),
            y: displayFrame.minY + ((appKitScreenFrame.maxY - appKitRect.maxY) * yScale),
            width: appKitRect.width * xScale,
            height: appKitRect.height * yScale
        )
    }
}

@MainActor
private final class RegionSelectionOverlayController {
    static let shared = RegionSelectionOverlayController()

    private var continuation: CheckedContinuation<ScreenSelection, Error>?
    private var windows: [RegionSelectionOverlayWindow] = []

    func selectRegion() async throws -> ScreenSelection {
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
            let window = RegionSelectionOverlayWindow(screen: screen)
            let view = RegionSelectionOverlayView(
                screenFrame: screen.frame,
                displayID: screen.displayID,
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
            window.orderFrontRegardless()
            window.makeKey()
            window.makeFirstResponder(view)
            return window
        }
    }

    private func complete(with selection: ScreenSelection) {
        let continuation = finishOverlay()
        continuation?.resume(returning: selection)
    }

    private func cancel() {
        let continuation = finishOverlay()
        continuation?.resume(throwing: TranslationFailure.captureCancelled)
    }

    private func finishOverlay() -> CheckedContinuation<ScreenSelection, Error>? {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

private final class RegionSelectionOverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class RegionSelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let displayID: CGDirectDisplayID?
    private let onComplete: (ScreenSelection) -> Void
    private let onCancel: () -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(
        screenFrame: CGRect,
        displayID: CGDirectDisplayID?,
        onComplete: @escaping (ScreenSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screenFrame = screenFrame
        self.displayID = displayID
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
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

        onComplete(ScreenSelection(rect: selection, screenFrame: screenFrame, displayID: displayID))
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

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
