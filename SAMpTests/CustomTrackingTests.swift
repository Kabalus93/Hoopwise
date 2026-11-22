import XCTest
@testable import Hoopwise

/// The coach's own tracked drills (23 Nov 2026): the definition on the drill,
/// results per measure, history and peers, the suggested rating, the plan
/// engine's signal, and results surviving whole-session saves.
@MainActor
final class CustomTrackingTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    private let drillId = UUID()

    private func session(day: Int, _ runs: [TrackedRun], status: SessionEventStatus = .completed) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 9))!
        var s = SessionEvent(programId: nil, title: "U10", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        s.curriculum.tracked = runs
        return s
    }

    private func run(_ def: TrackDefinition, _ values: [UUID: [Double?]]) -> TrackedRun {
        var r = TrackedRun(drillId: drillId, definition: def)
        for (id, v) in values { for (i, x) in v.enumerated() { r.set(x, for: id, spot: i) } }
        return r
    }

    func testTheDefinitionRidesInOneTagAndRoundTrips() throws {
        let def = TrackDefinition(measure: .count, spots: ["Left", "Right"], unit: "passes",
                                  higherIsBetter: true, skills: ["passing"])
        var drill = DrillItem(name: "Wall passes", category: .skills)
        drill.tags = ["visibility:private"]
        drill.tags = DrillItem.tags(drill.tags, tracking: def)
        XCTAssertEqual(drill.tags.filter { $0.hasPrefix(DrillItem.trackPrefix) }.count, 1)
        XCTAssertEqual(drill.tracking, def)
        XCTAssertEqual(drill.tracking?.attributes, [.passing])
        drill.tags = DrillItem.tags(drill.tags, tracking: nil)
        XCTAssertNil(drill.tracking)
        XCTAssertEqual(drill.tags, ["visibility:private"], "other tags untouched")
    }

    func testEachMeasureMakesItsResult() {
        let made = TrackDefinition(measure: .madeOf, amount: 10, spots: ["L", "R"])
        XCTAssertEqual(made.result([7, 5]) ?? 0, 0.6, accuracy: 0.0001)
        XCTAssertEqual(made.result([7, nil]) ?? 0, 0.7, accuracy: 0.0001, "only reported spots count")
        XCTAssertEqual(made.text(0.6, chinese: false), "60%")
        let time = TrackDefinition(measure: .timeToFinish)
        XCTAssertEqual(time.result([14.2]), 14.2)
        XCTAssertEqual(time.text(14.2, chinese: false), "14.2 s")
        XCTAssertTrue(time.lowerIsBetter && time.better(12, than: 14))
        let count = TrackDefinition(measure: .count, unit: "touches", higherIsBetter: false)
        XCTAssertTrue(count.lowerIsBetter)
        XCTAssertEqual(count.text(23, chinese: false), "23 touches")
        let inTime = TrackDefinition(measure: .inTime, amount: 60)
        XCTAssertEqual(inTime.text(12, chinese: false), "12 makes")
        XCTAssertNil(inTime.result([nil]))
        // A different amount does not compare.
        XCTAssertNotEqual(TrackDefinition(measure: .madeOf, amount: 10).key, TrackDefinition(measure: .madeOf, amount: 20).key)
        XCTAssertEqual(TrackDefinition(measure: .count, unit: "a").key, TrackDefinition(measure: .count, unit: "b").key)
    }

    func testStandingRanksAmongPeersAndSuggestsARating() throws {
        let def = TrackDefinition(measure: .timeToFinish, skills: ["ballHandling"])
        let sessions = [
            session(day: 2, [run(def, [a: [20], b: [15], c: [18], d: [25]])]),
            session(day: 9, [run(def, [a: [16], b: [15], c: [19], d: [24]])]),
            session(day: 16, [run(def, [a: [14]])], status: .skipped),   // did not happen: ignored
        ]
        let drill = DrillItem(id: drillId, name: "Full-court dribble", category: .skills)
        let st = try XCTUnwrap(CustomTrackHistory.standings(for: a, peers: [a, b, c, d], drills: [drill], sessions: sessions).first)
        XCTAssertEqual(st.recent, 18, accuracy: 0.001, "average of their results (lower is better)")
        XCTAssertEqual(st.rank, 2, "b is faster")
        XCTAssertEqual(st.of, 4)
        XCTAssertEqual(st.sessions, 2)
        let p = try XCTUnwrap(st.percentile)
        XCTAssertEqual(p, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(CustomTrackHistory.suggestion(for: .ballHandling, standings: [st]), 7)
        XCTAssertNil(CustomTrackHistory.suggestion(for: .shooting, standings: [st]), "not linked")
        // The best and the slowest.
        let top = CustomTrackHistory.standings(for: b, peers: [a, b, c, d], drills: [drill], sessions: sessions)
        XCTAssertEqual(CustomTrackHistory.suggestion(for: .ballHandling, standings: top), 9)
        let bottom = CustomTrackHistory.standings(for: d, peers: [a, b, c, d], drills: [drill], sessions: sessions)
        XCTAssertEqual(CustomTrackHistory.suggestion(for: .ballHandling, standings: bottom), 2)
        XCTAssertTrue(CustomTrackHistory.text(st, chinese: false).contains("2nd of 4 same grade"))
    }

    func testFewerThanThreeWithResultsSuggestsNothing() throws {
        let def = TrackDefinition(measure: .count, skills: ["passing"])
        let sessions = [session(day: 2, [run(def, [a: [20], b: [15]])])]
        let st = try XCTUnwrap(CustomTrackHistory.standings(for: a, peers: [a, b], drills: [], sessions: sessions).first)
        XCTAssertNil(st.percentile)
        XCTAssertNil(CustomTrackHistory.suggestion(for: .passing, standings: [st]))
    }

    func testThePlanEngineHearsALowMadeOfDrill() {
        let def = TrackDefinition(measure: .madeOf, amount: 10, skills: ["finishing"])
        let low = [run(def, [a: [2], b: [3], c: [3]])]
        let signals = DrillPlanGenerator.trackedSignals(runs: low, roster: [a, b, c])
        XCTAssertEqual(signals.map(\.0), [.finishing])
        XCTAssertEqual(DrillPlanGenerator.PlanRationale.readable(signals[0].1, zh: false), "low tracked-drill results: Finishing (27% average)")
        XCTAssertTrue(DrillPlanGenerator.trackedSignals(runs: [run(def, [a: [6], b: [7], c: [5]])], roster: [a, b, c]).isEmpty)
        let count = TrackDefinition(measure: .count, skills: ["passing"])
        XCTAssertTrue(DrillPlanGenerator.trackedSignals(runs: [run(count, [a: [1], b: [1], c: [1]])], roster: [a, b, c]).isEmpty,
                      "no common yardstick for counts")
    }

    func testResultsSurviveWholeSessionSavesAndHaveTheirOwnWriter() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let program = Program(name: "Tracked U10", ageGroup: .u10)
        dm.addProgram(program)
        let s = dm.createSession(.init(group: .program(program.id), start: Date().addingTimeInterval(-3600),
                                       durationMinutes: 90)).session
        let def = TrackDefinition(measure: .count, unit: "passes")
        dm.setSessionTracking(sessionId: s.id, runs: [run(def, [a: [23]])])
        // A stale copy closes the session.
        var closed = s
        XCTAssertTrue(SessionLifecycle.apply(.autoClose, to: &closed))
        dm.updateSessionEvent(closed)
        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == s.id })
        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(stored.curriculum.tracked.first?.result(for: a), 23)
        // Encoded beside the built-in shooting runs, under its own key.
        let data = try JSONEncoder().encode(stored.curriculum)
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: data)
        XCTAssertEqual(back.tracked, stored.curriculum.tracked)
    }

    func testADrillsTrackingSurvivesTheLibraryRefresh() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        dm.syncActivityLibrary()
        let library = try XCTUnwrap(dm.drills.first { $0.isLibraryDrill })
        dm.setDrillTracking(library.id, TrackDefinition(measure: .inTime, amount: 30))
        dm.syncActivityLibrary()
        XCTAssertEqual(dm.drills.first { $0.id == library.id }?.tracking?.amount, 30)
    }
}
