import XCTest
@testable import Hoopwise

@MainActor
final class GameStatsReportTests: XCTestCase {

    private let a = UUID(), b = UUID(), bench = UUID(), team = UUID()

    private func game(_ lines: [(UUID, Int, Int)], value: Int = 2, status: SessionGameStatus = .completed) -> SessionGame {
        let id = UUID()
        return SessionGame(sessionId: UUID(), gameType: .twoTeam,
                           playerStats: lines.map { SessionPlayerStats(playerId: $0.0, gameId: id, teamId: team,
                                                                       points: $0.1, rebounds: 1, assists: $0.2) },
                           basketValue: value, status: status)
    }

    private func session(day: Int, _ games: [SessionGame], status: SessionEventStatus = .completed) -> SessionEvent {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 9))!
        var s = SessionEvent(programId: nil, title: "U8", date: start, startTime: start,
                             endTime: start.addingTimeInterval(3600), status: status, attendeeIds: [])
        s.games = games
        return s
    }

    func testCollectiveAveragesAndAssistRate() {
        // Two games: 10 + 6 points (2-point baskets → 8 baskets), 2 + 2 assists.
        let s = session(day: 1, [game([(a, 6, 1), (b, 4, 1)]), game([(a, 6, 2)])])
        let r = GameStatsReport.make(sessions: [s], roster: [a, b, bench], current: nil)
        XCTAssertEqual(r.games, 2)
        XCTAssertEqual(r.average[.points], 8)
        XCTAssertEqual(r.average[.assists], 2)
        XCTAssertEqual(r.average[.rebounds], 1.5)
        XCTAssertEqual(r.average[.assistRate]!, 4.0 / 8.0, accuracy: 0.0001)
    }

    func testBasketValueIsRespected() {
        let s = session(day: 1, [game([(a, 3, 1)], value: 1)])
        let r = GameStatsReport.make(sessions: [s], roster: [a], current: nil)
        XCTAssertEqual(r.average[.assistRate]!, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testUnplayedAndDidNotHappenAreLeftOut() {
        let setup = session(day: 1, [game([(a, 10, 0)], status: .setup)])
        let skipped = session(day: 2, [game([(a, 10, 0)])], status: .skipped)
        let real = session(day: 3, [game([(a, 2, 0)])])
        let r = GameStatsReport.make(sessions: [setup, skipped, real], roster: [a], current: nil)
        XCTAssertEqual(r.games, 1)
        XCTAssertEqual(r.sessions, 1)
        XCTAssertEqual(r.average[.points], 2)
    }

    func testDirectionComparesRecentWithEarlier() {
        let early = (1...3).map { session(day: $0, [game([(a, 4, 0)])]) }
        let late = (4...6).map { session(day: $0, [game([(a, 8, 0)])]) }
        let r = GameStatsReport.make(sessions: early + late, roster: [a], current: nil)
        XCTAssertEqual(r.direction[.points]!, 1.0, accuracy: 0.0001)   // doubled
        XCTAssertEqual(r.trend.count, 6)
        XCTAssertEqual(r.trend.first?.values[.points], 4)
    }

    func testNoDirectionWithTooFewSessions() {
        let r = GameStatsReport.make(sessions: [session(day: 1, [game([(a, 4, 0)])])], roster: [a], current: nil)
        XCTAssertTrue(r.direction.isEmpty)
    }

    func testLeadersPlayingAndThisSession() {
        let s1 = session(day: 1, [game([(a, 10, 0), (b, 2, 3)])])
        let s2 = session(day: 2, [game([(a, 4, 0)])])
        let r = GameStatsReport.make(sessions: [s1, s2], roster: [a, b, bench], current: s2)
        XCTAssertEqual(r.leaders[.points]?.first?.playerId, a)
        XCTAssertEqual(r.leaders[.points]?.first?.total, 14)
        XCTAssertEqual(r.leaders[.assists]?.map(\.playerId), [b])
        XCTAssertEqual(r.playing.map(\.games), [2, 1, 0])
        XCTAssertEqual(r.playing.last?.playerId, bench)
        XCTAssertEqual(r.thisSession?[.points], 4)
    }
}
