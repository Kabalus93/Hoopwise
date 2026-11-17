import XCTest

/// The Coach board (17 Nov 2026, Luther): what is drawn stays until Clear —
/// closing the editor, leaving the page and relaunching keep it. Demo store
/// only; the test clears the board at the end.
final class CoachBoardUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "coachBoard"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        return app
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTheBoardKeepsWhatIsDrawnUntilCleared() {
        continueAfterFailure = false
        app = launch()
        // It opens straight in the editor: tools, court, no Cancel.
        let player = element("plays.editor.tool.player")
        XCTAssertTrue(player.waitForExistence(timeout: 30), "the board is the editor, with the drill tools")
        XCTAssertFalse(app.buttons["Cancel"].exists, "every change is kept; nothing to cancel")
        XCTAssertTrue(element("plays.editor.steps").exists, "steps sit behind one button")
        // Start from an empty board.
        if element("board.clear").isEnabled {
            element("board.clear").tap()
            XCTAssertTrue(element("board.confirmClear").waitForExistence(timeout: 5))
            element("board.confirmClear").tap()
        }
        XCTAssertFalse(element("board.clear").waitForEnabled(false, timeout: 5).isEnabled, "an empty board has nothing to clear")

        // Draw a sixth player; the steps button opens the strip.
        XCTAssertTrue(player.waitForExistence(timeout: 8))
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing of step 1'")).firstMatch
        player.tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)).tap()
        XCTAssertTrue(element("board.clear").waitForEnabled(true, timeout: 5).isEnabled, "the drawing is on the board")
        element("plays.editor.steps").tap()
        XCTAssertTrue(element("plays.editor.addStep").waitForExistence(timeout: 5), "the steps strip")
        attach("board steps")

        // Relaunch: still there.
        app.terminate()
        app = launch()
        XCTAssertTrue(element("plays.editor.tool.player").waitForExistence(timeout: 30))
        XCTAssertTrue(element("board.clear").isEnabled, "found as it was left")
        attach("board after relaunch")

        // Save offers a play or a drill.
        element("board.save").tap()
        XCTAssertTrue(element("board.saveAsPlay").waitForExistence(timeout: 5))
        XCTAssertTrue(element("board.saveAsDrill").exists)
        element("board.saveAsPlay").tap()
        XCTAssertTrue(app.navigationBars["New play"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        // Clear empties it.
        XCTAssertTrue(element("board.clear").waitForExistence(timeout: 5))
        element("board.clear").tap()
        XCTAssertTrue(element("board.confirmClear").waitForExistence(timeout: 5))
        element("board.confirmClear").tap()
        XCTAssertFalse(element("board.clear").waitForEnabled(false, timeout: 5).isEnabled)
    }
}

private extension XCUIElement {
    @discardableResult
    func waitForEnabled(_ enabled: Bool, timeout: TimeInterval) -> XCUIElement {
        let end = Date().addingTimeInterval(timeout)
        while isEnabled != enabled, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return self
    }
}
