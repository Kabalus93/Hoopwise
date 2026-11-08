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

        /// The player runs along it (cut, dribble, screen); a pass or shot
        /// sends the ball and leaves the player where they are.
        var movesPlayer: Bool { self == .cut || self == .dribble || self == .screen }
        /// The ball leaves the player's hands (pass, shot).
        var throwsBall: Bool { self == .pass || self == .shot }
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

    /// The first ball's holder: the play's ball when there is only one.
    var ball: Int? {
        get { balls.first }
        set { balls = newValue.map { [$0] } ?? [] }
    }

    init(offense: [Player] = [], defense: [Defender] = [], ball: Int? = nil, balls: [Int] = [],
         actions: [Action] = [], notes: [Note] = []) {
        self.offense = offense
        self.defense = defense
        self.balls = balls.isEmpty ? (ball.map { [$0] } ?? []) : balls
        self.actions = actions
        self.notes = notes
    }

    func player(_ number: Int) -> Player? { offense.first { $0.number == number } }

    func hasBall(_ number: Int) -> Bool { balls.contains(number) }

    // Stored as before with `ball` (the first holder) beside `balls`, so a
    // build from before several balls still reads a drawing's first ball,
    // and a drawing it saved (no `balls`) reads back as that one ball.
    private enum CodingKeys: String, CodingKey { case offense, defense, ball, balls, actions, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offense = try c.decode([Player].self, forKey: .offense)
        defense = try c.decode([Defender].self, forKey: .defense)
        actions = try c.decode([Action].self, forKey: .actions)
        notes = try c.decode([Note].self, forKey: .notes)
        let first = try c.decodeIfPresent(Int.self, forKey: .ball)
        let all = try c.decodeIfPresent([Int].self, forKey: .balls)
        balls = all ?? first.map { [$0] } ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(offense, forKey: .offense)
        try c.encode(defense, forKey: .defense)
        try c.encodeIfPresent(balls.first, forKey: .ball)
        try c.encode(balls, forKey: .balls)
        try c.encode(actions, forKey: .actions)
        try c.encode(notes, forKey: .notes)
    }
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
