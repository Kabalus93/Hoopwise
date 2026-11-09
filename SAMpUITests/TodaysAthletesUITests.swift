import XCTest

/// Home's Today's Athletes card shows the day's roster as the Next Up
/// widget does: a cluster of photo bubbles, each opening that athlete.
/// Demo store (a demo class falls today).
final class TodaysAthletesUITests: XCTestCase {

    func testRosterClusterOpensAnAthlete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let bubbles = app.buttons.matching(identifier: "today.cluster.athlete")
        XCTAssertTrue(bubbles.firstMatch.waitForExistence(timeout: 30), "the card shows today's roster as bubbles")
        XCTAssertGreaterThan(bubbles.count, 1)
        bubbles.element(boundBy: 1).tap()
        XCTAssertFalse(bubbles.firstMatch.isHittable, "a bubble opens that athlete's page over Home")
    }
}
