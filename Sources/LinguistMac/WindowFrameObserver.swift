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
    let preferredFrameWidth: CGFloat?

    init(
        revision: PopupWindowContentRevision,
        preferredContentHeight: CGFloat,
        minimumContentHeight: CGFloat,
        preferredFrameWidth: CGFloat? = nil
    ) {
        self.revision = revision
        self.preferredContentHeight = preferredContentHeight
        self.minimumContentHeight = minimumContentHeight
        self.preferredFrameWidth = preferredFrameWidth
    }
}

enum PopupWindowContentRevision: Equatable {
    case success(
        resultID: UUID,
        showsOriginal: Bool,
        wordTranslations: [WordTranslation],
        wordCard: TranslationPopupWordCardState?
    )
    case failure(TranslationFailure, originalText: String?)

    init(
        resultID: UUID,
        showsOriginal: Bool,
        wordTranslations: [WordTranslation],
        wordCard: TranslationPopupWordCardState?
    ) {
        self = .success(
            resultID: resultID,
            showsOriginal: showsOriginal,
            wordTranslations: wordTranslations,
            wordCard: wordCard
        )
    }

    var isSuccess: Bool {
        guard case .success = self else {
            return false
        }
        return true
    }
}

enum PopupWindowSizingPolicy {
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 720
    static let compactCaptureCancelledWidth: CGFloat = 480
    static let minimumFrameHeight: CGFloat = 240
    static let maximumFrameHeight: CGFloat = 640
    static let automaticFrameComparisonTolerance: CGFloat = 1

    static func frame(
        bySettingHeight preferredHeight: CGFloat,
        from currentFrame: CGRect,
        visibleFrame: CGRect,
        minimumHeight: CGFloat = minimumFrameHeight,
        preferredWidth: CGFloat? = nil
    ) -> CGRect {
        let size = clampedSize(
            width: preferredWidth ?? currentFrame.width,
            height: preferredHeight,
            visibleFrame: visibleFrame,
            minimumHeight: minimumHeight
        )
        var frame = CGRect(origin: currentFrame.origin, size: size)
        if preferredWidth != nil {
            frame.origin.x = currentFrame.midX - (size.width / 2)
        }
        frame.origin.y = currentFrame.maxY - size.height
        return clampedFrame(frame, visibleFrame: visibleFrame, minimumHeight: minimumHeight)
    }

    static func clampedFrame(
        _ frame: CGRect,
        visibleFrame: CGRect,
        minimumHeight: CGFloat = minimumFrameHeight
    ) -> CGRect {
        let size = clampedSize(
            width: frame.width,
            height: frame.height,
            visibleFrame: visibleFrame,
            minimumHeight: minimumHeight
        )
        let width = size.width
        let height = size.height
        let originX = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - width)
        let originY = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private static func clampedSize(
        width: CGFloat,
        height: CGFloat,
        visibleFrame: CGRect,
        minimumHeight: CGFloat
    ) -> CGSize {
        let maximumWidth = min(Self.maximumWidth, visibleFrame.width)
        let maximumHeight = min(maximumFrameHeight, visibleFrame.height)
        let minimumWidth = min(Self.minimumWidth, maximumWidth)
        let minimumHeight = min(minimumHeight, maximumHeight)
        let width = min(max(width, minimumWidth), maximumWidth)
        let height = min(max(height, minimumHeight), maximumHeight)
        return CGSize(width: width, height: height)
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= automaticFrameComparisonTolerance
            && abs(lhs.minY - rhs.minY) <= automaticFrameComparisonTolerance
            && abs(lhs.width - rhs.width) <= automaticFrameComparisonTolerance
            && abs(lhs.height - rhs.height) <= automaticFrameComparisonTolerance
    }

    static func preferredFrameWidth(for revision: PopupWindowContentRevision) -> CGFloat? {
        guard case .failure(.captureCancelled, _) = revision else {
            return nil
        }
        return compactCaptureCancelledWidth
    }

    static func startsNewSuccessResult(
        after previousRevision: PopupWindowContentRevision?,
        next revision: PopupWindowContentRevision
    ) -> Bool {
        guard case let .success(nextResultID, _, _, _) = revision else {
            return false
        }
        guard case let .success(previousResultID, _, _, _)? = previousRevision else {
            return true
        }
        return previousResultID != nextResultID
    }

