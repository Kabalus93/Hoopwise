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
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"       // full screen, as the Hub opens it
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

extension CoachBoardUITests {
    /// "Full court should be vertical" (Luther, 17 Nov 2026): attacking up,
    /// taller than wide. Puts the board back on the half court after.
    func testTheFullCourtStandsUpright() {
        continueAfterFailure = false
        app = launch()
        XCTAssertTrue(element("plays.editor.tool.player").waitForExistence(timeout: 30))
        element("board.court").tap()
        let full = app.buttons["Full court"].firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 5))
        full.tap()
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing of step 1'")).firstMatch
        XCTAssertTrue(court.waitForExistence(timeout: 8))
        sleep(1)
        attach("full court upright")
        XCTAssertGreaterThan(court.frame.height, court.frame.width * 1.4, "the full court is drawn upright")
        element("board.court").tap()
        app.buttons["Half court"].firstMatch.tap()
    }
}

extension CoachBoardUITests {
    /// The ball rule and playing in place (17 Nov 2026, Luther): a pass from
    /// a player without the ball draws nothing; from the ball handler it
    /// draws; ▶ plays on the board itself, no popup.
    func testBallRuleAndPlayInPlace() {
        continueAfterFailure = false
        app = launch()
        XCTAssertTrue(element("plays.editor.tool.pass").waitForExistence(timeout: 30))
        if element("board.clear").isEnabled {
            element("board.clear").tap()
            element("board.confirmClear").tap()
        }
        XCTAssertFalse(element("board.clear").waitForEnabled(false, timeout: 5).isEnabled)
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing of step 1'")).firstMatch
        func at(_ x: Double, _ y: Double) -> XCUICoordinate {   // court metres on the half court
            court.coordinate(withNormalizedOffset: CGVector(dx: (x + 1.3) / 17.6, dy: (y + 1.3) / 16.6))
        }
        element("plays.editor.tool.pass").tap()
        // 2 has no ball: nothing is drawn.
        at(12.6, 6.6).press(forDuration: 0.1, thenDragTo: at(13.9, 1.2))
        XCTAssertFalse(element("board.clear").waitForEnabled(true, timeout: 2).isEnabled, "a pass needs the ball")
        // 1 has it: the pass is drawn.
        at(7.5, 9.6).press(forDuration: 0.1, thenDragTo: at(12.6, 6.6))
        XCTAssertTrue(element("board.clear").waitForEnabled(true, timeout: 4).isEnabled, "the ball handler passes")
        attach("pass from the ball handler")

        // ▶ plays right there: the bar stays, no sheet comes up.
        XCTAssertTrue(element("board.play").exists)
        XCTAssertTrue(element("board.previous").exists && element("board.next").exists)
        element("board.play").tap()
        sleep(1)
        attach("playing in place")
        XCTAssertTrue(element("board.play").exists, "still the board")
        XCTAssertTrue(element("plays.editor.steps").exists, "still the board")
        XCTAssertEqual(app.navigationBars.count, 1, "no popup")

        element("board.clear").tap()
        element("board.confirmClear").tap()
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
