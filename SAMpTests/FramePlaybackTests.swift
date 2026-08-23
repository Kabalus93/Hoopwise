import XCTest
import CoreGraphics
@testable import Hoopwise

/// PLAY EDITOR v2, PHASE D — playback driven by frames.
///
/// The claim these defend is "the presentation look is UNCHANGED, only its
/// geometry source moved". That claim is not testable by looking at a
/// screenshot, so what is pinned here is every RULE the look is made of:
/// nothing renders before its time, draw-on grows tip-first, the path is
/// consumed behind the player with the tail tucked a fixed number of FEET
/// (never seconds), a movement too short to be a movement grows no arrowhead,
/// and there is exactly one head per path.
///
/// The ball tests defend something narrower and more important: that the
/// duration the frame model priced a pass at and the flight the renderer draws
/// are THE SAME NUMBER. Every ball bug this project has had was two derivations
/// of one instant disagreeing.
final class FramePlaybackTests: XCTestCase {

    private let o1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let o2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private let o5 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!
    private let rim = CGPoint(x: 25, y: 5.25)

    private var style: RenderStyle { .presentation }

    // MARK: - Fixtures

    /// One straight 20-foot cut, so arc length and straight-line distance are
    /// the same number and a tuck measured in feet is checkable directly.
    private func straightCut(pace: PaceTier? = nil) -> FrameSequence {
        var sequence = FrameSequence(
            startFormation: Formation([o1: CGPoint(x: 10, y: 20)]),
            frames: [], pace: .default, rim: rim)
        sequence.appendFrame()
        sequence.addAction(PlayAction(kind: .cut, actorId: o1,
                                      path: [CGPoint(x: 30, y: 20)],
                                      pace: pace), toFrame: 0)
        return sequence
    }

    /// O1 passes to O2, then O2 shoots. Two frames, one ball story.
    private func passThenShoot() -> FrameSequence {
        var sequence = FrameSequence(
            startFormation: Formation([o1: CGPoint(x: 25, y: 28),
                                       o2: CGPoint(x: 43, y: 22)]),
            frames: [], pace: .default, rim: rim)
        sequence.appendFrame(caption: "Entry")
        sequence.addAction(PlayAction(kind: .pass, actorId: o1,
                                      target: .player(o2)), toFrame: 0)
        sequence.appendFrame(caption: "Finish")
        sequence.addAction(PlayAction(kind: .shot, actorId: o2,
                                      target: .point(rim)), toFrame: 1)
        return sequence
    }

    private func onlyPiece(_ sequence: FrameSequence, at time: Double)
    -> FramePlayback.PathPiece? {
        FramePlayback.visiblePaths(in: sequence, at: time, style: style).pieces.first
    }

    // MARK: - Nothing before its time, nothing after

    func testNothingRendersBeforeTheDrawOnBegins() {
        let play = straightCut()
        // Draw-on starts 0.3s before the action, and the action starts at 0 —
        // so the lead is clamped to the start of the play and there is no
        // "before" to check on frame 1. Push the cut into a second frame.
        var withLead = FrameSequence(
            startFormation: Formation([o1: CGPoint(x: 10, y: 20),
                                       o2: CGPoint(x: 40, y: 20)]),
            frames: [], pace: .default, rim: rim)
        withLead.appendFrame()
        withLead.addAction(PlayAction(kind: .cut, actorId: o2,
                                      path: [CGPoint(x: 40, y: 40)]), toFrame: 0)
        withLead.appendFrame()
        withLead.addAction(PlayAction(kind: .cut, actorId: o1,
                                      path: [CGPoint(x: 30, y: 20)]), toFrame: 1)

        let secondStarts = withLead.frameStartTimes[1]
        let early = FramePlayback.visiblePaths(in: withLead,
                                              at: secondStarts - style.drawOnLead - 0.05,
                                              style: style)
        XCTAssertFalse(early.pieces.contains { $0.actorId == o1 },
                       "a path must not exist before its own action announces itself")
        _ = play
    }

