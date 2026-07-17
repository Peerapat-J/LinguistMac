import AppKit
@testable import LinguistMac
@testable import LinguistMacCore
import XCTest

final class TranslationPopupWidthSizingTests: XCTestCase {
    func testOnlyCaptureCancellationUsesCompactWidth() {
        XCTAssertEqual(
            PopupWindowSizingPolicy.preferredFrameWidth(
                for: .failure(.captureCancelled, originalText: nil)
            ),
            PopupWindowSizingPolicy.compactCaptureCancelledWidth
        )
        XCTAssertNil(
            PopupWindowSizingPolicy.preferredFrameWidth(
                for: .failure(.permissionDenied(.screenRecording), originalText: nil)
            )
        )
        XCTAssertNil(
            PopupWindowSizingPolicy.preferredFrameWidth(for: successRevision())
        )
    }

    func testNilPreferredWidthPreservesResultWidthAndHorizontalPosition() {
        let currentFrame = CGRect(x: 640, y: 200, width: 620, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 400,
            from: currentFrame,
            visibleFrame: visibleFrame,
            preferredWidth: nil
        )

        XCTAssertEqual(resizedFrame.width, currentFrame.width)
        XCTAssertEqual(resizedFrame.minX, currentFrame.minX)
    }

    func testOnlyNewSuccessResultAppliesConfiguredWidth() {
        let resultID = UUID()
        let currentRevision = successRevision(resultID: resultID)

        XCTAssertTrue(
            PopupWindowSizingPolicy.startsNewSuccessResult(
                after: nil,
                next: currentRevision
            )
        )
        XCTAssertFalse(
            PopupWindowSizingPolicy.startsNewSuccessResult(
                after: currentRevision,
                next: PopupWindowContentRevision(
                    resultID: resultID,
                    showsOriginal: true,
                    wordTranslations: [],
                    wordCard: nil
                )
            )
        )
        XCTAssertTrue(
            PopupWindowSizingPolicy.startsNewSuccessResult(
                after: currentRevision,
                next: successRevision(resultID: UUID())
            )
        )
    }

