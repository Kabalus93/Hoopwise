import Foundation
import SwiftData
import Testing
@testable import Hoopwise

/// Plays written from a description (the Claude Desktop connector's
/// create_play / get_play / add_play_step …, November 2026).
@MainActor
@Suite("Writing plays from a description", .serialized)
struct JournalPlayAuthoringTests {
    typealias P = JournalCourtPoint

    /// Horns, written the way Claude would: a set, then only what changes.
    static func horns() -> [String: Any] {
        [
            "name": "Horns Flare",
            "category": "half_court",
            "court": "half",
            "situation": "Early offence or after a timeout",
            "concept": "Bigs at the elbows; 1 enters to 4, 5 flares 2.",
            "source": "Conversation with Claude",
            "steps": [
                [
                    "caption": "Set",
                    "text": "4 and 5 at the elbows, 2 and 3 in the corners.",
                    "diagram": [
                        "offense": [
                            ["number": 1, "x": 7.5, "y": 9.6], ["number": 2, "x": 13.9, "y": 1.2],
                            ["number": 3, "x": 1.1, "y": 1.2], ["number": 4, "x": 5.05, "y": 5.8],
                            ["number": 5, "x": 9.95, "y": 5.8],
                        ],
                        "defense": [["x": 7.5, "y": 8.4, "read": true]],
                        "balls": [1],
                        "actions": [
                            ["kind": "pass", "player": 1, "to": 4],
                            ["kind": "screen", "player": 5, "path": [[12.2, 3.0]]],
                            ["kind": "cut", "player": 2, "path": [[13.5, 4.0], [12.4, 7.2]], "shape": "curved"],
                        ],
                    ],
                ],
                [
                    "caption": "Shot",
                    "text": "4 hits 2 off the flare; 2 shoots.",
                    "diagram": ["actions": [["kind": "pass", "player": 4, "to": 2], ["kind": "shot", "player": 2]]],
                ],
            ],
            "wrinkles": [[
                "name": "Slip",
                "notes": "5 slips when the defence switches.",
                "steps": [["caption": "Slip", "diagram": ["actions": [
                    ["kind": "dribble", "player": 1, "path": [[9.0, 7.5]]],
                    ["kind": "cut", "player": 5, "path": [[8.0, 2.2]]],
                ]]]],
            ]],
        ]
    }

    @Test func aWrittenPlayIsSavedAsTheEditorWouldDrawIt() throws {
        let context = try JournalPlayTestStore.freshContext()
        let made = try JournalPlayAuthoring.createPlay(Self.horns(), in: context)
        let play = made.play
        #expect(play.name == "Horns Flare" && play.category == .halfCourt && play.court == .half)
        #expect(play.situation == "Early offence or after a timeout")
        let steps = try #require(play.conceptPart?.sortedSteps)
        #expect(steps.map(\.caption) == ["Set", "Shot"])

        let set = steps[0].diagram
        #expect(set.offense.count == 5 && set.balls == [1] && set.defense.first?.isRead == true)
        // The pass is drawn 1 → 4 where they stand; moves start at the player.
        #expect(set.actions[0].path == [P(7.5, 9.6), P(5.05, 5.8)])
        #expect(set.actions[1].path == [P(9.95, 5.8), P(12.2, 3.0)])
        #expect(set.actions[2].path.first == P(13.9, 1.2) && set.actions[2].shape == .curved)

        // Step 2 carried over: 2 is at their flare spot, 4 has the ball.
        let shot = steps[1].diagram
        #expect(shot.player(2)?.at == P(12.4, 7.2))
        #expect(shot.balls == [4])
        #expect(shot.actions[0].path == [P(5.05, 5.8), P(12.4, 7.2)])
        #expect(shot.actions[1].kind == .shot && shot.actions[1].path.last == P(7.5, 1.575))
        #expect(made.warnings.isEmpty, "\(made.warnings)")

        // The wrinkle starts from the concept's set, without its lines.
        let slip = try #require(play.parts(.wrinkle).first?.sortedSteps.first?.diagram)
        #expect(slip.player(5)?.at == P(9.95, 5.8))
        #expect(slip.actions.count == 2 && slip.balls == [1])
    }

    @Test func mistakesNameTheFieldAndSaveNothing() throws {
        let context = try JournalPlayTestStore.freshContext()
        var spec = Self.horns()
        var steps = spec["steps"] as! [[String: Any]]
        steps[1]["diagram"] = ["actions": [["kind": "pass", "player": 4, "to": 9]]]
        spec["steps"] = steps
        #expect {
            try JournalPlayAuthoring.createPlay(spec, in: context)
        } throws: { error in
            (error as? JournalPlayAuthoringError)?.localizedDescription.contains("steps[1].actions[0]") == true
        }
        #expect(JournalPlayAuthoring.allPlays(in: context).isEmpty, "a failed create left a play behind")

