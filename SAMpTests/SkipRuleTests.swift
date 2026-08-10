import XCTest
@testable import Hoopwise

/// Phase 2.6. A skipped session and a cancelled one are the same fact — it did
/// not happen — and before this the app agreed with itself in only two places,
/// both of them about money.
///
/// The case that matters: mark attendance, then skip. Phase 0 refunds the
/// bundle slot, so the client is not charged; but the marks stay on the record
/// (skip preserves attendance deliberately), and every statistic counted them.
/// Refunded and still counted is the contradiction these pin shut.
@MainActor
final class SkipRuleTests: XCTestCase {

    private let studentId = UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
    private let start = Date(timeIntervalSince1970: 1_777_000_000)

    private func session(_ status: SessionEventStatus,
                         present: Bool = false,
                         absent: Bool = false) -> SessionEvent {
        SessionEvent(title: "Training", date: start,
                     startTime: start, endTime: start.addingTimeInterval(5400),
                     status: status,
                     attendeeIds: [studentId],
                     actualAttendeeIds: present ? [studentId] : [],
                     unexcusedAbsences: absent ? [studentId] : [])
    }

    private var now: Date { start.addingTimeInterval(86_400) }

    // MARK: - The predicate

    func testOnlySkippedAndCancelledCountAsDidNotHappen() {
        XCTAssertTrue(SessionLifecycle.didNotHappen(.skipped))
        XCTAssertTrue(SessionLifecycle.didNotHappen(.cancelled))
        XCTAssertFalse(SessionLifecycle.didNotHappen(.scheduled))
        XCTAssertFalse(SessionLifecycle.didNotHappen(.inProgress))
        XCTAssertFalse(SessionLifecycle.didNotHappen(.completed))
    }

    // MARK: - Statistics agree with the money

    func testASkippedSessionDoesNotWeighOnAttendanceRate() {
        // Two real absences and one skipped-after-marking session.
        let sessions = [session(.completed, present: true),
                        session(.completed, absent: true),
                        session(.skipped, absent: true)]

        let rate = AttendanceMath.rate(for: studentId, in: sessions, asOf: now)
        XCTAssertEqual(rate.of, 2, "The skipped session leaves the denominator…")
        XCTAssertEqual(rate.percent, 50, "…so the rate is 1 of 2, not 1 of 3.")
    }

    func testCancelledAndSkippedAreTreatedIdentically() {
        let withCancelled = [session(.completed, present: true), session(.cancelled, absent: true)]
        let withSkipped = [session(.completed, present: true), session(.skipped, absent: true)]

        let a = AttendanceMath.rate(for: studentId, in: withCancelled, asOf: now)
        let b = AttendanceMath.rate(for: studentId, in: withSkipped, asOf: now)
        XCTAssertEqual(a.percent, b.percent)
        XCTAssertEqual(a.of, b.of)
    }

    func testASkippedSessionDoesNotExtendAMissStreak() {
        // Skipping the most recent session must not read as a third miss.
        let sessions = [session(.completed, absent: true),
                        session(.completed, absent: true),
                        session(.skipped, absent: true)]
        XCTAssertEqual(AttendanceMath.consecutiveMisses(for: studentId, in: sessions, asOf: now), 2)
    }

    // MARK: - What the rule is NOT

    func testSkipStillRecordsItsReasonOnTheSession() {
        var event = session(.scheduled)
        XCTAssertTrue(SessionLifecycle.apply(.skip(.holiday), to: &event))
        XCTAssertEqual(event.status, .skipped)
        XCTAssertTrue(event.notes?.contains("Skipped:") ?? false,
                      "The record is what lets the coach explain the gap later — this is not a visibility rule.")
    }

    func testSkipPreservesAttendanceMarks() {
        var event = session(.scheduled, present: true)
        XCTAssertTrue(SessionLifecycle.apply(.skip(.weather), to: &event))
        XCTAssertEqual(event.actualAttendeeIds, [studentId],
                       "Skip does not erase what was recorded; the rule is about what those marks COUNT toward.")
    }

    func testASkippedSessionIsNotAutoClosed() {
        XCTAssertFalse(SessionLifecycle.isAllowed(.autoClose, from: .skipped),
                       "The close-out backlog is scheduled/inProgress only.")
    }
}
