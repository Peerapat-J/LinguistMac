@testable import LinguistMacCore
import XCTest

final class AppIdentityTests: XCTestCase {
    func testLinguistMacIdentityMatchesM0BundlePlan() {
        let identity = AppIdentity.linguistMac

        XCTAssertEqual(identity.displayName, "LinguistMac")
        XCTAssertEqual(identity.bundleIdentifier, "com.peerapatj.LinguistMac")
        XCTAssertEqual(identity.minimumMacOSVersion, "15.0")
        XCTAssertEqual(identity.shortVersion, "0.1")
        XCTAssertEqual(identity.buildVersion, "1")
    }
}
