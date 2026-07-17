import AppKit
@testable import LinguistMac
@testable import LinguistMacCore
import SwiftUI
import XCTest

final class TranslationPopupSizingTests: XCTestCase {
    func testSourceLanguageDisclosureAccessibilityLabelsDescribeState() {
        XCTAssertEqual(
            PopupTextPanelAccessibility.disclosureLabel(
                languageName: "English",
                showsOriginal: false
            ),
            "Show original text in English"
        )
        XCTAssertEqual(
            PopupTextPanelAccessibility.disclosureLabel(
                languageName: "English",
                showsOriginal: true
            ),
            "Hide original text in English"
        )
    }

    func testAutomaticResizeRevisionChangesForWordContent() {
        let resultID = UUID()
        let baseRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: false,
            wordTranslations: [],
            wordCard: nil
        )
        let wordTranslation = WordTranslation(sourceText: "hello", translatedText: "สวัสดี")
        let wordTranslationsRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: false,
            wordTranslations: [wordTranslation],
            wordCard: nil
        )
        let wordCardRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: false,
            wordTranslations: [wordTranslation],
            wordCard: TranslationPopupWordCardState(
                wordTranslation: wordTranslation,
                lookupState: .empty(
                    WordLookupRequest(
                        sourceText: "hello",
                        sentenceContext: "hello world",
                        sourceLanguage: .english,
                        targetLanguage: .thai,
                        providerID: .apple,
                        inputMode: .quickTranslate
                    )
                )
            )
        )

        XCTAssertNotEqual(baseRevision, wordTranslationsRevision)
        XCTAssertNotEqual(wordTranslationsRevision, wordCardRevision)
    }

    func testPanelLayoutBalancesExpandedPanels() {
        let availableHeight: CGFloat = 500

        let sourceHeight = PopupTextPanelLayout.sourcePanelHeight(for: availableHeight)
        let translationHeight = availableHeight - PopupTextPanelLayout.spacing - sourceHeight

        XCTAssertEqual(sourceHeight, translationHeight, accuracy: 0.001)
    }

    func testPanelLayoutPreservesPanelMinimums() {
        let availableHeight = PopupTextPanelLayout.minimumPanelStackHeight(
            showsOriginal: true
        )

        let sourceHeight = PopupTextPanelLayout.sourcePanelHeight(for: availableHeight)
        let translationHeight = availableHeight - PopupTextPanelLayout.spacing - sourceHeight

        XCTAssertEqual(sourceHeight, PopupTextPanelLayout.minimumSourcePanelHeight)
        XCTAssertGreaterThanOrEqual(
            translationHeight,
            PopupTextPanelLayout.minimumTranslationPanelHeight
        )
    }

    func testTranslationPanelMinimumIncludesVisibleTextViewport() {
        let viewportHeight = PopupTextPanelLayout.minimumTranslationPanelHeight
            - (PopupTextPanelLayout.panelPadding * 2)
            - PopupTextPanelLayout.sectionHeaderHeight
            - PopupTextPanelLayout.spacing

        XCTAssertGreaterThanOrEqual(
            viewportHeight,
            PopupTextPanelLayout.minimumTranslationTextViewportHeight
        )
    }

    func testCollapsedPanelStackMinimumKeepsSectionsAboveFooter() {
        let height = PopupTextPanelLayout.minimumPanelStackHeight(showsOriginal: false)

        XCTAssertEqual(
            height,
            PopupTextPanelLayout.minimumCollapsedSourcePanelHeight
                + PopupTextPanelLayout.spacing
                + PopupTextPanelLayout.minimumTranslationPanelHeight
        )
    }

    func testExpandedPanelStackMinimumKeepsBothTextViewportsVisible() {
        let height = PopupTextPanelLayout.minimumPanelStackHeight(showsOriginal: true)

        XCTAssertEqual(
            height,
            PopupTextPanelLayout.minimumSourcePanelHeight
                + PopupTextPanelLayout.spacing
                + PopupTextPanelLayout.minimumTranslationPanelHeight
        )
    }

    func testShowingOriginalAddsExactlyTheSourceTextViewportHeight() {
        let sourceTextViewportHeight = PopupTextPanelLayout.minimumSourcePanelHeight
            - PopupTextPanelLayout.minimumCollapsedSourcePanelHeight

        XCTAssertEqual(
            PopupTextPanelLayout.minimumExpandedContentHeight,
            PopupTextPanelLayout.minimumCollapsedContentHeight
                + sourceTextViewportHeight
        )
    }

    func testSourceAndTranslationPanelsUseMatchingMinimumTextViewports() {
        let viewportHeight = PopupTextPanelLayout.minimumSourcePanelHeight
            - PopupTextPanelLayout.minimumCollapsedSourcePanelHeight
            - PopupTextPanelLayout.spacing

        XCTAssertEqual(
            viewportHeight,
            PopupTextPanelLayout.minimumSourceTextViewportHeight
        )
        XCTAssertEqual(PopupTextPanelLayout.minimumTextViewportHeight, 28)
    }

    func testAutomaticResizeKeepsTopAndCentersCompactWidth() {
        let currentFrame = CGRect(x: 640, y: 200, width: 460, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 300,
            from: currentFrame,
            visibleFrame: visibleFrame,
            preferredWidth: 400
        )

        XCTAssertEqual(resizedFrame.height, 300)
        XCTAssertEqual(resizedFrame.width, 400)
        XCTAssertEqual(resizedFrame.midX, currentFrame.midX)
        XCTAssertEqual(resizedFrame.maxY, currentFrame.maxY)
    }

    func testAutomaticFrameComparisonAllowsBackingPixelRounding() {
        let automaticFrame = CGRect(x: 100, y: 200, width: 460, height: 500)
        let reportedFrame = CGRect(x: 100.5, y: 199.5, width: 460, height: 500.5)

        XCTAssertTrue(PopupWindowSizingPolicy.framesMatch(automaticFrame, reportedFrame))
    }

    func testSameRevisionCanGrowForACompletedHeightMeasurement() {
        let revision = popupContentRevision()
        let initialRequest = PopupWindowAutomaticResizeRequest(
            revision: revision,
            preferredContentHeight: 300,
            minimumContentHeight: 300
        )
        let completedRequest = PopupWindowAutomaticResizeRequest(
            revision: revision,
            preferredContentHeight: 320,
            minimumContentHeight: 300
        )

        XCTAssertTrue(
            PopupWindowSizingPolicy.shouldApplyAutomaticResize(
                after: initialRequest,
                next: completedRequest
            )
        )
    }

    func testSameRevisionDoesNotShrinkForTransientHeightMeasurements() {
        let revision = popupContentRevision()
        let completedRequest = PopupWindowAutomaticResizeRequest(
            revision: revision,
            preferredContentHeight: 320,
            minimumContentHeight: 300
        )
        let transientRequest = PopupWindowAutomaticResizeRequest(
            revision: revision,
            preferredContentHeight: 300,
            minimumContentHeight: 300
        )

        XCTAssertFalse(
            PopupWindowSizingPolicy.shouldApplyAutomaticResize(
                after: completedRequest,
                next: transientRequest
            )
        )
    }

    func testFailureCanReplaceAPreviouslyTallSuccessRequest() {
        let successRequest = PopupWindowAutomaticResizeRequest(
            revision: popupContentRevision(),
            preferredContentHeight: 640,
            minimumContentHeight: PopupTextPanelLayout.minimumCollapsedContentHeight
        )
        let failureRequest = PopupWindowAutomaticResizeRequest(
            revision: .failure(.permissionDenied(.screenRecording), originalText: nil),
            preferredContentHeight: 240,
            minimumContentHeight: 240
        )

        XCTAssertTrue(
            PopupWindowSizingPolicy.shouldApplyAutomaticResize(
                after: successRequest,
                next: failureRequest
            )
        )
    }

    func testUnchangedSizeDoesNotRepositionLongPopup() {
        let currentFrame = CGRect(x: 100, y: 200, width: 600, height: 640)
        let positionClampedFrame = CGRect(x: 100, y: 160, width: 600, height: 640)

        XCTAssertFalse(
            PopupWindowSizingPolicy.requiresFrameSizeChange(
                from: currentFrame,
                to: positionClampedFrame
            )
        )
    }

    func testAutomaticResizeDoesNotShrinkWhenShowingOriginalForSameResult() {
        let resultID = UUID()
        let hiddenRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: false,
            wordTranslations: [],
            wordCard: nil
        )
        let shownRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: true,
            wordTranslations: [],
            wordCard: nil
        )
        XCTAssertTrue(
            PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
                from: hiddenRevision,
                to: shownRevision
            )
        )
        XCTAssertFalse(
            PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
                from: hiddenRevision,
                to: .failure(.permissionDenied(.screenRecording), originalText: nil)
            )
        )
    }

    func testShowingOriginalExpandsWindowInsteadOfShrinkingTranslationPanel() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 480,
            currentFrameHeight: 500,
            minimumFrameHeight: 540,
            isShowingOriginal: true
        )

        XCTAssertEqual(height, 540)
    }

    func testShowingOriginalUsesAStableIncrementAcrossLanguageMeasurements() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 620,
            currentFrameHeight: 500,
            minimumFrameHeight: 540,
            isShowingOriginal: true
        )

        XCTAssertEqual(height, 620)
    }

    func testShowingOriginalGrowsAnAlreadyTallWindowForClippedContent() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 640,
            currentFrameHeight: 606,
            minimumFrameHeight: 388,
            isShowingOriginal: true
        )

        XCTAssertEqual(height, 640)
    }

    func testHidingOriginalReturnsToMeasuredContentHeight() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 420,
            currentFrameHeight: 640,
            minimumFrameHeight: 560,
            isShowingOriginal: false
        )

        XCTAssertEqual(height, 420)
    }

    func testFrameClampsToSecondaryDisplayVisibleFrame() {
        let proposedFrame = CGRect(x: -2500, y: -100, width: 900, height: 800)
        let secondaryVisibleFrame = CGRect(x: -1920, y: 23, width: 1920, height: 1057)

        let frame = PopupWindowSizingPolicy.clampedFrame(
            proposedFrame,
            visibleFrame: secondaryVisibleFrame
        )

        XCTAssertEqual(frame, CGRect(x: -1920, y: 23, width: 720, height: 640))
    }

    private func popupContentRevision() -> PopupWindowContentRevision {
        PopupWindowContentRevision(
            resultID: UUID(),
            showsOriginal: false,
            wordTranslations: [],
            wordCard: nil
        )
    }
}

