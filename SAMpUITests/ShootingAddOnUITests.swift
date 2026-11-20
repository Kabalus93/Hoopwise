import XCTest

/// Tracked shooting in the plan (20 Nov 2026): Free Throws and 5-Spot Twos
/// in a session's Skills show their add-ons; a number pad writes each
/// athlete's self-reported makes and moves on.
final class ShootingAddOnUITests: XCTestCase {

    private func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "0"
        app.launchEnvironment["HOOPWISE_DEMO_SHOOTING"] = mode
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testFreeThrowsLogFromThePad() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = app.descendants(matching: .any).matching(identifier: "shooting.addon.freeThrows").firstMatch
        for _ in 0..<6 where !addon.exists { app.swipeUp() }
        XCTAssertTrue(addon.waitForExistence(timeout: 10), "the add-on shows in the plan")
        attach("addon")
        let cells = addon.buttons.matching(identifier: "shooting.cell")
        XCTAssertGreaterThan(cells.count, 1, "one cell per athlete")
        cells.element(boundBy: 0).tap()
        let seven = app.buttons["shooting.pad.7"]
        XCTAssertTrue(seven.waitForExistence(timeout: 5), "the pad opens")
        attach("pad")
        seven.tap()
        // Free throws have one spot: the pad moves to the next athlete.
        app.buttons["shooting.pad.5"].tap()
        // After the last athlete the pad closes itself.
        if app.buttons["shooting.pad.done"].waitForExistence(timeout: 1) { app.buttons["shooting.pad.done"].tap() }
        XCTAssertTrue(addon.staticTexts["70%"].waitForExistence(timeout: 5), "7 of 10")
        XCTAssertTrue(addon.staticTexts["50%"].exists, "5 of 10")
        attach("logged")
    }

    func testFiveSpotsLogAthleteByAthleteFromLogMakes() {
        let app = launch("1")
        defer { _ = launch("clear") }
        let addon = app.descendants(matching: .any).matching(identifier: "shooting.addon.twos").firstMatch
        for _ in 0..<8 where !addon.exists || !addon.isHittable { app.swipeUp() }
        XCTAssertTrue(addon.waitForExistence(timeout: 10))
        addon.buttons["shooting.log"].tap()
        let six = app.buttons["shooting.pad.6"]
        XCTAssertTrue(six.waitForExistence(timeout: 5), "Log makes opens the pad")
        attach("pad")
        // One athlete's five spots, one tap each.
        for n in [6, 5, 7, 4, 8] { app.buttons["shooting.pad.\(n)"].tap() }
        attach("next athlete")
        XCTAssertGreaterThan(app.buttons.matching(identifier: "shooting.pad.athlete").count, 1, "everyone as photos")
        app.buttons["shooting.pad.done"].tap()
        // Whatever the shots a spot, all five spots of one athlete are in.
        let filled = addon.buttons.matching(NSPredicate(format: "identifier == 'shooting.cell' AND label ENDSWITH ' 8'"))
        XCTAssertTrue(filled.firstMatch.waitForExistence(timeout: 5), "the right-corner 8 is in the table")
        XCTAssertTrue(addon.buttons.matching(NSPredicate(format: "identifier == 'shooting.cell' AND label ENDSWITH ' 6'")).firstMatch.exists)
        attach("logged")
    }
}
