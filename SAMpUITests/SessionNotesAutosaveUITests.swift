import XCTest

/// Session notes save themselves (23 Nov 2026, Luther: "make sure notes are
/// syncing to the cloud like everything else"): text typed and LEFT ON SCREEN
/// — the Notes tab never left, the app then killed — is in the store at the
/// next launch. Demo store; the note is taken out again.
final class SessionNotesAutosaveUITests: XCTestCase {
    private let marker = "Autosave check 7Q"

    /// The demo session's own note, put back before and after the check.
    private let original = "Auto-closed: 2026-10-15 10:49"

    private func launch(resetNotes: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if resetNotes { app.launchEnvironment["HOOPWISE_DEMO_NOTES"] = original }
        app.launchEnvironment["HOOPWISE_SHOT"] = "sessionPage"
        app.launchEnvironment["HOOPWISE_SESSION_TAB"] = "3"
        app.launchEnvironment["HOOPWISE_SCREENSHOT_STORE"] = "1"   // never the synced store
        app.launchEnvironment["HOOPWISE_GALLERY_FULL"] = "1"
        app.launchArguments += ["-app_language", "en", "-hasOnboarded", "YES"]
        app.launch()
        // The first launch of a run can come up without its environment.
        // (An iPad upright has no Reminders | Notes switch — the notebook is
        // simply there, above the reminders.)
        if !app.descendants(matching: .any).matching(identifier: "notes.pane").firstMatch.waitForExistence(timeout: 8),
           !app.textViews.firstMatch.waitForExistence(timeout: 8) {
            app.terminate(); app.launch()
        }
        return app
    }

    private func notebook(_ app: XCUIApplication) -> XCUIElement {
        let pane = app.descendants(matching: .any).matching(identifier: "notes.pane").firstMatch
        // The switch exists on a phone and in a narrow window only.
        if pane.waitForExistence(timeout: 8) { pane.buttons["Notes"].firstMatch.tap() }
        // The card's identifier covers its children, so the editor carries it.
        let editor = app.textViews.matching(identifier: "notes.notebook").firstMatch
        if editor.waitForExistence(timeout: 5) { return editor }
        let any = app.textViews.firstMatch
        if !any.waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "no editor"; shot.lifetime = .keepAlways; add(shot)
            XCTFail("the notebook's editor: \(app.debugDescription.prefix(3000))")
        }
        return any
    }

    func testTypedNotesAreSavedWithoutLeavingTheTab() {
        continueAfterFailure = false
        var app = launch(resetNotes: true)
        var editor = notebook(app)
        XCTAssertFalse(((editor.value as? String) ?? "").contains(marker), "starts clean")
        editor.tap()
        editor.typeText(marker)
        sleep(4)            // the autosave waits two seconds after the last key
        app.terminate()     // the tab was never left

        app = launch()
        editor = notebook(app)
        let after = (editor.value as? String) ?? ""
        XCTAssertTrue(after.contains(marker), "the typed notes survived: \(after)")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "after relaunch"; shot.lifetime = .keepAlways; add(shot)

        // Put the demo notes back.
        app.terminate()
        app = launch(resetNotes: true)
        let restored = (notebook(app).value as? String) ?? ""
        XCTAssertFalse(restored.contains(marker), "cleaned up: \(restored)")
    }
}