    @MainActor
    func testNewResultRestoresConfiguredWidthAfterManualResize() {
        let firstResultID = UUID()
        let firstRequest = successResizeRequest(
            resultID: firstResultID,
            showsOriginal: false,
            preferredWidth: 656
        )
        let (window, controller) = configuredWindow(request: firstRequest)

        controller.windowWillStartLiveResize(window)
        var narrowFrame = window.frame
        narrowFrame.size.width = 420
        window.setFrame(narrowFrame, display: false)
        controller.windowDidResize(window)

        let nextRequest = successResizeRequest(
            resultID: UUID(),
            showsOriginal: false,
            preferredWidth: 656
        )
        controller.update(
            automaticResizeRequest: nextRequest,
            automaticResizeEnabled: false,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.update(
            automaticResizeRequest: nextRequest,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame.width, 656)
    }

    @MainActor
    func testNewResultRemeasuresHeightAfterConfiguredWidthIsRestored() {
        let firstResultID = UUID()
        let (window, controller) = configuredWindow(
            request: successResizeRequest(
                resultID: firstResultID,
                showsOriginal: false,
                preferredWidth: 656
            )
        )

        controller.windowWillStartLiveResize(window)
        var narrowFrame = window.frame
        narrowFrame.size.width = 420
        window.setFrame(narrowFrame, display: false)
        controller.windowDidResize(window)

        let nextResultID = UUID()
        let narrowMeasurement = successResizeRequest(
            resultID: nextResultID,
            showsOriginal: false,
            preferredWidth: 656,
            preferredHeight: 600
        )
        controller.update(
            automaticResizeRequest: narrowMeasurement,
            automaticResizeEnabled: false,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.update(
            automaticResizeRequest: narrowMeasurement,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        controller.update(
            automaticResizeRequest: successResizeRequest(
                resultID: nextResultID,
                showsOriginal: false,
                preferredWidth: 656,
                preferredHeight: 360
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame.width, 656)
        XCTAssertEqual(window.contentLayoutRect.height, 360, accuracy: 1)
    }

    @MainActor
    func testShowingOriginalPreservesManualWidthForSameResult() {
        let resultID = UUID()
        let (window, controller) = configuredWindow(
            request: successResizeRequest(
                resultID: resultID,
                showsOriginal: false,
                preferredWidth: 656
            )
        )

        controller.windowWillStartLiveResize(window)
        var narrowFrame = window.frame
        narrowFrame.size.width = 420
        window.setFrame(narrowFrame, display: false)
        controller.windowDidResize(window)

        controller.update(
            automaticResizeRequest: successResizeRequest(
                resultID: resultID,
                showsOriginal: true,
                preferredWidth: 656
            ),
            automaticResizeEnabled: false,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame.width, 420)
    }

    func testOversizedAutomaticHeightClampsBeforeKeepingTopEdge() {
        let currentFrame = CGRect(x: 100, y: 200, width: 656, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 1000,
            from: currentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resizedFrame.height, PopupWindowSizingPolicy.maximumFrameHeight)
        XCTAssertEqual(resizedFrame.maxY, currentFrame.maxY)
    }

    func testRepeatedOversizedAutomaticHeightDoesNotDriftDown() {
        let currentFrame = CGRect(x: 100, y: 200, width: 656, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)
        let firstFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 1000,
            from: currentFrame,
            visibleFrame: visibleFrame
        )

        let secondFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 1000,
            from: firstFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(secondFrame, firstFrame)
    }

    func testCompactWidthRestoresTheWidthFromBeforeCancellation() {
        var state = PopupWindowAutomaticWidthState()

        XCTAssertEqual(
            state.preferredFrameWidth(requestedWidth: 480, currentWidth: 656),
            480
        )
        XCTAssertEqual(
            state.preferredFrameWidth(requestedWidth: 480, currentWidth: 480),
            480
        )
        XCTAssertTrue(state.hasPendingRestore)
        XCTAssertEqual(
            state.preferredFrameWidth(requestedWidth: nil, currentWidth: 480),
            656
        )
        XCTAssertFalse(state.hasPendingRestore)
        XCTAssertNil(
            state.preferredFrameWidth(requestedWidth: nil, currentWidth: 656)
        )
    }

    @MainActor
    func testOnlyMouseInitiatedMovePublishesTheWindowFrame() {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 200, width: 656, height: 419),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        var publishedFrames: [CGRect] = []
        controller.update(
            automaticResizeRequest: nil,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { publishedFrames.append($0) },
            onManualResize: {}
        )
        controller.attach(to: window)
        publishedFrames.removeAll()

        controller.windowDidMove(window)
        XCTAssertTrue(publishedFrames.isEmpty)

        controller.windowWillMove(window, initiatedByMouse: true)
        controller.windowDidMove(window)
        controller.windowDidEndMove(window)
        XCTAssertEqual(publishedFrames, [window.frame])
    }

    func testOnlyDraggedMouseEventsStartAWindowMove() {
        XCTAssertTrue(PopupWindowMoveEventPolicy.isWindowDrag(.leftMouseDragged))
        XCTAssertFalse(PopupWindowMoveEventPolicy.isWindowDrag(.leftMouseDown))
        XCTAssertFalse(PopupWindowMoveEventPolicy.isWindowDrag(.leftMouseUp))
        XCTAssertFalse(PopupWindowMoveEventPolicy.isWindowDrag(nil))
    }

    private func successRevision() -> PopupWindowContentRevision {
        successRevision(resultID: UUID())
    }

    private func successRevision(resultID: UUID) -> PopupWindowContentRevision {
        PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: false,
            wordTranslations: [],
            wordCard: nil
        )
    }

    @MainActor
    private func configuredWindow(
        request: PopupWindowAutomaticResizeRequest
    ) -> (NSWindow, PopupWindowFrameController) {
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 656, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        controller.update(
            automaticResizeRequest: request,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.attach(to: window)
        return (window, controller)
    }

    private func successResizeRequest(
        resultID: UUID,
        showsOriginal: Bool,
        preferredWidth: CGFloat,
        preferredHeight: CGFloat = 500
    ) -> PopupWindowAutomaticResizeRequest {
        PopupWindowAutomaticResizeRequest(
            revision: PopupWindowContentRevision(
                resultID: resultID,
                showsOriginal: showsOriginal,
                wordTranslations: [],
                wordCard: nil
            ),
            preferredContentHeight: preferredHeight,
            minimumContentHeight: showsOriginal
                ? PopupTextPanelLayout.minimumExpandedContentHeight
                : PopupTextPanelLayout.minimumCollapsedContentHeight,
            preferredFrameWidth: preferredWidth
        )
    }
}

final class TranslationPopupPositionTransitionTests: XCTestCase {
    @MainActor
    func testResizableWindowMinimumUsesStructuralContentHeight() {
        let request = PopupWindowAutomaticResizeRequest(
            revision: successRevision(resultID: UUID(), showsOriginal: true),
            preferredContentHeight: 900,
            minimumContentHeight: PopupTextPanelLayout.minimumExpandedContentHeight
        )
        let (window, _) = configuredWindow(request: request)
        let minimumContentRect = CGRect(
            x: 0,
            y: 0,
            width: window.contentLayoutRect.width,
            height: PopupTextPanelLayout.minimumExpandedContentHeight
        )
        let expectedMinimumHeight = window.frameRect(
            forContentRect: minimumContentRect
        ).height

        XCTAssertEqual(window.minSize.height, expectedMinimumHeight)
        XCTAssertLessThan(window.minSize.height, window.maxSize.height)
    }

    @MainActor
    func testNewContentReenablesAutomaticSizingAfterManualResize() {
        let firstRequest = resizeRequest(
            resultID: UUID(),
            showsOriginal: false,
            height: 500
        )
        let (window, controller) = configuredWindow(request: firstRequest)
        controller.windowWillStartLiveResize(window)
        var manuallyResizedFrame = window.frame
        manuallyResizedFrame.size.height = 600
        window.setFrame(manuallyResizedFrame, display: false)
        controller.windowDidResize(window)

        let nextRequest = resizeRequest(
            resultID: UUID(),
            showsOriginal: false,
            height: 360
        )
        controller.update(
            automaticResizeRequest: nextRequest,
            automaticResizeEnabled: false,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        XCTAssertEqual(window.frame.height, 600)

        controller.update(
            automaticResizeRequest: nextRequest,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertLessThan(window.frame.height, 600)
    }

    @MainActor
    func testHideOriginalRestoresStableFrameAfterTransientLayoutMove() {
        let resultID = UUID()
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: resultID, showsOriginal: true)
        )
        let stableFrame = window.frame
        moveWindowDown(window)

        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: resultID,
                showsOriginal: false
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame, stableFrame)
    }

    @MainActor
    func testNewTranslationRestoresStableFrameAfterTransientLayoutMove() {
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: UUID(), showsOriginal: false)
        )
        let stableFrame = window.frame
        moveWindowDown(window)

        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: UUID(),
                showsOriginal: false
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame, stableFrame)
    }

    @MainActor
    func testSwappedTranslationRestoresStableFrameAfterTransientLayoutMove() {
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: UUID(), showsOriginal: true)
        )
        let stableFrame = window.frame
        var transientFrame = stableFrame
        transientFrame.origin.y -= 64
        transientFrame.size.height -= 120
        window.setFrame(transientFrame, display: false)

        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: UUID(),
                showsOriginal: true,
                height: transientFrame.height
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame, stableFrame)
    }

    @MainActor
    func testLateLayoutMoveIsRestoredAfterSuccessTransition() {
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: UUID(), showsOriginal: false)
        )
        let stableFrame = window.frame

        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: UUID(),
                showsOriginal: false
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        moveWindowDown(window)
        controller.windowDidMove(window)

        XCTAssertEqual(window.frame, stableFrame)
    }

    @MainActor
    func testLateLayoutResizeIsRestoredAfterSuccessTransition() {
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: UUID(), showsOriginal: false)
        )
        let stableFrame = window.frame
        var transientFrame = stableFrame
        transientFrame.size.height -= 120
        window.setFrame(transientFrame, display: false)

        controller.windowDidResize(window)

        XCTAssertEqual(window.frame, stableFrame)
    }

    @MainActor
    func testManualDragBecomesTheAnchorForLaterLayoutMoves() {
        let (window, controller) = configuredWindow(
            request: resizeRequest(resultID: UUID(), showsOriginal: false)
        )
        var draggedFrame = window.frame
        draggedFrame.origin.x += 80
        draggedFrame.origin.y -= 40

        controller.windowWillMove(window, initiatedByMouse: true)
        window.setFrame(draggedFrame, display: false)
        controller.windowDidMove(window)
        controller.windowDidEndMove(window)

        var layoutFrame = draggedFrame
        layoutFrame.origin.y -= 64
        window.setFrame(layoutFrame, display: false)
        controller.windowDidMove(window)

        XCTAssertEqual(window.frame, draggedFrame)
    }

    @MainActor
    private func configuredWindow(
        request: PopupWindowAutomaticResizeRequest
    ) -> (NSWindow, PopupWindowFrameController) {
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 656, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        controller.update(
            automaticResizeRequest: request,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.attach(to: window)
        return (window, controller)
    }

    private func resizeRequest(
        resultID: UUID,
        showsOriginal: Bool,
        height: CGFloat = 500
    ) -> PopupWindowAutomaticResizeRequest {
        PopupWindowAutomaticResizeRequest(
            revision: successRevision(
                resultID: resultID,
                showsOriginal: showsOriginal
            ),
            preferredContentHeight: height,
            minimumContentHeight: showsOriginal
                ? PopupTextPanelLayout.minimumExpandedContentHeight
                : PopupTextPanelLayout.minimumCollapsedContentHeight
        )
    }

    private func successRevision(
        resultID: UUID,
        showsOriginal: Bool
    ) -> PopupWindowContentRevision {
        PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: showsOriginal,
            wordTranslations: [],
            wordCard: nil
        )
    }

    @MainActor
    private func moveWindowDown(_ window: NSWindow) {
        var frame = window.frame
        frame.origin.y -= 64
        window.setFrame(frame, display: false)
    }
}
