import XCTest

/// A drill's "Add a visual" opens the Plays editor straight away (no menu of
/// photo / video / link sources), with a Player tool for any number of
/// players and a Cone tool; Done puts the drawing in the drill's visuals,
/// and tapping it opens the editor again. Runs on the demo store.
final class DrillVisualUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "drillsLibrary"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en", "-library.age", "U8"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func stepLabel(_ words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The drills page's first regular drill. Since 21 Nov 2026 the skill
    /// chips, the filters and the nine Tracked shooting rows come first, so
    /// on an iPad mini the first `library.row` is below the fold of a lazy
    /// list and not built until the list scrolls.
    private func firstLibraryRow() -> XCUIElement {
        XCTAssertTrue(app.buttons["Add Drill"].firstMatch.waitForExistence(timeout: 30), "the drills page")
        let row = element("library.row")
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "a library drill under Tracked shooting")
        return row
    }

    func testAddAVisualOpensTheEditorWithPlayersAndCones() {
        let row = firstLibraryRow()
        row.tap()

        let cta = element("drill.addVisual"), addTile = element("drill.visual.add")
        XCTAssertTrue(cta.waitForExistence(timeout: 8) || addTile.exists, "the drill offers Add a visual")
        // Start from no drawings (demo store): a run that failed before its
        // clean-up left one, and on a phone the page shows one drawing at a
        // time behind a toggle, so the new one would not be on screen.
        let leftover = app.buttons.matching(identifier: "drill.drawing.more")
        for _ in 0..<5 where leftover.firstMatch.exists {
            leftover.firstMatch.tap()
            guard app.buttons["Delete Drawing"].waitForExistence(timeout: 3) else { break }
            app.buttons["Delete Drawing"].tap()
            if app.buttons["Delete"].waitForExistence(timeout: 3) { app.buttons["Delete"].tap() }
            sleep(1)
        }
        let cards = app.buttons.matching(identifier: "drill.drawing.edit")
        let before = cards.count
        (cta.exists ? cta : addTile).tap()

        let cone = element("plays.editor.tool.cone")
        XCTAssertTrue(cone.waitForExistence(timeout: 8), "the Plays editor opens, with a Cone tool")
        XCTAssertFalse(app.staticTexts["Choose Photo"].exists, "no Add Visual menu")
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing of step 1'")).firstMatch
        XCTAssertTrue(court.exists)

        cone.tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55)).tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55)).tap()
        element("plays.editor.tool.player").tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        element("plays.editor.tool.defender").tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        // A second step (the old "Add a step after this one" button went with
        // the steps panel's 17 Nov 2026 redesign): the board layout's + on an
        // iPad, else the phone's steps bar "+ Add a step", tapped directly —
        // opening the bar's step menu first made that tap only close the menu.
        if element("board.addStep").exists {
            element("board.addStep").tap()
        } else {
            XCTAssertTrue(element("plays.editor.addStep").waitForExistence(timeout: 5), "the phone's steps bar")
            element("plays.editor.addStep").tap()
        }
        attach("drill editor, step 2")

        app.buttons["Done"].tap()
        XCTAssertTrue(cards.element(boundBy: before).waitForExistence(timeout: 8), "the drawing plays on the drill page")
        // The card's header is one element on the phone ("<caption>, Step 1
        // of 2"), its own text on the iPad: look for the words in a label.
        XCTAssertTrue(stepLabel("Step 1 of 2").waitForExistence(timeout: 4), "every step is reachable on the page")
        app.buttons["Next step"].firstMatch.tap()
        XCTAssertTrue(stepLabel("Step 2 of 2").waitForExistence(timeout: 4))
        attach("drill page playing the drawing")

        // Edit opens it in the editor again.
        cards.element(boundBy: before).tap()
        XCTAssertTrue(element("plays.editor.tool.cone").waitForExistence(timeout: 8), "the drawing reopens in the editor")
        app.buttons["Cancel"].tap()

        // Leave the demo store as it was.
        let more = app.buttons.matching(identifier: "drill.drawing.more").element(boundBy: before)
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let deleteItem = app.buttons["Delete Drawing"]
        if deleteItem.waitForExistence(timeout: 4) {
            deleteItem.tap()
            let confirm = app.buttons["Delete"]
            if confirm.waitForExistence(timeout: 4) { confirm.tap() }
        }
    }

    /// New Drill offers "Draw on the court"; on the iPhone the editor's steps
    /// bar adds, moves and deletes steps; Create saves the drawing as the
    /// drill's first visual. Deletes the drill afterwards.
    func testNewDrillCanBeDrawnWithStepsOrganisedOnThePhone() throws {
        // The phone's steps bar. On an iPad, Draw opens the board-style
        // editor (steps at the foot of the rail) — CoachBoardUITests and
        // BoardExtrasUITests cover that.
        if UIDevice.current.userInterfaceIdiom == .pad {
            throw XCTSkip("the iPhone's steps bar; the iPad draws in the board editor")
        }
        XCTAssertTrue(app.buttons["Add Drill"].firstMatch.waitForExistence(timeout: 30), "the drills page")
        app.buttons["Add Drill"].firstMatch.tap()
        let name = app.textFields["Drill Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        name.tap()
        name.typeText("UITest drawn drill")
        // The keyboard stays up after the name, and a swipe over it scrolls
        // nothing: put it away first, then scroll the form to the Visual.
        name.typeText("\n")
        let draw = element("newDrill.draw")
        for _ in 0..<8 where !(draw.exists && draw.isHittable) { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        draw.tap()

        // Three steps; the third moves to second, then the first is deleted.
        let add = element("plays.editor.addStep")
        XCTAssertTrue(add.waitForExistence(timeout: 8), "the phone editor has a steps bar")
        add.tap()
        add.tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 4))
        element("plays.editor.steps").tap()
        app.buttons["Move step earlier"].tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 4), "the step moved earlier")
        // Phone: the steps bar's ‹; iPad: the steps strip's first frame.
        if app.buttons["Previous step"].exists { app.buttons["Previous step"].tap() } else { element("plays.editor.step.1").tap() }
        element("plays.editor.steps").tap()
        // Not the strip's trash button (iPad): the menu's item, then the dialog's.
        let notTrash = NSPredicate(format: "label == 'Delete step' AND identifier != 'plays.editor.deleteStep'")
        app.buttons.matching(notTrash).firstMatch.tap()
        let confirm = app.buttons.matching(notTrash).firstMatch
        if confirm.waitForExistence(timeout: 4) { confirm.tap() }
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].waitForExistence(timeout: 4), "a step was deleted")
        attach("phone editor steps bar")
        app.buttons["Done"].tap()

        let editDrawing = app.buttons["Edit drawing"]
        for _ in 0..<6 where !editDrawing.exists { app.swipeUp() }
        XCTAssertTrue(editDrawing.waitForExistence(timeout: 6), "the form shows the drawing")
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].exists, "with both steps")
        attach("new drill with a drawing")
        app.buttons["Create"].tap()

        // The drill has the drawing; then leave the demo store as it was.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText("UITest drawn drill")
        let created = app.staticTexts["UITest drawn drill"].firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 6))
        created.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "drill.drawing.edit").firstMatch.waitForExistence(timeout: 8),
                      "the drawing is the drill's visual")

        // Leave the demo store as it was: the phone has no Delete for a
        // coach's drill, so a relaunch removes it (every copy, should an
        // earlier run have failed).
        app.terminate()
        app.launchEnvironment["HOOPWISE_DELETE_DRILLS_NAMED"] = "UITest drawn drill"
        app.launch()
        XCTAssertTrue(app.buttons["Add Drill"].firstMatch.waitForExistence(timeout: 30), "the drills page")
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("UITest drawn drill")
        XCTAssertFalse(app.staticTexts["UITest drawn drill"].waitForExistence(timeout: 3), "cleaned up")
    }
}
