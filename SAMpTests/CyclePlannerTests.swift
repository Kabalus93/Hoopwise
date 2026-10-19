import XCTest
import SwiftData
@testable import Hoopwise

/// The cycle planner (October 2026): phases fit the coach's dates and level,
/// sessions land on the program's days, every session gets a plan, and the
/// next-cycle reminder appears two weeks before the target.
@MainActor
final class CyclePlannerTests: XCTestCase {

    private var dm: SwiftDataManager!
    private let cal = Calendar.current
    private lazy var start = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!   // a Monday

    override func setUp() async throws {
        dm = SwiftDataManager.inMemoryForTesting()
        dm.syncActivityLibrary()
    }

    private func program(_ age: AgeGroup = .u8) -> Program {
        var p = Program(name: "Test \(age.rawValue)", ageGroup: age)
        p.recurringDays = [.monday, .wednesday]
        p.status = .active
        p.defaultSessionTime = cal.date(bySettingHour: 18, minute: 30, second: 0, of: start)
        p.defaultSessionDurationMinutes = 90
        return p
    }

    private func weeks(_ n: Int) -> Date { cal.date(byAdding: .day, value: n * 7 - 1, to: start)! }

    func testPhasesFitTheDatesExactly() {
        let plan = CyclePlanner.plan(.init(program: program(), start: start, target: weeks(12), level: 3, emphasis: []))
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(plan.first?.start, start)
        XCTAssertEqual(plan.last?.end, cal.startOfDay(for: weeks(12)), "the last phase ends ON the target")
        XCTAssertEqual(plan.reduce(0) { $0 + $1.weeks }, 12)
        XCTAssertEqual(plan.reduce(0) { $0 + $1.sessionCount }, 24, "Mon + Wed for 12 weeks")
        for (a, b) in zip(plan, plan.dropFirst()) {
            XCTAssertEqual(cal.date(byAdding: .day, value: 1, to: a.end), b.start, "phases are back to back")
        }
    }

    func testLevelChoosesTheChainAndEmphasisJoinsTheFocus() {
        let onAge = CyclePlanner.plan(.init(program: program(), start: start, target: weeks(12), level: 3, emphasis: []))
        let above = CyclePlanner.plan(.init(program: program(), start: start, target: weeks(12), level: 5, emphasis: [.defence]))
        XCTAssertNotEqual(onAge.map { $0.template.title.en }, above.map { $0.template.title.en },
                          "level 5 runs the next age group's arc")
        XCTAssertTrue(above.allSatisfy { $0.focus.contains(.defense) })
        XCTAssertTrue(above.allSatisfy { !$0.suggestedActivityIds.isEmpty })
    }

    func testShortCyclesKeepTheFirstPhases() {
        let plan = CyclePlanner.plan(.init(program: program(), start: start, target: weeks(2), level: 3, emphasis: []))
        XCTAssertEqual(plan.count, 2)
        XCTAssertTrue(plan.allSatisfy { $0.weeks == 1 })
    }

    func testApplyCreatesPhasesSessionsAndPlansAndAdoptsExisting() {
        let p = program()
        dm.addProgram(p)
        // A session already on the first Monday (e.g. from the class list), with no plan.
        let existingStart = cal.date(bySettingHour: 18, minute: 30, second: 0, of: start)!
        _ = dm.createSession(SessionCreation.Intent(group: .program(p.id), start: existingStart, durationMinutes: 90))
        let input = CyclePlanner.Input(program: p, start: start, target: weeks(8), level: 3, emphasis: [])
        let result = CyclePlanner.apply(CyclePlanner.plan(input), input: input, dataManager: dm)

        let sessions = dm.sessionEvents.filter { $0.programId == p.id }
        XCTAssertEqual(sessions.count, 16, "8 weeks × Mon/Wed, the existing Monday adopted, not doubled")
        XCTAssertTrue(sessions.allSatisfy { $0.microCycleId != nil }, "every session sits in a phase")
        XCTAssertTrue(sessions.allSatisfy { $0.curriculum.totalDrillCount > 0 }, "every session has a plan")
        XCTAssertEqual(result.sessionsPlanned, 16)
        XCTAssertEqual(dm.programs.first { $0.id == p.id }?.skillTargets?.level, 3)
    }

    func testNextCycleReminderAppearsTwoWeeksBeforeTheTarget() {
        let p = program()
        dm.addProgram(p)
        let input = CyclePlanner.Input(program: p, start: start, target: weeks(8), level: 3, emphasis: [])
        CyclePlanner.apply(CyclePlanner.plan(input), input: input, dataManager: dm)
        let target = weeks(8)
        let early = AttentionEngine.items(dataManager: dm, now: target.addingTimeInterval(-30 * 86_400))
        XCTAssertFalse(early.contains { $0.kind == .nextCycle })
        let close = AttentionEngine.items(dataManager: dm, now: target.addingTimeInterval(-10 * 86_400))
        XCTAssertTrue(close.contains { $0.kind == .nextCycle && $0.programId == p.id })
    }
}
