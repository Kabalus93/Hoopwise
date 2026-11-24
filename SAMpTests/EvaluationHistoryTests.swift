import XCTest
import PDFKit
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

    // MARK: Focus and the progress report

    func testTheFocusIsTheCoachsPickElseTheTwoLowestRatings() throws {
        var skills = SkillsEvaluation()
        XCTAssertTrue(AthleteFocus.suggested(skills).isEmpty)
        skills.setRating(3, for: .passing); skills.setRating(7, for: .shooting); skills.setRating(3, for: .ballHandling)
        XCTAssertTrue(AthleteFocus.suggested(skills).isEmpty, "three ratings are too few to say")
        skills.setRating(9, for: .defense)
        XCTAssertEqual(AthleteFocus.suggested(skills), [.ballHandling, .passing], "lowest, octagon order on a tie")
        XCTAssertEqual(AthleteFocus.current(skills), [.ballHandling, .passing])
        skills.focus = [DrillAttribute.defense.rawValue]
        XCTAssertEqual(AthleteFocus.current(skills), [.defense])
        XCTAssertEqual(try JSONDecoder().decode(SkillsEvaluation.self, from: JSONEncoder().encode(skills)).focus, skills.focus)
        var strong = SkillsEvaluation()
        for axis in DrillAttribute.allCases { strong.setRating(9, for: axis) }
        XCTAssertTrue(AthleteFocus.suggested(strong).isEmpty, "nothing under 8: no weakness to name")
    }

    func testTheReportReadsThePeriodAndInventsNothing() throws {
        let cal = utc
        var student = Student(name: "Maya Chen")
        student.chineseName = nil
        var player = Player(studentId: student.id)
        var skills = SkillsEvaluation()
        let none = skills
        skills.setRating(4, for: .passing); skills.setRating(5, for: .shooting)
        skills.setRating(6, for: .defense); skills.setRating(7, for: .finishing)
        skills.recordEvaluation(replacing: none, at: day(-10), calendar: cal)
        var later = skills
        later.setRating(6, for: .passing)
        later.recordEvaluation(replacing: skills, at: day(20), calendar: cal)
        player.skills = later

        func session(_ n: Int, present: Bool, best: Bool = false) -> SessionEvent {
            var s = SessionEvent(title: "Class", date: day(n), startTime: day(n), endTime: day(n).addingTimeInterval(3600))
            if present { s.actualAttendeeIds = [student.id] } else { s.unexcusedAbsences = [student.id] }
            if best { s.manOfTheMatchId = student.id }
            return s
        }
        let sessions = [session(-30, present: true), session(1, present: true, best: true),
                        session(8, present: false), session(15, present: true)]
        let f = ProgressReportFacts.make(student: student, players: [player], programs: [], sessions: sessions, drills: [],
                                         from: day(0), to: day(30), coachWords: "  Great term.  ",
                                         coach: "Coach", academy: "Academy", chinese: false)
        XCTAssertEqual(f.classesPresent, 2); XCTAssertEqual(f.classesTaken, 3, "the class before the period is not counted")
        XCTAssertEqual(f.playerOfTheSession, 1)
        XCTAssertEqual(f.games, 0); XCTAssertTrue(f.perGame.isEmpty); XCTAssertTrue(f.results.isEmpty); XCTAssertTrue(f.workedOn.isEmpty)
        let passing = try XCTUnwrap(f.skills.first { $0.axis == .passing })
        XCTAssertEqual(passing.then, 4); XCTAssertEqual(passing.now, 6); XCTAssertEqual(passing.change, 2)
        XCTAssertEqual(f.skills.count, 4, "only rated skills")
        XCTAssertEqual(f.focus, ["Shooting", "Passing"])
        XCTAssertEqual(f.coachWords, "Great term.")

        // One page of text.
        let doc = try XCTUnwrap(PDFDocument(data: ProgressReportDocument.pdf(f)))
        XCTAssertEqual(doc.pageCount, 1)
        let text = doc.page(at: 0)?.string ?? ""
        for word in ["Maya Chen", "2/3", "Great term.", "Passing"] { XCTAssertTrue(text.contains(word), word) }
    }

    // MARK: Group fit

    func testGroupFitNamesWhoOutgrewTheGroupInAgeOrLevel() {
        let older = UUID(), top = UUID(), behind = UUID(), fine = UUID(), young = UUID(), unknown = UUID()
        let signals = GroupFit.signals(
            programAge: .u10,
            members: [(fine, 9), (behind, 8), (top, 9), (older, 10), (young, 7), (unknown, nil)],
            tiers: [fine: .average, behind: .bottom, top: .best, older: .best, young: .better])
        XCTAssertEqual(signals.map(\.studentId), [older, top, behind], "older first, then the top, then the bottom")
        XCTAssertEqual(signals[0].reasons, [.older(.u12), .top])
        XCTAssertEqual(GroupFit.band(forAge: 7), .u8); XCTAssertEqual(GroupFit.band(forAge: 8), .u10)
        XCTAssertTrue(GroupFit.signals(programAge: .u10, members: [(young, 7)], tiers: [:]).isEmpty, "playing up is the coach's choice")
    }
}
