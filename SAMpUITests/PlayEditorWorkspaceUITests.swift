import XCTest

/// The step editor's workspace (regular width: iPad, and the Mac where most
/// plays are drawn): the tool rail, selection, and the keyboard shortcuts,
/// driven by real key presses. Run it on an iPad simulator; on a phone the
/// workspace does not exist and the test skips. Isolated demo store.
final class PlayEditorWorkspaceUITests: XCTestCase {

    func testShortcutsAndSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "plays"
        app.launchEnvironment["HOOPWISE_PLAYS_OPEN"] = "editor"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES", "-plays.lineShape", "straight"]
        app.launch()

        let move = app.buttons["plays.editor.tool.move"].firstMatch
        guard move.waitForExistence(timeout: 20) else {
            throw XCTSkip("No workspace: this destination is compact width")
        }
        XCTAssertTrue(move.isSelected)

        // Single keys pick tools.
        app.typeKey("c", modifierFlags: [])
        XCTAssertTrue(app.buttons["plays.editor.tool.cut"].firstMatch.isSelected, "C did not pick Cut")
        XCTAssertTrue(app.segmentedControls["plays.editor.lineShape"].firstMatch.exists, "no Straight | Curved for Cut")
        app.typeKey("x", modifierFlags: [])
        XCTAssertTrue(app.buttons["plays.editor.tool.defender"].firstMatch.isSelected, "X did not pick Defender")
        app.typeKey("v", modifierFlags: [])
        XCTAssertTrue(move.isSelected, "V did not pick Move")

