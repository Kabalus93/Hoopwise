import XCTest

/// Rating a drill for the plan engine (19 Nov 2026, Luther): the drill
/// page's "In my plans" card. Demo store; puts the drill back to Normal.
final class DrillPreferenceUITests: XCTestCase {
    func testNeverAsksWhyAndGoesBack() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "drillDetail"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let card = app.descendants(matching: .any).matching(identifier: "drill.preferenceCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "the card is on the drill page")
        for _ in 0..<4 where !app.buttons["Never"].isHittable { app.swipeUp() }
        app.buttons["Never"].tap()
        let tooEasy = app.buttons["Too easy"]
        XCTAssertTrue(tooEasy.waitForExistence(timeout: 5), "Never asks why")
        tooEasy.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "never"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Normal"].tap()
        XCTAssertFalse(tooEasy.waitForExistence(timeout: 2), "Normal needs no reason")
    }
}
