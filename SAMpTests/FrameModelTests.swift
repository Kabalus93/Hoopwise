import XCTest
import CoreGraphics
@testable import Hoopwise

/// PLAY EDITOR v2, PHASE A — the frame model.
///
/// The acceptance for this phase: round-trip tests, and a hand-built four-frame
/// play that resolves to correct positions and possession at any t. The
/// four-frame play below is the one the phase is accepted on — a horns-ish
/// entry: O1 dribbles right, O5 screens for O2, O1 passes to O2, O2 shoots.
///
/// What these are really guarding: TIME IS DERIVED. Nothing in this model
/// stores a timestamp, so every assertion about "at 1.2 seconds" is really an
/// assertion that the derivation from path length ÷ pace is stable. If someone
/// later adds a stored duration, these are the tests that should stop them.
final class FrameModelTests: XCTestCase {

    // Fixed ids so failures name a player rather than a UUID.
    private let o1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let o2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private let o5 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!
    private let rim = CGPoint(x: 25, y: 5.25)

    private var pace: PlayPace { .default }

    /// O1 top of the key, O2 right wing, O5 left block.
    private func startFormation() -> Formation {
        Formation([o1: CGPoint(x: 25, y: 28),
                   o2: CGPoint(x: 43, y: 22),
                   o5: CGPoint(x: 8, y: 10)])
    }

    /// The four-frame acceptance play.
    ///
    ///   1  O1 dribbles right toward the wing.
    ///   2  O5 climbs to set a screen for O2 (and O2 cuts off it).
    ///   3  O1 passes to O2.
    ///   4  O2 shoots.
    private func acceptancePlay() -> FrameSequence {
        var sequence = FrameSequence(startFormation: startFormation(),
                                     frames: [], pace: pace, rim: rim)
        sequence.appendFrame(caption: "O1 dribbles right")
        sequence.addAction(PlayAction(kind: .dribble, actorId: o1,
                                      path: [CGPoint(x: 34, y: 28)]), toFrame: 0)

        sequence.appendFrame(caption: "O5 up to screen, O2 curls")
        sequence.addAction(PlayAction(kind: .screen, actorId: o5,
                                      path: [CGPoint(x: 20, y: 18)],
                                      screenForId: o2), toFrame: 1)
        sequence.addAction(PlayAction(kind: .cut, actorId: o2,
                                      path: [CGPoint(x: 30, y: 14)]), toFrame: 1)

        sequence.appendFrame(caption: "Pass to the curl")
        sequence.addAction(PlayAction(kind: .pass, actorId: o1,
                                      target: .player(o2)), toFrame: 2)

        sequence.appendFrame(caption: "Finish")
        sequence.addAction(PlayAction(kind: .shot, actorId: o2,
                                      target: .point(rim)), toFrame: 3)
        return sequence
    }

    // MARK: - Structure

    func testFourFrameStructure() {
        let play = acceptancePlay()
        XCTAssertEqual(play.frames.count, 4)
        XCTAssertEqual(play.frames.map(\.caption),
                       ["O1 dribbles right", "O5 up to screen, O2 curls",
                        "Pass to the curl", "Finish"])
        XCTAssertEqual(play.frames[1].validActions.count, 2,
                       "actions in one frame run concurrently — both belong to frame 2")
    }

    /// A frame lasts as long as its LONGEST action, because a frame is one
    /// moment and everything in it happens at once.
    func testFrameDurationIsItsLongestAction() {
        let play = acceptancePlay()
        let start = play.formation(enteringFrame: 1)
        let frame = play.frames[1]
        let screen = frame.duration(of: frame.validActions[0], from: start, pace: pace, rim: rim)
        let cut = frame.duration(of: frame.validActions[1], from: start, pace: pace, rim: rim)
        XCTAssertEqual(frame.duration(from: start, pace: pace, rim: rim),
                       max(screen, cut), accuracy: 0.0001)
        XCTAssertNotEqual(screen, cut, accuracy: 0.0001,
                          "fixture must have unequal actions or it proves nothing")
    }

    /// Duration is path length ÷ pace, and nothing else. Checked against the
    /// arithmetic done by hand, so a change to the derivation shows up here
    /// rather than as a play that suddenly runs at the wrong speed.
    func testDurationIsPathLengthOverPace() {
        let play = acceptancePlay()
        // Frame 1: O1 dribbles (25,28) → (34,28) = 9 ft at the cut tier.
        let expected = 9.0 / pace.cut
        XCTAssertEqual(play.frameDurations[0], expected, accuracy: 0.0001)
    }

