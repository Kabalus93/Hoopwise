import XCTest
@testable import Hoopwise

/// Drill series (18 Nov 2026, Luther): levels as whole drills, stored on one
/// record's tags; spread over a phase easiest first.
final class DrillSeriesTests: XCTestCase {
    private let l = (0..<7).map { _ in UUID() }

    func testASeriesRoundTripsThroughItsRecord() throws {
        let series = DrillSeries(name: "Dribbling", summary: "Stationary to combos", levels: Array(l.prefix(3)), block: .skills)
        let record = series.applied(to: DrillItem(id: series.id, name: "", category: .skills))
        XCTAssertTrue(record.isSeries)
        let back = try XCTUnwrap(DrillSeries(drill: record))
        XCTAssertEqual(back, series)
        XCTAssertNil(DrillSeries(drill: DrillItem(name: "Plain", category: .skills)))
        XCTAssertEqual(DrillSeries.containing(l[1], in: [record]).first?.level, 2)
    }

    func testEvenPacingEarlyLevelsTakeTheExtraAndReviewThePrevious() {
        let slots = SeriesSpread.plan(levels: Array(l.prefix(3)), sessions: 8)
        XCTAssertEqual(slots.map { $0.teach }, [[l[0]], [l[0]], [l[0]], [l[1]], [l[1]], [l[1]], [l[2]], [l[2]]])
        XCTAssertNil(slots[0].review)
        XCTAssertEqual(slots[3].review, l[0], "a new level opens with the one before")
        XCTAssertNil(slots[4].review, "only its first session reviews")
        XCTAssertEqual(slots[6].drills, [l[1], l[2]])
    }

    func testMoreLevelsThanSessionsStopsOrDoublesUp() {
        let stop = SeriesSpread.plan(levels: l, sessions: 4, overflow: .stop)
        XCTAssertEqual(stop.map { $0.teach.count }, [1, 1, 1, 1], "never more than one new level")
        XCTAssertEqual(SeriesSpread.reached(stop, levels: l), 4)
        let double = SeriesSpread.plan(levels: l, sessions: 4, overflow: .doubleUp)
        XCTAssertEqual(double.count, 4)
        XCTAssertEqual(SeriesSpread.reached(double, levels: l), 7, "the whole series is reached")
        XCTAssertTrue(double.allSatisfy { $0.teach.count <= 2 })
        XCTAssertEqual(double.first?.teach, [l[0]], "level 1 keeps a session to itself")
    }

    func testReSpreadingNeverDoubles() {
        let series = DrillSeries(name: "S", levels: Array(l.prefix(2)), block: .warmup)
        var plan = SessionCurriculum()
        plan.warmupDrillIds = [l[0], UUID()]
        let slot = SeriesSpread.Slot(review: l[0], teach: [l[1]])
        let out = SeriesSpread.applying(slot, series: series, to: plan)
        XCTAssertEqual(out.warmupDrillIds.filter { $0 == l[0] }.count, 1)
        XCTAssertEqual(Array(out.warmupDrillIds.suffix(2)), [l[0], l[1]], "review, then the new level")
    }
}
