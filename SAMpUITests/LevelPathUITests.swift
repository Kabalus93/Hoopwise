import XCTest

/// The level pill opens the path to the next level (27 Nov 2026).
final class LevelPathUITests: XCTestCase {
    func testTheLevelPillOpensThePath() throws {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "studentProfile"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let pill = app.descendants(matching: .any).matching(identifier: "athlete.levelMark").firstMatch
        try XCTSkipUnless(pill.waitForExistence(timeout: 25), "the demo athlete is in no group program")
        pill.tap()
        let ranked = app.descendants(matching: .any).matching(identifier: "level.header").firstMatch
        let missing = app.descendants(matching: .any).matching(identifier: "level.missing").firstMatch
        XCTAssertTrue(ranked.waitForExistence(timeout: 8) || missing.exists, "the path opens")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "level"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
    }
}
