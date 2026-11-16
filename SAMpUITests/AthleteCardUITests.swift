import XCTest

/// The player card (16 Nov 2026): the athlete profile and the quick peep both
/// open the same share sheet — the card as it will be sent, a coach's line,
/// Share image and A3 print sheet. Demo store.
final class AthleteCardUITests: XCTestCase {

    private func launch(_ shot: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = shot
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    private func checkTheShareSheet(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["athleteCard.preview"].waitForExistence(timeout: 10),
                      "the sheet shows the card as it will be sent")
        let line = app.textFields["athleteCard.coachLine"].firstMatch
        XCTAssertTrue(line.exists)
        line.tap()
        line.typeText("Great month")
        XCTAssertTrue(app.buttons["athleteCard.shareImage"].exists)
        XCTAssertTrue(app.buttons["athleteCard.print"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheProfileSharesThePlayerCard() {
        continueAfterFailure = false
        let app = launch("studentProfile")
        let share = app.buttons["athlete.shareCard"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the profile has a player card button")
        share.tap()
        checkTheShareSheet(app)
    }

    func testTheQuickPeepSharesTheSameCard() {
        continueAfterFailure = false
        let app = launch("quickPeep")
        let share = app.buttons["peep.shareCard"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 30), "the quick peep has a player card button")
        share.tap()
        checkTheShareSheet(app)
    }
}
