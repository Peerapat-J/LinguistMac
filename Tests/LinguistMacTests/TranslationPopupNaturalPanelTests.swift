import AppKit
@testable import LinguistMac
@testable import LinguistMacCore
import SwiftUI
import XCTest

@MainActor
final class PopupNaturalPanelTests: XCTestCase {
    func testCollapsedNaturalPanelStackMeasuresWrappedTranslationText() {
        let height = fittingHeight(showsOriginal: false)

        XCTAssertEqual(height, 200, accuracy: 1)
        XCTAssertGreaterThan(
            height,
            PopupTextPanelLayout.minimumPanelStackHeight(showsOriginal: false)
        )
    }

    func testExpandedNaturalPanelStackUsesTallerWrappedPanelForBothSections() {
        let height = fittingHeight(showsOriginal: true)

        XCTAssertEqual(height, 284, accuracy: 1)
        XCTAssertGreaterThan(
            height,
            PopupTextPanelLayout.minimumPanelStackHeight(showsOriginal: true)
        )
    }

    func testSelectableTwoLineTranslationMeasuresTallerThanOneLine() {
        let oneLineHeight = selectableTranslationPanelHeight(
            text: "I disagree. It's still useful to write code."
        )
        let twoLineHeight = selectableTranslationPanelHeight(
            text: "Even with Fable-like intelligence, humans get value from writing code. "
                + "Not because agents are worse at coding than humans."
        )

        XCTAssertGreaterThan(twoLineHeight, oneLineHeight + 10)
    }

    private func fittingHeight(showsOriginal: Bool) -> CGFloat {
        let hostingView = NSHostingView(
            rootView: PopupNaturalPanelStackLayout(showsOriginal: showsOriginal) {
                naturalPanel(
                    title: "English",
                    text: showsOriginal ? wrappedSampleText : nil
                )
                naturalPanel(title: "Thai", text: wrappedSampleText)
            }
            .frame(width: 616)
            .fixedSize(horizontal: false, vertical: true)
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    private func naturalPanel(title: String, text: String?) -> some View {
        PopupTextPanel {
            VStack(alignment: .leading, spacing: PopupTextPanelLayout.spacing) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("Copy Speak")
                }
                .frame(minHeight: PopupTextPanelLayout.sectionHeaderHeight)

                if let text {
                    Text(text)
                        .font(.system(size: 20))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func selectableTranslationPanelHeight(text: String) -> CGFloat {
        let hostingView = NSHostingView(
            rootView: PopupTextPanel {
                VStack(alignment: .leading, spacing: PopupTextPanelLayout.spacing) {
                    HStack {
                        Text("Thai")
                            .font(.headline)
                        Spacer()
                        Text("Copy Speak")
                    }
                    .frame(minHeight: PopupTextPanelLayout.sectionHeaderHeight)

                    Text(text)
                        .font(.system(size: 20))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize.height
    }

    private var wrappedSampleText: String {
        "แม้จะมีสติปัญญาแบบ Fable มนุษย์ก็ได้รับคุณค่าจากการเขียนโค้ด "
            + "ไม่ใช่เพราะตัวแทนเขียนโค้ดได้แย่กว่ามนุษย์ แต่เพื่อคิดโดยตรงในสภาพแวดล้อมการดำเนินการ "
            + "ไม่ใช่พร็อกซีผ่านภาษาอังกฤษ"
    }
}
