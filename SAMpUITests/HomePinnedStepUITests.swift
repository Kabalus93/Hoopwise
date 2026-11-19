import XCTest

/// A play's step pinned to Home (19 Nov 2026, Luther): the play page's ⋯
/// pins the step on screen, and Home's play card draws that step.
final class HomePinnedStepUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    func testHomeShowsThePinnedStep() {
        let app = launch(["HOOPWISE_SHOT": "homeCards", "HOOPWISE_HOME_PIN_STEP": "1"])
        let card = app.descendants(matching: .any).matching(identifier: "home.play").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no play card")
        XCTAssertTrue(card.label.contains("PINNED · STEP 2"), card.label)
    }

    func testThePlayPageOffersToPinTheStep() {
        let app = launch(["HOOPWISE_SHOT": "plays", "HOOPWISE_PLAYS_OPEN": "play"])
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 20), "no play page")
        more.tap()
        let pin = app.buttons["Show this step on Home"]
        if !pin.waitForExistence(timeout: 3) {
            // Already pinned from an earlier run: take it off first.
            app.buttons["Remove from Home"].tap()
            more.tap()
        }
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.tap()
        more.tap()
        XCTAssertTrue(app.buttons["Remove from Home"].waitForExistence(timeout: 3), "the step is pinned")
        app.buttons["Remove from Home"].tap()
    }
}
