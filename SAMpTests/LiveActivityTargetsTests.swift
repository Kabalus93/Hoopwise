import XCTest
@testable import Hoopwise

/// Which classes may have a Lock Screen / Dynamic Island activity (October
/// 2026, Luther): live ones, and ones about to start — scheduled to appear
/// 10 minutes ahead. Nothing finished, skipped or disallowed.
@MainActor
final class LiveActivityTargetsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(startsIn minutes: Double, length: Double = 90,
                         status: SessionEventStatus = .scheduled) -> SessionEvent {
        let start = now.addingTimeInterval(minutes * 60)
        var event = SessionEvent(programId: UUID(), title: "Class", date: start,
                                 startTime: start, endTime: start.addingTimeInterval(length * 60),
                                 status: status, attendeeIds: [])
        event.status = status
        return event
    }

    private func targets(_ sessions: [SessionEvent], allows: @escaping (SessionEvent) -> Bool = { _ in true }) -> [UUID] {
        SessionStatusMonitor.liveActivityTargets(sessions: sessions, now: now, allows: allows).map(\.id)
    }

    func testLiveAndUpcomingAreTargetsFinishedIsNot() {
        let live = session(startsIn: -30, status: .inProgress)
        let soon = session(startsIn: 5)
        let later = session(startsIn: 180)
        let over = session(startsIn: -120, length: 90, status: .inProgress)
        XCTAssertEqual(targets([later, over, soon, live]), [live.id, soon.id, later.id],
                       "later classes are SCHEDULED for their T−10, not shown now")
    }

    func testSkippedCancelledCompletedAndDisallowedNeverShow() {
        let skipped = session(startsIn: 5, status: .skipped)
        let cancelled = session(startsIn: 5, status: .cancelled)
        let completed = session(startsIn: -10, status: .completed)
        let privateOne = session(startsIn: 5)
        XCTAssertTrue(targets([skipped, cancelled, completed]).isEmpty)
        XCTAssertTrue(targets([privateOne], allows: { _ in false }).isEmpty)
    }

    func testBeyondTheHorizonWaitsAndTheCountIsCapped() {
        XCTAssertTrue(targets([session(startsIn: 13 * 60)]).isEmpty)
        let many = (0..<8).map { session(startsIn: Double(10 + $0 * 60)) }
        XCTAssertEqual(targets(many).count, 4)
    }
}
