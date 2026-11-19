import XCTest

/// Generate / Regenerate open the coach's choices first (19 Nov 2026,
/// Luther), and the games list keeps its status word whole on the iPad.
final class PlanGenerateUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(_ env: [String: String]) {
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testGenerateAsksFirst() {
        continueAfterFailure = false
        launch(["HOOPWISE_SHOT": "sessionPage", "HOOPWISE_SESSION_TAB": "0"])
        let regenerate = app.buttons["Regenerate"], generate = app.buttons["Generate Plan"]
        let deadline = Date().addingTimeInterval(30)
        while !regenerate.exists && !generate.exists && Date() < deadline { sleep(1) }
        (regenerate.exists ? regenerate : generate).tap()
        let go = app.descendants(matching: .any).matching(identifier: "generate.go").firstMatch
        XCTAssertTrue(go.waitForExistence(timeout: 5), "the choices come first")
        app.descendants(matching: .any).matching(identifier: "generate.skill.shooting").firstMatch.tap()
        attach("generate sheet")
        go.tap()
        XCTAssertFalse(go.waitForExistence(timeout: 2), "Generate closes the sheet")
        attach("plan after generate")
    }

    func testGameRowsKeepTheirStatusWord() {
        continueAfterFailure = false
        launch(["HOOPWISE_SHOT": "sessionPage", "HOOPWISE_SESSION_TAB": "2", "HOOPWISE_DEMO_READY_GAMES": "1"])
        let row = app.descendants(matching: .any).matching(identifier: "games.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["Ready"].exists, "the status word is whole")
        attach("game rows")
        // Put the demo session back.
        app.terminate()
        launch(["HOOPWISE_SHOT": "sessionPage", "HOOPWISE_SESSION_TAB": "2", "HOOPWISE_DEMO_READY_GAMES": "clear"])
        sleep(3)
    }
}
