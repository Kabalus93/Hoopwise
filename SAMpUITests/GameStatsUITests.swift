import XCTest

/// The Games tab's insights (HOOPWISE_SHOT=gameStats): a header and at most
/// three insights — never the old wall of numbers.
final class GameStatsUITests: XCTestCase {

    func testInsightsAreFewAndWorded() {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "gameStats"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["GAME INSIGHTS"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Team averages"].exists)
        XCTAssertFalse(app.staticTexts["Leaders"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "insights"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