        // Click 5's baseline cut: it is selected and the inspector edits it.
        let canvas = app.otherElements["Drawing of step 1"].firstMatch
        XCTAssertTrue(canvas.exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.13)).tap()
        XCTAssertTrue(app.staticTexts["Line by 5"].firstMatch.waitForExistence(timeout: 3), "clicking a line did not select it")

        // The inspector deletes it; ⌘Z brings it back. (⌫ and Esc take the
        // same route as the arrows below, but XCUITest cannot send them on
        // the simulator — see JournalEditorKeys.)
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertFalse(undo.isEnabled)
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["Line by 5"].firstMatch.exists, "Delete did not delete the line")
        XCTAssertTrue(undo.isEnabled)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(undo.isEnabled, "⌘Z did not undo")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.13)).tap()
        XCTAssertTrue(app.staticTexts["Line by 5"].firstMatch.waitForExistence(timeout: 3), "⌘Z did not bring the line back")

        // Arrows nudge the selected player (the special-key route).
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.155, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Player 3"].firstMatch.waitForExistence(timeout: 3), "clicking a player did not select it")
        XCTAssertFalse(undo.isEnabled)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift)
        XCTAssertTrue(undo.isEnabled, "⇧→ did not nudge the player")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(undo.isEnabled, "⌘Z did not undo the nudge")

        // Clicking the empty floor deselects.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        XCTAssertFalse(app.staticTexts["Player 3"].firstMatch.exists, "clicking the floor did not deselect")

        // Typing in the caption types; it does not switch tools.
        let caption = app.textFields.firstMatch
        caption.tap()
        caption.typeText("cv")
        XCTAssertTrue(move.isSelected, "typing in the caption switched tools")
        XCTAssertTrue((caption.value as? String ?? "").hasSuffix("cv"))

        attachScreenshot(app, "workspace")
    }

    /// Several steps in one editor: each keeps its draft and its own undo;
    /// Add a step works; Cancel drops every change and the added step.
    func testMovingBetweenSteps() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "plays"
        app.launchEnvironment["HOOPWISE_PLAYS_OPEN"] = "editor"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        guard app.buttons["plays.editor.tool.move"].firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("No workspace: this destination is compact width")
        }
        let title = app.buttons["plays.editor.steps"].firstMatch
        let undo = app.buttons["Undo"].firstMatch
        let canvas = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH %@", "Drawing of step")).firstMatch
        XCTAssertTrue(title.label.contains("Step 1 of 2"), title.label)

        // Step 2: add a defender.
        app.buttons["plays.editor.step.2"].firstMatch.tap()
        XCTAssertTrue(title.label.contains("Step 2 of 2"), title.label)
        XCTAssertFalse(undo.isEnabled)
        app.typeKey("x", modifierFlags: [])
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        XCTAssertTrue(undo.isEnabled, "the defender was not added")

        // Step 1 has its own (empty) undo; back on step 2 the draft is there.
        app.buttons["plays.editor.step.1"].firstMatch.tap()
        XCTAssertFalse(undo.isEnabled, "step 1 shares step 2's undo")
        app.buttons["plays.editor.step.2"].firstMatch.tap()
        XCTAssertTrue(undo.isEnabled, "step 2's draft was lost on the way")

        // A new step after this one.
        app.buttons["plays.editor.addStep"].firstMatch.tap()
        XCTAssertTrue(title.label.contains("Step 3 of 3"), title.label)
        XCTAssertTrue(app.buttons["plays.editor.step.3"].firstMatch.exists)

        // Delete step: the added step goes outright, then saved step 1 is
        // hidden until Done.
        let deleteStep = app.buttons["plays.editor.deleteStep"].firstMatch
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Delete step' AND identifier != 'plays.editor.deleteStep'")).firstMatch
        deleteStep.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Delete step did not ask")
        confirm.tap()
        XCTAssertTrue(waitForLabel(title, containing: "Step 2 of 2"), "deleting the added step: \(title.label)")
        app.buttons["plays.editor.step.1"].firstMatch.tap()
        deleteStep.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(waitForLabel(title, containing: "Step 1 of 1"), "deleting step 1: \(title.label)")
        XCTAssertFalse(deleteStep.isEnabled, "the last step can be deleted")

        // Cancel discards it all.
        app.buttons["Cancel"].firstMatch.tap()
        let discard = app.buttons["Discard changes"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3), "Cancel did not ask")
        discard.tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].firstMatch.waitForExistence(timeout: 5) ||
                      app.staticTexts["Step 2 of 2"].firstMatch.exists, "Cancel did not restore the steps")
    }

    /// A wide, short window (iPad landscape, like a Mac window): the play
    /// page's court and ‹ ▶ › fit without scrolling (November 2026: the half
    /// court ran off the bottom of the Mac window).
    func testPlayPageFitsAWideWindow() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "plays"
        app.launchEnvironment["HOOPWISE_PLAYS_OPEN"] = "play"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let play = app.buttons["plays.player.play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        guard app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height else {
            throw XCTSkip("Not a wide window on this destination")
        }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(play.frame), "Play is below the window: \(play.frame) in \(window)")
        let next = app.buttons["Next step"].firstMatch
        XCTAssertTrue(window.contains(next.frame), "the step arrows are below the window")
        XCTAssertTrue(play.isHittable, "Play is covered")
        attachScreenshot(app, "play page, wide window")
    }

    /// Upright (taller than wide) the inspector goes under the court and
    /// the court takes the whole width; on its side the inspector is a
    /// column again. Add a step fits on one line in both.
    func testInspectorFollowsTheWindowShape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "plays"
        app.launchEnvironment["HOOPWISE_PLAYS_OPEN"] = "editor"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        guard app.buttons["plays.editor.tool.move"].firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("No workspace: this destination is compact width")
        }
        let add = app.buttons["plays.editor.addStep"].firstMatch
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Drawing of step'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(add.frame.minY, court.frame.maxY, "upright: the inspector is under the court")
        XCTAssertLessThan(add.frame.height, 60, "Add a step is on one line")
        attachScreenshot(app, "editor upright")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertGreaterThan(add.frame.minX, court.frame.maxX, "on its side: the inspector is a column")
        XCTAssertLessThan(add.frame.height, 60, "Add a step is on one line")
        attachScreenshot(app, "editor on its side")
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 3) == .completed
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
