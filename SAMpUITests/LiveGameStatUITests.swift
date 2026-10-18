import XCTest

/// The live-game stat buttons, driven for real: tap adds, hold removes ONE,
/// and the release of a hold adds nothing back (October 2026 field report:
/// the removed point came straight back).
final class LiveGameStatUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "liveGame"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchArguments += ["-app_language", "en"]
        app.launch()
    }

    private func points() -> String {
        let label = app.descendants(matching: .any).matching(identifier: "stat.PTS").firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 20), "no player row")
        return label.value as? String ?? ""
    }

    func testHoldRemovesExactlyOnePointAndReleaseDoesNotReAdd() {
        XCTAssertEqual(points(), "0")
        let plusTwo = app.descendants(matching: .any).matching(NSPredicate(format: "label == '+2'")).firstMatch
        XCTAssertTrue(plusTwo.waitForExistence(timeout: 5))
        plusTwo.tap()
        plusTwo.tap()
        XCTAssertEqual(points(), "4", "two taps = two baskets")
        plusTwo.press(forDuration: 1.0)
        sleep(1)                                   // let any stray release tap land
        XCTAssertEqual(points(), "2", "one hold removes one basket, and nothing comes back")
    }
}