    func testFullyConsumedWhenTheActionEnds() {
        let play = straightCut()
        let end = play.duration
        XCTAssertNil(onlyPiece(play, at: end),
                     "the path is gone at completion — it is an announcement, not a trail")
        XCTAssertNil(onlyPiece(play, at: end + 0.5))
    }

    // MARK: - Draw-on

    func testDrawOnGrowsTipFirstFromTheActor() {
        // A cut in the SECOND frame, so it has a lead to draw on into.
        var play = FrameSequence(
            startFormation: Formation([o1: CGPoint(x: 10, y: 20),
                                       o2: CGPoint(x: 40, y: 20)]),
            frames: [], pace: .default, rim: rim)
        play.appendFrame()
        play.addAction(PlayAction(kind: .cut, actorId: o2,
                                  path: [CGPoint(x: 40, y: 44)]), toFrame: 0)
        play.appendFrame()
        play.addAction(PlayAction(kind: .cut, actorId: o1,
                                  path: [CGPoint(x: 30, y: 20)]), toFrame: 1)

        let start = play.frameStartTimes[1]
        func lengthOfO1Path(at time: Double) -> CGFloat {
            let pieces = FramePlayback.visiblePaths(in: play, at: time, style: style).pieces
            guard let piece = pieces.first(where: { $0.actorId == o1 }) else { return 0 }
            var total: CGFloat = 0
            for index in 0..<(piece.points.count - 1) {
                total += hypot(piece.points[index + 1].x - piece.points[index].x,
                               piece.points[index + 1].y - piece.points[index].y)
            }
            return total
        }

        let early = lengthOfO1Path(at: start - style.drawOnLead + 0.03)
        let later = lengthOfO1Path(at: start - style.drawOnLead + 0.20)
        XCTAssertGreaterThan(early, 0, "draw-on is visible during the lead")
        XCTAssertGreaterThan(later, early, "and it grows tip-first toward the destination")

        // It grows FROM the actor: the first point stays where he stands.
        let pieces = FramePlayback.visiblePaths(in: play, at: start - 0.2, style: style).pieces
        let piece = pieces.first { $0.actorId == o1 }
        XCTAssertEqual(piece?.points.first?.x ?? 0, 10, accuracy: 0.01)
    }

    // MARK: - Consumption

    func testPathIsConsumedBehindTheMovingPlayer() {
        let play = straightCut()
        let midway = play.duration / 2
        guard let piece = onlyPiece(play, at: midway) else {
            return XCTFail("a moving player's path is on screen while he runs")
        }
        XCTAssertEqual(piece.points.last?.x ?? 0, 30, accuracy: 0.01,
                       "the path always reaches the destination")
        let player = play.position(of: o1, at: midway)
        XCTAssertLessThan(piece.points.first?.x ?? 0, player.x + 0.001,
                          "nothing is drawn ahead of where he has already been")
    }

    /// THE TUCK IS IN FEET. A time-based tuck stretches with velocity, and at
    /// speed the tail escapes the puck entirely — which is why the same
    /// distance must come back at two very different paces.
    func testTailTucksAFixedDistanceRegardlessOfPace() {
        for tier in [PaceTier.walk, .sprint] {
            let play = straightCut(pace: tier)
            let midway = play.duration / 2
            guard let piece = onlyPiece(play, at: midway) else {
                return XCTFail("\(tier) path missing")
            }
            let player = play.position(of: o1, at: midway)
            let tail = piece.points[0]
            XCTAssertEqual(hypot(player.x - tail.x, player.y - tail.y),
                           style.trailingTuckFeet, accuracy: 0.02,
                           "\(tier): the tail tucks \(style.trailingTuckFeet)ft behind him, "
                           + "and that is a distance, not a duration")
        }
    }

    // MARK: - The hold guard and the one head

