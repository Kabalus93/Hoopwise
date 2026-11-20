import XCTest

/// The board's Defense dock (20 Nov 2026, Luther): its own expandable place
/// between the Step button and the play bar — mode and the man scheme.
final class BoardDefenseUITests: XCTestCase {
    private var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testTheDockSetsTheDefense() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "coachBoard"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let dock = element("plays.editor.defenseDock")
        XCTAssertTrue(dock.waitForExistence(timeout: 30), "the dock sits in the bottom bar")
        if element("board.clear").isEnabled { element("board.clear").tap(); element("board.confirmClear").tap() }

        dock.tap()
        XCTAssertTrue(element("plays.editor.defense").waitForExistence(timeout: 5), "it opens upward")
        app.buttons["Man"].firstMatch.tap()
        XCTAssertTrue(element("plays.editor.defense.screens").waitForExistence(timeout: 5), "man shows its scheme")
        app.buttons["Drop"].firstMatch.tap()
        attach("man drop")
        XCTAssertTrue(dock.label.contains("Drop"), dock.label)

        app.buttons["2-3"].firstMatch.tap()
        XCTAssertFalse(element("plays.editor.defense.screens").waitForExistence(timeout: 2), "zones have no man scheme")
        dock.tap()
        attach("zone 2-3")

        // The steps popover no longer holds the defense.
        element("plays.editor.steps").tap()
        XCTAssertFalse(element("plays.editor.defense").waitForExistence(timeout: 2))
        app.tap()
        element("board.clear").tap(); element("board.confirmClear").tap()
    }
}
