import XCTest

/// The session page's attendance roster, driven for real.
///
/// - The three-position switch: right = present, left = excused, middle =
///   not marked. It never writes absent.
/// - The roster is a List (October 2026). In the old LazyVStack `.swipeActions`
///   never fired; swiping a row here proves they now do.
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
        let control = row.descendants(matching: .any)["attendanceControl"]
        XCTAssertTrue(control.waitForExistence(timeout: 5), "attendance control missing")
        return control
    }

    private func tap(_ control: XCUIElement, at x: CGFloat) {
        control.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
    }

    private func waitForValue(_ control: XCUIElement, _ value: String) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: control)
        return XCTWaiter().wait(for: [exp], timeout: 5) == .completed
    }

    func testThreePositions() {
        let control = control(in: firstRow())
        tap(control, at: 0.85)
        XCTAssertTrue(waitForValue(control, "Present"), "right should be present")
        tap(control, at: 0.15)
        XCTAssertTrue(waitForValue(control, "Excused"), "left should be excused")
        tap(control, at: 0.5)
        XCTAssertTrue(waitForValue(control, "Not marked"), "middle should be not marked")
    }

    /// Swipes fire now (List rows), and Absent is not one of them.
    func testSwipesFireAndOfferNoAbsent() {
        let row = firstRow()
        let toggle = control(in: row)
        tap(toggle, at: 0.85)                      // something recorded → Clear exists
        XCTAssertTrue(waitForValue(toggle, "Present"))
        // Swipe from the name area, not the control (the control owns drags).
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertTrue(app.buttons["Clear"].waitForExistence(timeout: 5),
                      "trailing swipe did not reveal Clear")
        XCTAssertFalse(app.buttons["Absent"].exists, "Absent is inferred, never swiped")
        app.buttons["Clear"].tap()
        XCTAssertTrue(waitForValue(control(in: firstRow()), "Not marked"))
    }
}
