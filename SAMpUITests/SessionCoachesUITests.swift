import XCTest

/// A scrimmage's Add Athlete also lists the organization's coaches; one added
/// shows on the roster with a Coach tag and can be taken off again.
/// Demo store.
final class SessionCoachesUITests: XCTestCase {

    func testACoachJoinsAScrimmageAndLeavesAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "scrimmageSession"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Athlete'")).firstMatch
        for _ in 0..<8 where !(add.exists && add.isHittable) { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout: 20))
        add.tap()

        XCTAssertTrue(app.staticTexts["Coaches"].waitForExistence(timeout: 8), "the sheet lists coaches first")
        let coachTag = app.staticTexts["Coach"].firstMatch
        XCTAssertTrue(coachTag.exists)
        coachTag.tap()
        app.buttons["Add"].tap()

        let row = app.descendants(matching: .any).matching(identifier: "session.coachRow").firstMatch
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the coach is on the roster")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; self.add(shot)

        // Leave the demo store as it was.
        app.buttons["session.coachRow.more"].firstMatch.tap()
        app.buttons["Remove from session"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 3), "the coach is off again")
        app.terminate()
        app.launchEnvironment["HOOPWISE_SCRIMMAGE_RESET"] = "1"
        app.launch()
        sleep(3)
    }
}
