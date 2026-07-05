@testable import LinguistMacCore
import XCTest

final class CaptureSelectionStateTests: XCTestCase {
    func testStartIgnoresDuplicateActiveSelection() {
        var machine = CaptureSelectionStateMachine()

        XCTAssertTrue(machine.start())
        XCTAssertFalse(machine.start())
        XCTAssertEqual(machine.state, .selecting)
    }

    func testSelectionCanCompleteCancelAndReset() {
        var machine = CaptureSelectionStateMachine()
        let region = CapturedScreenRegion(imageData: Data([1, 2, 3]), scale: 2)

        machine.start()
        machine.complete(with: region)

        XCTAssertEqual(machine.state, .completed(region))

        machine.reset()
        machine.start()
        machine.cancel()

        XCTAssertEqual(machine.state, .cancelled)
    }

    func testCompletionOutsideActiveSelectionIsIgnored() {
        var machine = CaptureSelectionStateMachine()
        let region = CapturedScreenRegion(imageData: Data([1]))

        machine.complete(with: region)

        XCTAssertEqual(machine.state, .idle)
    }
}