    static func preservesHeightWhenShowingOriginal(
        from previousRevision: PopupWindowContentRevision?,
        to nextRevision: PopupWindowContentRevision
    ) -> Bool {
        guard let previousRevision else {
            return false
        }

        guard case let .success(previousResultID, previousShowsOriginal, _, _) = previousRevision,
              case let .success(nextResultID, nextShowsOriginal, _, _) = nextRevision
        else {
            return false
        }

        guard nextShowsOriginal else {
            return false
        }
        return previousResultID != nextResultID || !previousShowsOriginal
    }

    static func preferredFrameHeight(
        measuredFrameHeight: CGFloat,
        currentFrameHeight: CGFloat,
        minimumFrameHeight: CGFloat,
        isShowingOriginal: Bool
    ) -> CGFloat {
        guard isShowingOriginal else {
            return measuredFrameHeight
        }
        return max(measuredFrameHeight, max(currentFrameHeight, minimumFrameHeight))
    }

    static func referenceFrameHeight(
        currentFrameHeight: CGFloat,
        lastSuccessFrameHeight: CGFloat?,
        isShowingOriginal: Bool
    ) -> CGFloat {
        guard isShowingOriginal,
              let lastSuccessFrameHeight
        else {
            return currentFrameHeight
        }
        return max(currentFrameHeight, lastSuccessFrameHeight)
    }

    static func shouldApplyAutomaticResize(
        after previousRequest: PopupWindowAutomaticResizeRequest?,
        next request: PopupWindowAutomaticResizeRequest
    ) -> Bool {
        guard let previousRequest else {
            return true
        }
        guard previousRequest.revision == request.revision else {
            return true
        }
        return request.preferredContentHeight
            > previousRequest.preferredContentHeight + automaticFrameComparisonTolerance
            || request.minimumContentHeight
            > previousRequest.minimumContentHeight + automaticFrameComparisonTolerance
    }

    static func requiresFrameSizeChange(from currentFrame: CGRect, to nextFrame: CGRect) -> Bool {
        abs(currentFrame.width - nextFrame.width) > automaticFrameComparisonTolerance
            || abs(currentFrame.height - nextFrame.height) > automaticFrameComparisonTolerance
    }
}

enum PopupWindowMoveEventPolicy {
    static func isWindowDrag(_ eventType: NSEvent.EventType?) -> Bool {
        eventType == .leftMouseDragged
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
    private var appliedAutomaticResizeRequest: PopupWindowAutomaticResizeRequest?
    private var didObserveManualResize = false
    private var didObserveManualMove = false
    private var lastAutomaticFrame: CGRect?
    private var lastSuccessFrameHeight: CGFloat?
    private var lastSuccessFrame: CGRect?
    private var isApplyingAutomaticFrame = false
    private var automaticWidthState = PopupWindowAutomaticWidthState()

    func update(
        automaticResizeRequest: PopupWindowAutomaticResizeRequest?,
        automaticResizeEnabled: Bool,
        savedFrame: CGRect?,
        onFrameChange: @escaping (CGRect) -> Void,
        onManualResize: @escaping () -> Void
    ) {
        let isReenablingAutomaticResize = automaticResizeEnabled
            && !self.automaticResizeEnabled
        self.automaticResizeRequest = automaticResizeRequest
        self.automaticResizeEnabled = automaticResizeEnabled
        self.savedFrame = savedFrame
        self.onFrameChange = onFrameChange
        self.onManualResize = onManualResize
        if isReenablingAutomaticResize {
            didObserveManualResize = false
            appliedAutomaticResizeRequest = nil
        }
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
            appliedAutomaticResizeRequest = nil
            didObserveManualResize = false
            didObserveManualMove = false
            lastAutomaticFrame = nil
            lastSuccessFrameHeight = nil
            lastSuccessFrame = nil
            isApplyingAutomaticFrame = false
            automaticWidthState.reset()
        }
        applySavedFrameIfNeeded()
        applyAutomaticResizeIfNeeded()
    }

