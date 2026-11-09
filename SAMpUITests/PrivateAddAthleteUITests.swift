import XCTest

/// Add Athlete on a PRIVATE session adds to that session only (November
/// 2026: it used to enroll the second client in the first client's private
/// program, so they were expected — and inferred absent — at every later
/// lesson). Isolated demo store.
final class PrivateAddAthleteUITests: XCTestCase {
    func testAddAthleteOnAPrivateSessionIsThisSessionOnly() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "privateSession"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        if app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'privateSession:'")).firstMatch.waitForExistence(timeout: 8) {
            throw XCTSkip("No private session in this demo store")
        }
        let attend = app.buttons["Attend"].firstMatch
        if attend.waitForExistence(timeout: 10) { attend.tap() }

        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add someone to this session only'")).firstMatch
        if !add.waitForExistence(timeout: 10) { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the private session's Add Athlete does not say 'this session only'")
        add.tap()

        XCTAssertTrue(app.staticTexts["This Session Only"].firstMatch.waitForExistence(timeout: 5), "the picker's banner is the group one")
        attachScreenshot(app, "picker")
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
