import XCTest
@testable import Hoopwise

/// Medical notes and the family contact log reach the screens through these
/// (25 Nov 2026): both were stored with no way to enter or read them.
@MainActor
final class AthleteSafetyTests: XCTestCase {
    func testAMedicalNoteIsReadAndAContactIsLoggedOnTheStoredAthlete() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let student = Student(name: "Safety Kid")
        var player = Player(id: UUID(), studentId: student.id)
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

    // MARK: The Mac's drag onto a class (25 Nov 2026)

    func testADroppedDrillOrPlayJoinsTheClasssPlanOnce() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let start = Date().addingTimeInterval(3600)
        let session = SessionEvent(programId: nil, title: "Class", date: start, startTime: start, endTime: start.addingTimeInterval(3600))
        dm.addSessionEvent(session)
        let drill = DrillItem(name: "Dropped drill", category: .shooting)
        dm.addDrill(drill)
        let play = SessionPlayRef(key: "created:42", name: "Horns")

        XCTAssertEqual(FilmRoomDrag.parse(FilmRoomDrag.payload(.drill(drill.id))), .drill(drill.id))
        XCTAssertEqual(FilmRoomDrag.parse(FilmRoomDrag.payload(.play(play))), .play(play))
        XCTAssertNil(FilmRoomDrag.parse("some other text"))

        XCTAssertEqual(dm.drop(.drill(drill.id), onSession: session.id), .addedToSkills, "a coach's own drill goes to Skills")
        XCTAssertEqual(dm.drop(.drill(drill.id), onSession: session.id), .alreadyThere)
        XCTAssertEqual(dm.drop(.play(play), onSession: session.id), .addedPlay)
        XCTAssertEqual(dm.drop(.play(play), onSession: session.id), .alreadyThere)
        let stored = try XCTUnwrap(dm.sessionEvents.first { $0.id == session.id })
        XCTAssertEqual(stored.curriculum.skillDrillIds, [drill.id])
        XCTAssertEqual(stored.curriculum.plays.map(\.key), ["created:42"])
        XCTAssertEqual(dm.drop(.drill(UUID()), onSession: session.id), .notPossible)
        XCTAssertEqual(dm.drop(.play(play), onSession: UUID()), .notPossible)
    }
}