    func testAMovementTooShortToBeAMovementDrawsNothing() {
        var play = FrameSequence(startFormation: Formation([o1: CGPoint(x: 10, y: 20)]),
                                 frames: [], pace: .default, rim: rim)
        play.appendFrame()
        // Half a foot — a pose adjustment, not a cut.
        play.addAction(PlayAction(kind: .cut, actorId: o1,
                                  path: [CGPoint(x: 10.5, y: 20)]), toFrame: 0)
        let visible = FramePlayback.visiblePaths(in: play, at: play.duration / 2, style: style)
        XCTAssertTrue(visible.pieces.isEmpty,
                      "below \(style.minMovementFeet)ft it is a hold")
        XCTAssertTrue(visible.heads.isEmpty,
                      "and a hold must never sprout an arrowhead at a stationary player")
    }

    func testExactlyOneHeadPerPath() {
        // A path bent through three legs — direction changes, and in the
        // keyframe model each of those was a segment that could have grown its
        // own head. An action is one path, so there is one place a head can go.
        var play = FrameSequence(startFormation: Formation([o1: CGPoint(x: 10, y: 20)]),
                                 frames: [], pace: .default, rim: rim)
        play.appendFrame()
        play.addAction(PlayAction(kind: .cut, actorId: o1,
                                  path: [CGPoint(x: 20, y: 20),
                                         CGPoint(x: 20, y: 34),
                                         CGPoint(x: 34, y: 34)]), toFrame: 0)
        let visible = FramePlayback.visiblePaths(in: play, at: play.duration * 0.4, style: style)
        XCTAssertEqual(visible.pieces.count, 1)
        XCTAssertEqual(visible.heads.count, 1)
        XCTAssertFalse(visible.heads[0].isScreen)
    }

    func testAScreenEndsInItsBarNotAnArrow() {
        var play = FrameSequence(
            startFormation: Formation([o5: CGPoint(x: 8, y: 10), o2: CGPoint(x: 30, y: 14)]),
            frames: [], pace: .default, rim: rim)
        play.appendFrame()
        play.addAction(PlayAction(kind: .screen, actorId: o5,
                                  path: [CGPoint(x: 20, y: 18)],
                                  screenForId: o2), toFrame: 0)
        let visible = FramePlayback.visiblePaths(in: play, at: play.duration * 0.5, style: style)
        XCTAssertEqual(visible.heads.count, 1)
        XCTAssertTrue(visible.heads[0].isScreen)
    }

    /// A head pointing due east is what `atan2(0, 0)` looks like on screen. It
    /// happens whenever the visible window is short enough that consecutive
    /// samples land on top of each other, which is exactly the first frame of
    /// draw-on.
    func testHeadAngleFollowsThePathEvenInATinyWindow() {
        var play = FrameSequence(
            startFormation: Formation([o1: CGPoint(x: 10, y: 20),
                                       o2: CGPoint(x: 40, y: 20)]),
            frames: [], pace: .default, rim: rim)
        play.appendFrame()
        play.addAction(PlayAction(kind: .cut, actorId: o2,
                                  path: [CGPoint(x: 40, y: 44)]), toFrame: 0)
        play.appendFrame()
        // Straight UP the floor: the correct angle is +y, never 0.
        play.addAction(PlayAction(kind: .cut, actorId: o1,
                                  path: [CGPoint(x: 10, y: 44)]), toFrame: 1)

        let start = play.frameStartTimes[1]
        let visible = FramePlayback.visiblePaths(in: play,
                                                 at: start - style.drawOnLead + 0.001,
                                                 style: style)
        guard let head = visible.heads.first(where: { $0.actorId == o1 }) else {
            return XCTFail("draw-on carries its head at the leading tip")
        }
        XCTAssertEqual(head.angle, .pi / 2, accuracy: 0.05,
                       "the head points along the path, not due east")
    }

    // MARK: - Edit style

