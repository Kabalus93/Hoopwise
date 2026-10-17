import XCTest
@testable import Hoopwise

/// The attendance history the coach-insight engines read (quick peep,
/// Student Intelligence card). Until October 2026 they counted every session
/// whose stored roster held the student — future ones included — and called
/// anything not present "absent", so the next three scheduled classes read as
/// "Missed 3 of last 3" beside a 0% rate.
@MainActor
final class AttendanceRecordTests: XCTestCase {

    private let kid = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(daysFromNow: Double,
                         present: Bool = false, excused: Bool = false, absent: Bool = false,
                         status: SessionEventStatus = .completed) -> SessionEvent {
        let start = now.addingTimeInterval(daysFromNow * 86_400)
        var event = SessionEvent(programId: UUID(), title: "Class", date: start,
                                 startTime: start, endTime: start.addingTimeInterval(5400),
                                 status: status, attendeeIds: [kid])
        event.status = status
        if present { event.actualAttendeeIds = [kid] }
        if excused { event.excusedAbsences = [kid] }
        if absent { event.unexcusedAbsences = [kid] }
        return event
    }

    func testFutureClassesAreNeitherAttendedNorMissed() {
        let sessions = [session(daysFromNow: -7, present: true),
                        session(daysFromNow: 1, status: .scheduled),
                        session(daysFromNow: 3, status: .scheduled),
                        session(daysFromNow: 8, status: .scheduled)]
        let records = AttendanceRecord.marked(for: kid, in: sessions, asOf: now)
        XCTAssertEqual(records.map(\.status), [.present])
    }

    func testUnmarkedIsNotAbsent() {
        let records = AttendanceRecord.marked(for: kid, in: [session(daysFromNow: -2)], asOf: now)
        XCTAssertTrue(records.isEmpty)
    }

    func testMarksAreKeptAsRecorded() {
        let sessions = [session(daysFromNow: -3, absent: true),
                        session(daysFromNow: -2, excused: true),
                        session(daysFromNow: -1, present: true)]
        let records = AttendanceRecord.marked(for: kid, in: sessions, asOf: now)
        XCTAssertEqual(records.map(\.status), [.absent, .excused, .present],
                       "oldest first — the engines read recent as suffix")
    }

    func testSkippedClassesAreLeftOut() {
        let skipped = session(daysFromNow: -2, present: true, status: .cancelled)
        XCTAssertTrue(AttendanceRecord.marked(for: kid, in: [skipped], asOf: now).isEmpty)
    }
}
