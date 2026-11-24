import XCTest
import PDFKit
@testable import Hoopwise

/// Game day (23 Nov 2026): a team's game is a session of type `.game` with a
/// plan in its curriculum; never billed; scored against the opponent.
@MainActor
final class GameDayTests: XCTestCase {

    func testThePlanRidesInTheCurriculumAndOlderPlansHaveNone() throws {
        var plan = GamePlan()
        plan.opponent = "Tigers"; plan.isHome = false
        plan.starters = [UUID(), UUID()]
        plan.keys = ["Box out", "  ", "Run"]
        plan.opponentNotes = "#7 shoots"
        var c = SessionCurriculum()
        c.teamId = UUID(); c.gamePlan = plan
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.gamePlan, plan)
        XCTAssertEqual(plan.cleanKeys, ["Box out", "Run"])
        XCTAssertEqual(plan.title(team: "Ballers", chinese: false), "Ballers @ Tigers")
        let old = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(SessionCurriculum()))
        XCTAssertNil(old.gamePlan)
        // A plan written by a build with fewer fields still reads.
        let partial = try JSONDecoder().decode(GamePlan.self, from: Data(#"{"opponent":"Lions"}"#.utf8))
        XCTAssertEqual(partial.opponent, "Lions"); XCTAssertTrue(partial.isHome); XCTAssertTrue(partial.starters.isEmpty)
        XCTAssertEqual(GamePlan().opponentName(chinese: false), "Opponent")
    }

    func testStartersLeadTheTeamAndTheOpponentHasNobody() {
        let a = UUID(), b = UUID(), c = UUID(), away = UUID()
        let team = Team(name: "Ballers", shortName: "BAL")
        var plan = GamePlan(); plan.opponent = "Tigers"; plan.starters = [c, away, a]
        let teams = GameDay.teams(team: team, plan: plan, pool: [a, b, c], chinese: false)
        XCTAssertEqual(teams[0].id, team.id)
        XCTAssertEqual(teams[0].playerIds, [c, a, b], "starters in the plan's order, the absent one out, then the bench")
        XCTAssertEqual(teams[0].starters, 2)
        XCTAssertEqual(teams[1].id, GamePlan.opponentTeamId)
        XCTAssertEqual(teams[1].name, "Tigers"); XCTAssertTrue(teams[1].playerIds.isEmpty)
        // No starters picked: up to five start.
        XCTAssertEqual(GameDay.teams(team: team, plan: GamePlan(), pool: [a, b, c], chinese: false)[0].starters, 3)
    }

    func testTheScoreAddsEveryPeriodPlayed() {
        let team = Team(name: "Ballers", shortName: "BAL")
        let kid = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = SessionEvent(programId: nil, title: "Ballers vs Tigers", date: start, startTime: start,
                                   endTime: start.addingTimeInterval(3600), status: .scheduled, attendeeIds: [kid])
        session.sessionType = .game
        session.curriculum.teamId = team.id
        XCTAssertNil(GameDay.score(of: session), "nothing played yet")
        func period(_ ours: Int, _ theirs: Int, _ status: SessionGameStatus) -> SessionGame {
            var g = SessionGame(sessionId: session.id, teams: GameDay.teams(team: team, plan: GamePlan(), pool: [kid], chinese: false),
                                status: status)
            g.teamScores[team.id] = ours; g.teamScores[GamePlan.opponentTeamId] = theirs
            return g
        }
        session.games = [period(0, 0, .ready)]
        XCTAssertNil(GameDay.score(of: session), "a period nobody played does not count")
        session.games = [period(12, 8, .completed), period(6, 9, .inProgress)]
        let running = GameDay.score(of: session)
        XCTAssertEqual(running?.ours, 18); XCTAssertEqual(running?.theirs, 17)
        XCTAssertEqual(running?.isFinal, false)
        XCTAssertEqual(running?.text(chinese: false), "18–17")
        session.games = [period(12, 8, .completed), period(6, 12, .completed)]
        XCTAssertEqual(GameDay.score(of: session)?.text(chinese: false), "L 18–20")
        session.games = [period(0, 4, .ready)]
        XCTAssertEqual(GameDay.score(of: session)?.theirs, 4, "scored before the clock ran")
    }

    func testAGameIsNeverBilledAndIsNotPrivate() throws {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Game Day Kid")
        dm.addStudent(kid)
        dm.addContract(Contract(studentId: kid.id, contractNumber: 1, kind: .group, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        dm.addContract(Contract(studentId: kid.id, contractNumber: 2, kind: .privateBundle, bundleSize: 10,
                                bundlePurchaseDate: Date(timeIntervalSince1970: 1_600_000_000)))
        var curriculum = SessionCurriculum()
        curriculum.teamId = UUID()
        var plan = GamePlan(); plan.opponent = "Tigers"; plan.starters = [kid.id]
        curriculum.gamePlan = plan
        dm.createSession(SessionCreation.Intent(group: .unassigned, sessionType: .game,
                                                start: Date(timeIntervalSince1970: 1_700_000_000),
                                                durationMinutes: 60, title: "Ballers vs Tigers",
                                                roster: [kid.id], curriculum: curriculum))
        let session = try XCTUnwrap(dm.sessionEvents.first { $0.sessionType == .game })
        XCTAssertEqual(session.curriculum.gamePlan?.starters, [kid.id], "the plan is stored")
        XCTAssertFalse(SessionPrivacy.isPrivate(session, programs: dm.programs, contracts: dm.contracts))
        // On the calendar it is a Game, not a Group class (its own icon and colour).
        XCTAssertEqual(dm.sessionFormat(session), .game)
        XCTAssertNotEqual(SessionFormat.game.icon, SessionFormat.group.icon)
        dm.setStudentAttendanceState(sessionId: session.id, studentId: kid.id, state: .present)
        for contract in dm.allContracts(for: kid.id) {
            XCTAssertEqual(contract.bundleRedemptionsRemaining, 10, "contract #\(contract.contractNumber) was charged")
        }
        // A whole-session save keeps the plan.
        var copy = session; copy.notes = "Bring water"
        dm.updateSessionEvent(copy)
        XCTAssertEqual(dm.sessionEvents.first { $0.id == session.id }?.curriculum.gamePlan?.opponent, "Tigers")
        dm.deleteSessionEvent(session)
    }

    // MARK: The plan page (24 Nov 2026): subs, defense, matchups, calls, sheet

    func testSubsDefenseAndMatchupsRideInThePlanAndOlderPlansAreUnchanged() throws {
        let a = UUID(), b = UUID(), c = UUID()
        var plan = GamePlan()
        plan.opponent = "Tigers"
        // A plan that uses none of the new fields writes none of their keys.
        let plain = String(data: try JSONEncoder().encode(plan), encoding: .utf8)!
        for key in ["subs", "defense", "defenseNote", "threats"] { XCTAssertFalse(plain.contains("\"\(key)\""), key) }

        plan.starters = [a, b]
        plan.subs = [PlannedSub(playerIn: c, playerOut: a, when: "Mid first half")]
        plan.defense = .zone23
        plan.defenseNote = "Trap the corner"
        plan.threats = [OpponentPlayer(number: "7", note: "Left hand", guardedBy: b), OpponentPlayer()]
        let back = try JSONDecoder().decode(GamePlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(back, plan)
        XCTAssertEqual(back.cleanThreats.count, 1, "an empty line is not a player")
        XCTAssertEqual(back.cleanThreats[0].label, "#7")

        // A defense this build does not know reads as unset, not as a failure.
        let odd = try JSONDecoder().decode(GamePlan.self, from: Data(#"{"opponent":"Lions","defense":"boxAndOne"}"#.utf8))
        XCTAssertEqual(odd.opponent, "Lions"); XCTAssertNil(odd.defense)
    }

    func testPlannedSubsFollowTheLineup() {
        let a = UUID(), b = UUID(), c = UUID(), gone = UUID()
        var plan = GamePlan()
        plan.starters = [a]
        plan.subs = [PlannedSub(playerIn: c, playerOut: a), PlannedSub(playerIn: b, playerOut: gone),
                     PlannedSub(playerIn: a), PlannedSub(playerIn: gone)]
        let valid = plan.validSubs(roster: [a, b, c])
        XCTAssertEqual(valid.map(\.playerIn), [c, b], "a starter or someone off the roster is not a planned sub")
        XCTAssertEqual(valid[0].playerOut, a)
        XCTAssertNil(valid[1].playerOut, "coming in for someone who no longer starts = for whoever needs a rest")
    }

    func testCallsAreGroupedByThePlaybooksSituations() {
        let horns = SessionPlayRef(key: "created:1", name: "Horns")
        let box = SessionPlayRef(key: "created:2", name: "Box")
        let flex = SessionPlayRef(key: "created:3", name: "Flex")
        var book = TeamPlaybook()
        var blob = book[.blob]; blob.plays = [box]; book[.blob] = blob
        var base = book[.baseOffense]; base.plays = [horns]; book[.baseOffense] = base
        let groups = GameCalls.groups(plays: [flex, box, horns], playbook: book)
        XCTAssertEqual(groups.map(\.kind), [.baseOffense, .blob, nil], "playbook order, then the rest")
        XCTAssertEqual(groups.map { $0.plays.map(\.name) }, [["Horns"], ["Box"], ["Flex"]])
        XCTAssertEqual(GameCalls.groups(plays: [flex], playbook: nil).first?.plays, [flex])
        XCTAssertTrue(GameCalls.groups(plays: [], playbook: book).isEmpty)
    }

    func testTheGameSheetIsOneA4PageOfText() throws {
        var f = GameSheetFacts()
        f.teamName = "Ballers"; f.title = "Ballers vs Tigers"; f.whenLine = "Wed 25 Nov 2026 · 14:00 · Home"
        f.starters = ["Maya Chen", "Leo Martin"]; f.bench = ["Ava Park"]
        f.subs = [.init(id: UUID(), line: "Ava Park in for Leo Martin", when: "Mid first half")]
        f.keys = ["Box out on every shot"]; f.defense = "2-3 zone — Trap the corner"
        f.calls = [.init(id: "blob", title: "BLOB", plays: ["Box"])]
        f.opponentName = "Tigers"; f.opponentNotes = "They press"
        f.threats = [.init(id: UUID(), number: "#7", note: "Left hand", guardName: "Maya Chen")]
        let doc = try XCTUnwrap(PDFDocument(data: GameSheetDocument.pdf(f)))
        XCTAssertEqual(doc.pageCount, 1)
        let page = try XCTUnwrap(doc.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        let text = page.string ?? ""
        for word in ["Ballers vs Tigers", "Box out on every shot", "Ava Park in for Leo Martin", "2-3 zone", "#7", "Maya Chen"] {
            XCTAssertTrue(text.contains(word), "the sheet's text is text: \(word)")
        }
        XCTAssertNotNil(GameSheetDocument.image(f))
    }
}
