@testable import LinguistMacCore
import XCTest

final class PermissionBaselineTests: XCTestCase {
    func testDefaultRequirementsIncludeScreenRecordingForDefaultWorkflow() {
        let requirement = PermissionBaseline.defaultRequirements.first {
            $0.kind == .screenRecording
        }

        XCTAssertEqual(requirement?.isRequiredForDefaultWorkflow, true)
    }

    func testAccessibilityIsTrackedButNotRequiredForDefaultWorkflow() {
        let requirement = PermissionBaseline.defaultRequirements.first {
            $0.kind == .accessibility
        }

        XCTAssertEqual(requirement?.isRequiredForDefaultWorkflow, false)
    }

    func testDefaultRequirementsCoverCloudProviderPrivacyBoundaries() {
        let kinds = Set(PermissionBaseline.defaultRequirements.map(\.kind))

        XCTAssertTrue(kinds.contains(.keychain))
        XCTAssertTrue(kinds.contains(.network))
    }

    func testDefaultRequirementsIncludeVoicePermissionBoundaries() {
        let requirements = Dictionary(
            uniqueKeysWithValues: PermissionBaseline.defaultRequirements.map { ($0.kind, $0) }
        )

        XCTAssertEqual(requirements[.microphone]?.isRequiredForDefaultWorkflow, false)
        XCTAssertEqual(requirements[.speechRecognition]?.isRequiredForDefaultWorkflow, false)
        XCTAssertTrue(requirements[.microphone]?.reason.contains("push-to-talk") == true)
        XCTAssertTrue(requirements[.speechRecognition]?.reason.contains("spoken phrases") == true)
    }
}
