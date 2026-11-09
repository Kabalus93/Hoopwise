import Foundation
import Testing
@testable import Hoopwise

/// Drill drawings: the Plays editor's diagram with cones and any number of
/// players, stored as a drill visual's editable file.
struct DrillDrawingTests {
    typealias P = JournalCourtPoint

    @Test func aPlayWithoutConesWritesNoConesKey() throws {
        let diagram = JournalPlayMath.defaultAlignment(.half)
        let json = try #require(String(data: JSONEncoder().encode(diagram), encoding: .utf8))
        #expect(!json.contains("cones"))
        #expect(try JSONDecoder().decode(JournalPlayDiagram.self, from: JSONEncoder().encode(diagram)) == diagram)
    }

    @Test func conesRoundTripAndCarryIntoTheNextStep() throws {
        var diagram = JournalPlayMath.defaultAlignment(.half)
        diagram.cones = [P(3, 8), P(12, 8)]
        let back = try JSONDecoder().decode(JournalPlayDiagram.self, from: JSONEncoder().encode(diagram))
        #expect(back.cones == diagram.cones)
        #expect(JournalPlayMath.startOfNextStep(after: diagram).cones == diagram.cones)
    }

    @Test func aConeIsHitAndErased() {
        var diagram = JournalPlayDiagram()
        diagram.cones = [P(3, 8), P(12, 8)]
        #expect(JournalPlayMath.hit(P(12.1, 8), in: diagram, radius: 0.5) == .cone(1))
        #expect(JournalPlayMath.erasing(.cone(0), in: diagram).cones == [P(12, 8)])
    }

    @Test func conesFollowACourtChange() {
        var diagram = JournalPlayDiagram()
        diagram.cones = [P(3, 8)]
        #expect(JournalPlayMath.converted(diagram, from: .half, to: .full).cones == [P(20, 3)])
    }

    @Test func aSixthPlayerTakesTheNextNumber() {
        let diagram = JournalPlayMath.defaultAlignment(.half)
        #expect(diagram.nextPlayerNumber == 6)
        #expect(JournalPlayDiagram().nextPlayerNumber == 1)
    }

    @Test func removingAPlayerTakesTheirLinesPassesToThemAndTheirBall() {
        let diagram = JournalPlayDiagram(
            offense: [.init(number: 1, at: P(7, 10)), .init(number: 2, at: P(12, 6)), .init(number: 3, at: P(2, 6))],
            balls: [1, 2],
            actions: [
                .init(kind: .pass, player: 1, path: [P(7, 10), P(12, 6)], receiver: 2),
                .init(kind: .cut, player: 2, path: [P(12, 6), P(9, 2)]),
                .init(kind: .cut, player: 3, path: [P(2, 6), P(5, 2)]),
            ])
        let out = JournalPlayMath.removing(player: 2, from: diagram)
        #expect(out.offense.map(\.number) == [1, 3])
        #expect(out.balls == [1])
        #expect(out.actions.count == 1)
        #expect(out.actions.first?.player == 3)
    }

    @Test func aDrawingRoundTripsAndOtherDataIsNotOne() throws {
        var drawing = DrillDrawing.new()
        drawing.steps[0].caption = "Set"
        drawing.steps.append(.init(diagram: JournalPlayMath.startOfNextStep(after: drawing.steps[0].diagram)))
        let back = try #require(DrillDrawing.decode(drawing.encoded))
        #expect(back == drawing)
        #expect(DrillDrawing.decode(Data([0x08, 0x01, 0x12])) == nil)   // a PencilKit blob
        #expect(DrillDrawing.decode(Data("{}".utf8)) == nil)
        #expect(DrillDrawing.decode(nil) == nil)
    }
}
