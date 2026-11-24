import XCTest
@testable import Hoopwise

/// Evaluation history (25 Nov 2026): every evaluation is kept with its date,
/// so growth can be read.
@MainActor
final class EvaluationHistoryTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 86_400) }
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func testEveryEvaluationIsKeptAndGrowthIsReadFromTheFirst() throws {
        var skills = SkillsEvaluation()
        let none = skills
        skills.setRating(4, for: .passing); skills.setRating(6, for: .shooting)
        skills.recordEvaluation(replacing: none, at: day(0), calendar: utc)
        XCTAssertEqual(skills.history.count, 1)
        XCTAssertNil(skills.baseline, "one evaluation is not growth yet")
        XCTAssertTrue(SkillGrowthRow.rows(skills).isEmpty)

        // Corrected the same day: still one evaluation.
        var same = skills
        same.setRating(5, for: .passing)
        same.recordEvaluation(replacing: skills, at: day(0).addingTimeInterval(3600), calendar: utc)
        XCTAssertEqual(same.history.count, 1); XCTAssertEqual(same.history[0].axes[DrillAttribute.passing.rawValue], 5)

        var later = same
        later.setRating(7, for: .passing); later.setRating(5, for: .shooting); later.setRating(3, for: .defense)
        later.recordEvaluation(replacing: same, at: day(30), calendar: utc)
        XCTAssertEqual(later.history.count, 2)
        XCTAssertEqual(later.change(.passing), 2); XCTAssertEqual(later.change(.shooting), -1)
        XCTAssertNil(later.change(.defense), "not rated at the start: no change to claim")
        XCTAssertEqual(later.rating(.passing, asOf: day(10)), 5)
        XCTAssertEqual(later.lastEvaluatedDate, day(30))
        XCTAssertEqual(SkillGrowthRow.rows(later).map(\.axis), [.passing, .shooting])

        // Saved again unchanged: nothing added.
        var again = later
        again.recordEvaluation(replacing: later, at: day(40), calendar: utc)
        XCTAssertEqual(again.history.count, 2)

        let back = try JSONDecoder().decode(SkillsEvaluation.self, from: JSONEncoder().encode(later))
        XCTAssertEqual(back.history, later.history)
    }

    func testAnEvaluationMadeBeforeHistoryExistedBecomesTheBaseline() throws {
        // What an older build stored: ratings and a date, no history.
        var old = SkillsEvaluation(lastEvaluatedDate: day(0))
        old.setRating(4, for: .ballHandling)
        XCTAssertFalse(String(data: try JSONEncoder().encode(old), encoding: .utf8)!.contains("history"))
        var new = old
        new.setRating(6, for: .ballHandling)
        new.recordEvaluation(replacing: old, at: day(0).addingTimeInterval(7200), calendar: utc)
        XCTAssertEqual(new.history.map { $0.axes[DrillAttribute.ballHandling.rawValue] }, [4, 6],
                       "the replaced evaluation is kept even on the same day")
        XCTAssertEqual(new.change(.ballHandling), 2)
    }
}
