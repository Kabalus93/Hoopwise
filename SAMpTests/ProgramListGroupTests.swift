import XCTest
@testable import Hoopwise

/// A program with no weekday is not a Saturday class (23 Nov 2026: every
/// private client's program was listed under Saturday).
final class ProgramListGroupTests: XCTestCase {
    func testAProgramWithoutADayIsNotFiledUnderSaturday() {
        var client = Program(name: "Private · Test", ageGroup: .adult, recurringDays: [])
        client.programType = .privateSessions
        XCTAssertEqual(ProgramListGroup.of(client), .privateLessons)

        let camp = Program(name: "Camp", ageGroup: .u12, recurringDays: [])
        XCTAssertEqual(ProgramListGroup.of(camp), .noFixedDay)

        let friday = Program(name: "Friday class", ageGroup: .u10, recurringDays: [.friday, .saturday])
        XCTAssertEqual(ProgramListGroup.of(friday), .day(.friday))
    }
}