        var offCourt = Self.horns()
        var bad = offCourt["steps"] as! [[String: Any]]
        bad[0]["diagram"] = ["offense": [["number": 1, "x": 30, "y": 5]]]
        offCourt["steps"] = bad
        #expect(throws: JournalPlayAuthoringError.self) { try JournalPlayAuthoring.createPlay(offCourt, in: context) }
    }

    @Test func aPassWithoutTheBallIsSavedWithAWarning() throws {
        let context = try JournalPlayTestStore.freshContext()
        let made = try JournalPlayAuthoring.createPlay([
            "name": "Two balls",
            "steps": [["diagram": ["balls": [1, 2], "actions": [["kind": "pass", "player": 3, "to": 4]]]]],
        ], in: context)
        #expect(made.warnings.contains { $0.contains("without a ball") })
    }

    @Test func getPlayReadsBackInTheFormatCreateTakes() throws {
        let context = try JournalPlayTestStore.freshContext()
        let original = try JournalPlayAuthoring.createPlay(Self.horns(), in: context).play
        var described = JournalPlayAuthoring.describe(original)
        let parts = described["parts"] as! [[String: Any]]
        described["name"] = "Horns Flare copy"
        described["steps"] = parts[0]["steps"]
        described["wrinkles"] = parts.filter { $0["kind"] as? String == "wrinkle" }
        // Through JSON, as the connector sends it.
        let json = try JSONSerialization.data(withJSONObject: described)
        let spec = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let copy = try JournalPlayAuthoring.createPlay(spec, in: context).play
        let a = original.sortedParts.flatMap(\.sortedSteps).map(\.diagram)
        let b = copy.sortedParts.flatMap(\.sortedSteps).map(\.diagram)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(x.balls == y.balls && x.offense.map(\.number) == y.offense.map(\.number))
            #expect(zip(x.actions, y.actions).allSatisfy { $0.kind == $1.kind && $0.player == $1.player && $0.shape == $1.shape
                && zip($0.path, $1.path).allSatisfy { $0.distance(to: $1) < 0.01 } })
        }
    }

    @Test func stepsAreAddedAndChangedInPlace() throws {
        let context = try JournalPlayTestStore.freshContext()
        let play = try JournalPlayAuthoring.createPlay(Self.horns(), in: context).play
        let id = JournalPlayAuthoring.playID(play)
        #expect(try JournalPlayAuthoring.find(id, in: context) === play)
        #expect(try JournalPlayAuthoring.find("horns flare", in: context) === play)

        let concept = try JournalPlayAuthoring.part("concept", of: play)
        let (added, _) = try JournalPlayAuthoring.addStep(to: concept, after: nil, [
            "caption": "Rebound", "diagram": ["actions": [["kind": "cut", "player": 5, "path": [[9, 2]]]]],
        ], in: context)
        #expect(added.order == 2 && concept.sortedSteps.count == 3)
        #expect(added.diagram.balls.isEmpty, "after a shot the ball is out of play")

        let first = concept.sortedSteps[0]
        _ = try JournalPlayAuthoring.updateStep(first, ["caption": "Horns", "diagram": ["defense": []]], in: context)
        #expect(first.caption == "Horns" && first.diagram.defense.isEmpty && first.diagram.actions.count == 3)

        try JournalPlayAuthoring.updatePlay(play, ["court": "full", "category": "transition"], in: context)
        #expect(play.court == .full && play.category == .transition)
        #expect(play.conceptPart?.sortedSteps[1].diagram.actions[1].path.last == P(26.425, 7.5))

        let (variation, _) = try JournalPlayAuthoring.addPart(to: play, [
            "kind": "variation", "name": "Horns Twist",
            "steps": [["diagram": ["actions": [["kind": "screen", "player": 4, "path": [[18, 9]]]]]]],
        ], in: context)
        #expect(try JournalPlayAuthoring.part(variation.name, of: play) === variation)
    }

    @Test func theGuideCoversEveryKindAndBothCourts() {
        for word in ["cut", "dribble", "pass", "shot", "screen", "straight", "curved", "balls", "read", "half", "full", "(7.5, 1.575)", "(26.425, 7.5)"] {
            #expect(JournalPlayAuthoring.guide.contains(word), "\(word)")
        }
    }
}
