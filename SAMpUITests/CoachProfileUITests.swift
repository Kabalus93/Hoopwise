import XCTest

/// The coach form sets a 5v5 position and tendencies; the profile shows
/// them. Demo store; puts the coach back as it was.
final class CoachProfileUITests: XCTestCase {

    func testPositionAndTendenciesShowOnTheProfile() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "coachProfile"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let edit = app.buttons["coach.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 20))
        edit.tap()
        let position = app.segmentedControls["coach.form.position"]
        for _ in 0..<6 where !(position.exists && position.isHittable) { app.swipeUp() }
        position.buttons["PG"].tap()
        app.buttons["Shooter"].tap()
        app.buttons["High IQ"].tap()
        let shot1 = XCTAttachment(screenshot: app.screenshot()); shot1.lifetime = .keepAlways; self.add(shot1)
        app.buttons["coach.form.save"].tap()

        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Point guard'")).firstMatch
                        .waitForExistence(timeout: 5), "the profile shows the position")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Shooter'")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'High IQ'")).firstMatch.exists)
        let shot2 = XCTAttachment(screenshot: app.screenshot()); shot2.lifetime = .keepAlways; self.add(shot2)

        // Put the coach back.
        edit.tap()
        for _ in 0..<6 where !(position.exists && position.isHittable) { app.swipeUp() }
        position.buttons["—"].tap()
        app.buttons["Shooter"].tap()
        app.buttons["High IQ"].tap()
        app.buttons["coach.form.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not set'")).firstMatch
                        .waitForExistence(timeout: 5))
    }
}
