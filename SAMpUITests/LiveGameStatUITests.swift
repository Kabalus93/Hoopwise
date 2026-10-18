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

    private var firstRow: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "live.row").firstMatch
    }

    /// Hold-to-remove lives on REB / STL / BLK (points are undone with Undo).
    func testHoldRemovesExactlyOneAndReleaseDoesNotReAdd() {
        XCTAssertTrue(firstRow.waitForExistence(timeout: 20), "no player row")
        let reb = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'REB'")).firstMatch
        XCTAssertTrue(reb.waitForExistence(timeout: 5))
        reb.tap()
        reb.tap()
        XCTAssertTrue(firstRow.label.contains("2 REB"), firstRow.label)
        reb.press(forDuration: 1.0)
        sleep(1)                                   // let any stray release tap land
        XCTAssertTrue(firstRow.label.contains("1 REB"),
                      "one hold removes one, and nothing comes back: \(firstRow.label)")
    }
}
