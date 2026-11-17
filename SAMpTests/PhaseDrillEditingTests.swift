import XCTest
@testable import Hoopwise

/// Changing a phase's plans in one go (18 Nov 2026, Luther): only upcoming
/// scheduled sessions change; a recurring drill is never doubled; removal
/// takes it out of both blocks.
@MainActor
final class PhaseDrillEditingTests: XCTestCase {
    private let phase = UUID(), other = UUID()
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func session(days: Double, phase: UUID? = nil, status: SessionEventStatus = .scheduled,
                         warmup: [UUID] = [], skills: [UUID] = []) -> SessionEvent {
        let start = now.addingTimeInterval(days * 86_400)
        var s = SessionEvent(programId: UUID(), title: "U8", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        s.microCycleId = phase ?? self.phase
        s.curriculum.warmupDrillIds = warmup
        s.curriculum.skillDrillIds = skills
        return s
    }

    func testOnlyUpcomingScheduledSessionsOfThePhaseChange() {
        let sessions = [
            session(days: 3), session(days: 1),
            session(days: -2),                         // already happened
            session(days: 2, status: .completed),      // marked done
            session(days: 4, status: .skipped),        // will not happen
            session(days: 5, phase: other),            // another phase
        ]
        let editable = PhaseDrillEditing.editableSessions(sessions, phaseId: phase, now: now)
        XCTAssertEqual(editable.count, 2)
        XCTAssertLessThan(editable[0].startTime, editable[1].startTime, "soonest first")
    }

    func testUsageCountsSessionsMostUsedFirst() {
        let a = UUID(), b = UUID()
        let sessions = [session(days: 1, warmup: [b, a]), session(days: 2, skills: [a]), session(days: 3, warmup: [a])]
        let usage = PhaseDrillEditing.usage(in: sessions)
        XCTAssertEqual(usage.map { $0.drillId }, [a, b])
        XCTAssertEqual(usage.first?.sessionIds.count, 3)
    }

    func testAddingNeverDoublesAndRemovingClearsBothBlocks() {
        let a = UUID(), b = UUID()
        var plan = SessionCurriculum()
        plan.skillDrillIds = [a]
        XCTAssertEqual(PhaseDrillEditing.adding(a, to: plan, block: .warmup), plan, "already planned in Skills")
        let added = PhaseDrillEditing.adding(b, to: plan, block: .warmup)
        XCTAssertEqual(added.warmupDrillIds, [b])
        var both = added
        both.skillDrillIds.append(b)
        let removed = PhaseDrillEditing.removing(b, from: both)
        XCTAssertFalse(removed.warmupDrillIds.contains(b))
        XCTAssertFalse(removed.skillDrillIds.contains(b))
        XCTAssertEqual(removed.skillDrillIds, [a])
    }
}
