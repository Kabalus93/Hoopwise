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

    // MARK: The type drives it (24 Nov 2026)

    func testEveryKindHasASensiblePreset() {
        for kind in TrackKind.allCases {
            let d = kind.preset(chinese: false)
            XCTAssertEqual(d.kind, kind)
            XCTAssertEqual(d.measure, kind.measures[0], "\(kind) starts on its usual measure")
            XCTAssertTrue(Set(d.some).isSubset(of: Set(d.skills)), "\(kind)")
            if kind != .other { XCTAssertFalse(d.mainAttributes.isEmpty, "\(kind) has a main skill") }
            for m in kind.measures { XCTAssertEqual(kind.preset(measure: m, chinese: false).measure, m) }
        }
        let shooting = TrackKind.shooting.preset(chinese: false)
        XCTAssertEqual(shooting.mainAttributes, [.shooting])
        XCTAssertEqual(shooting.weight(for: .footwork), 0.5)
        XCTAssertEqual(shooting.weight(for: .passing), 0)
        let sprint = TrackKind.conditioning.preset(chinese: false)
        XCTAssertEqual(sprint.measure, .timeToFinish)
        XCTAssertEqual(sprint.course, .downAndBack)
        XCTAssertEqual(sprint.mainAttributes, [.footwork])
        XCTAssertEqual(sprint.weight(for: .defense), 0.5)
        XCTAssertEqual(TrackKind.conditioning.preset(measure: .inTime, chinese: false).unit, "laps")
        let errors = TrackKind.ballHandling.preset(measure: .count, chinese: false)
        XCTAssertTrue(errors.lowerIsBetter, "errors: fewer is better")
        // An unknown measure for the kind falls back to its usual one.
        XCTAssertEqual(TrackKind.finishing.preset(measure: .timeToFinish, chinese: false).measure, .madeOf)
    }

    func testAnOlderDefinitionReadsAsBeforeAndTheNewFieldsRoundTrip() throws {
        // What yesterday's build wrote.
        let old = #"{"measure":"count","amount":10,"spots":["Left","Right"],"unit":"passes","higherIsBetter":true,"skills":["passing"]}"#
        let d = try JSONDecoder().decode(TrackDefinition.self, from: Data(old.utf8))
        XCTAssertEqual(d.kind, .other)
        XCTAssertEqual(d.weight(for: .passing), 1, "every old link is a main one")
        XCTAssertEqual(d.key, "count|0|2", "its key — and so its history — is unchanged")
        // A plain definition writes no new keys.
        let json = String(data: try JSONEncoder().encode(d), encoding: .utf8)!
        XCTAssertFalse(json.contains("kind") || json.contains("zones") || json.contains("some") || json.contains("course"))
        var full = TrackKind.shooting.preset(chinese: false)
        full.zones = [5, 7, 9]
        let back = try JSONDecoder().decode(TrackDefinition.self, from: try JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
        XCTAssertEqual(back.spotCount, 3)
        XCTAssertEqual(back.spotName(1, chinese: false), "Top")
        XCTAssertEqual(back.key, "madeOf|10|3|z5.7.9")
        // The course is part of what compares.
        var half = TrackKind.conditioning.preset(chinese: false); half.course = .halfCourt
        XCTAssertNotEqual(half.key, TrackKind.conditioning.preset(chinese: false).key)
    }

    func testAShootingDrillsZonesJoinTheAthletesShotChart() {
        var def = TrackKind.shooting.preset(chinese: false)
        def.zones = [5, 9]                                    // both corners, 10 shots each
        let corners = session(day: 3, [run(def, [a: [4, 7]])])
        var map = ShootingHistory.zoneMap(for: a, sessions: [corners])
        XCTAssertEqual(map[5], ShotZoneValue(made: 4, attempted: 10))
        XCTAssertEqual(map[9], ShotZoneValue(made: 7, attempted: 10))
        XCTAssertNil(map[7])
        XCTAssertEqual(ShootingHistory.latestMapSession(for: a, sessions: [corners])?.id, corners.id)
        // A finishing drill lands at the rim, both hands pooled.
        let layups = session(day: 4, [run(TrackKind.finishing.preset(chinese: false), [a: [8, 5]])])
        map = ShootingHistory.zoneMap(for: a, sessions: [corners, layups])
        XCTAssertEqual(map[0], ShotZoneValue(made: 13, attempted: 20))
        // Makes in a time have no attempts: off the map.
        var timed = TrackKind.shooting.preset(measure: .inTime, chinese: false); timed.zones = [7]
        XCTAssertNil(ShootingHistory.zoneMap(for: a, sessions: [session(day: 5, [run(timed, [a: [12]])])])[7])
        // A passing drill never touches it; a skipped class neither.
        XCTAssertTrue(ShootingHistory.zoneMap(for: a, sessions: [session(day: 6, [run(TrackKind.passing.preset(measure: .madeOf, chinese: false), [a: [9]])])]).allSatisfy { $0 == nil })
        XCTAssertTrue(ShootingHistory.zoneMap(for: a, sessions: [session(day: 7, [run(def, [a: [4, 7]])], status: .skipped)]).allSatisfy { $0 == nil })
    }

    func testMainWeighsMoreThanSomeInTheSuggestion() throws {
        // a is the best shooter (main: shooting) and the slowest sprinter
        // (main: footwork, some: defense).
        var shoot = TrackKind.shooting.preset(chinese: false); shoot.some = []; shoot.skills = ["shooting", "footwork"]; shoot.some = ["footwork"]
        let sprint = TrackKind.conditioning.preset(chinese: false)
        let sprintId = UUID()
        var sprintRun = TrackedRun(drillId: sprintId, definition: sprint)
        for (id, t) in [(a, 20.0), (b, 14.0), (c, 15.0), (d, 16.0)] { sprintRun.set(t, for: id, spot: 0) }
        let sessions = [session(day: 2, [run(shoot, [a: [9], b: [3], c: [4], d: [5]]), sprintRun])]
        let st = CustomTrackHistory.standings(for: a, peers: [a, b, c, d], drills: [], sessions: sessions)
        XCTAssertEqual(st.count, 2)
        XCTAssertEqual(CustomTrackHistory.suggestion(for: .shooting, standings: st), 9, "top of the main drill")
        // Footwork: main in the sprint (bottom, weight 1), some in shooting (top, 0.5) → (0·1 + 1·0.5) / 1.5.
        XCTAssertEqual(CustomTrackHistory.suggestion(for: .footwork, standings: st), 4)
        // Defense is only a "some" link: not enough to move a rating.
        XCTAssertNil(CustomTrackHistory.suggestion(for: .defense, standings: st))
    }

    func testThePlanEngineHearsAGroupGettingWorse() {
        let sprint = TrackKind.conditioning.preset(chinese: false)
        let slower = [run(sprint, [a: [14], b: [15], c: [16]]), run(sprint, [a: [16], b: [17], c: [18]])]
        let signals = DrillPlanGenerator.trackedSignals(runs: slower, roster: [a, b, c])
        XCTAssertEqual(signals.map(\.0), [.footwork], "the sprint's MAIN skill only — defense is 'some'")
        XCTAssertEqual(DrillPlanGenerator.PlanRationale.readable(signals[0].1, zh: false),
                       "tracked-drill results down 13% on last time: Footwork & athleticism")
        let faster = [run(sprint, [a: [16], b: [17], c: [18]]), run(sprint, [a: [14], b: [15], c: [16]])]
        XCTAssertTrue(DrillPlanGenerator.trackedSignals(runs: faster, roster: [a, b, c]).isEmpty)
        // A different course is another test: no "previous" to compare.
        var half = sprint; half.course = .halfCourt
        XCTAssertTrue(DrillPlanGenerator.trackedSignals(runs: [run(sprint, [a: [14], b: [15], c: [16]]),
                                                               run(half, [a: [30], b: [30], c: [30]])], roster: [a, b, c]).isEmpty)
    }

    func testTheConnectorsTrackingObject() throws {
        let d = try TrackDefinition.parsed(["kind": "shooting", "amount": 20, "zones": [5, 9], "main": ["shooting"], "some": ["footwork"]],
                                           chinese: false)
        XCTAssertEqual(d.kind, .shooting); XCTAssertEqual(d.measure, .madeOf); XCTAssertEqual(d.amount, 20)
        XCTAssertEqual(d.zones, [5, 9]); XCTAssertEqual(d.mainAttributes, [.shooting]); XCTAssertEqual(d.some, ["footwork"])
        XCTAssertEqual(d.asValues["zones"] as? [Int], [5, 9])
        let sprint = try TrackDefinition.parsed(["kind": "conditioning", "course": "fullCourt"], chinese: false)
        XCTAssertEqual(sprint.course, .fullCourt); XCTAssertEqual(sprint.measure, .timeToFinish)
        func message(_ args: [String: Any]) -> String? {
            do { _ = try TrackDefinition.parsed(args, chinese: false); return nil }
            catch { return (error as? TrackDefinition.ParseError)?.message }
        }
        XCTAssertTrue(message(["kind": "dunking"])?.hasPrefix("tracking.kind") == true)
        XCTAssertTrue(message(["kind": "finishing", "measure": "timeToFinish"])?.contains("tracking.measure") == true)
        XCTAssertTrue(message(["kind": "passing", "zones": [1]])?.contains("only a shooting drill") == true)
        XCTAssertTrue(message(["kind": "shooting", "zones": [3, 3]])?.contains("distinct") == true)
        XCTAssertTrue(message(["kind": "shooting", "main": ["dunks"]])?.contains("not a skill") == true)
        XCTAssertTrue(message(["kind": "shooting", "course": "lap"])?.contains("tracking.course") == true)
    }

    func testClaudesTrackingProposalBecomesADefinition() throws {
        let answer = #"{"instructions":["a"],"keyPoints":["b"],"attributes":[0,0,3,0,0,0,0,1],"tracking":{"kind":"shooting","measure":"madeOf","amount":20,"unit":"","main":["shooting"],"some":["footwork"],"zones":[5,9,5,12]}}"#
        let response = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": answer]]])
        let result = try DrillWriter.parse(response)
        let d = try XCTUnwrap(result.tracking?.definition(chinese: false))
        XCTAssertEqual(d.kind, .shooting); XCTAssertEqual(d.amount, 20)
        XCTAssertEqual(d.zones, [5, 9], "duplicates and off-court numbers dropped")
        XCTAssertEqual(d.mainAttributes, [.shooting])
        // "none" proposes nothing.
        let none = #"{"instructions":[],"keyPoints":[],"attributes":[0,0,0,0,0,0,0,0],"tracking":{"kind":"none","measure":"count","amount":0,"unit":"","main":[],"some":[],"zones":[]}}"#
        XCTAssertNil(try DrillWriter.parse(try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": none]]])).tracking)
        // A named course rides along for a timed run.
        let sprint = #"{"instructions":[],"keyPoints":[],"attributes":[0,0,0,0,0,0,0,3],"tracking":{"kind":"conditioning","measure":"timeToFinish","amount":0,"unit":"","main":["footwork"],"some":[],"zones":[],"course":"lineDrill"}}"#
        let timed = try DrillWriter.parse(try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": sprint]]]))
        XCTAssertEqual(timed.tracking?.definition(chinese: false).course, .lineDrill)
        XCTAssertEqual(TrackKind.finishing.preset(measure: .inTime, chinese: false).spots, [], "a timed finishing run is one number")
        // The request asks for it.
        let body = DrillWriter.requestBody(name: "x", description: "y", minPlayers: 1, minutes: 5)
        let schema = ((body["output_config"] as? [String: Any])?["format"] as? [String: Any])?["schema"] as? [String: Any]
        XCTAssertTrue((schema?["required"] as? [String])?.contains("tracking") == true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    // MARK: Rounds (23 Nov 2026)

    func testRoundsPoolAShareAndKeepTheBestOfTheRest() throws {
        var made = TrackKind.shooting.preset(chinese: false); made.amount = 10; made.zones = [5, 9]
        var r = run(made, [a: [4, 6]])
        var second = r.round(0); second.entries = [:]
        second.set(8, for: a, spot: 0)
        r.setRound(r.addRound(), entries: second.entries)
        XCTAssertEqual(try XCTUnwrap(r.result(for: a)), 18.0 / 30.0, accuracy: 0.0001, "three reports of 10")
        XCTAssertEqual(try XCTUnwrap(r.round(1).result(for: a)), 0.8, accuracy: 0.0001)
        let zones = ShootingHistory.zones(of: r, student: a)
        XCTAssertEqual(zones[5]?.made, 12); XCTAssertEqual(zones[5]?.attempted, 20)
        XCTAssertEqual(zones[9]?.attempted, 10)

        let sprint = TrackKind.conditioning.preset(chinese: false)
        XCTAssertEqual(sprint.measure, .timeToFinish)
        var t = run(sprint, [a: [12.4]])
        var faster = t.round(0); faster.entries = [:]; faster.set(11.8, for: a, spot: 0)
        t.setRound(t.addRound(), entries: faster.entries)
        var slower = t.round(0); slower.entries = [:]; slower.set(12.9, for: a, spot: 0)
        t.setRound(t.addRound(), entries: slower.entries)
        XCTAssertEqual(t.result(for: a), 11.8, "the fastest round is the session's time")

        let back = try JSONDecoder().decode(TrackedRun.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        t.addRound(); t.dropEmptyRounds()
        XCTAssertEqual(t.roundCount, 3)
        t.removeRound(1)
        XCTAssertEqual(t.result(for: a), 12.4)
    }
}