final class TranslationPopupPanelAllocationTests: XCTestCase {
    func testCollapsedLayoutKeepsSourceCompactAndGivesTranslationTheRemainder() {
        let availableHeight = PopupTextPanelLayout.minimumPanelStackHeight(
            showsOriginal: false
        ) + 40
        let allocation = PopupTextPanelLayout.allocatedPanelHeights(
            availableHeight: availableHeight,
            showsOriginal: false
        )

        XCTAssertEqual(
            allocation.sourcePanel,
            PopupTextPanelLayout.minimumCollapsedSourcePanelHeight
        )
        XCTAssertEqual(
            allocation.sourcePanel
                + PopupTextPanelLayout.spacing
                + allocation.translationPanel,
            availableHeight
        )
    }

    func testExpandedLayoutAllocatesTheExactAvailableHeight() {
        let availableHeight = PopupTextPanelLayout.minimumPanelStackHeight(
            showsOriginal: true
        ) + 80
        let allocation = PopupTextPanelLayout.allocatedPanelHeights(
            availableHeight: availableHeight,
            showsOriginal: true
        )

        XCTAssertGreaterThanOrEqual(
            allocation.sourcePanel,
            PopupTextPanelLayout.minimumSourcePanelHeight
        )
        XCTAssertGreaterThanOrEqual(
            allocation.translationPanel,
            PopupTextPanelLayout.minimumTranslationPanelHeight
        )
        XCTAssertEqual(
            allocation.sourcePanel
                + PopupTextPanelLayout.spacing
                + allocation.translationPanel,
            availableHeight
        )
    }

