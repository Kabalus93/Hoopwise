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

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testAddAVisualOpensTheEditorWithPlayersAndCones() {
        let row = element("library.row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()

        let cta = element("drill.addVisual"), addTile = element("drill.visual.add")
        XCTAssertTrue(cta.waitForExistence(timeout: 8) || addTile.exists, "the drill offers Add a visual")
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
        // A second step.
        element("plays.editor.steps").tap()
        app.buttons["Add a step after this one"].tap()
        attach("drill editor, step 2")

        app.buttons["Done"].tap()
        XCTAssertTrue(cards.element(boundBy: before).waitForExistence(timeout: 8), "the drawing plays on the drill page")
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].exists, "every step is reachable on the page")
        app.buttons["Next step"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Step 2 of 2"].waitForExistence(timeout: 4))
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
}
