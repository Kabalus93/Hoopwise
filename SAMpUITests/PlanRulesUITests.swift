import XCTest

/// The plan's Plays card takes game RULES too (27 Nov 2026): + offers Add
/// Plays or Add a Rule; a rule from the common list shows under the plays and
/// comes out again. The demo plan is left as it was.
final class PlanRulesUITests: XCTestCase {
    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testARuleGoesInTheplanAndComesOut() {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "0"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let plus = app.buttons["plan.plays.add"]
        for _ in 0..<8 where !plus.exists || !plus.isHittable { app.swipeUp() }
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        // Leftovers from an earlier failed run.
        while app.buttons["plan.rule.remove"].firstMatch.exists { app.buttons["plan.rule.remove"].firstMatch.tap() }

        plus.tap()
        let addRule = app.buttons["plan.plays.add.rule"]
        XCTAssertTrue(addRule.waitForExistence(timeout: 5), "+ offers Add a Rule")
        XCTAssertTrue(app.buttons["plan.plays.add.play"].exists, "and Add Plays")
        attach("menu")
        addRule.tap()

        let noDribble = app.buttons["No dribble"]
        XCTAssertTrue(noDribble.waitForExistence(timeout: 8), "the common rules are offered")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Rule options'")).firstMatch.exists,
                      "and the library's rule options")
        attach("rule sheet")
        noDribble.tap()

        let rule = app.otherElements["plan.rule"].firstMatch
        XCTAssertTrue(rule.waitForExistence(timeout: 5), "the rule shows in the plan")
        XCTAssertTrue(app.staticTexts["No dribble"].exists)
        attach("rule in the plan")

        app.buttons["plan.rule.remove"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["No dribble"].waitForExistence(timeout: 2), "and comes out again")
    }
}
