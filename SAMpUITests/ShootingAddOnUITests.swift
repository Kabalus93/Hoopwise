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
}
