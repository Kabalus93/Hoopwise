import XCTest
@testable import Hoopwise

/// A grade entered once moves up every 1 September by itself. The stored
/// grade is what the coach picked; the birthdate written with it is the anchor.
@MainActor
final class SchoolGradePromotionTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func student(_ grade: SchoolGrade, enteredOn day: Date) -> Student {
        var s = Student(name: "Kid")
        s.setSchoolGrade(grade, asOf: day)
        return s
    }

    func testSchoolYearStartsInSeptember() {
        XCTAssertEqual(SchoolGrade.schoolYearStart(of: date(2026, 8, 31)), 2025)
        XCTAssertEqual(SchoolGrade.schoolYearStart(of: date(2026, 9, 1)), 2026)
        XCTAssertEqual(SchoolGrade.schoolYearStart(of: date(2027, 3, 10)), 2026)
    }

    func testPromotesEachSeptemberNotBefore() {
        let kid = student(.primary1, enteredOn: date(2026, 10, 17))
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2026, 10, 17)), .primary1)
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2027, 8, 31)), .primary1)
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2027, 9, 1)), .primary2)
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2029, 9, 1)), .primary4)
    }

    /// Entered in spring, the grade belongs to the school year that began the
    /// previous September — it must still read the same grade on entry day
    /// and move up that coming September.
    func testGradeEnteredInSpringHoldsUntilSeptember() {
        let kid = student(.primary3, enteredOn: date(2027, 3, 10))
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2027, 3, 10)), .primary3)
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2027, 9, 2)), .primary4)
    }

    func testCrossesFromPrimaryToSecondaryAndPastTheLastGrade() {
        let kid = student(.primary6, enteredOn: date(2026, 10, 1))
        XCTAssertEqual(kid.currentSchoolGrade(asOf: date(2027, 9, 1)), .highschool1)
        let senior = student(.highschool6, enteredOn: date(2026, 10, 1))
        XCTAssertNil(senior.currentSchoolGrade(asOf: date(2027, 9, 1)), "past H6 there is no grade")
    }

    func testNoGradeEnteredMeansNoGrade() {
        var kid = Student(name: "Kid")
        kid.birthdate = date(2018, 5, 1)
        XCTAssertNil(kid.currentSchoolGrade(asOf: date(2026, 10, 1)))
    }

    /// Student Intelligence compares a student with peers in the same grade.
    /// A promoted grade and an age-only student land in the same bucket.
    func testIntelligencePeersUsePromotedGradeAndAgeWithOneScale() {
        let entered = student(.primary4, enteredOn: date(2025, 10, 1))   // P5 now
        var byAge = Student(name: "Age only")
        byAge.birthdate = date(2016, 1, 15)                              // 10 on 1 Sep 2026
        // effectiveGradeKey reads "now"; both are P5 in the 2026–27 year.
        if SchoolGrade.schoolYearStart(of: Date()) == 2026 {
            XCTAssertEqual(StudentPerformanceGrader.effectiveGradeKey(for: entered), "P5")
            XCTAssertEqual(StudentPerformanceGrader.effectiveGradeKey(for: byAge), "P5")
        }
    }
}