    func testEditStyleDrawsTheWholePathWithNoTimeWindow() {
        let play = straightCut()
        for time in [0.0, 0.1, play.duration * 0.9, play.duration * 2] {
            let visible = FramePlayback.visiblePaths(in: play, at: time, style: .edit)
            XCTAssertEqual(visible.pieces.count, 1,
                           "a frame answers 'is this current' structurally — "
                           + "there is no window left to apply at t=\(time)")
            XCTAssertEqual(visible.pieces[0].points.first?.x ?? 0, 10, accuracy: 0.01)
            XCTAssertEqual(visible.pieces[0].points.last?.x ?? 0, 30, accuracy: 0.01)
        }
    }

    // MARK: - The ball

    /// THE POINT OF THE WHOLE BALL LAYER: the duration the frame model priced
    /// the pass at, and the flight the renderer draws, are one number.
    func testFlightDurationEqualsTheDerivedPossessionGap() {
        let play = passThenShoot()
        let possessions = play.derivedPossessions(startingWith: o1)
        XCTAssertEqual(possessions.count, 2)
        let release = possessions[0].end!
        let arrival = possessions[1].start

        let midflight = (release + arrival) / 2
        guard case .inFlight(let flight, _) = play.ballState(at: midflight,
                                                            ballHome: .zero,
                                                            openingHolder: o1) else {
            return XCTFail("the ball is in the air between release and catch")
        }
        XCTAssertEqual(flight.duration, arrival - release, accuracy: 0.0001,
                       "the drawn flight and the derived possession are the same instant")
    }

    /// The constant held offset shifts BOTH ends of a pass by the same vector,
    /// so the flight is exactly as long as the centre-to-centre distance the
    /// duration was priced from. That is why the two cannot drift.
    func testHeldOffsetCancelsAcrossAPass() {
        let play = passThenShoot()
        let possessions = play.derivedPossessions(startingWith: o1)
        let release = possessions[0].end!
        guard case .inFlight(let flight, _) = play.ballState(at: release + 0.01,
                                                            ballHome: .zero,
                                                            openingHolder: o1) else {
            return XCTFail("in flight just after release")
        }
        let passer = play.position(of: o1, at: release)
        let receiver = play.position(of: o2, at: possessions[1].start)
        XCTAssertEqual(hypot(flight.to.x - flight.from.x, flight.to.y - flight.from.y),
                       hypot(receiver.x - passer.x, receiver.y - passer.y),
                       accuracy: 0.0001)
        XCTAssertEqual(flight.arcFeet, 0, "a pass is a straight line at constant velocity")
    }

    func testTheBallIsHeldBesideItsHolderNotOnTopOfHim() {
        let play = passThenShoot()
        let ball = play.ballPosition(at: 0, ballHome: .zero, openingHolder: o1)
        let holder = play.position(of: o1, at: 0)
        let gap = hypot(ball.x - holder.x, ball.y - holder.y)
        XCTAssertGreaterThan(gap, 1.0)
        XCTAssertLessThan(gap, 3.0)
    }

    func testAfterTheShotTheBallRestsAtTheRim() {
        let play = passThenShoot()
        let resting = play.ballPosition(at: play.duration + 2,
                                        ballHome: .zero, openingHolder: o1)
        XCTAssertEqual(resting.x, rim.x, accuracy: 0.01)
        XCTAssertEqual(resting.y, rim.y, accuracy: 0.01)
    }

    /// A shot is priced hand-to-rim while its frame is priced centre-to-rim, so
    /// the two differ by at most the held offset ÷ shot pace. Nothing follows a
    /// shot, so this cannot desynchronise anything — but it is a real gap and
    /// it is bounded here rather than left to be rediscovered.
    func testShotFlightAgreesWithItsFrameToWithinTheHeldOffset() {
        let play = passThenShoot()
        let shotFrameStart = play.frameStartTimes[1]
        let possessions = play.derivedPossessions(startingWith: o1)
        guard let shooter = possessions.last,
              let release = shooter.end,
              let flight = BallDerivation.flight(after: shooter, among: possessions,
                                                 passSpeed: play.pace.pass,
                                                 shotSpeed: play.pace.shot,
                                                 offset: FrameSequence.heldBallOffset,
                                                 positionOf: { id, t in play.position(of: id, at: t) })
        else { return XCTFail("the shot releases") }
        XCTAssertEqual(release, shotFrameStart, accuracy: 0.0001)
        let frameDuration = play.frameDurations[1]
        let tolerance = 1.9 / play.pace.shot + 0.0001
        XCTAssertEqual(flight.duration, frameDuration, accuracy: tolerance)
        XCTAssertEqual(flight.arcFeet, BallFlight.shotArcFeet, "a shot rises; a pass does not")
    }

