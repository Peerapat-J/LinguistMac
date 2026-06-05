@testable import LinguistMacCore
import XCTest

final class OCRTextPreprocessorTests: XCTestCase {
    func testJoinsWrappedProseLinesWithinParagraph() {
        let normalized = OCRTextPreprocessor.normalize(
            lines: [
                "This is a wrapped",
                "sentence from OCR.",
                "",
                "Next paragraph."
            ]
        )

        XCTAssertEqual(normalized, "This is a wrapped sentence from OCR.\n\nNext paragraph.")
    }

    func testPreservesBulletAndNumberedLists() {
        let normalized = OCRTextPreprocessor.normalize(
            lines: [
                "- First item",
                "- Second item",
                "",
                "1. Numbered",
                "2. List"
            ]
        )

        XCTAssertEqual(normalized, "- First item\n- Second item\n\n1. Numbered\n2. List")
    }

    func testJoinsWrappedBulletContinuation() {
        let normalized = OCRTextPreprocessor.normalize(
            lines: [
                "- First item wraps",
                "onto the next line",
                "- Second item"
            ]
        )

        XCTAssertEqual(normalized, "- First item wraps onto the next line\n- Second item")
    }

    func testRepairsHyphenatedLineBreaks() {
        let normalized = OCRTextPreprocessor.normalize(
            lines: [
                "trans-",
                "lation"
            ]
        )

        XCTAssertEqual(normalized, "translation")
    }
}
