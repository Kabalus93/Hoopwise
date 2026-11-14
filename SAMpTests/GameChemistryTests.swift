import XCTest
@testable import Hoopwise

/// The basket log (who scored, who passed) and what GameChemistry reads from
/// it: how a player scores, and who connects with whom (14 November 2026).
final class GameChemistryTests: XCTestCase {

    private let a = UUID(), b = UUID(), c = UUID(), coach = UUID(), team = UUID()

    private func session(_ baskets: [(UUID, UUID?)], status: SessionEventStatus = .completed) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        var s = SessionEvent(programId: nil, title: "U10", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        var g = SessionGame(sessionId: s.id, teams: [GameTeam(id: team, name: "Blue", colorHex: "#007AFF",
                                                              playerIds: [a, b, c, coach])])
        g.baskets = baskets.map { GameBasket(scorerId: $0.0, assisterId: $0.1, points: 2, teamId: team) }
        s.games = [g]
        return s
    }

    func testABasketIsLoggedAndUndoRemovesExactlyIt() {
        var g = SessionGame(sessionId: UUID(), teams: [GameTeam(id: team, name: "Blue", colorHex: "#007AFF",
                                                                playerIds: [a, b])])
        let first = GameStatAction(playerId: a, teamId: team, kind: .points(2), assistId: b)
        let second = GameStatAction(playerId: b, teamId: team, kind: .points(3))
        first.apply(to: &g); second.apply(to: &g)
        XCTAssertEqual(g.baskets.count, 2)
        XCTAssertEqual(g.baskets[0].assisterId, b)
        first.undo(on: &g)
        XCTAssertEqual(g.baskets.map(\.scorerId), [b])
        GameStatAction(playerId: a, teamId: team, kind: .rebound).apply(to: &g)
        XCTAssertEqual(g.baskets.count, 1, "only baskets are logged")
    }

    func testTheLogRoundTripsAndOlderGamesReadEmpty() throws {
        let s = session([(a, b)])
        let data = try JSONEncoder().encode(s.games[0])
        XCTAssertEqual(try JSONDecoder().decode(SessionGame.self, from: data).baskets, s.games[0].baskets)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "baskets")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(SessionGame.self, from: old).baskets, [])
    }

    func testSummaryCountsCreationDuosAndPlaymakers() {
        // a: 4 off b's pass + 1 own; c: 2 own; b finds a four times.
        let s = session([(a, b), (a, b), (a, b), (a, b), (a, nil), (c, nil), (c, nil), (b, c)])
        let sum = GameChemistry.summary(sessions: [s])
        XCTAssertEqual(sum.baskets, 8)
        XCTAssertEqual(sum.assisted, 5)
        XCTAssertEqual(sum.creation.first?.playerId, a)
        XCTAssertEqual(sum.creation.first?.assisted, 4)
        XCTAssertEqual(sum.duos.first, GameChemistry.Duo(passer: b, scorer: a, count: 4))
        XCTAssertEqual(sum.playmakers.first?.playerId, b)
        XCTAssertEqual(sum.playmakers.first?.favourite, a)
    }

    func testSkippedSessionsAndCoachesAreLeftOut() {
        let skipped = session([(a, b), (a, b)], status: .cancelled)
        let played = session([(coach, a), (a, coach)])
        let sum = GameChemistry.summary(sessions: [skipped, played], excluding: [coach])
        XCTAssertEqual(sum.baskets, 1, "the coach's basket goes; the skipped class says nothing")
        XCTAssertEqual(sum.creation.first?.assisted, 0, "a coach's pass is not an assist")
        XCTAssertTrue(sum.duos.isEmpty)
    }

    func testReadingsStayQuietUntilThereIsEnough() {
        let few = GameChemistry.player(a, sessions: [session([(a, b), (a, b)])])
        XCTAssertTrue(GameChemistry.readings(for: few).isEmpty)

        let s = session([(a, b), (a, b), (a, b), (a, c), (a, b), (b, a), (b, a), (c, a)])
        let p = GameChemistry.player(a, sessions: [s])
        let r = GameChemistry.readings(for: p)
        XCTAssertTrue(r.contains(.finisher(assisted: 5, of: 5)))
        XCTAssertTrue(r.contains(.fedBy(player: b, count: 4, of: 5)))
        XCTAssertTrue(r.contains(.feeds(player: b, count: 2, of: 3)))

        let solo = GameChemistry.player(c, sessions: [session(Array(repeating: (c, nil), count: 6))])
        XCTAssertEqual(GameChemistry.readings(for: solo), [.creator(own: 6, of: 6)])
    }
}
