import XCTest

/// What a drill develops (the octagon on its page, Adjust and back) and the
/// program's phase balance. Demo store; the drill is put back as it was.
final class DrillAttributesUITests: XCTestCase {

    private func launch(_ shot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = shot
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        // The first launch of a test run has come up without its environment
        // (the plain app) on this simulator: launch twice.
        app.launch()
        app.terminate()
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testADrillShowsWhatItDevelopsAndTheCoachCanAdjustIt() {
        continueAfterFailure = false
        let app = launch("drillDetail")
        let card = app.buttons["drill.attributes.adjust"]
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !card.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.exists, "the drill page shows what it develops")
        XCTAssertTrue(app.staticTexts["Rated by Claude"].exists || app.staticTexts["Adjusted by you"].exists)
        attach(app, "drill page")

        app.buttons["drill.attributes.adjust"].tap()
        let save = app.buttons["drill.attributes.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["Main"].firstMatch.tap()
        attach(app, "adjust")
        save.tap()
        XCTAssertTrue(app.staticTexts["Adjusted by you"].waitForExistence(timeout: 5), "the coach's rating wins")

        // Put it back.
        app.buttons["drill.attributes.adjust"].tap()
        let reset = app.buttons["Go back to Claude's rating"]
        for _ in 0..<4 where !reset.isHittable { app.swipeUp() }
        reset.tap()
        XCTAssertTrue(app.staticTexts["Rated by Claude"].waitForExistence(timeout: 5))
    }

    func testTheProgramShowsItsPhaseBalance() {
        continueAfterFailure = false
        let app = launch("programDetail")
        let card = app.descendants(matching: .any).matching(identifier: "program.coverage").firstMatch
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<6 where !card.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.exists, "the program page shows the phase balance")
        attach(app, "program")
    }
}
