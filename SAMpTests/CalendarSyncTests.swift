import XCTest
@testable import Hoopwise

/// What Hoopwise writes to Apple Calendar: the right sessions, matched to
/// existing events by their hoopwise:// URL, never duplicated.
@MainActor
final class CalendarSyncTests: XCTestCase {

    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!

    private func session(daysFromNow: Double, status: SessionEventStatus = .scheduled, title: String = "U8") -> SessionEvent {
        let start = now.addingTimeInterval(daysFromNow * 86_400)
        var s = SessionEvent(programId: nil, title: title, date: start, startTime: start,
                             endTime: start.addingTimeInterval(5400), status: status, attendeeIds: [UUID(), UUID()])
        s.location = "酷迅"
        return s
    }

    private func existing(_ e: CalendarSync.Entry, id: String) -> CalendarSync.Existing {
        .init(eventId: id, sessionId: e.sessionId, title: e.title, start: e.start, end: e.end,
              location: e.location, notes: e.notes)
    }

    func testWindowAndSessionsThatDidNotHappen() {
        let keep = [session(daysFromNow: -6), session(daysFromNow: 1), session(daysFromNow: 59)]
        let drop = [session(daysFromNow: -8), session(daysFromNow: 61),
                    session(daysFromNow: 2, status: .cancelled), session(daysFromNow: 3, status: .skipped)]
        let entries = CalendarSync.entries(sessions: drop + keep, programs: [], now: now)
        XCTAssertEqual(entries.map(\.sessionId), keep.map(\.id))
        XCTAssertEqual(entries[1].location, "酷迅")
        XCTAssertEqual(entries[1].end.timeIntervalSince(entries[1].start), 5400)
        XCTAssertEqual(entries[1].url.absoluteString, "hoopwise://session/\(keep[1].id.uuidString)")
    }

    func testPlanCreatesUpdatesAndDeletes() {
        let a = CalendarSync.entries(sessions: [session(daysFromNow: 1)], programs: [], now: now)[0]
        var b = CalendarSync.entries(sessions: [session(daysFromNow: 2)], programs: [], now: now)[0]
        let gone = CalendarSync.entries(sessions: [session(daysFromNow: 3)], programs: [], now: now)[0]
        let moved = existing(b, id: "B")
        b.start = b.start.addingTimeInterval(1800); b.end = b.end.addingTimeInterval(1800)
        let notOurs = CalendarSync.Existing(eventId: "X", sessionId: nil, title: "Dentist",
                                            start: now, end: now, location: nil, notes: nil)
        let changes = CalendarSync.plan(desired: [a, b],
                                        existing: [moved, existing(gone, id: "G"), notOurs])
        XCTAssertEqual(changes.create, [a])
        XCTAssertEqual(changes.update.map(\.eventId), ["B"])
        XCTAssertEqual(changes.update.first?.entry.start, b.start)
        XCTAssertEqual(changes.delete, ["G", "X"])
    }

    func testUnchangedIsEmptyAndCopiesAreRemoved() {
        let a = CalendarSync.entries(sessions: [session(daysFromNow: 1)], programs: [], now: now)[0]
        XCTAssertTrue(CalendarSync.plan(desired: [a], existing: [existing(a, id: "1")]).isEmpty)
        let changes = CalendarSync.plan(desired: [a], existing: [existing(a, id: "1"), existing(a, id: "2")])
        XCTAssertEqual(changes.delete, ["2"])
        XCTAssertTrue(changes.create.isEmpty && changes.update.isEmpty)
    }

    func testSessionIdFromURL() {
        let id = UUID()
        XCTAssertEqual(CalendarSync.sessionId(from: URL(string: "hoopwise://session/\(id.uuidString)")), id)
        XCTAssertNil(CalendarSync.sessionId(from: URL(string: "hoopwise://athlete/\(id.uuidString)")))
        XCTAssertNil(CalendarSync.sessionId(from: URL(string: "https://example.com")))
        XCTAssertNil(CalendarSync.sessionId(from: nil))
    }
}
