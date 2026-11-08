import Foundation
import Testing
@testable import Hoopwise

/// Several balls in a drawing (a drill where more than one player has a
/// ball), and plays named in a session plan.
struct JournalPlayBallsTests {
    typealias P = JournalCourtPoint

    /// 1 and 2 each have a ball: 1 passes to 3, 2 passes to 4.
    static let twoBalls = JournalPlayDiagram(
        offense: [
            .init(number: 1, at: P(5, 10)), .init(number: 2, at: P(10, 10)),
            .init(number: 3, at: P(2, 5)), .init(number: 4, at: P(13, 5)),
        ],
        balls: [1, 2],
        actions: [
            .init(kind: .pass, player: 1, path: [P(5, 10), P(2, 5)], receiver: 3),
            .init(kind: .pass, player: 2, path: [P(10, 10), P(13, 5)], receiver: 4),
        ])

    @Test func eachPassMovesItsPassersBall() {
        #expect(JournalPlayMath.ballsAfter(Self.twoBalls) == [3, 4])
        #expect(JournalPlayMath.startOfNextStep(after: Self.twoBalls).balls == [3, 4])
    }

    @Test func playbackDrawsEveryBall() {
        let start = JournalPlayMath.frame(Self.twoBalls, at: 0)
        #expect(start.balls.map(\.at) == [P(5, 10), P(10, 10)])
        // Halfway through the first pass: 1's ball in the air, 2's still held.
        let mid = JournalPlayMath.frame(Self.twoBalls, at: 0.25)
        #expect(mid.balls.count == 2)
        #expect(mid.balls[0].inFlight && !mid.balls[1].inFlight)
        #expect(mid.balls[1].at == P(10, 10))
        let end = JournalPlayMath.frame(Self.twoBalls, at: 1)
        #expect(end.balls.map(\.at) == [P(2, 5), P(13, 5)])
    }

    @Test func oneBallStillMovesOnAnyPass() {
        // A play's single ball goes with a pass even when drawn from another player.
        var diagram = Self.twoBalls
        diagram.balls = [2]
        diagram.actions = [Self.twoBalls.actions[0]]
        #expect(JournalPlayMath.ballsAfter(diagram) == [3])
    }

    @Test func drawingsStoreTheFirstBallForOlderBuilds() throws {
        let data = try JSONEncoder().encode(Self.twoBalls)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["ball"] as? Int == 1)
        #expect(json["balls"] as? [Int] == [1, 2])
        #expect(try JSONDecoder().decode(JournalPlayDiagram.self, from: data) == Self.twoBalls)
    }

    @Test func aDrawingFromBeforeSeveralBallsReadsAsOne() throws {
        let old = #"{"offense":[{"number":1,"at":{"x":1,"y":1}}],"defense":[],"ball":1,"actions":[],"notes":[]}"#
        let diagram = try JSONDecoder().decode(JournalPlayDiagram.self, from: Data(old.utf8))
        #expect(diagram.balls == [1])
        let none = #"{"offense":[],"defense":[],"actions":[],"notes":[]}"#
        #expect(try JSONDecoder().decode(JournalPlayDiagram.self, from: Data(none.utf8)).balls.isEmpty)
    }

    // MARK: - Plays in a session plan

    @Test func aPlanFromBeforePlaysHasNone() throws {
        let old = #"{"warmupDrillIds":[],"skillDrillIds":[],"gameDrillIds":[],"warmupMinutes":30,"skillsMinutes":30,"gameMinutes":30}"#
        let plan = try JSONDecoder().decode(SessionCurriculum.self, from: Data(old.utf8))
        #expect(plan.plays.isEmpty)
        var withPlays = plan
        withPlays.plays = [SessionPlayRef(key: "starter:zone-23", name: "Zone-23")]
        let back = try JSONDecoder().decode(SessionCurriculum.self, from: JSONEncoder().encode(withPlays))
        #expect(back == withPlays)
    }

    @Test func aPlayIsFoundByStarterKeyOrCreationMoment() {
        let created = Date(timeIntervalSince1970: 1_800_000_000.123456)
        let ref = SessionPlayRef(key: SessionPlayRef.createdKey(created), name: "Mine")
        #expect(ref.matches(starterKey: nil, createdAt: created))
        // Another device reads CloudKit's millisecond date.
        #expect(ref.matches(starterKey: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_000.123)))
        #expect(!ref.matches(starterKey: nil, createdAt: created.addingTimeInterval(0.01)))
        let starter = SessionPlayRef(key: SessionPlayRef.starterKey("horns"), name: "Horns")
        #expect(starter.matches(starterKey: "horns", createdAt: created))
        #expect(!starter.matches(starterKey: "zone-23", createdAt: created))
    }
}
