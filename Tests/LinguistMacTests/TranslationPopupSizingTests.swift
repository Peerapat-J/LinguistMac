@testable import LinguistMac
@testable import LinguistMacCore
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

    func testSourcePanelMinimumUsesCompactEditableViewport() {
        let viewportHeight = PopupTextPanelLayout.minimumSourcePanelHeight
            - PopupTextPanelLayout.minimumCollapsedSourcePanelHeight
            - PopupTextPanelLayout.spacing

        XCTAssertEqual(
            viewportHeight,
            PopupTextPanelLayout.minimumSourceTextViewportHeight
        )
    }

    func testAutomaticResizeUsesCurrentWindowPosition() {
        let currentFrame = CGRect(x: 640, y: 200, width: 460, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 300,
            from: currentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resizedFrame.height, 300)
        XCTAssertEqual(resizedFrame.minX, currentFrame.minX)
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

    func testUnchangedHeightDoesNotRepositionLongPopup() {
        let currentFrame = CGRect(x: 100, y: 200, width: 600, height: 640)
        let positionClampedFrame = CGRect(x: 100, y: 160, width: 600, height: 640)

        XCTAssertFalse(
            PopupWindowSizingPolicy.requiresFrameHeightChange(
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
        let differentResultRevision = PopupWindowContentRevision(
            resultID: UUID(),
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
                to: differentResultRevision
            )
        )
    }

    func testShowingOriginalExpandsWindowInsteadOfShrinkingTranslationPanel() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 480,
            currentFrameHeight: 500,
            expandedContentHeightIncrement: PopupTextPanelLayout.expandedContentHeightIncrement,
            isShowingOriginal: true
        )

        XCTAssertEqual(
            height,
            500 + PopupTextPanelLayout.expandedContentHeightIncrement
        )
    }

    func testHidingOriginalReturnsToMeasuredContentHeight() {
        let height = PopupWindowSizingPolicy.preferredFrameHeight(
            measuredFrameHeight: 420,
            currentFrameHeight: 640,
            expandedContentHeightIncrement: 140,
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
