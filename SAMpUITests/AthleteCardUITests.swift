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
        // The peep's own card IS the exported card, and flips.
        let card = app.descendants(matching: .any)["athleteCard.flip"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the quick peep shows the player card")
        card.tap()
        share.tap()
        checkTheShareSheet(app)
    }

    /// A cut-out photo: before sharing, keep the level colour (chosen at first)
    /// or pick one of the Photos colours (20 Nov 2026). Needs a demo athlete
    /// with a cut-out — run once with HOOPWISE_DEMO_CUTOUTS (see
    /// ProfileBackgroundDebug.swift); skips when the photo is not cut out.
    func testTheShareSheetAsksForThePhotoBackground() throws {
        continueAfterFailure = false
        let app = launch("athleteCard")
        XCTAssertTrue(app.descendants(matching: .any)["athleteCard.preview"].waitForExistence(timeout: 15))
        let level = app.buttons["cardBackdrop.level"].firstMatch
        guard level.waitForExistence(timeout: 3) else {
            throw XCTSkip("this demo athlete's photo is not a cut-out")
        }
        XCTAssertTrue(level.isSelected, "the level colour is kept unless the coach picks another")
        let blue = app.buttons["cardBackdrop.#00ACF9"].firstMatch
        XCTAssertTrue(blue.exists, "the Photos petals are offered")
        blue.tap()
        XCTAssertTrue(blue.isSelected)
        XCTAssertFalse(level.isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "blue background"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
