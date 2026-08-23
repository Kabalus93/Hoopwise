import Foundation
import CoreGraphics

// MARK: - Frame notation
//
// HOW EACH ACTION KIND IS DRAWN, as data. Shared (Phase D) because the printed
// play card and the authoring canvas must draw a cut the same way — a card a
// coach runs a play from and the screen it was authored on disagreeing about
// what a dashed line means is worse than either being wrong on its own.
//
// The presentation renderer deliberately ignores this: it paints ONE uniform
// brush and lets the travelling ball read as the pass. The semantic
// distinction lives in the data and surfaces in edit and in print.

/// How each action kind is DRAWN. The coaching conventions, as data.
///
/// Dribble keeps the shared geometry's WAVE rather than a zigzag: the wave is
/// this codebase's documented dribble convention and is what presentation
/// already renders, and a second dribble look would be a divergence with
/// nothing behind it.
struct FrameNotation {
    var geometry: PathKind
    var headKind: PathKind
    var dash: [CGFloat]
    var usesBallColour: Bool

    static func `for`(_ kind: PlayActionKind) -> FrameNotation {
        switch kind {
        case .cut:
            return FrameNotation(geometry: .run, headKind: .run, dash: [], usesBallColour: false)
        case .dribble:
            return FrameNotation(geometry: .dribble, headKind: .run, dash: [], usesBallColour: false)
        case .screen:
            return FrameNotation(geometry: .run, headKind: .screen, dash: [], usesBallColour: false)
        case .pass:
            return FrameNotation(geometry: .run, headKind: .run, dash: [7, 5], usesBallColour: true)
        case .handoff:
            return FrameNotation(geometry: .run, headKind: .run, dash: [3, 3], usesBallColour: true)
        case .shot:
            return FrameNotation(geometry: .run, headKind: .run, dash: [10, 6], usesBallColour: true)
        }
    }
}