    /// An action's pace tier is the only knob, and `sprint` is reachable.
    func testSprintTierShortensTheSamePath() {
        var walkPlay = FrameSequence(startFormation: startFormation(), pace: pace, rim: rim)
        walkPlay.appendFrame()
        walkPlay.addAction(PlayAction(kind: .cut, actorId: o1,
                                      path: [CGPoint(x: 25, y: 8)]), toFrame: 0)
        var sprintPlay = walkPlay
        sprintPlay.frames[0].actions[0].pace = .sprint
        XCTAssertLessThan(sprintPlay.duration, walkPlay.duration)
        XCTAssertEqual(sprintPlay.duration,
                       walkPlay.duration * (pace.cut / pace.sprint), accuracy: 0.0001)
    }

    // MARK: - Positions at any t

    func testPositionsResolveAtAnyTime() {
        let play = acceptancePlay()
        let starts = play.frameStartTimes
        let durations = play.frameDurations

        // Before the play: the start formation.
        XCTAssertEqual(play.position(of: o1, at: -1).x, 25, accuracy: 0.0001)

        // Halfway through frame 1, O1 is halfway along a straight 9ft dribble.
        let mid = starts[0] + durations[0] / 2
        XCTAssertEqual(play.position(of: o1, at: mid).x, 29.5, accuracy: 0.01)

        // CONTINUITY IS THE DEFAULT: O2 has no action in frame 1, so he is
        // exactly where he started — no keyframe required to pin him.
        XCTAssertEqual(play.position(of: o2, at: mid).x, 43, accuracy: 0.0001)
        XCTAssertEqual(play.position(of: o2, at: mid).y, 22, accuracy: 0.0001)

        // End of frame 2: everyone at that frame's end formation.
        let afterTwo = starts[2]
        XCTAssertEqual(play.position(of: o5, at: afterTwo).x, 20, accuracy: 0.01)
        XCTAssertEqual(play.position(of: o2, at: afterTwo).y, 14, accuracy: 0.01)
        // …and O1 held his ground through frame 2 rather than snapping back.
        XCTAssertEqual(play.position(of: o1, at: afterTwo).x, 34, accuracy: 0.01)

        // Past the end: the last formation, held.
        XCTAssertEqual(play.position(of: o2, at: play.duration + 5).y, 14, accuracy: 0.01)
    }

