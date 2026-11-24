import XCTest
@testable import Hoopwise

/// How the coach uses a drill teaches the plan engine (19 Nov 2026, Luther).
@MainActor
final class DrillPreferenceTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheRatingRoundTripsThroughTags() {
        var d = DrillItem(name: "Walks", category: .warmup)
        XCTAssertEqual(d.preference, .normal)
        d.tags = DrillItem.tags(["library", "attr:passing=2"], preference: .never, reason: .tooEasy)
        XCTAssertEqual(d.preference, .never)
        XCTAssertEqual(d.preferenceReason, .tooEasy)
        XCTAssertTrue(d.tags.contains("attr:passing=2"), "other tags stay")
        d.tags = DrillItem.tags(d.tags, preference: .more, reason: .tooEasy)
        XCTAssertEqual(d.preference, .more)
        XCTAssertNil(d.preferenceReason, "a reason only goes with less or never")
        d.tags = DrillItem.tags(d.tags, preference: .normal, reason: nil)
        XCTAssertFalse(d.tags.contains { $0.hasPrefix(DrillItem.preferencePrefix) }, "normal writes nothing")
    }

    private func plan(_ drills: [DrillItem], runs: Int = 40) -> [UUID: Int] {
        let program = Program(name: "U10", ageGroup: .u10)
        var counts: [UUID: Int] = [:]
        for k in 0..<runs {
            var s = SessionEvent(programId: program.id, title: "Class", date: t0, startTime: t0,
                                 endTime: t0.addingTimeInterval(5400), status: .scheduled, attendeeIds: [])
            s.curriculum = SessionCurriculum(warmupMinutes: 20, skillsMinutes: 30, gameMinutes: 0)
            let ctx = DrillPlanGenerator.Context(session: s, program: program, phase: nil, enrolledStudents: [],
                                                 players: [], allDrills: drills, programHistory: [])
            var x = 0.1 + Double(k) * 0.023
            let c = DrillPlanGenerator.generatePlan(in: ctx, random: {
                x = (x * 9301 + 0.49297).truncatingRemainder(dividingBy: 1); return x }).curriculum
            for id in c.warmupDrillIds + c.skillDrillIds { counts[id, default: 0] += 1 }
        }
        return counts
    }

    func testTheEngineFollowsTheCoach() throws {
        let library = ActivityLibrary.shared.plannable.map { ActivityLibrary.drill(for: $0) }
        let base = plan(library)
        // The drill the engine liked most, and one it used sometimes.
        let favourite = try XCTUnwrap(base.max { $0.value < $1.value }?.key)
        let sometimes = try XCTUnwrap(base.filter { $0.value >= 2 && $0.value <= 10 }.min { $0.value < $1.value }?.key)

        func rated(_ id: UUID, _ p: DrillPreference) -> [DrillItem] {
            library.map { d in
                guard d.id == id else { return d }
                var r = d
                r.tags = DrillItem.tags(r.tags, preference: p, reason: nil)
                return r
            }
        }
        XCTAssertNil(plan(rated(favourite, .never))[favourite], "never is never planned")
        XCTAssertLessThan(plan(rated(favourite, .less))[favourite] ?? 0, base[favourite] ?? 0, "use less: less often")
        XCTAssertGreaterThan(plan(rated(sometimes, .more))[sometimes] ?? 0, base[sometimes] ?? 0, "use more: more often")
    }

    // MARK: The reason steers the engine (25 Nov 2026)

    func testAUseLessRatingFollowsItsReasonAtTheGroupsLevel() {
        func drill(_ pref: DrillPreference, _ why: DrillPreferenceReason?) -> DrillItem {
            var d = DrillItem(name: "D", category: .shooting)
            d.tags = DrillItem.tags([], preference: pref, reason: why)
            return d
        }
        XCTAssertEqual(drill(.less, .tooEasy).preference(atLevel: 2), .normal, "not too easy for a weaker group")
        XCTAssertEqual(drill(.less, .tooEasy).preference(atLevel: 3), .less)
        XCTAssertEqual(drill(.less, .tooHard).preference(atLevel: 4), .normal, "not too hard for a stronger group")
        XCTAssertEqual(drill(.less, .notNow).preference(atLevel: 5), .normal)
        XCTAssertEqual(drill(.less, .tooHard).preference(atLevel: 3), .less)
        XCTAssertEqual(drill(.less, .boring).preference(atLevel: 1), .less, "boring at any level")
        XCTAssertEqual(drill(.less, nil).preference(atLevel: 5), .less)
        XCTAssertEqual(drill(.never, .tooEasy).preference(atLevel: 1), .never, "never stays never")
        XCTAssertEqual(drill(.more, nil).preference(atLevel: 3), .more)

        XCTAssertEqual(DrillLevelHint.make(tooEasy: 3, tooHard: 0), .raise(3))
        XCTAssertEqual(DrillLevelHint.make(tooEasy: 1, tooHard: 4), .lower(4))
        XCTAssertNil(DrillLevelHint.make(tooEasy: 3, tooHard: 2), "mixed signals say nothing")
        XCTAssertNil(DrillLevelHint.make(tooEasy: 2, tooHard: 0))
    }
}
