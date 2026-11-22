import XCTest

/// The Quick Peep opens part-way; its handle pulls it into the whole screen,
/// down again to the peep, and down once more away (24 Nov 2026). iPad: the
/// peep stage; iPhone: the system sheet.
final class QuickPeepSheetUITests: XCTestCase {
    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func openPeep() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "1"
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        // iPad: attendance cards; iPhone: List rows.
        let card = app.descendants(matching: .any).matching(identifier: "attendance.card").firstMatch
        let row = card.waitForExistence(timeout: 10) ? card : app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "a roster row")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 8), "the peep opens")
        sleep(1)
        return app
    }

    private func drag(_ app: XCUIApplication, from element: XCUIElement, toY y: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
    }

    func testTheHandlePullsThePeepToFullScreenAndBackAndAway() throws {
        let app = openPeep()
        let window = app.windows.firstMatch.frame
        let stage = app.descendants(matching: .any).matching(identifier: "peep.stage").firstMatch
        guard stage.waitForExistence(timeout: 3) else {
            throw XCTSkip("the iPad stage — this is the iPhone sheet")
        }
        attach("peep")
        XCTAssertLessThan(stage.frame.width, window.width - 20, "the peep is centred, narrower than the screen")
        XCTAssertGreaterThan(stage.frame.minY, window.height * 0.25, "opens part-way")

        let handle = app.descendants(matching: .any).matching(identifier: "peep.handle").firstMatch
        drag(app, from: handle, toY: 0.02)
        let full = app.descendants(matching: .any).matching(identifier: "peep.stage.full").firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 3), "pulled into full screen")
        XCTAssertEqual(full.frame.width, window.width, accuracy: 1, "the whole width")
        XCTAssertLessThan(full.frame.minY, 2, "the whole height")
        attach("full screen")

        drag(app, from: handle, toY: 0.45)
        XCTAssertTrue(stage.waitForExistence(timeout: 3), "down again: the peep")
        attach("back to peep")

        drag(app, from: handle, toY: 0.98)
        XCTAssertFalse(app.navigationBars["Quick Peep"].waitForExistence(timeout: 2), "down once more: gone")
    }

    func testDoneClosesTheFullScreenPeep() throws {
        let app = openPeep()
        let handle = app.descendants(matching: .any).matching(identifier: "peep.handle").firstMatch
        guard handle.waitForExistence(timeout: 3) else { throw XCTSkip("iPad stage only") }
        handle.tap()   // a tap toggles full screen too
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "peep.stage.full").firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons["Done"].tap()
        sleep(1)
        XCTAssertFalse(app.navigationBars["Quick Peep"].exists, "Done closes it")
    }
}
