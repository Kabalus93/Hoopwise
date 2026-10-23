import XCTest
@testable import Hoopwise

/// A program edit reaches its upcoming sessions — but only the ones that
/// still follow it, and never history.
@MainActor
final class ProgramSessionSyncTests: XCTestCase {

    private let cal = Calendar.current
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: day < 24 ? 10 : 10, day: day, hour: hour, minute: minute))!
    }

    private func program() -> Program {
        var p = Program(name: "U8", ageGroup: .u8)
        p.defaultSessionTime = at(1, 18)
        p.defaultSessionDurationMinutes = 60
        p.locationName = "酷迅"
        p.recurringDays = [.saturday]
        return p
    }

    private func session(_ p: Program, _ day: Int, hour: Int = 18, minutes: Int = 60,
                         status: SessionEventStatus = .scheduled, venue: String? = "酷迅",
                         roster: [UUID] = []) -> SessionEvent {
        let start = at(day, hour)
        var s = SessionEvent(programId: p.id, title: "U8", date: start, startTime: start,
                             endTime: start.addingTimeInterval(TimeInterval(minutes * 60)),
                             status: status, attendeeIds: roster)
        s.location = venue
        return s
    }

    func testTimeChangeMovesFollowersOnly() {
        let before = program()
        var after = before
        after.defaultSessionTime = at(1, 18, 30)
        let past = session(before, 17, status: .completed)
        let next = session(before, 31)
        let ownTime = session(before, 31, hour: 19)
        let changed = ProgramSessionSync.follow(before: before, after: after,
                                                sessions: [past, next, ownTime], now: now)
        XCTAssertEqual(changed.map(\.id), [next.id])
        let c = cal.dateComponents([.hour, .minute], from: changed[0].startTime)
        XCTAssertEqual([c.hour, c.minute], [18, 30])
        XCTAssertEqual(changed[0].endTime.timeIntervalSince(changed[0].startTime), 3600)
        XCTAssertEqual(changed[0].date, changed[0].startTime)
    }

    func testLengthVenueAndRoster() {
        let kid = UUID(), newKid = UUID()
        var before = program()
        before.enrolledStudentIds = [kid]
        var after = before
        after.defaultSessionDurationMinutes = 90
        after.locationName = "体育馆"
        after.enrolledStudentIds = [kid, newKid]
        let follows = session(before, 31, roster: [kid])
        let guest = session(before, 31, venue: "Other gym", roster: [kid, UUID()])
        let changed = ProgramSessionSync.follow(before: before, after: after,
                                                sessions: [follows, guest], now: now)
        let f = changed.first { $0.id == follows.id }!
        XCTAssertEqual(f.endTime.timeIntervalSince(f.startTime), 90 * 60)
        XCTAssertEqual(f.location, "体育馆")
        XCTAssertEqual(Set(f.attendeeIds), [kid, newKid])
        let g = changed.first { $0.id == guest.id }!   // length follows, venue and roster are its own
        XCTAssertEqual(g.location, "Other gym")
        XCTAssertEqual(g.attendeeIds.count, 2)
        XCTAssertFalse(g.attendeeIds.contains(newKid))
    }

    func testUnrelatedEditChangesNothing() {
        let before = program()
        var after = before
        after.name = "U8 Elite"
        XCTAssertTrue(ProgramSessionSync.follow(before: before, after: after,
                                                sessions: [session(before, 31)], now: now).isEmpty)
    }

    func testWeekdaySwapMovesTheClassWithItsPlan() throws {
        let p = program()
        var sat = session(p, 31)                       // Saturday 31 Oct
        sat.curriculum = SessionCurriculum(skillDrillIds: [UUID()])
        let moved = try XCTUnwrap(ProgramSessionSync.move(programId: p.id, from: [.saturday], to: [.sunday],
                                                          sessions: [sat], now: now))
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(cal.component(.day, from: moved[0].startTime), 1)   // Sunday 1 Nov
        XCTAssertEqual(moved[0].curriculum, sat.curriculum)
        XCTAssertNil(ProgramSessionSync.move(programId: p.id, from: [.saturday], to: [.sunday, .monday],
                                             sessions: [sat], now: now))
    }

    func testRemovedClassesKeepThePlanOrder() {
        let p = program()
        let plans = (0..<3).map { _ in SessionCurriculum(skillDrillIds: [UUID()]) }
        var a = session(p, 27), b = session(p, 29), c = session(p, 31)
        a.curriculum = plans[0]; b.curriculum = plans[1]; c.curriculum = plans[2]
        let r = ProgramSessionSync.reflowPlans(removing: [a.id], programId: p.id,
                                               sessions: [a, b, c], now: now)
        XCTAssertEqual(r.updated.map(\.id), [b.id, c.id])
        XCTAssertEqual(r.updated.map(\.curriculum), [plans[0], plans[1]])
        XCTAssertEqual(r.leftOver, 1)
    }

    /// Through the manager: a time edit reaches the stored session.
    func testManagerUpdateProgramTricklesDown() {
        let dm = SwiftDataManager.inMemoryForTesting()
        var p = program()
        p.startDate = nil
        dm.addProgram(p)
        let start = cal.date(byAdding: .day, value: 7, to: cal.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!)!
        let created = dm.createSession(.init(group: .program(p.id), start: start, durationMinutes: 60)).session
        var edited = dm.programs.first { $0.id == p.id }!
        edited.defaultSessionTime = cal.date(bySettingHour: 18, minute: 45, second: 0, of: Date())
        dm.updateProgram(edited)
        let s = dm.sessionEvents.first { $0.id == created.id }!
        XCTAssertEqual(cal.component(.minute, from: s.startTime), 45)
        XCTAssertEqual(cal.component(.hour, from: s.startTime), 18)
    }
}
