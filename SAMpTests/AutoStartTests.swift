import XCTest
@testable import Hoopwise

/// Sessions start by themselves at their time (October 2026) — and only then.
@MainActor
final class AutoStartTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ status: SessionEventStatus) -> SessionEvent {
        var event = SessionEvent(programId: UUID(), title: "Class", date: start,
                                 startTime: start, endTime: start.addingTimeInterval(5400),
                                 status: status, attendeeIds: [])
        event.status = status
        return event
    }

    func testStartsOnceItsTimeArrives() {
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.scheduled), at: start.addingTimeInterval(-60)))
        XCTAssertTrue(SessionLifecycle.shouldAutoStart(session(.scheduled), at: start))
        XCTAssertTrue(SessionLifecycle.shouldAutoStart(session(.scheduled), at: start.addingTimeInterval(3600)))
    }

    func testNeverStartsAfterItEnded() {
        // A class the app never saw running is not started after the fact;
        // the coach marks it completed (or auto-close does, with its marker).
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.scheduled), at: start.addingTimeInterval(5400)))
    }

    func testCancelledOrSkippedNeverStart() {
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.cancelled), at: start))
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.skipped), at: start))
    }

    func testAlreadyRunningOrDoneIsLeftAlone() {
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.inProgress), at: start))
        XCTAssertFalse(SessionLifecycle.shouldAutoStart(session(.completed), at: start))
    }
}
