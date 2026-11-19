import XCTest

/// The Coach board's editor additions (19 Nov 2026, Luther): the five lanes
/// on and off, a defender moved with the Cut tool, annotations drawn with
/// Annotate. Demo store; the board is cleared at the end.
final class BoardExtrasUITests: XCTestCase {
    private var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLanesDefenderCutAndAnnotations() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "coachBoard"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        XCTAssertTrue(element("plays.editor.tool.defender").waitForExistence(timeout: 30), "the board")
        if element("board.clear").isEnabled {
            element("board.clear").tap()
            element("board.confirmClear").tap()
        }
        let court = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Drawing of step 1'")).firstMatch
        XCTAssertTrue(court.waitForExistence(timeout: 5))

        // Lanes on.
        element("board.lanes").tap()
        // (Toolbar buttons do not report isSelected to XCUITest; the screenshot shows the lanes.)

        // A defender, then a cut drawn from him.
        element("plays.editor.tool.defender").tap()
        let x = court.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.62))
        x.tap()
        element("plays.editor.tool.cut").tap()
        x.press(forDuration: 0.1, thenDragTo: court.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3)))
        // Select the line: the inspector names it a defender's cut.
        element("plays.editor.tool.move").tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)).tap()
        attach("lanes and a defender's cut")

        // Annotate: ink over the court.
        element("board.annotations").tap()
        XCTAssertTrue(element("board.annotate").waitForExistence(timeout: 5))
        element("board.annotate").tap()
        sleep(1)   // the menu closes; the ink canvas (a PencilKit view) has no accessibility element
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: court.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55)))
        attach("annotation")

        // Pen or highlighter, each with its colours (the last choice is
        // remembered, so start from the pen).
        element("board.annotate.pen").tap()
        XCTAssertTrue(element("board.annotate.color.white").waitForExistence(timeout: 5), "the pen's colours")
        element("board.annotate.highlighter").tap()
        XCTAssertTrue(element("board.annotate.color.pink").waitForExistence(timeout: 5), "the highlighter's colours")
        element("board.annotate.color.green").tap()
        court.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: court.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8)))
        attach("highlighter")
        element("board.annotate.pen").tap()
        XCTAssertTrue(element("board.annotate.color.white").waitForExistence(timeout: 5), "back to the pen")
        element("board.annotate.done").tap()

        // Clean up.
        element("board.clear").tap()
        element("board.confirmClear").tap()
    }
}