    func windowWillMove(_ window: NSWindow, initiatedByMouse: Bool) {
        guard self.window === window,
              initiatedByMouse
        else {
            return
        }
        didObserveManualMove = true
    }

    func windowDidMove(_ window: NSWindow) {
        guard self.window === window else {
            return
        }

        if didObserveManualMove {
            updateLastSuccessFrame(window.frame, for: automaticResizeRequest?.revision)
            publishFrame(window.frame)
        } else {
            restoreLastSuccessFrameIfNeeded(for: window)
        }
    }

    func windowDidEndMove(_ window: NSWindow) {
        guard self.window === window,
              didObserveManualMove
        else {
            return
        }
        updateLastSuccessFrame(window.frame, for: automaticResizeRequest?.revision)
        didObserveManualMove = false
    }

    func windowDidResize(_ window: NSWindow) {
        guard self.window === window else {
            return
        }

        if didObserveManualResize || window.inLiveResize {
            lastSuccessFrameHeight = window.frame.height
            updateLastSuccessFrame(window.frame, for: automaticResizeRequest?.revision)
            publishFrame(window.frame)
        } else {
            restoreLastSuccessFrameIfNeeded(for: window)
        }
    }

    func windowWillStartLiveResize(_ window: NSWindow) {
        guard self.window === window,
              !didObserveManualResize
        else {
            return
        }
        didObserveManualResize = true
        automaticWidthState.reset()
        onManualResize?()
    }
}

private extension PopupWindowFrameController {
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

        configureSizeLimits(
            for: window,
            request: request,
            visibleFrame: visibleFrame
        )
        guard PopupWindowSizingPolicy.shouldApplyAutomaticResize(
            after: appliedAutomaticResizeRequest,
            next: request
        ) else {
            return
        }

