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
        // Clear leaves an empty court (22 Nov 2026): five attackers first.
        element("plays.editor.offenseDock").tap()
        element("plays.editor.preset.fiveOut").tap()

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

    /// His screenshot (22 Nov 2026): a 3v3 with 2 inbounding from behind the
    /// baseline. The dock reads the format and the inbound, offers the
    /// situation and the inbounder's defender, and no zones (three attackers).
    func testAnInboundIsReadAndZonesNeedFive() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "coachBoard"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_BOARD_DEMO"] = "blob"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let dock = element("plays.editor.defenseDock")
        XCTAssertTrue(dock.waitForExistence(timeout: 30))
        XCTAssertTrue(dock.label.contains("3v3"), dock.label)
        XCTAssertTrue(dock.label.contains("Inbound"), dock.label)
        dock.tap()
        XCTAssertTrue(element("plays.editor.defense.situation").waitForExistence(timeout: 5), "the situation can be chosen")
        XCTAssertTrue(element("plays.editor.defense.inbounder").exists, "and the inbounder's defender")
        XCTAssertTrue(element("plays.editor.defense.zonesNeedFive").exists, "a 3v3 is told why there is no zone")
        XCTAssertFalse(app.buttons["2-3"].exists)
        app.buttons["Protect the rim"].firstMatch.tap()
        attach("blob protect the rim")
        app.buttons["Live ball"].firstMatch.tap()
        XCTAssertFalse(dock.label.contains("Inbound"), "Live: the inbound rules are off — " + dock.label)
        XCTAssertFalse(element("plays.editor.defense.inbounder").exists)
        attach("blob forced live")
    }
}