    // MARK: - Runs

    func testABranchedPlayFlattensIntoOneSequencePerRun() {
        var diagram = PlayDiagram(playId: UUID(), space: CourtSpace(standard: .fiba, mode: .half))
        let entity = DiagramEntity(kind: .player(team: .offense, number: 1, role: nil),
                                   label: "1", homePosition: CGPoint(x: 25, y: 28))
        diagram.entities = [entity]

        var root = ReadNode(title: "Base")
        var rootSequence = FrameSequence(startFormation: diagram.homeFormation,
                                         frames: [], pace: .default, rim: diagram.rimPoint)
        rootSequence.appendFrame(caption: "entry")
        rootSequence.addAction(PlayAction(kind: .cut, actorId: entity.id,
                                          path: [CGPoint(x: 34, y: 28)]), toFrame: 0)
        rootSequence.appendFrame(caption: "second")
        root.frames = rootSequence.frames

        // TWO reads, because a branch is a CHOICE: a read carrying one edge
        // means the play always takes it, and the "else" is its own edge — the
        // same shape `frameBranches` has always had.
        var under = ReadNode(title: "Reject")
        var underSequence = FrameSequence(startFormation: Formation(), frames: [],
                                          pace: .default, rim: diagram.rimPoint)
        underSequence.appendFrame(caption: "back door")
        underSequence.addAction(PlayAction(kind: .cut, actorId: entity.id,
                                           path: [CGPoint(x: 25, y: 8)]), toFrame: 0)
        under.frames = underSequence.frames

        var over = ReadNode(title: "Chase")
        over.frames = [PlayFrame(actions: [PlayAction(kind: .cut, actorId: entity.id,
                                                      path: [CGPoint(x: 44, y: 28)])],
                                 caption: "flare")]

        root.edges = [ReadEdge(targetId: under.id, kind: .branch,
                               condition: "defender goes under", afterFrameIndex: 0),
                      ReadEdge(targetId: over.id, kind: .branch,
                               condition: "defender chases over", afterFrameIndex: 0)]

        diagram.nodes = [root, under, over]
        diagram.rootNodeId = root.id

        let runs = diagram.frameRuns()
        XCTAssertEqual(runs.count, 3,
                       "the play as authored, plus one per read that replaces it")

        // THE BASE RUN IS THE PLAY. It carries no condition because nothing was
        // read, and it plays the root to its own end rather than stopping at
        // the branch point.
        let base = runs.first { $0.conditions.isEmpty }
        XCTAssertEqual(base?.sequence.frames.count, 2)
        XCTAssertEqual(base?.nodeIds, [root.id])

        let branchRun = runs.first { $0.conditions.contains("defender goes under") }
        XCTAssertNotNil(branchRun)
        XCTAssertEqual(branchRun?.sequence.frames.count, 2,
                       "the parent's frames UP TO the branch, then the child's")
        XCTAssertEqual(branchRun?.conditionSummary, "defender goes under")

        // AND THE CHILD CONTINUES rather than restarting: its frame opens where
        // the parent's frame 0 left the cutter, not at his home position.
        let entering = branchRun!.sequence.formation(enteringFrame: 1)
        XCTAssertEqual(entering[entity.id]?.x ?? 0, 34, accuracy: 0.01)
    }

    func testARunsDurationIsTheSumOfItsFrames() {
        let play = passThenShoot()
        XCTAssertEqual(play.duration,
                       play.frameDurations.reduce(0, +), accuracy: 0.0001)
    }
}