    /// A bent path is walked by ARC LENGTH, so a player does not lurch between
    /// control points.
    func testBentPathIsTraversedAtConstantSpeed() {
        var play = FrameSequence(startFormation: Formation([o1: CGPoint(x: 0, y: 0)]),
                                 pace: pace, rim: rim)
        play.appendFrame()
        // 10 ft east, then 10 ft north: halfway by length is the corner.
        play.addAction(PlayAction(kind: .cut, actorId: o1,
                                  path: [CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)]),
                       toFrame: 0)
        let half = play.position(of: o1, at: play.duration / 2)
        XCTAssertEqual(half.x, 10, accuracy: 0.01)
        XCTAssertEqual(half.y, 0, accuracy: 0.01)
    }

    // MARK: - Possession

    /// The derivation produces the EXISTING possession model, which is what
    /// keeps BALL_LANE_SPEC §1/§2 true without a second implementation.
    func testPossessionDerivesFromActions() {
        let play = acceptancePlay()
        let possessions = play.derivedPossessions(startingWith: o1)
        XCTAssertEqual(possessions.count, 2, "O1 holds, passes, O2 holds")

        XCTAssertEqual(possessions[0].holderId, o1)
        XCTAssertEqual(possessions[0].start, 0, accuracy: 0.0001)
        // Released at the start of frame 3 — the frame the pass is drawn in.
        XCTAssertEqual(possessions[0].end ?? -1, play.frameStartTimes[2], accuracy: 0.0001)
        guard case .pass(let toId)? = possessions[0].release else {
            return XCTFail("frame 3 must derive a pass")
        }
        XCTAssertEqual(toId, o2)

        // O2 attaches when the ball ARRIVES, not when it was thrown.
        XCTAssertGreaterThan(possessions[1].start, play.frameStartTimes[2])
        XCTAssertEqual(possessions[1].holderId, o2)

        // The shot ENDS possession: nothing receives it.
        XCTAssertEqual(possessions[1].end ?? -1, play.frameStartTimes[3], accuracy: 0.0001)
        guard case .shot(let target)? = possessions[1].release else {
            return XCTFail("frame 4 must derive a shot")
        }
        XCTAssertEqual(target.y, rim.y, accuracy: 0.0001)
    }

    func testHolderAtAnyTime() {
        let play = acceptancePlay()
        let starts = play.frameStartTimes
        XCTAssertEqual(play.holder(at: 0, startingWith: o1), o1)
        XCTAssertEqual(play.holder(at: starts[1], startingWith: o1), o1,
                       "a dribble and a screen change nothing about who holds it")
        // Mid-flight nobody holds it.
        XCTAssertNil(play.holder(at: starts[2] + 0.01, startingWith: o1))
        XCTAssertEqual(play.holder(at: starts[3], startingWith: o1), o2)
        // After the shot the ball is nobody's.
        XCTAssertNil(play.holder(at: play.duration, startingWith: o1))
    }

    /// The opening holder is inferred when not stated — the first player to do
    /// something only a holder can do.
    func testOpeningHolderIsInferred() {
        XCTAssertEqual(acceptancePlay().openingHolder(), o1)
    }

    /// Possession only moves from whoever actually has it. An action claiming
    /// otherwise is authoring noise: the derivation must come out IDENTICAL
    /// with and without it, rather than teleporting the ball to O5's receiver.
    func testNonHolderCannotGiveTheBallAway() {
        var noisy = acceptancePlay()
        noisy.addAction(PlayAction(kind: .pass, actorId: o5, target: .player(o2)), toFrame: 0)
        let derived = noisy.derivedPossessions(startingWith: o1)

        // The BALL STORY is unchanged: O1 holds, passes to O2, O2 shoots.
        XCTAssertEqual(derived.map(\.holderId), [o1, o2])
        guard case .pass? = derived.first?.release else {
            return XCTFail("O1's pass must still be the first release")
        }
        // And it still leaves O1's hand in FRAME 3, not in frame 1 where the
        // stray action was drawn.
        XCTAssertEqual(derived[0].end ?? -1, noisy.frameStartTimes[2], accuracy: 0.0001)

        // NOTE what this does NOT claim: the stray action still lengthens its
        // frame, because a frame lasts as long as its longest action and an
        // action that exists occupies time. Making duration depend on whether
        // possession accepts the action would make timing and possession
        // mutually recursive — possession derivation is priced FROM frame
        // durations. Phase B cannot author this case anyway: a pass comes from
        // dragging the ball, which only its holder has.
    }

    /// A handoff moves the ball at the end of the carry, not across a flight.
    func testHandoffMovesPossession() {
        var play = FrameSequence(startFormation: startFormation(), pace: pace, rim: rim)
        play.appendFrame()
        play.addAction(PlayAction(kind: .handoff, actorId: o1, target: .player(o2)), toFrame: 0)
        let possessions = play.derivedPossessions(startingWith: o1)
        XCTAssertEqual(possessions.count, 2)
        XCTAssertEqual(possessions[1].holderId, o2)
    }

    // MARK: - The stored end formation is never allowed to drift

    func testEveryMutationLeavesTheStoredFormationCorrect() {
        var play = acceptancePlay()
        XCTAssertEqual(play.driftedFrames(), [])

        play.duplicateFrame(at: 1)
        XCTAssertEqual(play.driftedFrames(), [], "duplicate")

        play.moveFrame(from: 0, to: 2)
        XCTAssertEqual(play.driftedFrames(), [], "reorder")

        play.removeFrame(at: 0)
        XCTAssertEqual(play.driftedFrames(), [], "delete")

        play.insertFrame(at: 1, caption: "inserted")
        XCTAssertEqual(play.driftedFrames(), [], "insert")

        play.addAction(PlayAction(kind: .cut, actorId: o5,
                                  path: [CGPoint(x: 2, y: 2)]), toFrame: 1)
        XCTAssertEqual(play.driftedFrames(), [], "add action")

        play.removeAction(id: play.frames[1].actions[0].id, fromFrame: 1)
        XCTAssertEqual(play.driftedFrames(), [], "remove action")
    }

    /// Hand-corrupting a stored formation must be DETECTED, or the drift guard
    /// above is vacuous. It cascades on purpose: everything after a corrupt
    /// frame is also wrong, and the report says so.
    func testDriftIsActuallyDetected() {
        var play = acceptancePlay()
        play.frames[0].endFormation[o1] = CGPoint(x: 99, y: 99)
        let drifted = play.driftedFrames()
        XCTAssertTrue(drifted.contains(0), "the corrupted frame must be named")
        XCTAssertTrue(drifted.contains(1), "and everything downstream of it")
        // Re-resolving repairs the whole chain.
        play.reresolve()
        XCTAssertEqual(play.driftedFrames(), [])
    }

    // MARK: - Frame CRUD

    func testAppendContinuesFromTheEndFormation() {
        var play = acceptancePlay()
        let before = play.endFormation
        play.appendFrame(caption: "reset")
        XCTAssertEqual(play.frames.count, 5)
        XCTAssertEqual(play.frames[4].endFormation, before,
                       "a new frame changes nothing until something is drawn in it")
    }

    func testDuplicateIsIndependent() {
        var play = acceptancePlay()
        play.duplicateFrame(at: 0)
        XCTAssertEqual(play.frames.count, 5)
        XCTAssertNotEqual(play.frames[0].id, play.frames[1].id)
        XCTAssertNotEqual(play.frames[0].actions[0].id, play.frames[1].actions[0].id,
                          "a duplicate must be editable without touching its source")
        XCTAssertEqual(play.frames[1].caption, play.frames[0].caption)
    }

    func testEmptyFrameStillHoldsABeat() {
        var play = FrameSequence(startFormation: startFormation(), pace: pace, rim: rim)
        play.appendFrame(caption: "the set")
        XCTAssertEqual(play.duration, PlayFrame.emptyFrameDuration, accuracy: 0.0001)
    }

    // MARK: - What a drag means
    //
    // These exist because the inference shipped BROKEN and the Phase B
    // acceptance did not catch it: the scripted run supplied `screenFor:`
    // explicitly, so it exercised the model and never the thing the ⌥ gesture
    // actually depends on. Setting a screen on OPEN FLOOR — the normal case,
    // where no teammate is under the drop point — came out a cut.

    func testDragOnAPlayerIsACut() {
        XCTAssertEqual(PlayActionKind.inferred(asScreen: false, actorHoldsBall: false), .cut)
    }

    func testDragOnTheBallHandlerIsADribble() {
        XCTAssertEqual(PlayActionKind.inferred(asScreen: false, actorHoldsBall: true), .dribble)
    }

    /// THE REGRESSION. The modifier decides, on its own, with nobody under the
    /// drop point and nothing else to go on.
    func testOptionDragIsAScreenEvenOnOpenFloor() {
        XCTAssertEqual(PlayActionKind.inferred(asScreen: true, actorHoldsBall: false), .screen)
    }

    /// …and it outranks holding the ball: a ball-handler can set a screen.
    func testOptionDragBeatsTheDribbleInference() {
        XCTAssertEqual(PlayActionKind.inferred(asScreen: true, actorHoldsBall: true), .screen)
    }

    // MARK: - Round trip

    func testFrameSequenceRoundTrips() throws {
        let play = acceptancePlay()
        let data = try JSONEncoder().encode(play)
        let decoded = try JSONDecoder().decode(FrameSequence.self, from: data)
        XCTAssertEqual(decoded, play)
        XCTAssertEqual(decoded.duration, play.duration, accuracy: 0.0001)
        XCTAssertEqual(decoded.derivedPossessions(startingWith: o1).count,
                       play.derivedPossessions(startingWith: o1).count)
    }

    /// A diagram stored BEFORE the rebuild has no frames, no pace and no branch
    /// index. It must still decode — the wipe is a decision the coach makes,
    /// not something a decoding failure makes for them.
    func testPreRebuildBlobStillDecodes() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","playId":"\(UUID().uuidString)",
         "space":{"standard":"fiba","mode":"half"},
         "entities":[],"nodes":[{"id":"\(UUID().uuidString)","title":"Base",
         "teachingPoints":[],"tracks":[],"edges":[],"possessions":[]}],
         "rootNodeId":"\(UUID().uuidString)","camera":{"keyframes":[]},
         "themeName":"Video","createdAt":0,"updatedAt":0}
        """
        let decoded = try JSONDecoder().decode(PlayDiagram.self,
                                               from: Data(legacy.utf8))
        XCTAssertEqual(decoded.nodes.first?.frames.count, 0)
        XCTAssertNil(decoded.pace)
        XCTAssertEqual(decoded.effectivePace, .default)
    }

    // MARK: - Branch at a frame

    /// A read is a branch AT A FRAME. The parent plays through its branch
    /// frame, then each child continues from the formation that leaves.
    func testBranchAtFrameProducesTwoRuns() {
        let rootId = UUID(), underId = UUID(), overId = UUID()
        var root = ReadNode(id: rootId, title: "Base")
        root.frames = acceptancePlay().frames

        var under = ReadNode(id: underId, title: "Under")
        under.frames = [PlayFrame(actions: [PlayAction(kind: .cut, actorId: o2,
                                                       path: [CGPoint(x: 25, y: 24)])],
                                  caption: "pop out")]
        var over = ReadNode(id: overId, title: "Over")
        over.frames = [PlayFrame(actions: [PlayAction(kind: .cut, actorId: o2,
                                                      path: [CGPoint(x: 25, y: 6)])],
                                 caption: "back cut")]

        // Both reads depart AFTER FRAME 2 (index 1) — no time anywhere.
        root.edges = [ReadEdge(targetId: underId, condition: "they go under",
                               afterFrameIndex: 1),
                      ReadEdge(targetId: overId, condition: "they chase over",
                               afterFrameIndex: 1)]

        var diagram = PlayDiagram(playId: UUID(),
                                  entities: [
                                    DiagramEntity(id: o1, kind: .player(team: .offense, number: 1, role: nil),
                                                  homePosition: CGPoint(x: 25, y: 28)),
                                    DiagramEntity(id: o2, kind: .player(team: .offense, number: 2, role: nil),
                                                  homePosition: CGPoint(x: 43, y: 22)),
                                    DiagramEntity(id: o5, kind: .player(team: .offense, number: 5, role: nil),
                                                  homePosition: CGPoint(x: 8, y: 10))],
                                  nodes: [root, under, over],
                                  rootNodeId: rootId)
        diagram.pace = .default

        let branches = diagram.frameBranches()
        XCTAssertEqual(branches.count, 2)
        for branch in branches {
            // Two parent frames (0 and 1) then the child's one.
            XCTAssertEqual(branch.steps.count, 3)
            XCTAssertEqual(branch.steps[0].nodeId, rootId)
            XCTAssertEqual(branch.steps[2].nodeId == underId
                           || branch.steps[2].nodeId == overId, true)
            // Times are the SUM of what precedes, never stored.
            XCTAssertEqual(branch.steps[0].startsAt, 0, accuracy: 0.0001)
            XCTAssertEqual(branch.steps[1].startsAt,
                           branch.steps[0].duration, accuracy: 0.0001)
            XCTAssertEqual(branch.steps[2].startsAt,
                           branch.steps[0].duration + branch.steps[1].duration,
                           accuracy: 0.0001)
            XCTAssertEqual(branch.duration,
                           branch.steps[2].startsAt + branch.steps[2].duration,
                           accuracy: 0.0001)
        }
        XCTAssertEqual(Set(branches.flatMap(\.conditions)),
                       ["they go under", "they chase over"])
    }

    /// The child continues from where the parent's branch frame LEFT everyone —
    /// continuity across a read boundary, by construction rather than by a pin.
    func testChildReadContinuesFromTheBranchFormation() {
        let rootId = UUID(), childId = UUID()
        var root = ReadNode(id: rootId, title: "Base")
        var sequence = FrameSequence(startFormation: startFormation(), pace: pace, rim: rim)
        sequence.appendFrame()
        sequence.addAction(PlayAction(kind: .cut, actorId: o1,
                                      path: [CGPoint(x: 12, y: 20)]), toFrame: 0)
        root.frames = sequence.frames
        root.edges = [ReadEdge(targetId: childId, condition: "x", afterFrameIndex: 0)]

        var child = ReadNode(id: childId, title: "Child")
        child.frames = [PlayFrame(caption: "hold")]

        var diagram = PlayDiagram(playId: UUID(),
                                  entities: [
                                    DiagramEntity(id: o1, kind: .player(team: .offense, number: 1, role: nil),
                                                  homePosition: CGPoint(x: 25, y: 28))],
                                  nodes: [root, child],
                                  rootNodeId: rootId)
        diagram.pace = .default

        guard let branch = diagram.frameBranches().first else { return XCTFail("no branch") }
        // The child's frame stores the formation it inherited: O1 at (12,20),
        // not back at his home position.
        let inherited = branch.steps[1].frame.endFormation[o1]
        XCTAssertEqual(inherited?.x ?? 0, 12, accuracy: 0.01)
        XCTAssertEqual(inherited?.y ?? 0, 20, accuracy: 0.01)
    }
}
