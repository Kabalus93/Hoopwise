import XCTest

/// The attendance control is the system segmented control (November 2026,
/// Luther: the hand-built switch lagged), taps are saved, and "All present"
/// marks the roster in one go. Runs on a past, still-scheduled class in the
/// isolated demo store (HOOPWISE_SHOT=pastSession) and leaves it unmarked.
final class AttendanceControlUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "pastSession"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    private func controls(_ app: XCUIApplication) -> XCUIElementQuery {
        app.segmentedControls.matching(identifier: "attendanceControl")
    }

    func testMarkSaveAndAllPresent() {
        continueAfterFailure = false
        var app = launch()
        let first = controls(app).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let count = controls(app).count
        XCTAssertGreaterThan(count, 1)

        // One tap: the segment is selected at once.
        let present = first.buttons["Present"]
        present.tap()
        XCTAssertTrue(present.isSelected)

        // All present: confirm, then every row is present.
        app.buttons["attendance.allPresent"].tap()
        let confirm = app.buttons["Mark all present"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        for i in 0..<count {
            XCTAssertTrue(controls(app).element(boundBy: i).buttons["Present"].isSelected, "row \(i)")
        }

        // Saved: a fresh launch shows the same.
        sleep(1)
        app.terminate()
        app = launch()
        XCTAssertTrue(controls(app).firstMatch.waitForExistence(timeout: 30))
        for i in 0..<count {
            XCTAssertTrue(controls(app).element(boundBy: i).buttons["Present"].isSelected, "row \(i) after relaunch")
        }

        // Leave the demo class as it was: nobody marked.
        for i in 0..<count {
            controls(app).element(boundBy: i).buttons["Not marked"].tap()
        }
        sleep(1)
        app.terminate()
    }
}
