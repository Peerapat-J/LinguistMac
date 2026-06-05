@testable import LinguistMacCore
import XCTest

final class AppFeatureTests: XCTestCase {
    func testStarterFeaturesAreNotEmpty() {
        XCTAssertFalse(AppFeature.starterFeatures.isEmpty)
    }

    func testStarterFeatureIDsAreUnique() {
        let ids = AppFeature.starterFeatures.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testStarterFeaturesIncludeScreenTranslation() {
        XCTAssertTrue(
            AppFeature.starterFeatures.contains { $0.id == "screen-translation" }
        )
    }

    func testStarterFeaturesIncludeQuickTranslate() {
        XCTAssertTrue(
            AppFeature.starterFeatures.contains { $0.id == "quick-translate" }
        )
    }
}