    func testConstrainedLayoutNeverAllocatesBeyondAvailableHeight() {
        let availableHeight: CGFloat = 80
        let allocation = PopupTextPanelLayout.allocatedPanelHeights(
            availableHeight: availableHeight,
            showsOriginal: true
        )

        XCTAssertGreaterThanOrEqual(allocation.sourcePanel, 0)
        XCTAssertGreaterThanOrEqual(allocation.translationPanel, 0)
        XCTAssertEqual(
            allocation.sourcePanel
                + PopupTextPanelLayout.spacing
                + allocation.translationPanel,
            availableHeight
        )
    }

    func testNaturalExpandedMeasurementUsesTheTallerPanelForBothSections() {
        let allocation = PopupTextPanelLayout.naturalPanelAllocation(
            sourcePanelHeight: 120,
            translationPanelHeight: 180,
            showsOriginal: true
        )

        XCTAssertEqual(allocation.sourcePanel, 180)
        XCTAssertEqual(allocation.translationPanel, 180)
    }

    func testNaturalExpandedMeasurementIncludesRoundingTolerance() {
        let allocation = PopupTextPanelLayout.naturalPanelAllocation(
            sourcePanelHeight: 120.2,
            translationPanelHeight: 120,
            showsOriginal: true
        )

        XCTAssertEqual(allocation.sourcePanel, 121)
        XCTAssertEqual(allocation.translationPanel, 121)
    }

