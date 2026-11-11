import XCTest
@testable import Hoopwise

/// What drills develop (eight axes, 0–3) and what a plan trains from them.
final class DrillAttributesTests: XCTestCase {

    func testEveryLibraryActivityIsRated() {
        for activity in ActivityLibrary.shared.plannable {
            let scores = ActivityLibraryAttributes.ratings[activity.key]
            XCTAssertEqual(scores?.count, 8, "\(activity.key) is not rated")
            XCTAssertTrue(scores?.allSatisfy { (0...3).contains($0) } ?? false)
            XCTAssertTrue(scores?.contains { $0 >= 2 } ?? false, "\(activity.key) works nothing")
        }
    }

    func testTheCoachsTagsWinOverTheLibraryAndSurviveARoundTrip() {
        var profile = AttributeProfile()
        profile[.defense] = 3
        profile[.footwork] = 9   // clamped
        let tags = profile.replacing(in: ["library", "attr:passing=3"], byCoach: true)
        XCTAssertTrue(tags.contains("library") && tags.contains(AttributeProfile.coachTag))
        let back = AttributeProfile(tags: tags)
        XCTAssertEqual(back?[.defense], 3)
        XCTAssertEqual(back?[.footwork], 3)
        XCTAssertEqual(back?[.passing], 0, "the old attr tag is replaced, not merged")
        XCTAssertNil(AttributeProfile(tags: ["library", "type:passing"]))
    }

    func testTheGuessIsNeverBlank() {
        for type in ActivityType.allCases where type != .rules {
            XCTAssertFalse(AttributeProfile.guess(type: type, category: .skills).isEmpty, type.rawValue)
        }
        for category in DrillCategory.allCases {
            XCTAssertFalse(AttributeProfile.guess(type: nil, category: category).isEmpty, category.rawValue)
        }
    }

    // MARK: Plan coverage

    private func drill(_ scores: [DrillAttribute: Int], minutes: Int = 10) -> DrillItem {
        var d = DrillItem(name: "D", category: .skills, difficulty: .beginner, durationMinutes: minutes,
                          description: "", instructions: [], keyPoints: [], minPlayers: 1)
        d.tags = AttributeProfile(scores: scores).tags(byCoach: true)
        return d
    }

    func testMinutesWeighTheDrillsAndNeglectFollowsTheTarget() {
        let passing = drill([.passing: 3, .gameIQ: 1])
        let dribbling = drill([.ballHandling: 3])
        var plan = SessionCurriculum()
        plan.warmupDrillIds = [dribbling.id]
        plan.warmupMinutes = 10
        plan.skillDrillIds = [passing.id]
        plan.skillsMinutes = 30
        plan.gameMinutes = 0
        let minutes = PlanCoverage.minutes(of: plan, drills: [passing, dribbling])
        XCTAssertEqual(minutes[.passing] ?? 0, 30, accuracy: 0.01, "a 3 in a 30-minute block = 30 minutes")
        XCTAssertEqual(minutes[.ballHandling] ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(minutes[.gameIQ] ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(PlanCoverage.emphasis(minutes).first, .passing)

        let target = PlanCoverage.target(phaseFocus: [.defense, .passing], skillTargets: nil)
        XCTAssertEqual(target?[.defense], 1)
        XCTAssertEqual(PlanCoverage.neglected(plan: minutes, target: target), [.defense],
                       "the phase asks for defense and the plan has none")
        XCTAssertNil(PlanCoverage.target(phaseFocus: [], skillTargets: nil), "nothing asks, no target")
    }

    func testBothTargetsCount() {
        var goals = ProgramSkillTargets()
        goals.lastUpdatedDate = Date()
        let target = PlanCoverage.target(phaseFocus: [.shooting], skillTargets: goals)
        XCTAssertNotNil(target?[.shooting])
        XCTAssertNotNil(target?[.gameIQ], "the program's goals add axes the phase focus doesn't")
    }
}
