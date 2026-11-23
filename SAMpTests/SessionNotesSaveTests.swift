import XCTest
@testable import Hoopwise

/// Session notes are written field by field while they are typed (23 Nov
/// 2026), so they reach iCloud without waiting for the Notes tab to be left.
@MainActor
final class SessionNotesSaveTests: XCTestCase {

    func testNotesAreWrittenAloneAndKeepNoRevision() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Notes Kid")
        dm.addStudent(kid)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        dm.createSession(SessionCreation.Intent(group: .unassigned, start: start, durationMinutes: 60,
                                                title: "Notes class", roster: [kid.id]))
        let session = try XCTUnwrap(dm.sessionEvents.first { $0.title == "Notes class" })
        dm.setStudentAttendanceState(sessionId: session.id, studentId: kid.id, state: .present)
        let revisionsBefore = dm.sessionRevisions(for: session.id).count

        dm.setSessionNotes(sessionId: session.id, notes: "Closeouts were late", coachNotes: nil)
        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == session.id })
        XCTAssertEqual(stored.notes, "Closeouts were late")
        XCTAssertEqual(stored.actualAttendeeIds, [kid.id], "nothing else of the session moved")
        XCTAssertGreaterThan(stored.updatedAt, session.updatedAt, "the change is stamped, so it syncs and pages refresh")
        XCTAssertEqual(dm.sessionRevisions(for: session.id).count, revisionsBefore,
                       "typing does not use up the restore points")

        // Writing the same text again is not a change.
        dm.setSessionNotes(sessionId: session.id, notes: "Closeouts were late", coachNotes: nil)
        XCTAssertEqual(dm.sessionEvents.first { $0.id == session.id }?.updatedAt, stored.updatedAt)

        // Cleared notes are stored as none.
        dm.setSessionNotes(sessionId: session.id, notes: nil, coachNotes: "Older reflection")
        let cleared = try XCTUnwrap(dm.sessionEvents.first { $0.id == session.id })
        XCTAssertNil(cleared.notes)
        XCTAssertEqual(cleared.coachNotes, "Older reflection")
        dm.deleteSessionEvent(cleared)
    }
}