    func testNaturalCollapsedMeasurementDoesNotDoubleCompactTranslationHeight() {
        let allocation = PopupTextPanelLayout.naturalPanelAllocation(
            sourcePanelHeight: PopupTextPanelLayout.minimumCollapsedSourcePanelHeight,
            translationPanelHeight: 120,
            showsOriginal: false
        )

        XCTAssertEqual(
            allocation.sourcePanel,
            PopupTextPanelLayout.minimumCollapsedSourcePanelHeight
        )
        XCTAssertEqual(allocation.translationPanel, 120)
    }
}

final class TranslationPopupTransitionSizingTests: XCTestCase {
    @MainActor
    func testRepeatedShowOriginalRestoresStableWindowPosition() {
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 656, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        let resultID = UUID()
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: resultID,
                showsOriginal: false,
                height: 500
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.attach(to: window)
        let stableFrame = window.frame

        for _ in 0 ..< 2 {
            var movedFrame = stableFrame
            movedFrame.origin.y -= 48
            window.setFrame(movedFrame, display: false)

            controller.update(
                automaticResizeRequest: resizeRequest(
                    resultID: resultID,
                    showsOriginal: true,
                    height: 500
                ),
                automaticResizeEnabled: true,
                savedFrame: nil,
                onFrameChange: { _ in },
                onManualResize: {}
            )
            XCTAssertEqual(window.frame, stableFrame)

            controller.update(
                automaticResizeRequest: resizeRequest(
                    resultID: resultID,
                    showsOriginal: false,
                    height: 500
                ),
                automaticResizeEnabled: true,
                savedFrame: nil,
                onFrameChange: { _ in },
                onManualResize: {}
            )
        }
    }

