import XCTest
@testable import Hoopwise

/// `removeStudentEnrollment` takes a student off ONE roster (November 2026: a
/// private client sat on another client's private program, so its sessions
/// expected him and inferred him absent). The other rosters stay; the primary
/// class moves to one they are still on.
@MainActor
final class RemoveEnrollmentTests: XCTestCase {
    func testRemovingOneProgramKeepsTheOthers() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Two Classes Kid")
        dm.addStudent(kid)
        let first = Program(name: "Private · Client A", ageGroup: .u12)
        let second = Program(name: "Private · Client B", ageGroup: .u12)
        dm.addProgram(first)
        dm.addProgram(second)
        dm.addStudentEnrollment(studentId: kid.id, programId: first.id)
        dm.addStudentEnrollment(studentId: kid.id, programId: second.id)
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.programId, first.id)

        dm.removeStudentEnrollment(studentId: kid.id, programId: first.id)

        XCTAssertFalse(dm.programs.first { $0.id == first.id }!.enrolledStudentIds.contains(kid.id))
        XCTAssertTrue(dm.programs.first { $0.id == second.id }!.enrolledStudentIds.contains(kid.id))
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.programId, second.id, "the primary class moves to one they are still on")

        dm.removeStudentEnrollment(studentId: kid.id, programId: second.id)
        XCTAssertNil(dm.students.first { $0.id == kid.id }?.programId)
    }
}
