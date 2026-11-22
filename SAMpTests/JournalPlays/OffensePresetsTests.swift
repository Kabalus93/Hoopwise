import Foundation
import Testing
@testable import Hoopwise

/// The board's Offense presets and the empty court Clear leaves (22 Nov 2026).
struct OffensePresetsTests {
    @Test func everyFormatHasPresetsAndIdsAreUnique() {
        for n in 1...5 { #expect(!OffensePresets.with(players: n).isEmpty, "\(n)v\(n)") }
        #expect(Set(OffensePresets.all.map(\.id)).count == OffensePresets.all.count)
        // Everyone on the floor, numbered 1…n, 1 with the ball.
        for preset in OffensePresets.all {
            let d = preset.diagram(court: .half)
            #expect(d.offense.map(\.number).sorted() == Array(1...preset.players), "\(preset.id)")
            #expect(d.balls == [1], "\(preset.id)")
            #expect(d.offense.allSatisfy { $0.at.x >= 0 && $0.at.x <= 15 && $0.at.y >= 0 && $0.at.y <= 14 }, "\(preset.id)")
        }
    }

    @Test func fiveOutIsTheFamiliarStart() {
        let five = OffensePresets.all.first { $0.id == "fiveOut" }!
        #expect(JournalPlayMath.applying(five, to: JournalPlayDiagram(), court: .half) == JournalPlayMath.defaultAlignment(.half))
        #expect(OffensePresets.matching(JournalPlayMath.defaultAlignment(.half), court: .half)?.id == "fiveOut")
        #expect(OffensePresets.matching(JournalPlayDiagram(), court: .half) == nil, "an empty court is no set")
    }

    @Test func applyingASetDropsTheLinesAndRematchesTheDefense() {
        var d = JournalPlayMath.defaultAlignment(.half)
        d.actions = [.init(kind: .cut, player: 2, path: [JournalCourtPoint(12.6, 6.6), JournalCourtPoint(9, 3)])]
        d.cones = [JournalCourtPoint(4, 8)]
        d = JournalPlayMath.applyingDefense(.man, to: [d], court: .half)[0]
        let three = OffensePresets.all.first { $0.id == "threeOut" }!
        let out = JournalPlayMath.applying(three, to: d, court: .half)
        #expect(out.offense.count == 3)
        #expect(out.actions.isEmpty, "lines drawn from the old spots go")
        #expect(out.cones == d.cones, "cones stay")
        #expect(out.defense.count == 3 && Set(out.defense.compactMap(\.guards)) == [1, 2, 3], "one defender per attacker")
    }

    @Test func aFullCourtGetsTheSetAtTheAttackedEnd() {
        let horns = OffensePresets.all.first { $0.id == "horns" }!.diagram(court: .full)
        #expect(horns.offense.allSatisfy { $0.at.x > 14 }, "in the front court")
    }

    @Test func clearLeavesAnEmptyCourtThatCountsAsBlank() {
        let empty = DrillDrawing.empty(court: .half)
        #expect(empty.steps.count == 1 && empty.steps[0].diagram.offense.isEmpty)
        #expect(CoachBoardStore.isBlank(empty))
        #expect(CoachBoardStore.isBlank(.new(court: .half)), "a drill drawing's start is blank too")
    }
}
