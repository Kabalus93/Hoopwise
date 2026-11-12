import Foundation

/// Where a play happens.
nonisolated enum JournalCourtKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// One end, baseline at the top: x across 0…15 m (left sideline to
    /// right), y from the baseline 0…14 m (to half court).
    case half
    /// The whole floor, attacking right: x along 0…28 m (own baseline to
    /// the baseline we attack), y across 0…15 m.
    case full

    var id: String { rawValue }

    /// Width and height of the playing area in metres.
    var size: (width: Double, height: Double) {
        switch self {
        case .half: (15, 14)
        case .full: (28, 15)
        }
    }

    var label: JPString {
        switch self {
        case .half: "Half court"
        case .full: "Full court"
        }
    }

    /// The centre of each rim, in this court's metres (FIBA: 1.575 m in from
    /// the baseline). The half court has one; the full court both, the one
    /// attacked (right) first.
    var baskets: [JournalCourtPoint] {
        switch self {
        case .half: [JournalCourtPoint(7.5, 1.575)]
        case .full: [JournalCourtPoint(28 - 1.575, 7.5), JournalCourtPoint(1.575, 7.5)]
        }
    }

    /// Within this many metres of a rim, a line ends AT the basket.
    static let basketReach = 1.4

    func isAtBasket(_ point: JournalCourtPoint) -> Bool {
        baskets.contains { $0.distance(to: point) <= Self.basketReach }
    }
}