    @MainActor
    func testCompletedShownMeasurementKeepsTheStableTopEdge() {
        let window = NSWindow(
            contentRect: CGRect(x: 200, y: 200, width: 656, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        let resultID = UUID()
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: resultID,
                showsOriginal: false,
                height: 500
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.attach(to: window)
        let stableTop = window.frame.maxY
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: resultID,
                showsOriginal: true,
                height: 500
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        var movedFrame = window.frame
        movedFrame.origin.y -= 48
        window.setFrame(movedFrame, display: false)
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: resultID,
                showsOriginal: true,
                height: 540
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )

        XCTAssertEqual(window.frame.maxY, stableTop)
    }

    @MainActor
    func testRoundTripSwapRestoresHeightAfterEachLoadingTransition() {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 200, width: 656, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = PopupWindowFrameController()
        let firstResult = resizeRequest(resultID: UUID(), showsOriginal: false, height: 600)
        controller.update(
            automaticResizeRequest: firstResult,
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        controller.attach(to: window)
        let stableHeight = window.frame.height

        setHeight(360, for: window)
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: UUID(),
                showsOriginal: true,
                height: 360
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        XCTAssertEqual(window.frame.height, stableHeight)

        setHeight(360, for: window)
        controller.update(
            automaticResizeRequest: resizeRequest(
                resultID: UUID(),
                showsOriginal: true,
                height: 360
            ),
            automaticResizeEnabled: true,
            savedFrame: nil,
            onFrameChange: { _ in },
            onManualResize: {}
        )
        XCTAssertEqual(window.frame.height, stableHeight)
    }

    func testSwapUsesLastSuccessfulHeightAfterTransientLoadingShrink() {
        let height = PopupWindowSizingPolicy.referenceFrameHeight(
            currentFrameHeight: 360,
            lastSuccessFrameHeight: 640,
            isShowingOriginal: true
        )

        XCTAssertEqual(height, 640)
    }

    func testCollapsedResultUsesCurrentMeasuredHeight() {
        let height = PopupWindowSizingPolicy.referenceFrameHeight(
            currentFrameHeight: 360,
            lastSuccessFrameHeight: 640,
            isShowingOriginal: false
        )

        XCTAssertEqual(height, 360)
    }

    func testAutomaticResizeDoesNotShrinkSwappedExpandedResult() {
        let previousRevision = PopupWindowContentRevision(
            resultID: UUID(),
            showsOriginal: true,
            wordTranslations: [],
            wordCard: nil
        )
        let swappedRevision = PopupWindowContentRevision(
            resultID: UUID(),
            showsOriginal: true,
            wordTranslations: [],
            wordCard: nil
        )

        XCTAssertTrue(
            PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
                from: previousRevision,
                to: swappedRevision
            )
        )
    }

    func testExpandedContentRevisionCanResizeForSameResult() {
        let resultID = UUID()
        let previousRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: true,
            wordTranslations: [],
            wordCard: nil
        )
        let updatedRevision = PopupWindowContentRevision(
            resultID: resultID,
            showsOriginal: true,
            wordTranslations: [
                WordTranslation(sourceText: "hello", translatedText: "สวัสดี")
            ],
            wordCard: nil
        )

        XCTAssertFalse(
            PopupWindowSizingPolicy.preservesHeightWhenShowingOriginal(
                from: previousRevision,
                to: updatedRevision
            )
        )
    }

    private func resizeRequest(
        resultID: UUID,
        showsOriginal: Bool,
        height: CGFloat
    ) -> PopupWindowAutomaticResizeRequest {
        PopupWindowAutomaticResizeRequest(
            revision: PopupWindowContentRevision(
                resultID: resultID,
                showsOriginal: showsOriginal,
                wordTranslations: [],
                wordCard: nil
            ),
            preferredContentHeight: height,
            minimumContentHeight: showsOriginal
                ? PopupTextPanelLayout.minimumExpandedContentHeight
                : PopupTextPanelLayout.minimumCollapsedContentHeight
        )
    }

    @MainActor
    private func setHeight(_ height: CGFloat, for window: NSWindow) {
        var frame = window.frame
        frame.size.height = height
        window.setFrame(frame, display: false)
    }
}
