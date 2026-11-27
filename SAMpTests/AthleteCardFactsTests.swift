import XCTest
@testable import Hoopwise

/// The player card (16 Nov 2026): every number is a fact the app has — this
/// month's classes where attendance was taken, games, and what the classes
/// they ATTENDED trained. Nothing invented.
@MainActor
final class AthleteCardFactsTests: XCTestCase {

    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
    private var student = Student(name: "Maya Chen", chineseName: "陈玛雅")
    private lazy var program: Program = {
        var p = Program(name: "Elite U8", ageGroup: .u8)
        p.enrolledStudentIds = [student.id]
        return p
    }()

    private func drill(_ scores: [DrillAttribute: Int]) -> DrillItem {
        var d = DrillItem(name: "D", category: .skills, durationMinutes: 10)
        d.tags = AttributeProfile(scores: scores).tags(byCoach: true)
        return d
    }

    private func session(month: Int = 11, day: Int, plan: DrillItem? = nil, present: Bool = false,
                         excused: Bool = false, games: [SessionGame] = []) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
        var s = SessionEvent(programId: program.id, title: "U8", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: .completed, attendeeIds: [])
        if let plan {
            s.curriculum.skillDrillIds = [plan.id]
            s.curriculum.skillsMinutes = 30
        }
        if present { s.actualAttendeeIds = [student.id] }
        if excused { s.excusedAbsences = [student.id] }
        s.games = games
        return s
    }

    private func game(points: Int) -> SessionGame {
        let id = UUID()
        return SessionGame(sessionId: UUID(), gameType: .twoTeam,
                           playerStats: [SessionPlayerStats(playerId: student.id, gameId: id, teamId: UUID(),
                                                            points: points, rebounds: 2, assists: 1)],
                           basketValue: 2, status: .completed)
    }

    private func card(_ sessions: [SessionEvent], drills: [DrillItem] = []) -> AthleteCardFacts {
        AthleteCardFacts.make(student: student, players: [], programs: [program], sessions: sessions, drills: drills,
                              categoryHex: "#007AFF", coach: "Jordan", academy: "Riverside", now: now)
    }

    func testClassesCountOnlyWhereAttendanceWasTaken() {
        let c = card([
            session(day: 3, present: true),
            session(day: 10, excused: true),
            session(day: 17),                 // roll call never taken: not a miss
            session(month: 10, day: 27, present: true),   // last month
        ])
        XCTAssertEqual(c.classesAttended, 1)
        XCTAssertEqual(c.classesExpected, 2, "the class nobody marked is left out — unmarked is not absent")
    }

    func testTheOctagonReadsOnlyClassesTheyAttended() {
        let passing = drill([.passing: 3]), defense = drill([.defense: 3])
        let c = card([session(day: 3, plan: passing, present: true),
                      session(day: 10, plan: defense)], drills: [passing, defense])
        XCTAssertEqual(c.trainedScope, .month)
        XCTAssertEqual(c.trainedClasses, 1)
        XCTAssertEqual(c.trained[.passing] ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(c.trained[.defense] ?? 0, 0, accuracy: 0.001, "a class they missed did not train them")
    }

    func testOctagonFallsBackToEveryClassThenToNothing() {
        let passing = drill([.passing: 3])
        let earlier = card([session(month: 10, day: 6, plan: passing, present: true)], drills: [passing])
        XCTAssertEqual(earlier.trainedScope, .allTime)
        let none = card([session(day: 3, present: true)])
        XCTAssertEqual(none.trainedScope, .none)
        XCTAssertTrue(none.trained.isEmpty, "no plan, no octagon — never a guess")
    }

    func testGamesPerGameAndThisMonth() {
        let c = card([session(month: 10, day: 6, games: [game(points: 4)]),
                      session(day: 3, games: [game(points: 8)])])
        XCTAssertEqual(c.gamesPlayed, 2)
        XCTAssertEqual(c.gamesThisMonth, 1)
        XCTAssertEqual(c.perGame[.points] ?? 0, 6, accuracy: 0.001)
        XCTAssertTrue(card([]).perGame.isEmpty, "no games, no averages")
    }

    func testNamesProgramAndNothingInvented() {
        LocalizationManager.shared.currentLanguage = .english
        let c = card([])
        XCTAssertEqual(c.name, "Maya Chen")
        XCTAssertEqual(c.secondName, "陈玛雅")
        XCTAssertEqual(c.program, "Elite U8")
        XCTAssertNil(c.ageGroup, "U8 is already in the program's name")
        XCTAssertNil(c.jersey, "no number given, none shown")
        XCTAssertEqual(c.academy, "Riverside")
    }

    func testTheCardRendersBothSidesTheSameSize() throws {
        let c = card([session(day: 3, present: true, games: [game(points: 6)])])
        let front = try XCTUnwrap(AthleteCardRenderer.image(AthleteCardFront(card: c), scale: 1))
        let back = try XCTUnwrap(AthleteCardRenderer.image(AthleteCardBack(card: c), scale: 1))
        XCTAssertEqual(front.size, AthleteCardLayout.size)
        XCTAssertEqual(back.size, front.size, "front and back must line up when printed")
        let share = try XCTUnwrap(AthleteCardRenderer.shareImage(c, scale: 1))
        XCTAssertGreaterThan(share.size.width, share.size.height, "front and back side by side")
        let pdf = try XCTUnwrap(AthleteCardRenderer.printSheet([c, c]))
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        XCTAssertEqual(document.numberOfPages, 2, "fronts, then backs")
    }

    /// The header runs out to the colour behind the child in their photo: the
    /// corners of the photo, not its middle.
    func testTheHeaderColourIsThePhotoBackground() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        let photo = renderer.jpegData(withCompressionQuality: 0.95) { ctx in
            UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1).setFill()       // the swatch
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
            UIColor.orange.setFill()                                             // the child
            ctx.cgContext.fillEllipse(in: CGRect(x: 20, y: 20, width: 80, height: 80))
        }
        let hex = try XCTUnwrap(AthleteCardFacts.backgroundHex(ofPhoto: photo))
        let value = try XCTUnwrap(UInt32(hex.dropFirst(), radix: 16))
        XCTAssertEqual(Double((value >> 16) & 0xFF) / 255, 0.2, accuracy: 0.05)
        XCTAssertEqual(Double((value >> 8) & 0xFF) / 255, 0.6, accuracy: 0.05)
        XCTAssertEqual(Double(value & 0xFF) / 255, 0.3, accuracy: 0.05)
        XCTAssertGreaterThan(AthleteCardFacts.luminance(ofHex: "#F5F0E6"), 0.72, "cream takes dark type")
        XCTAssertLessThan(AthleteCardFacts.luminance(ofHex: hex), 0.72, "green keeps white type")
    }

    /// The back compares the athlete with the group (27 Nov 2026): the
    /// group's average on each skill two or more of its athletes are rated on.
    func testTheGroupAverageIsTheProgramsRatedAthletes() {
        let mate = UUID(), outsider = UUID()
        var group = program
        group.enrolledStudentIds = [student.id, mate]
        func player(_ id: UUID, _ ratings: [DrillAttribute: Int]) -> Player {
            var p = Player(studentId: id)
            for (axis, r) in ratings { p.skills.setRating(r, for: axis) }
            return p
        }
        let players = [player(student.id, [.shooting: 8, .defense: 4]),
                       player(mate, [.shooting: 4]),
                       player(outsider, [.shooting: 10, .defense: 10])]
        let card = AthleteCardFacts.make(student: student, players: players, programs: [group], sessions: [], drills: [],
                                         categoryHex: "#007AFF", coach: "Jordan", academy: "Riverside", now: now)
        XCTAssertEqual(card.evaluation[.shooting] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(card.groupEvaluation[.shooting] ?? 0, 0.6, accuracy: 0.001, "the two in the program, not the outsider")
        XCTAssertNil(card.groupEvaluation[.defense], "one rated athlete is not a group")
        // A private client has no group to compare with.
        var privateProgram = group
        privateProgram.programType = .privateSessions
        XCTAssertTrue(AthleteCardFacts.make(student: student, players: players, programs: [privateProgram], sessions: [], drills: [],
                                            categoryHex: "#007AFF", coach: "Jordan", academy: "Riverside", now: now).groupEvaluation.isEmpty)
    }
}
