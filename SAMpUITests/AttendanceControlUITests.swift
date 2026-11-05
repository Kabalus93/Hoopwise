import XCTest

/// The attendance control is the system segmented control (November 2026,
/// Luther: the hand-built switch lagged), taps are saved, and "All present"
/// marks the roster in one go. Runs on the first program's earliest class in the
/// isolated demo store (HOOPWISE_SHOT=sessionPage) and leaves it unmarked.
final class AttendanceControlUITests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchArguments += ["-app_language", "en"]
        app.launch()
        return app
    }

    private func becomesSelected(_ element: XCUIElement) -> Bool {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter().wait(for: [exp], timeout: 5) == .completed
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
        let labels = ["Excused", "Not marked", "Present"]
        // What the class looked like, to put it back afterwards.
        let before: [String] = (0..<count).map { i in
            labels.first { controls(app).element(boundBy: i).buttons[$0].isSelected } ?? "Not marked"
        }

        // One tap: the segment is selected at once.
        let present = first.buttons["Present"]
        present.tap()
        XCTAssertTrue(becomesSelected(present))
        // Leave someone for "All present" to mark.
        let last = controls(app).element(boundBy: count - 1).buttons["Not marked"]
        last.tap()
        XCTAssertTrue(becomesSelected(last))

        // All present: confirm, then every row is present.
        app.buttons["attendance.allPresent"].tap()
        let confirm = app.buttons["Mark all present"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        for i in 0..<count {
            XCTAssertTrue(becomesSelected(controls(app).element(boundBy: i).buttons["Present"]), "row \(i)")
        }

        // Saved: a fresh launch shows the same.
        sleep(1)
        app.terminate()
        app = launch()
        XCTAssertTrue(controls(app).firstMatch.waitForExistence(timeout: 30))
        for i in 0..<count {
            XCTAssertTrue(becomesSelected(controls(app).element(boundBy: i).buttons["Present"]), "row \(i) after relaunch")
        }

        // Put the demo class back as it was.
        for (i, label) in before.enumerated() where label != "Present" {
            controls(app).element(boundBy: i).buttons[label].tap()
        }
        sleep(1)
        app.terminate()
    }
}
