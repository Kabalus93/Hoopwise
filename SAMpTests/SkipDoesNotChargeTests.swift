import XCTest
@testable import Hoopwise

/// The money rules around a session that did not happen.
///
/// `SkipSessionSheet` tells the coach "Skipped sessions won't count toward
/// contracts". Nothing enforced that: `redeemPrivateAttendance` gated on
/// privateness and attendance-array membership and never looked at status, so
/// marking attendance and *then* skipping charged the client permanently —
/// redemption is deliberately one-way, so only a manual refund could undo it.
///
/// These tests run against a real in-memory `SwiftDataManager`, so they
/// exercise the actual redemption authority rather than a restatement of it.
@MainActor
final class SkipDoesNotChargeTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var student: Student!
    private var contract: Contract!

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()

        student = Student(name: "Round Trip Kid")
        dm.addStudent(student)

        // A ten-session private bundle: the shape the redemption authority
        // recognises (private bundle + active + capacity remaining).
        contract = Contract(studentId: student.id,
                            kind: .privateBundle,
                            pricePerSession: 375,
                            bundleSize: 10)
        dm.addContract(contract)
    }

    override func tearDown() async throws {
        dm = nil; student = nil; contract = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A private session: no program, the bundle student on the roster. That
    /// is what `eventIsPrivate` requires for the program-less path.
    private func makePrivateSession(status: SessionEventStatus = .scheduled) -> SessionEvent {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var event = SessionEvent(programId: nil,
                                 title: "Private · Round Trip Kid",
                                 date: start,
                                 startTime: start,
                                 endTime: start.addingTimeInterval(3600),
                                 status: status,
                                 attendeeIds: [student.id])
        event.status = status
        dm.addSessionEvent(event)
        return event
    }

    private var remaining: Int {
        dm.contracts.first { $0.id == contract.id }?.bundleRedemptionsRemaining ?? -1
    }

    // MARK: - Baseline

    func testPresentConsumesASession() {
        let event = makePrivateSession()
        XCTAssertEqual(remaining, 10, "Fixture should start with a full bundle.")

        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .present)

        XCTAssertEqual(remaining, 9, "Marking present must consume one prepaid session.")
    }

    // MARK: - The promise

    /// The exact sequence the sheet promises about: mark attendance, then skip.
    func testMarkAttendedThenSkipRefundsTheSession() {
        let event = makePrivateSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .present)
        XCTAssertEqual(remaining, 9, "Precondition: the session was charged.")

        var toSkip = dm.sessionEvents.first { $0.id == event.id }!
        XCTAssertTrue(SessionLifecycle.apply(.skip(.weather), to: &toSkip),
                      "Skip must be a legal transition from scheduled.")
        dm.updateSessionEvent(toSkip)

        XCTAssertEqual(remaining, 10,
                       "Skipping a charged session must return the prepaid session — the skip sheet promises it.")
    }

    /// Skipping first must never charge afterwards either.
    func testSkippedSessionCannotBeCharged() {
        let event = makePrivateSession()
        var toSkip = event
        XCTAssertTrue(SessionLifecycle.apply(.skip(.holiday), to: &toSkip))
        dm.updateSessionEvent(toSkip)

        // Attendance recorded on an already-skipped session (possible from the
        // attendance surfaces, which do not gate on status).
        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .present)

        XCTAssertEqual(remaining, 10, "A skipped session must never consume a prepaid session.")
    }

    func testCancelledSessionCannotBeCharged() {
        let event = makePrivateSession()
        var toCancel = event
        XCTAssertTrue(SessionLifecycle.apply(.cancel, to: &toCancel))
        dm.updateSessionEvent(toCancel)

        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .present)

        XCTAssertEqual(remaining, 10, "A cancelled session must never consume a prepaid session.")
    }

    /// An unexcused absence still consumes — clause 4. The refund above must
    /// not have loosened that.
    func testUnexcusedAbsenceStillConsumes() {
        let event = makePrivateSession()

        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .absent)

        XCTAssertEqual(remaining, 9,
                       "An unexcused absence consumes the session (agreement clause 4).")
    }

    func testExcusedAbsenceConsumesNothing() {
        let event = makePrivateSession()

        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .excused)

        XCTAssertEqual(remaining, 10, "An excused absence must consume nothing.")
    }

    // MARK: - Undo as one step

    /// Creating a back-dated private session and marking it attended charges a
    /// slot immediately. Deleting that session must return it, so the whole
    /// create-and-charge is undone in one action rather than leaving a charge
    /// behind with no record to find it on.
    func testDeletingASessionReturnsTheSessionItConsumed() {
        let event = makePrivateSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: student.id, state: .present)
        XCTAssertEqual(remaining, 9, "Precondition: the session was charged.")

        dm.deleteSessionEvent(dm.sessionEvents.first { $0.id == event.id }!)

        XCTAssertEqual(remaining, 10,
                       "Deleting a session must return any prepaid session it consumed.")
        XCTAssertFalse(dm.contracts.contains { $0.bundleSessionIds.contains(event.id) },
                       "No contract may still reference a deleted session.")
    }
}
