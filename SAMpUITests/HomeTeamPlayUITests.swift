import XCTest

/// Home's TEAM card (a pinned team) and PLAY card (the play being worked
/// on): HOOPWISE_SHOT=homeCards pins the demo team and marks its focus play
/// edited, then shows Home. Each card opens what it shows.
final class HomeTeamPlayUITests: XCTestCase {

    func testThePinnedTeamAndTheRecentPlayAreOnHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "homeCards"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()

        let play = app.buttons["home.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 25), "the play being worked on is on Home")
        XCTAssertTrue(play.label.contains("WORKING ON"))
        let openTeam = app.buttons["home.team.open"]
        for _ in 0..<5 where !openTeam.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(openTeam.waitForExistence(timeout: 5), "the pinned team is on Home")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
        openTeam.tap()
        XCTAssertTrue(app.buttons["team.menu"].waitForExistence(timeout: 5), "the card opens the team")
    }
}
