import XCTest
@testable import Hoopwise

/// Deleting an athlete takes them out of everything that names them
/// (15 November 2026): program enrolment, team rosters, upcoming class
/// rosters and reminder tags. Past classes keep their marks as history.
@MainActor
final class DeleteStudentTests: XCTestCase {
    func testDeletingAnAthleteLeavesNoGhosts() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let gone = Student(name: "Leaving Kid")
        let stays = Student(name: "Staying Kid")
        dm.addStudent(gone)
        dm.addStudent(stays)
        let program = Program(name: "U10 Group", ageGroup: .u10)
        dm.addProgram(program)
        dm.addStudentEnrollment(studentId: gone.id, programId: program.id)
        dm.addStudentEnrollment(studentId: stays.id, programId: program.id)

        var team = Team(name: "Hawks", shortName: "HWK", colorHex: "#5856D6")
        team.playerIds = [gone.id, stays.id]
        dm.addTeam(team)

        let future = Date().addingTimeInterval(3 * 86_400)
        let past = Date().addingTimeInterval(-3 * 86_400)
        var upcoming = SessionEvent(programId: program.id, title: "Next", date: future, startTime: future,
                                    endTime: future.addingTimeInterval(3600), status: .scheduled, attendeeIds: [gone.id, stays.id])
        upcoming.actualAttendeeIds = []
        var history = SessionEvent(programId: program.id, title: "Last", date: past, startTime: past,
                                   endTime: past.addingTimeInterval(3600), status: .completed, attendeeIds: [gone.id, stays.id])
        history.actualAttendeeIds = [gone.id, stays.id]
        dm.addSessionEvent(upcoming)
        dm.addSessionEvent(history)

        dm.addReminder(Reminder(title: "Ask about the ankle", dueDate: future, taggedStudentIds: [gone.id, stays.id]))

        dm.deleteStudent(gone)

        XCTAssertNil(dm.students.first { $0.id == gone.id })
        XCTAssertEqual(dm.programs.first { $0.id == program.id }?.enrolledStudentIds, [stays.id])
        XCTAssertEqual(dm.teams.first { $0.id == team.id }?.playerIds, [stays.id])
        XCTAssertEqual(dm.sessionEvents.first { $0.id == upcoming.id }?.attendeeIds, [stays.id])
        XCTAssertEqual(Set(dm.sessionEvents.first { $0.id == history.id }?.actualAttendeeIds ?? []), [gone.id, stays.id],
                       "past classes keep their attendance")
        XCTAssertEqual(dm.reminders.first?.taggedStudentIds, [stays.id])
    }
}
