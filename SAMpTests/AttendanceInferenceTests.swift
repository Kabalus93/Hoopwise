import XCTest
@testable import Hoopwise

/// The rule that lets an unmarked student count as absent (October 2026).
///
/// It reverses "unmarked is NOT absent", so its bounds are what keep it from
/// inventing charges: nothing before roll call starts, nothing before the
/// adoption date, nothing for a session that did not happen, and the charge
/// only an hour after class. The money half runs against a real in-memory
/// store, so it exercises the one redemption authority.
@MainActor
final class AttendanceInferenceTests: XCTestCase {

    private var dm: SwiftDataManager!
    private var marked: Student!
    private var silent: Student!
    private var bundle: Contract!

    /// A class on the adoption day, 18:00–19:00.
    private let start: Date = AttendanceInference.effectiveFrom.addingTimeInterval(18 * 3600)
    private var end: Date { start.addingTimeInterval(3600) }

    override func setUp() async throws {
        try await super.setUp()
        dm = SwiftDataManager.inMemoryForTesting()
        marked = Student(name: "Marked Kid")
        silent = Student(name: "Silent Kid")
        dm.addStudent(marked)
        dm.addStudent(silent)
        // The silent student holds a private bundle, so a charge is visible.
        bundle = Contract(studentId: silent.id, kind: .privateBundle,
                          pricePerSession: 300, bundleSize: 10)
        dm.addContract(bundle)
    }

    override func tearDown() async throws {
        dm = nil; marked = nil; silent = nil; bundle = nil
        try await super.tearDown()
    }

    private func makeSession(start: Date? = nil) -> SessionEvent {
        let s = start ?? self.start
        let event = SessionEvent(programId: nil, title: "Private pair", date: s,
                                 startTime: s, endTime: s.addingTimeInterval(3600),
                                 status: .scheduled,
                                 attendeeIds: [marked.id, silent.id])
        dm.addSessionEvent(event)
        return event
    }

    private func fresh(_ event: SessionEvent) -> SessionEvent {
        dm.sessionEvents.first { $0.id == event.id }!
    }

    private var remaining: Int {
        dm.contracts.first { $0.id == bundle.id }?.bundleRedemptionsRemaining ?? -1
    }

    // MARK: - Display

    func testNothingIsInferredBeforeRollCallStarts() {
        let event = makeSession()
        XCTAssertFalse(AttendanceInference.isInferredAbsent(silent.id, in: fresh(event)))
    }

    func testUnmarkedReadsAbsentOnceAnyoneIsMarked() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        XCTAssertTrue(AttendanceInference.isInferredAbsent(silent.id, in: fresh(event)))
        XCTAssertFalse(AttendanceInference.isInferredAbsent(marked.id, in: fresh(event)))
    }

    func testAnExcuseAlsoStartsRollCall() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .excused)
        XCTAssertTrue(AttendanceInference.isInferredAbsent(silent.id, in: fresh(event)))
    }

    func testSessionsBeforeAdoptionInferNothing() {
        let event = makeSession(start: AttendanceInference.effectiveFrom.addingTimeInterval(-6 * 3600))
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        XCTAssertFalse(AttendanceInference.isInferredAbsent(silent.id, in: fresh(event)))
    }

    func testSkippedSessionInfersNothing() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        var skipped = fresh(event)
        XCTAssertTrue(SessionLifecycle.apply(.skip(.weather), to: &skipped))
        dm.updateSessionEvent(skipped)
        XCTAssertFalse(AttendanceInference.isInferredAbsent(silent.id, in: fresh(event)))
    }

    // MARK: - Money

    func testInferredAbsenceIsNotChargedDuringOrJustAfterClass() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        XCTAssertEqual(dm.chargeInferredAbsences(now: end.addingTimeInterval(59 * 60)), 0)
        XCTAssertEqual(remaining, 10, "Shown as absent, but not charged before the hour is up.")
        XCTAssertFalse(fresh(event).unexcusedAbsences.contains(silent.id))
    }

    func testInferredAbsenceIsChargedAnHourAfterClass() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        XCTAssertEqual(dm.chargeInferredAbsences(now: end.addingTimeInterval(3600)), 1)
        XCTAssertTrue(fresh(event).unexcusedAbsences.contains(silent.id),
                      "The absence is written as an explicit unexcused absence.")
        XCTAssertEqual(remaining, 9, "…and charged through the redemption authority.")
        XCTAssertEqual(dm.chargeInferredAbsences(now: end.addingTimeInterval(7200)), 0,
                       "Idempotent: a written absence is no longer unmarked.")
        XCTAssertEqual(remaining, 9)
    }

    func testForgottenRollCallChargesNobody() {
        let event = makeSession()
        XCTAssertEqual(dm.chargeInferredAbsences(now: end.addingTimeInterval(24 * 3600)), 0)
        XCTAssertEqual(remaining, 10, "Nobody marked → stays unmarked, the alert fires instead.")
        XCTAssertTrue(fresh(event).unexcusedAbsences.isEmpty)
    }

    func testExcusedDuringClassIsNeverCharged() {
        let event = makeSession()
        dm.setStudentAttendanceState(sessionId: event.id, studentId: marked.id, state: .present)
        dm.setStudentAttendanceState(sessionId: event.id, studentId: silent.id, state: .excused)
        XCTAssertEqual(dm.chargeInferredAbsences(now: end.addingTimeInterval(3600)), 0)
        XCTAssertEqual(remaining, 10)
    }
}