        let previousRevision = appliedAutomaticResizeRequest?.revision
        let isShowingOriginal = PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
            from: previousRevision,
            to: request.revision
        )
        guard (automaticResizeEnabled && !didObserveManualResize) || isShowingOriginal else {
            return
        }
        appliedAutomaticResizeRequest = request

        let startsNewSuccessResult = PopupWindowSizingPolicy.startsNewSuccessResult(
            after: previousRevision,
            next: request.revision
        )
        let isRestoringCompactWidth = !startsNewSuccessResult
            && request.preferredFrameWidth == nil
            && automaticWidthState.hasPendingRestore
        let preferredFrameWidth: CGFloat?
        if startsNewSuccessResult {
            automaticWidthState.reset()
            preferredFrameWidth = request.preferredFrameWidth
        } else if request.revision.isSuccess {
            preferredFrameWidth = nil
        } else {
            preferredFrameWidth = automaticWidthState.preferredFrameWidth(
                requestedWidth: request.preferredFrameWidth,
                currentWidth: window.frame.width
            )
        }
        let frame = automaticResizeFrame(
            for: request,
            window: window,
            visibleFrame: visibleFrame,
            isShowingOriginal: isShowingOriginal,
            preferredFrameWidth: preferredFrameWidth
        )
        let didChangeWidth = abs(frame.width - window.frame.width)
            > PopupWindowSizingPolicy.automaticFrameComparisonTolerance
        let shouldRemeasureAfterWidthChange = isRestoringCompactWidth
            || (startsNewSuccessResult && didChangeWidth)
        updateLastSuccessFrame(frame, for: request.revision)
        finishAutomaticResize(
            to: frame,
            request: request,
            window: window,
            shouldRemeasureAfterWidthChange: shouldRemeasureAfterWidthChange
        )
    }

    func finishAutomaticResize(
        to frame: CGRect,
        request: PopupWindowAutomaticResizeRequest,
        window: NSWindow,
        shouldRemeasureAfterWidthChange: Bool
    ) {
        let requiresFrameChange = request.revision.isSuccess
            ? !PopupWindowSizingPolicy.framesMatch(window.frame, frame)
            : PopupWindowSizingPolicy.requiresFrameSizeChange(
                from: window.frame,
                to: frame
            )
        guard requiresFrameChange else {
            lastAutomaticFrame = frame
            return
        }
        applyAutomaticFrame(frame, to: window)
        if shouldRemeasureAfterWidthChange {
            appliedAutomaticResizeRequest = nil
        }
    }

    private func automaticResizeFrame(
        for request: PopupWindowAutomaticResizeRequest,
        window: NSWindow,
        visibleFrame: CGRect,
        isShowingOriginal: Bool,
        preferredFrameWidth: CGFloat?
    ) -> CGRect {
        let referenceFrame = request.revision.isSuccess
            ? lastSuccessFrame ?? window.frame
            : window.frame
        let measuredFrameHeight = frameHeight(
            forContentHeight: request.preferredContentHeight,
            window: window
        )
        let minimumFrameHeight = frameHeight(
            forContentHeight: request.minimumContentHeight,
            window: window
        )
        let preferredFrameHeight = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: measuredFrameHeight,
            currentFrameHeight: PopupWindowSizingPolicy.referenceFrameHeight(
                currentFrameHeight: referenceFrame.height,
                lastSuccessFrameHeight: lastSuccessFrameHeight,
                isShowingOriginal: isShowingOriginal
            ),
            minimumFrameHeight: minimumFrameHeight,
            isShowingOriginal: isShowingOriginal
        )
        return PopupWindowSizingPolicy.frame(
            bySettingHeight: preferredFrameHeight,
            from: referenceFrame,
            visibleFrame: visibleFrame,
            minimumHeight: minimumFrameHeight,
            preferredWidth: preferredFrameWidth
        )
    }

    private func publishFrame(_ frame: CGRect) {
        guard !isApplyingAutomaticFrame else {
            return
        }
        if let lastAutomaticFrame {
            guard !PopupWindowSizingPolicy.framesMatch(frame, lastAutomaticFrame) else {
                return
            }
        }
        lastAutomaticFrame = nil
        onFrameChange?(frame)
    }

    private func updateLastSuccessFrame(
        _ frame: CGRect,
        for revision: PopupWindowContentRevision?
    ) {
        guard let revision else {
            return
        }
        switch revision {
        case .success:
            lastSuccessFrame = frame
            lastSuccessFrameHeight = frame.height
        case .failure:
            break
        }
    }

    private func applyAutomaticFrame(_ frame: CGRect, to window: NSWindow) {
        isApplyingAutomaticFrame = true
        defer { isApplyingAutomaticFrame = false }
        lastAutomaticFrame = frame
        window.setFrame(frame, display: true)
    }

    private func restoreLastSuccessFrameIfNeeded(for window: NSWindow) {
        guard !isApplyingAutomaticFrame,
              automaticResizeEnabled,
              !didObserveManualResize,
              automaticResizeRequest?.revision.isSuccess == true,
              let lastSuccessFrame,
              !PopupWindowSizingPolicy.framesMatch(window.frame, lastSuccessFrame)
        else {
            return
        }
        applyAutomaticFrame(lastSuccessFrame, to: window)
    }

    private func configureSizeLimits(
        for window: NSWindow,
        request: PopupWindowAutomaticResizeRequest,
        visibleFrame: CGRect
    ) {
        let minimumHeight = min(
            frameHeight(
                forContentHeight: request.minimumContentHeight,
                window: window
            ),
            min(PopupWindowSizingPolicy.maximumFrameHeight, visibleFrame.height)
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
    private var willMoveObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?
    private var mouseUpMonitor: Any?

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

        observeMoveNotifications(for: window)
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseUp
        ) { [weak self, weak window] event in
            guard let window else {
                return event
            }
            Task { @MainActor in
                self?.controller?.windowDidEndMove(window)
            }
            return event
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

    private func observeMoveNotifications(for window: NSWindow) {
        willMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                let initiatedByMouse = PopupWindowMoveEventPolicy.isWindowDrag(
                    NSApp.currentEvent?.type
                )
                self?.controller?.windowWillMove(
                    window,
                    initiatedByMouse: initiatedByMouse
                )
            }
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
    }

    private func stopObserving() {
        let observers = [willMoveObserver, moveObserver, resizeObserver, liveResizeObserver]
        for observer in observers.compactMap(\.self) {
            NotificationCenter.default.removeObserver(observer)
        }
        willMoveObserver = nil
        moveObserver = nil
        resizeObserver = nil
        liveResizeObserver = nil
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
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
