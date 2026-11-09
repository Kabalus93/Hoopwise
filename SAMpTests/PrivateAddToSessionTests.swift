import XCTest
@testable import Hoopwise

/// The private session's Add Athlete (`addStudentsToSessionOnly`, November
/// 2026): a second client joins THAT session and is charged from THEIR OWN
/// private bundle; the first client's private program is never touched, so
/// they are not expected (or inferred absent) at its later lessons.
@MainActor
final class PrivateAddToSessionTests: XCTestCase {
    func testASecondClientJoinsOneSessionNotTheProgram() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let owner = Student(name: "Client A"), guest = Student(name: "Client B")
        dm.addStudent(owner); dm.addStudent(guest)
        var program = Program(name: "Private · Client A", ageGroup: .u12)
        program.programType = .privateSessions
        dm.addProgram(program)
        dm.addStudentEnrollment(studentId: owner.id, programId: program.id)
        for student in [owner, guest] {
            dm.addContract(Contract(studentId: student.id, contractNumber: 1, kind: .privateBundle, bundleSize: 10,
                                    bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        }
        func lesson(_ days: Double) -> SessionEvent {
            let start = Date(timeIntervalSince1970: 1_700_000_000 + days * 86_400)
            let event = SessionEvent(programId: program.id, title: program.name, date: start, startTime: start,
                                     endTime: start.addingTimeInterval(5400), status: .scheduled, attendeeIds: [])
            dm.addSessionEvent(event)
            return event
        }
        let today = lesson(0), nextWeek = lesson(7)
        let remaining = { (id: UUID) in dm.contracts.first { $0.studentId == id }?.bundleRedemptionsRemaining }

        dm.setStudentAttendanceState(sessionId: today.id, studentId: owner.id, state: .present)
        dm.addStudentsToSessionOnly(sessionId: today.id, studentIds: [guest.id])

        let after = dm.sessionEvents.first { $0.id == today.id }!
        XCTAssertEqual(Set(after.attendeeIds), [owner.id, guest.id], "both are expected at this lesson")
        XCTAssertTrue(after.actualAttendeeIds.contains(guest.id), "the guest is marked present")
        XCTAssertEqual(remaining(owner.id), 9)
        XCTAssertEqual(remaining(guest.id), 9, "the guest is charged from their own bundle")
        XCTAssertEqual(dm.programs.first { $0.id == program.id }?.enrolledStudentIds, [owner.id], "the program is untouched")
        let later = dm.sessionEvents.first { $0.id == nextWeek.id }!
        XCTAssertEqual(AttendanceMath.expectedIds(of: later, programs: dm.programs), [owner.id],
                       "the guest is not expected at the owner's later lessons")
    }
}
