@testable import LinguistMac
import XCTest

final class TranslationPopupSizingTests: XCTestCase {
    func testPanelLayoutGivesTranslationMostAdditionalHeight() {
        let availableHeight: CGFloat = 500

        let sourceHeight = PopupTextPanelLayout.sourcePanelHeight(for: availableHeight)
        let translationHeight = availableHeight - PopupTextPanelLayout.spacing - sourceHeight

        XCTAssertEqual(sourceHeight, 214.72, accuracy: 0.001)
        XCTAssertGreaterThan(translationHeight, sourceHeight)
    }

    func testPanelLayoutPreservesPanelMinimums() {
        let availableHeight: CGFloat = 241

        let sourceHeight = PopupTextPanelLayout.sourcePanelHeight(for: availableHeight)
        let translationHeight = availableHeight - PopupTextPanelLayout.spacing - sourceHeight

        XCTAssertEqual(sourceHeight, PopupTextPanelLayout.minimumSourcePanelHeight)
        XCTAssertGreaterThanOrEqual(
            translationHeight,
            PopupTextPanelLayout.minimumTranslationPanelHeight
        )
    }

    func testAutomaticResizePreservesTopEdge() {
        let currentFrame = CGRect(x: 100, y: 200, width: 460, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 300,
            from: currentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(resizedFrame.height, 300)
        XCTAssertEqual(resizedFrame.maxY, currentFrame.maxY)
    }

    func testAutomaticResizeUsesRecordedTopEdgeInsteadOfCurrentWindowPosition() {
        let currentFrame = CGRect(x: 100, y: 200, width: 460, height: 500)
        let visibleFrame = CGRect(x: 0, y: 23, width: 1440, height: 877)
        let recordedTopLeft = CGPoint(x: 100, y: 800)

        let resizedFrame = PopupWindowSizingPolicy.frame(
            bySettingHeight: 300,
            from: currentFrame,
            visibleFrame: visibleFrame,
            anchoredAt: recordedTopLeft
        )

        XCTAssertEqual(resizedFrame.minX, recordedTopLeft.x)
        XCTAssertEqual(resizedFrame.maxY, recordedTopLeft.y)
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
}
