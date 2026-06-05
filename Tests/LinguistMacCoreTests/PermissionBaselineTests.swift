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
}
