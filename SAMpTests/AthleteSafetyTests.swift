import XCTest
@testable import Hoopwise

/// Medical notes and the family contact log reach the screens through these
/// (25 Nov 2026): both were stored with no way to enter or read them.
@MainActor
final class AthleteSafetyTests: XCTestCase {
    func testAMedicalNoteIsReadAndAContactIsLoggedOnTheStoredAthlete() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let student = Student(name: "Safety Kid")
        var player = Player(id: UUID(), studentId: student.id, handedness: .right)
        player.medicalNotes = "  Peanut allergy  "
        player.secondaryParentInfo = ParentInfo(name: "Aunt", relationship: "Guardian", phone: "123")
        dm.addStudent(student, player: player)
        XCTAssertEqual(dm.medicalNote(for: student.id), "Peanut allergy")
        XCTAssertEqual(dm.players.first { $0.studentId == student.id }?.secondaryParentInfo?.name, "Aunt")
        XCTAssertNil(dm.medicalNote(for: UUID()))

        let when = Date(timeIntervalSince1970: 1_790_000_000)
        dm.logParentContact(studentId: student.id, type: .call, note: " Talked about attendance ", at: when)
        dm.logParentContact(studentId: student.id, type: .reportCard, note: "", at: when.addingTimeInterval(60))
        let stored = try XCTUnwrap(dm.students.first { $0.id == student.id })
        XCTAssertEqual(stored.parentalTouchpoints.map(\.type), [.call, .reportCard])
        XCTAssertEqual(stored.parentalTouchpoints[0].notes, "Talked about attendance")
        XCTAssertNil(stored.parentalTouchpoints[1].notes)
        XCTAssertEqual(stored.lastParentContact, when.addingTimeInterval(60))

        // A focus is not an evaluation: ratings and their history stay.
        var evaluated = try XCTUnwrap(dm.players.first { $0.studentId == student.id })
        evaluated.skills.setRating(4, for: .passing)
        evaluated.skills.recordEvaluation(replacing: SkillsEvaluation(), at: when)
        dm.updatePlayer(evaluated)
        dm.setAthleteFocus([.defense, .passing, .shooting], for: student.id)
        let after = try XCTUnwrap(dm.players.first { $0.studentId == student.id })
        XCTAssertEqual(dm.athleteFocus(student.id), [.defense, .passing], "two at most")
        XCTAssertEqual(after.skills.history.count, 1); XCTAssertEqual(after.skills.rating(.passing), 4)
        XCTAssertEqual(after.medicalNotes, "  Peanut allergy  ", "untouched by other writes")
    }
}
