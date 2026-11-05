import XCTest

/// The session page's attendance roster, driven for real.
///
/// - The three positions (the system segmented control since November
///   2026): right = present, left = excused, middle = not marked. It never
///   writes absent.
/// - The roster is a List (October 2026). In the old LazyVStack `.swipeActions`
///   never fired; the leading Photo swipe here proves they now do.
///
/// Launches through SheetGalleryDebug (HOOPWISE_SHOT=sessionPage), which
/// opens the first program's earliest session on its Attendance tab and seeds
/// fixtures into an empty store.
final class AttendanceSwipeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        // The simulators are signed into the coach's iCloud: these taps must
        // land in the isolated demo store, never in the synced one.
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"
        // The assertions read English labels; the app's saved language is
        // whatever the simulator last ran in.
        app.launchArguments += ["-app_language", "en"]
        app.launch()
    }

    private func firstRow() -> XCUIElement {
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no roster row appeared")
        return row
    }

    private func control(in row: XCUIElement) -> XCUIElement {
        let control = row.segmentedControls["attendanceControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 5), "attendance control missing")
        return control
    }

    private func choose(_ control: XCUIElement, _ label: String) {
        control.buttons[label].tap()
    }

    private func isSelected(_ control: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "isSelected == true")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: control.buttons[label])
        return XCTWaiter().wait(for: [exp], timeout: 5) == .completed
    }

    func testThreePositions() {
        let control = control(in: firstRow())
        choose(control, "Present")
        XCTAssertTrue(isSelected(control, "Present"), "right should be present")
        choose(control, "Excused")
        XCTAssertTrue(isSelected(control, "Excused"), "left should be excused")
        choose(control, "Not marked")
        XCTAssertTrue(isSelected(control, "Not marked"), "middle should be not marked")
    }

    /// Right-to-left offers nothing (October 2026): Clear duplicated the
    /// control's middle and Refund lives on the contract sheet. Absent was
    /// never a swipe — it is inferred.
    func testTrailingSwipeOffersNothing() {
        let row = firstRow()
        let toggle = control(in: row)
        choose(toggle, "Present")                  // a recorded mark
        XCTAssertTrue(isSelected(toggle, "Present"))
        // Swipe from the name area, not the control.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertFalse(app.buttons["Clear"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Refund session"].exists)
        XCTAssertFalse(app.buttons["Absent"].exists)
        XCTAssertTrue(isSelected(control(in: firstRow()), "Present"), "the mark is untouched")
        choose(control(in: firstRow()), "Not marked")   // leave the demo class unmarked
    }

    /// Tapping a student in the session opens the quick peep, and the peep
    /// offers Edit — the coach never has to leave the session to fix a record.
    func testQuickPeepFromSessionOffersEdit() {
        let row = firstRow()
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
        let edit = app.navigationBars.buttons["Edit Student"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), "quick peep has no Edit button")
        edit.tap()
        XCTAssertTrue(app.staticTexts["BASIC INFORMATION"].waitForExistence(timeout: 8),
                      "Edit did not open the student editor")
    }

    /// The leading swipe retakes the student's profile photo: it opens the
    /// masked camera directly (no library, no Quick Measure).
    func testLeadingSwipeOpensProfileCamera() {
        let row = firstRow()
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        let photo = app.buttons["Photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "leading swipe did not reveal Photo")
        XCTAssertFalse(app.buttons["Metrics"].exists, "Quick Measure is no longer the swipe")
        photo.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Photo did not open the camera")
        XCTAssertFalse(app.staticTexts["Quick Measure"].exists)
        cancel.tap()
        XCTAssertTrue(firstRow().exists, "cancel should land back on the roster")
    }
}
