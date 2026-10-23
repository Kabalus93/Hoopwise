import XCTest

/// The Games tab inline stats (HOOPWISE_SHOT=gameStats), scrolled through
/// with a screenshot per screen.
final class GameStatsUITests: XCTestCase {

    func testStatsSheetScrollsThroughEverySection() {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "gameStats"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Team averages"].waitForExistence(timeout: 30))
        for i in 0..<3 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "stats-\(i)"
            shot.lifetime = .keepAlways
            add(shot)
            app.swipeUp()
            sleep(1)
        }
        XCTAssertTrue(app.staticTexts["Leaders"].exists)
        XCTAssertTrue(app.staticTexts["Games played"].exists)
    }
}