/// A point on the court, in metres (see `JournalCourtKind`).
nonisolated struct JournalCourtPoint: Codable, Hashable, Sendable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: JournalCourtPoint) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// One step of a play as the coaching diagrams draw it: the five on
/// offense, any defenders, who has the ball, and what happens (cuts,
/// dribbles, passes, screens).
nonisolated struct JournalPlayDiagram: Codable, Equatable, Sendable {
    struct Player: Codable, Equatable, Sendable {
        /// 1…5, the role.
        var number: Int
        var at: JournalCourtPoint
    }

    struct Defender: Codable, Equatable, Sendable {
        var at: JournalCourtPoint
        /// The defender the ball handler reads (amber in the diagrams).
        var isRead = false
        /// Man-to-man (`defenseMode` .man): the offensive player this
        /// defender guards. Optional, so older builds read the drawing and
        /// keep the defender at `at` (12 November 2026).
        var guards: Int? = nil
        /// The coach's nudge from the calculated spot, in metres: "X2 plays
        /// him tighter" follows him through every move.
        var nudge: JournalCourtPoint? = nil
    }

    /// Auto defense (12 November 2026, Luther): defenders are placed by the
    /// rules in JournalPlayDefense instead of by hand. nil = drawn by hand.
    enum DefenseMode: String, Codable, CaseIterable, Sendable {
        case man, zone23, zone32
    }

    enum ActionKind: String, Codable, CaseIterable, Sendable {
        /// Solid line, arrowhead: the player runs there.
        case cut
        /// Zigzag line, arrowhead: the ball handler dribbles there.
        case dribble
        /// Dashed line, arrowhead: the ball goes to `receiver`.
        case pass
        /// Line ending in a bar: the player sets a screen there.
        case screen
        /// Solid red line to the rim: the player shoots (November 2026).
        case shot
        /// Short solid line ending in a double bar: the player hands the
        /// ball to `receiver` (12 November 2026, Luther). Older builds
        /// cannot decode it, as with `shot`.
        case handoff

        /// The player runs along it (cut, dribble, screen); a pass or shot
        /// sends the ball and leaves the player where they are.
        var movesPlayer: Bool { self == .cut || self == .dribble || self == .screen }
        /// The ball leaves the player's hands (pass, shot, hand-off).
        var throwsBall: Bool { self == .pass || self == .shot || self == .handoff }
        /// The ball goes to a teammate, who is named (pass, hand-off).
        var hasReceiver: Bool { self == .pass || self == .handoff }
    }

    /// How a line runs through its bend points (Luther, November 2026: a
    /// line followed the hand and came out wobbly).
    enum PathShape: String, Codable, Sendable {
        /// Straight segments, sharp corners at the bends.
        case straight
        /// One smooth curve through the bends.
        case curved
    }

    struct Action: Codable, Equatable, Sendable {
        var kind: ActionKind
        /// Who acts (the passer, for a pass).
        var player: Int
        /// From where the player starts to where the action ends, with any
        /// bend points between. At least two points.
        var path: [JournalCourtPoint]
        /// For a pass: who catches it.
        var receiver: Int?
        /// `nil` on lines drawn before shapes existed: they were always drawn
        /// curved through their points, and still are.
        var shape: PathShape?

        /// Drawn as straight segments: chosen straight, or nothing to bend.
        var isStraight: Bool { shape == .straight || path.count < 3 }
    }

    /// A short note written on the court ("Rebound", "Push").
    struct Note: Codable, Equatable, Sendable {
        var text: String
        var at: JournalCourtPoint
    }

    var offense: [Player] = []
    var defense: [Defender] = []
    /// The players with a ball when the step starts, one entry per ball. A
    /// play has one; a drill can give several players one each (Luther,
    /// November 2026).
    var balls: [Int] = []
    var actions: [Action] = []
    var notes: [Note] = []
    /// Cones on the floor (drill drawings, November 2026). A play has none,
    /// and a drawing without cones writes no `cones` key, so plays' JSON is
    /// unchanged and older builds read a drawing with cones minus the cones.
    var cones: [JournalCourtPoint] = []
    /// Auto defense; nil when the defenders are drawn by hand. Written only
    /// when set, so a hand-drawn step's JSON is unchanged.
    var defenseMode: DefenseMode? = nil

    /// The first ball's holder: the play's ball when there is only one.
    var ball: Int? {
        get { balls.first }
        set { balls = newValue.map { [$0] } ?? [] }
    }

    init(offense: [Player] = [], defense: [Defender] = [], ball: Int? = nil, balls: [Int] = [],
         actions: [Action] = [], notes: [Note] = [], cones: [JournalCourtPoint] = []) {
        self.offense = offense
        self.defense = defense
        self.balls = balls.isEmpty ? (ball.map { [$0] } ?? []) : balls
        self.actions = actions
        self.notes = notes
        self.cones = cones
    }

    func player(_ number: Int) -> Player? { offense.first { $0.number == number } }

    func hasBall(_ number: Int) -> Bool { balls.contains(number) }

    // Stored as before with `ball` (the first holder) beside `balls`, so a
    // build from before several balls still reads a drawing's first ball,
    // and a drawing it saved (no `balls`) reads back as that one ball.
    private enum CodingKeys: String, CodingKey { case offense, defense, ball, balls, actions, notes, cones, defenseMode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offense = try c.decode([Player].self, forKey: .offense)
        defense = try c.decode([Defender].self, forKey: .defense)
        actions = try c.decode([Action].self, forKey: .actions)
        notes = try c.decode([Note].self, forKey: .notes)
        let first = try c.decodeIfPresent(Int.self, forKey: .ball)
        let all = try c.decodeIfPresent([Int].self, forKey: .balls)
        balls = all ?? first.map { [$0] } ?? []
        cones = try c.decodeIfPresent([JournalCourtPoint].self, forKey: .cones) ?? []
        defenseMode = try? c.decodeIfPresent(DefenseMode.self, forKey: .defenseMode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(offense, forKey: .offense)
        try c.encode(defense, forKey: .defense)
        try c.encodeIfPresent(balls.first, forKey: .ball)
        try c.encode(balls, forKey: .balls)
        try c.encode(actions, forKey: .actions)
        try c.encode(notes, forKey: .notes)
        if !cones.isEmpty { try c.encode(cones, forKey: .cones) }
        try c.encodeIfPresent(defenseMode, forKey: .defenseMode)
    }

    /// The number a new player takes: one past the highest on the court.
    var nextPlayerNumber: Int { (offense.map(\.number).max() ?? 0) + 1 }
}

import Foundation

/// When a play is run. The library is grouped by these.
nonisolated enum JournalPlayCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case transition
    case halfCourt
    case baselineInbound
    case sidelineInbound
    case versusMan
    case other

    var id: String { rawValue }

    var label: JPString {
        switch self {
        case .transition: "Transition"
        case .halfCourt: "Half court"
        case .baselineInbound: "Baseline inbound"
        case .sidelineInbound: "Sideline inbound"
        case .versusMan: "Against man-to-man"
        case .other: "Other"
        }
    }
}

/// The parts of a play: its concept (the base action), then wrinkles (a
/// small change the defense doesn't expect) and variations (another way
/// into the same idea).
nonisolated enum JournalPlayPartKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case concept
    case wrinkle
    case variation

    var id: String { rawValue }

    var label: JPString {
        switch self {
        case .concept: "Concept"
        case .wrinkle: "Wrinkles"
        case .variation: "Variations"
        }
    }
}
