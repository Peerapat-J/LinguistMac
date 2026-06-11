@testable import LinguistMacCore
import XCTest

final class ShortcutRegistrationTests: XCTestCase {
    func testShortcutPlanRegistersDefaultShortcutsWhenAccessibilityIsGranted() {
        let results = ShortcutRegistrationPlan(settings: AppSettings())
            .validated(accessibilityStatus: .granted)

        XCTAssertTrue(results.allSatisfy(\.isRegistered))
        XCTAssertEqual(Set(results.map(\.action)), [.screenTranslation, .textSelectionTranslation, .quickTranslate])
    }

    func testShortcutPlanReportsAccessibilityRequirement() {
        let results = ShortcutRegistrationPlan(settings: AppSettings())
            .validated(accessibilityStatus: .denied)

        XCTAssertEqual(
            results.map(\.issue),
            [
                .permissionDenied(.accessibility),
                .permissionDenied(.accessibility),
                .permissionDenied(.accessibility)
            ]
        )
    }

    func testShortcutPlanReportsConflictsAgainstFirstOwner() {
        var settings = AppSettings()
        settings.quickTranslateShortcut = .screenTranslationDefault

        let results = ShortcutRegistrationPlan(settings: settings)
            .validated(accessibilityStatus: .granted)
        let quickTranslateResult = results.first { $0.action == .quickTranslate }

        XCTAssertEqual(quickTranslateResult?.issue, .duplicate(.screenTranslation))
    }

    func testShortcutCoordinatorUnregistersInvalidatedActions() async {
        let registry = RecordingShortcutRegistry()
        let coordinator = ShortcutRegistrationCoordinator(registry: registry)
        _ = await coordinator.refresh(settings: AppSettings(), accessibilityStatus: .granted)

        var conflictedSettings = AppSettings()
        conflictedSettings.quickTranslateShortcut = .screenTranslationDefault
        let results = await coordinator.refresh(settings: conflictedSettings, accessibilityStatus: .granted)
        let quickTranslateShortcut = await registry.registeredShortcut(for: .quickTranslate)
        let screenTranslationShortcut = await registry.registeredShortcut(for: .screenTranslation)

        XCTAssertEqual(results.first { $0.action == .quickTranslate }?.issue, .duplicate(.screenTranslation))
        XCTAssertNil(quickTranslateShortcut)
        XCTAssertEqual(screenTranslationShortcut, .screenTranslationDefault)
    }

    func testDoubleCopyDetectorTriggersOnlyInsideWindowAndResetsAfterTrigger() {
        var detector = DoubleCopyTriggerDetector(triggerWindow: 0.5)
        let start = Date(timeIntervalSince1970: 10)

        XCTAssertFalse(detector.recordCopyCommand(at: start))
        XCTAssertFalse(detector.recordCopyCommand(at: start.addingTimeInterval(0.8)))
        XCTAssertTrue(detector.recordCopyCommand(at: start.addingTimeInterval(1.0)))
        XCTAssertFalse(detector.recordCopyCommand(at: start.addingTimeInterval(1.1)))
    }
}
