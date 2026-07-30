import Foundation
import CoreGraphics

// MARK: - Court Space
//
// The single coordinate system for all play diagrams.
//
// Units are COURT FEET, never normalized 0-1. The legacy `CourtPlayer.position`
// used a 0-1 space; nothing was ever persisted in it, so it converted for free.
// Do not reintroduce a normalized space — a diagram authored in one and read in
// the other is silently wrong, and the error scales with court size.
//
// Orientation matches CourtBackgroundView:
//   x = 0    left sideline          x = width   right sideline
//   y = 0    attacking baseline     y increases away from that basket
//
// A half-court diagram uses y in 0...halfLength. A full-court diagram uses
// y in 0...fullLength, with the second basket at y = fullLength.

/// Rule set the court geometry follows.
///
/// This is part of the model, not a renderer setting. A diagram authored
/// against a 6.75m FIBA arc and later re-read as NBA would place shooters on
/// the wrong side of the line — the positions are only meaningful relative to
/// the markings they were drawn against.
enum CourtStandard: String, Codable, CaseIterable, Hashable {
    case nba
    case fiba

    var displayName: String {
        switch self {
        case .nba:  return "NBA"
        case .fiba: return "FIBA"
        }
    }

    var metrics: CourtMetrics {
        switch self {
        case .nba:  return .nba
        case .fiba: return .fiba
        }
    }
}

/// How much of the floor a diagram covers.
enum CourtMode: String, Codable, CaseIterable, Hashable {
    /// One end. The common case for set plays and shell work.
    case half
    /// Both ends. Required for press breaks and fast breaks, which are
    /// existing PlayCategory cases that a half-court space cannot express.
    case full

    var displayName: String {
        switch self {
        case .half: return "Half court"
        case .full: return "Full court"
        }
    }
}

/// Court dimensions and markings in feet.
///
/// FIBA figures are metric converted to feet, so they are deliberately not
/// round numbers. Keep them as-is: rounding a 6.75m arc to 22ft moves the line
/// almost two inches, which is visible at print size.
struct CourtMetrics: Hashable, Sendable {
    /// Sideline to sideline.
    var width: CGFloat
    /// Baseline to baseline.
    var fullLength: CGFloat
    /// Baseline to half-court line.
    var halfLength: CGFloat { fullLength / 2 }

    /// Basket centre, measured from the baseline.
    var basketFromBaseline: CGFloat
    /// Rim radius, for drawing.
    var rimRadius: CGFloat
    /// Backboard width.
    var backboardWidth: CGFloat

    /// Paint width, sideline-to-sideline direction.
    var keyWidth: CGFloat
    /// Baseline to free-throw line.
    var freeThrowLineFromBaseline: CGFloat
    /// Free-throw circle radius.
    var freeThrowCircleRadius: CGFloat

    /// Three-point arc radius, measured from the basket centre.
    var threePointRadius: CGFloat
    /// Distance from each sideline to the straight corner-three line.
    var cornerThreeInsetFromSideline: CGFloat

    /// No-charge semicircle radius, from the basket centre.
    var restrictedAreaRadius: CGFloat
    /// Centre circle radius at half court.
    var centerCircleRadius: CGFloat

    static let nba = CourtMetrics(
        width: 50,
        fullLength: 94,
        basketFromBaseline: 5.25,
        rimRadius: 0.75,
        backboardWidth: 6,
        keyWidth: 16,
        freeThrowLineFromBaseline: 19,
        freeThrowCircleRadius: 6,
        threePointRadius: 23.75,
        cornerThreeInsetFromSideline: 3,
        restrictedAreaRadius: 4,
        centerCircleRadius: 6
    )

    /// 28m x 15m. Arc 6.75m, rectangular key 4.9m x 5.8m.
    static let fiba = CourtMetrics(
        width: 49.2126,                     // 15 m
        fullLength: 91.8635,                // 28 m
        basketFromBaseline: 5.1673,         // 1.575 m
        rimRadius: 0.7415,                  // 0.226 m
        backboardWidth: 5.9055,             // 1.8 m
        keyWidth: 16.0761,                  // 4.9 m
        freeThrowLineFromBaseline: 19.0289, // 5.8 m
        freeThrowCircleRadius: 5.9055,      // 1.8 m
        threePointRadius: 22.1457,          // 6.75 m
        cornerThreeInsetFromSideline: 2.9528, // 0.9 m
        restrictedAreaRadius: 4.1010,       // 1.25 m
        centerCircleRadius: 5.9055          // 1.8 m
    )

    /// Basket centre for the near end.
    var nearBasket: CGPoint {
        CGPoint(x: width / 2, y: basketFromBaseline)
    }

    /// Basket centre for the far end. Only meaningful in `.full` mode.
    var farBasket: CGPoint {
        CGPoint(x: width / 2, y: fullLength - basketFromBaseline)
    }
}

/// The drawable extent of a diagram: which rules, and how much floor.
struct CourtSpace: Codable, Hashable {
    var standard: CourtStandard
    var mode: CourtMode

    init(standard: CourtStandard = .fiba, mode: CourtMode = .half) {
        self.standard = standard
        self.mode = mode
    }

    var metrics: CourtMetrics { standard.metrics }

    var width: CGFloat { metrics.width }

    var length: CGFloat {
        switch mode {
        case .half: return metrics.halfLength
        case .full: return metrics.fullLength
        }
    }

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: length)
    }

    /// Clamps a point into the court, so dragging can't strand an entity
    /// off-floor where it would never render.
    func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), width),
                y: min(max(point.y, 0), length))
    }

    func contains(_ point: CGPoint) -> Bool {
        bounds.contains(point)
    }
}
