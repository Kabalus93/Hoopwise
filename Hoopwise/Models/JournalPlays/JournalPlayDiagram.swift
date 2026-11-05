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
    }

    /// A short note written on the court ("Rebound", "Push").
    struct Note: Codable, Equatable, Sendable {
        var text: String
        var at: JournalCourtPoint
    }

    var offense: [Player] = []
    var defense: [Defender] = []
    /// The player with the ball when the step starts.
    var ball: Int?
    var actions: [Action] = []
    var notes: [Note] = []

    func player(_ number: Int) -> Player? { offense.first { $0.number == number } }
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
