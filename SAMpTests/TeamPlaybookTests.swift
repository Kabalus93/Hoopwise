import XCTest
@testable import Hoopwise

/// A team's playbook: sections of plays and notes, kept in SDTeam.playbookData
/// and carried by addTeam / updateTeam.
@MainActor
final class TeamPlaybookTests: XCTestCase {

    func testSectionsHoldPlaysAndNotesAndEmptyOnesDisappear() {
        var book = TeamPlaybook()
        book[.blob].plays = [SessionPlayRef(key: "starter:box", name: "Box")]
        book[.defense].notes = "Switch 1–4, show on the big"
        XCTAssertEqual(book.playCount, 1)
        XCTAssertEqual(book.sections.count, 2)
        book[.blob].plays = []
        XCTAssertNil(book.sections[TeamPlaybook.Kind.blob.rawValue], "an emptied section is not stored")
    }

    func testThePlaybookIsSavedWithTheTeam() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        var team = Team(name: "Ballers", shortName: "BAL")
        dm.addTeam(team)
        var book = team.playbook
        book[.baseOffense].plays = [SessionPlayRef(key: "starter:horns", name: "Horns")]
        book[.vsZone].notes = "1-3-1, ball to the middle"
        team.playbook = book
        team.playerIds = [UUID()]
        dm.updateTeam(team)

        let stored = try XCTUnwrap(dm.teams.first { $0.id == team.id })
        XCTAssertEqual(stored.playbook, book)
        XCTAssertEqual(stored.playerIds, team.playerIds)
        dm.deleteTeam(stored)
    }

    // MARK: Standards

    func testABreakdownBuildsEachPlayersWorkoutAndTheTeamsDemands() {
        let maya = UUID(), leo = UUID()
        let shooting = UUID(), passing = UUID(), post = UUID()
        var book = TeamPlaybook()
        let triangle = SessionPlayRef(key: "created:1", name: "Triangle")
        let horns = SessionPlayRef(key: "created:2", name: "Horns")
        book[.baseOffense].plays = [triangle, horns]
        book.breakdowns[triangle.key] = PlayBreakdown(playName: "Triangle", roles: [
            .init(number: 1, standard: "Two-pass read", skills: ["passing", "shooting"], drillIds: [passing, shooting], playerIds: [maya]),
            .init(number: 5, skills: ["post"], drillIds: [post], playerIds: [leo]),
        ])
        book.breakdowns[horns.key] = PlayBreakdown(playName: "Horns", roles: [
            .init(number: 2, skills: ["shooting"], drillIds: [shooting], playerIds: [maya]),
        ])

        let mayaWorkout = book.workout(for: maya)
        XCTAssertEqual(mayaWorkout.map(\.drillId), [passing, shooting], "a drill two roles share appears once")
        XCTAssertEqual(mayaWorkout.first { $0.drillId == shooting }?.sources.count, 2, "and says both roles it serves")
        XCTAssertEqual(book.roles(of: maya), ["Triangle · 1", "Horns · 2"])
        XCTAssertEqual(book.workout(for: leo).map(\.drillId), [post])
        XCTAssertEqual(book.skillDemands.first?.skill, "shooting", "the skill most roles need leads")
        XCTAssertEqual(book.skillDemands.first?.roles.count, 2)
    }

    func testIdentityObjectivesAndBreakdownsSurviveTheStore() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        var team = Team(name: "Standards", shortName: "STD")
        dm.addTeam(team)
        var book = team.playbook
        book.identity = "Pace and space"
        book.objectives = ["Spacing in the triangle", "Talk on defense"]
        book.breakdowns["created:9"] = PlayBreakdown(playName: "Triangle", roles: [.init(number: 3, standard: "Seal")])
        team.playbook = book
        dm.updateTeam(team)
        let stored = try XCTUnwrap(dm.teams.first { $0.id == team.id })
        XCTAssertEqual(stored.playbook, book)
        dm.deleteTeam(stored)
    }

    // MARK: Team practice

    func testATeamPracticeIsNeverBilledAndIsNotPrivate() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Team Practice Kid")
        dm.addStudent(kid)
        // A balance shared by every class, and a private bundle: neither pays.
        dm.addContract(Contract(studentId: kid.id, contractNumber: 1, kind: .group, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        dm.addContract(Contract(studentId: kid.id, contractNumber: 2, kind: .privateBundle, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        var curriculum = SessionCurriculum()
        curriculum.teamId = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        dm.createSession(SessionCreation.Intent(group: .unassigned, sessionType: .teamPractice, start: start,
                                                durationMinutes: 90, title: "Ballers Practice",
                                                roster: [kid.id], curriculum: curriculum))
        let session = try XCTUnwrap(dm.sessionEvents.first { $0.sessionType == .teamPractice })
        XCTAssertFalse(SessionPrivacy.isPrivate(session, programs: dm.programs, contracts: dm.contracts))
        dm.setStudentAttendanceState(sessionId: session.id, studentId: kid.id, state: .present)
        for contract in dm.allContracts(for: kid.id) {
            XCTAssertEqual(contract.bundleRedemptionsRemaining, 10, "contract #\(contract.contractNumber) was charged")
        }
        XCTAssertEqual(teamPractices(of: kid.id, in: dm).map(\.id), [session.id], "the record keeps it")
        dm.deleteSessionEvent(session)
    }
}
