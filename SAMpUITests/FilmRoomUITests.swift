import XCTest

/// The Mac's film room (25 Nov 2026): a sidebar over the court instead of the
/// tab bar. The Mac cannot be driven from here, so the DEBUG flag
/// HOOPWISE_FILM_ROOM=1 shows the same shell on the iPad simulator in
/// landscape. Demo store.
final class FilmRoomUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testTheSidebarReachesEveryPlaceOverTheCourt() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "the shell is a wide-window layout")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_FILM_ROOM"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "filmRoom.sidebar").firstMatch
        if !sidebar.waitForExistence(timeout: 20) { app.terminate(); app.launch() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 20), "the sidebar replaces the tab bar")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "no tab bar in the film room")
        sleep(2)
        shot(app, "0 home")
        let names = ["1 sessions", "2 athletes", "3 hub", "4 plays", "5 drills", "6 lexicon", "7 teams", "8 organization"]
        for (i, name) in names.enumerated() {
            let row = app.buttons["filmRoom.place.\(i + 1)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), name)
            row.tap()
            sleep(2)
            shot(app, name)
            XCTAssertTrue(row.isSelected, "\(name) is the place on screen")
        }
        // Back where a page was left: Home is still alive.
        app.buttons["filmRoom.place.0"].tap()
        XCTAssertTrue(app.buttons["filmRoom.board"].exists, "the board opens in its own window")
    }
}
