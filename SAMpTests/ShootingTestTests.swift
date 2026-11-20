import XCTest
@testable import Hoopwise

/// Tracked shooting drills (20 Nov 2026): scoring, comparability, history,
/// evidence and the plan engine's signal.
@MainActor
final class ShootingTestTests: XCTestCase {

    private let a = UUID(), b = UUID(), c = UUID()

    private func session(day: Int, _ runs: [ShootingRun], status: SessionEventStatus = .completed) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 9))!
        var s = SessionEvent(programId: nil, title: "U10", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        s.curriculum.shooting = runs
        return s
    }

    private func run(_ setup: ShootingSetup, _ makes: [UUID: [Int?]]) -> ShootingRun {
        var r = ShootingRun(setup: setup)
        for (id, m) in makes { r.entries.append(ShootingEntry(studentId: id, makes: m)) }
        return r
    }

    private var twosMid10: ShootingSetup { ShootingSetup(drill: .twos, mode: .attempts, shots: 10, range: .mid) }
    private var ft10: ShootingSetup { ShootingSetup(drill: .freeThrows, mode: .attempts, shots: 10) }

    func testMadeOutOfShotsIsAShareOverTheSpotsReported() {
        let r = run(twosMid10, [a: [5, 6, nil, 7, 2]])
        let result = r.result(for: a)!
        XCTAssertEqual(result.made, 20)
        XCTAssertEqual(result.value, 20.0 / 40.0, accuracy: 0.0001, "four spots reported of 10 shots")
        XCTAssertEqual(result.spotValue(1)!, 0.6, accuracy: 0.0001)
        XCTAssertNil(result.spotValue(2))
    }

    func testTimedIsMakesAMinute() {
        let setup = ShootingSetup(drill: .threes, mode: .timed, seconds: 30)
        let result = run(setup, [a: [3, 4, 2, 3, 3]]).result(for: a)!
        XCTAssertEqual(result.value, 15.0 / 2.5, accuracy: 0.0001, "15 makes over 5 × 30 s")
    }

    func testOnlyLikeIsComparedWithLike() {
        XCTAssertNotEqual(twosMid10.key, ShootingSetup(drill: .twos, mode: .attempts, shots: 10, range: .short).key)
        XCTAssertNotEqual(ft10.key, ShootingSetup(drill: .freeThrows, mode: .attempts, shots: 20).key)
        XCTAssertNotEqual(ft10.key, ShootingSetup(drill: .freeThrows, mode: .timed, seconds: 60).key)
        let s1 = session(day: 1, [run(ft10, [a: [4]])])
        let s2 = session(day: 2, [run(ShootingSetup(drill: .freeThrows, mode: .attempts, shots: 20), [a: [12]])])
        XCTAssertEqual(ShootingHistory.series(for: a, sessions: [s1, s2]).count, 2, "two different tests")
    }

    func testSettingAndClearingAnEntry() {
        var r = ShootingRun(setup: twosMid10)
        r.set(6, for: a, spot: 2)
        XCTAssertEqual(r.makes(a, spot: 2), 6)
        XCTAssertNil(r.makes(a, spot: 0))
        r.set(nil, for: a, spot: 2)
        XCTAssertTrue(r.entries.isEmpty, "an athlete with nothing reported has no entry")
    }

    func testHistoryLastTimeAndSkippedSessionsLeftOut() {
        let s1 = session(day: 1, [run(ft10, [a: [4]])])
        let s2 = session(day: 2, [run(ft10, [a: [9]])], status: .skipped)
        let s3 = session(day: 3, [run(ft10, [a: [6]])])
        let s4 = session(day: 4, [run(ft10, [a: [7]])])
        let series = ShootingHistory.series(for: a, sessions: [s4, s2, s1, s3])
        XCTAssertEqual(series.first?.points.map(\.result.made), [4, 6, 7], "oldest first, skipped out")
        XCTAssertEqual(series.first?.best ?? 0, 0.7, accuracy: 0.0001)
        let last = ShootingHistory.previous(a, setup: ft10, before: s4.startTime, sessions: [s1, s2, s3, s4])
        XCTAssertEqual(last?.made, 6)
    }

    func testEvidenceTrendAndRankAmongPeers() {
        let days = (1...6).map { d in session(day: d, [run(ft10, [a: [d <= 3 ? 4 : 7], b: [5], c: [8]])]) }
        let e = ShootingHistory.evidence(for: a, peers: [a, b, c], sessions: days)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].recent, 0.7, accuracy: 0.0001)
        XCTAssertEqual(e[0].earlier ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(e[0].rank, 2)
        XCTAssertEqual(e[0].of, 3)
        let text = ShootingHistory.text(e[0], chinese: false)
        XCTAssertTrue(text.contains("70%") && text.contains("up from 40%") && text.contains("2nd of 3"), text)
    }

    func testOlderPlansDecodeWithNoShooting() throws {
        let old = SessionCurriculum(warmupDrillIds: [], skillDrillIds: [])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "shooting")
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(back.shooting.isEmpty)
        var withRuns = old
        withRuns.shooting = [run(ft10, [a: [5]])]
        let again = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(withRuns))
        XCTAssertEqual(again.shooting.first?.result(for: a)?.made, 5)
    }

    func testTrackedDrillsAreRecognised() {
        var ids = Set<UUID>()
        for t in ShootingDrill.allCases {
            XCTAssertEqual(ShootingDrill.of(t.drillItem), t)
            let main: DrillAttribute = (t == .layups || t == .mikan) ? .finishing : .shooting
            XCTAssertEqual(t.drillItem.attributes[main], 3, t.rawValue)
            XCTAssertTrue(ids.insert(t.drillId).inserted, "ids are unique")
            XCTAssertEqual(t.defaultSetup.drill, t)
        }
        // The first three keep the ids results were saved under.
        XCTAssertEqual(ShootingDrill.freeThrows.drillId.uuidString, "5A0715F0-0001-4000-8000-000000000001")
        XCTAssertEqual(ShootingDrill.twos.drillId.uuidString, "5A0715F0-0002-4000-8000-000000000002")
        XCTAssertEqual(ShootingDrill.threes.drillId.uuidString, "5A0715F0-0003-4000-8000-000000000003")
        XCTAssertEqual(ShootingDrill.layups.spotCount, 2)
        XCTAssertEqual(ShootingDrill.midRange.spotCount, 1)
    }

    func testThePlanEngineHearsALowShootingGroup() {
        let low = run(ft10, [a: [2], b: [3], c: [3]])
        XCTAssertNotNil(DrillPlanGenerator.shootingSignal(runs: [low], roster: [a, b, c]))
        let good = run(ft10, [a: [6], b: [7], c: [5]])
        XCTAssertNil(DrillPlanGenerator.shootingSignal(runs: [low, good], roster: [a, b, c]), "the later results win")
        XCTAssertNil(DrillPlanGenerator.shootingSignal(runs: [low], roster: [a, b]), "fewer than three athletes")
    }
}
