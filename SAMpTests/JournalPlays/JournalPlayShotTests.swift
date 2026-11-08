import Foundation
import Testing
@testable import Hoopwise

/// Shots (November 2026): a solid red line to the rim; a dribble that ends
/// at the rim is drawn red too.
struct JournalPlayShotTests {
    typealias P = JournalCourtPoint

    static let five = JournalPlayMath.defaultAlignment(.half)

    @Test func aShotEndsInTheRimWhereverTheFingerStops() throws {
        let added = try #require(JournalPlayMath.adding(.shot, by: 1, along: [P(7.5, 9.6), P(7, 6), P(6.5, 4)],
                                                        to: Self.five, radius: 0.8))
        let shot = try #require(added.actions.last)
        #expect(shot.kind == .shot)
        #expect(shot.path == [P(7.5, 9.6), P(7.5, 1.575)])
    }

    @Test func onTheFullCourtAShotGoesToTheNearerBasket() throws {
        let full = JournalPlayMath.defaultAlignment(.full)
        let right = try #require(JournalPlayMath.adding(.shot, by: 1, along: [P(5.5, 7.5), P(20, 7.5)], to: full,
                                                        radius: 0.8, court: .full))
        #expect(right.actions.last?.path.last == P(26.425, 7.5))
        let left = try #require(JournalPlayMath.adding(.shot, by: 1, along: [P(5.5, 7.5), P(3, 7.5)], to: full,
                                                       radius: 0.8, court: .full))
        #expect(left.actions.last?.path.last == P(1.575, 7.5))
    }

    @Test func aShotSendsTheBallToTheRimAndOutOfPlay() {
        var diagram = Self.five
        diagram.actions = [.init(kind: .shot, player: 1, path: [P(7.5, 9.6), P(7.5, 1.575)])]
        #expect(!JournalPlayMath.endSpots(diagram).contains { $0.number == 1 }, "a shot does not move the shooter")
        #expect(JournalPlayMath.ballsAfter(diagram).isEmpty)
        #expect(JournalPlayMath.startOfNextStep(after: diagram).balls.isEmpty)
        let mid = JournalPlayMath.frame(diagram, at: 0.5)
        #expect(mid.balls.first?.inFlight == true)
        let end = JournalPlayMath.frame(diagram, at: 1)
        #expect(end.balls.map(\.at) == [P(7.5, 1.575)], "the ball rests at the rim at the end of the step")
        #expect(end.players[1] == P(7.5, 9.6))
    }

    @Test func aDribbleToTheRimIsAtTheBasket() {
        #expect(JournalCourtKind.half.isAtBasket(P(7.9, 2.3)))
        #expect(!JournalCourtKind.half.isAtBasket(P(7.5, 5.8)))
        #expect(JournalCourtKind.full.isAtBasket(P(26, 7)))
    }

    @Test func courtsConvertShotsRimToRim() {
        var diagram = Self.five
        diagram.actions = [.init(kind: .shot, player: 1, path: [P(7.5, 9.6), P(7.5, 1.575)])]
        let full = JournalPlayMath.converted(diagram, from: .half, to: .full)
        #expect(full.actions[0].path.last == P(26.425, 7.5))
    }
}
