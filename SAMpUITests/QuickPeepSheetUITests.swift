import XCTest

/// The Quick Peep opens part-way and its handle pulls it up to full height
/// (24 Nov 2026).
final class QuickPeepSheetUITests: XCTestCase {
    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testTheHandlePullsThePeepUpAndDownAgain() {
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
        let done = app.navigationBars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "the peep opens")
        sleep(1)
        let bar = app.navigationBars["Quick Peep"]
        let window = app.windows.firstMatch.frame
        let openY = bar.frame.minY
        attach("opened")
        XCTAssertGreaterThan(openY, window.height * 0.25, "opens part-way, not full height")
        // Pull the handle (just above the bar) up.
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: bar.frame.midX, dy: openY - 6))
        start.press(forDuration: 0.2, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        sleep(1)
        attach("pulled up")
        XCTAssertLessThan(bar.frame.minY, openY - window.height * 0.15, "the handle pulls it up")
        done.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
}
