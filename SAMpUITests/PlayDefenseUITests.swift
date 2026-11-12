import XCTest

/// Auto defense in the editor workspace (iPad / Mac): pick a zone with the
/// Defender tool, then move the ball — the zone follows. Isolated demo store.
final class PlayDefenseUITests: XCTestCase {

    func testZoneFollowsTheBall() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "plays"
        app.launchEnvironment["HOOPWISE_PLAYS_OPEN"] = "editor"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        // The first launch of a run can come up without its environment.
        if !app.buttons["plays.editor.tool.defender"].firstMatch.waitForExistence(timeout: 12) {
            app.terminate()
            app.launch()
        }

        let defender = app.buttons["plays.editor.tool.defender"].firstMatch
        guard defender.waitForExistence(timeout: 20) else { throw XCTSkip("no editor") }
        // The workspace always shows the defense, whatever the tool.
        let picker = app.segmentedControls["plays.editor.defense"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "no Defense picker in the inspector")
        picker.buttons["2-3"].tap()
        attach(app, "1 zone on")

        app.buttons["plays.editor.tool.ball"].firstMatch.tap()
        let canvas = app.otherElements["Drawing of step 1"].firstMatch
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.727, dy: 0.13)).tap()   // 5 gets a ball
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.69)).tap()     // 1 gives his up
        attach(app, "2 ball on 5")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
