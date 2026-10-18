import XCTest
@testable import Hoopwise

/// The live-entry rules behind the October 2026 redesign: a basket and its
/// assist are ONE action, Undo reverses exactly it, and only a drag onto a
/// teammate's row is an assist.
final class LiveGameEntryTests: XCTestCase {

    private let scorer = UUID(), passer = UUID(), team = UUID()

    private func game() -> SessionGame {
        SessionGame(sessionId: UUID(), teams: [GameTeam(id: team, name: "Blue", colorHex: "#007AFF",
                                                        playerIds: [scorer, passer])])
    }

    func testABasketWithAssistAndItsUndo() {
        var g = game()
        let action = GameStatAction(playerId: scorer, teamId: team, kind: .points(2), assistId: passer)
        action.apply(to: &g)
        XCTAssertEqual(g.stats(for: scorer)?.points, 2)
        XCTAssertEqual(g.stats(for: passer)?.assists, 1)
        XCTAssertEqual(g.score(for: team), 2)
        action.undo(on: &g)
        XCTAssertEqual(g.stats(for: scorer)?.points, 0)
        XCTAssertEqual(g.stats(for: passer)?.assists, 0)
        XCTAssertEqual(g.score(for: team), 0)
    }

    func testOnlyADragOntoATeammateIsAnAssist() {
        let rows = [scorer: CGRect(x: 0, y: 0, width: 300, height: 80),
                    passer: CGRect(x: 0, y: 90, width: 300, height: 80)]
        XCTAssertEqual(AssistDrop.passer(scorer: scorer, travelled: 100, end: CGPoint(x: 50, y: 120), rows: rows), passer)
        XCTAssertNil(AssistDrop.passer(scorer: scorer, travelled: 100, end: CGPoint(x: 50, y: 400), rows: rows),
                     "released on empty space = basket only")
        XCTAssertNil(AssistDrop.passer(scorer: scorer, travelled: 100, end: CGPoint(x: 50, y: 40), rows: rows),
                     "back on your own row = no assist")
        XCTAssertNil(AssistDrop.passer(scorer: scorer, travelled: 5, end: CGPoint(x: 50, y: 120), rows: rows),
                     "a press that barely moved is a tap")
    }
}

/// The standard basket value set on the setup page travels with the game.
final class GameBasketValueTests: XCTestCase {

    func testOlderGamesReadTwoAndTheValueRoundTrips() throws {
        var game = SessionGame(sessionId: UUID(), basketValue: 3)
        let data = try JSONEncoder().encode(game)
        XCTAssertEqual(try JSONDecoder().decode(SessionGame.self, from: data).basketValue, 3)

        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "basketValue")                 // a game saved before the field
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(SessionGame.self, from: old).basketValue, 2)

        game = SessionGame(sessionId: UUID(), basketValue: 7)
        XCTAssertEqual(game.basketValue, 3, "only 1, 2 or 3")
    }
}
