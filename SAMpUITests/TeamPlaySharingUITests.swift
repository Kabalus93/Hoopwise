import XCTest

/// A team's play (23 Nov 2026, Luther): Numbers | Players over the court, a
/// chip per role to follow that player, and Share — which asks about the
/// defenders every time before it will make a sheet.
final class TeamPlaySharingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ env: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testFacesFollowAndShare() {
        let app = launch(["HOOPWISE_SHOT": "teamPlay", "HOOPWISE_TEAMPLAY_PEOPLE": "0"])
        let marks = element(app, "teamPlay.marks")
        XCTAssertTrue(marks.waitForExistence(timeout: 25), "no Numbers | Players switch on the team's play")
        marks.buttons["Players"].tap()
        XCTAssertTrue(marks.buttons["Players"].isSelected)

        let follow = element(app, "teamPlay.follow.1")
        XCTAssertTrue(follow.waitForExistence(timeout: 5), "no chip for role 1")
        follow.tap()
        XCTAssertTrue(follow.isSelected, "role 1 is followed")
        element(app, "teamPlay.follow.all").tap()
        XCTAssertFalse(follow.isSelected, "Everyone stops following")

        element(app, "teamPlay.share").tap()
        let pdf = element(app, "playSheet.sharePDF")
        XCTAssertTrue(pdf.waitForExistence(timeout: 10), "no share sheet")
        XCTAssertTrue(element(app, "playSheet.preview").waitForExistence(timeout: 10), "no preview of the sheet")
        let defenders = element(app, "playSheet.defenders")
        if defenders.exists {
            XCTAssertFalse(pdf.isEnabled, "the defenders are asked first")
            defenders.buttons["Hide"].tap()
        }
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: pdf)
        wait(for: [enabled], timeout: 5)
        XCTAssertTrue(element(app, "playSheet.kind").exists, "team, a player or everyone")
    }
}
