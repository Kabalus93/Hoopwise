import SwiftUI

// MARK: - The Whistle mascot — original layered vector art
//
// A classic coach's pea whistle in 3/4 view: chunky rounded body,
// mouthpiece, top ring with a short lanyard tail, and the pea visible
// through the sound window. Every part is a separately animatable layer
// (pea offset, lanyard sway, puff progress, body wiggle) because the
// character comes from motion, not a face. Reduce Motion renders it
// static — animation parameters simply stay at rest.
//
// Drawn in a 100×100 design space and scaled; silhouette must read at
// 16pt and shine at 64pt.

/// Proportion presets — the three silhouette candidates.
struct WhistleProportions {
    var barrelRadius: CGFloat       // chamber size
    var barrelSquish: CGFloat       // 1 = circle, <1 = sportier ellipse
    var mouthLength: CGFloat        // mouthpiece reach, left of the barrel
    var mouthThickness: CGFloat     // mouthpiece height at the tip
    var tiltDegrees: Double         // whole-body stance
    var lanyardDrop: CGFloat        // cord tail length

    static let stubby = WhistleProportions(
        barrelRadius: 30, barrelSquish: 1.0, mouthLength: 30,
        mouthThickness: 19, tiltDegrees: -4, lanyardDrop: 16)
    static let classic = WhistleProportions(
        barrelRadius: 26, barrelSquish: 0.97, mouthLength: 40,
        mouthThickness: 15, tiltDegrees: -9, lanyardDrop: 20)
    static let sporty = WhistleProportions(
        barrelRadius: 22, barrelSquish: 0.92, mouthLength: 48,
        mouthThickness: 12, tiltDegrees: -15, lanyardDrop: 24)
}

/// Animatable state — all at rest for the static icon.
struct WhistleMotionState {
    var peaOffset: CGSize = .zero          // rattle inside the window
    var lanyardSway: CGFloat = 0           // -1…1, cord control-point lag
    var puffProgress: CGFloat = 0          // 0 hidden … 1 fully out, fades
    var bobOffset: CGFloat = 0             // vertical micro-bob
    var wiggleDegrees: Double = 0          // completion wiggle

    static let rest = WhistleMotionState()
}

struct WhistleIconView: View {
    var proportions: WhistleProportions = .classic
    var tint: Color = Color(red: 0.91, green: 0.51, blue: 0.29)   // warm default
    var motion: WhistleMotionState = .rest
    var darkScheme = false

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            context.scaleBy(x: scale, y: scale)

            let p = proportions
            // Barrel center: placed so mouthpiece + barrel stay in frame.
            let cx: CGFloat = 100 - p.barrelRadius - 12
            let cy: CGFloat = 58 + motion.bobOffset
            let center = CGPoint(x: cx, y: cy)

            // Whole-body stance + wiggle around the barrel center.
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(p.tiltDegrees + motion.wiggleDegrees))
            context.translateBy(x: -center.x, y: -center.y)

            let outline = tint.mix(with: .black, by: darkScheme ? 0.62 : 0.55)
            let metalDark = tint.mix(with: .black, by: darkScheme ? 0.32 : 0.24)
            let metalLight = tint.mix(with: .white, by: 0.18)

            // ---- Layer 1: lanyard (behind everything) ----
            let ringAngle: CGFloat = -.pi / 9       // right shoulder, clear of the notch
            let ringCenter = CGPoint(
                x: cx + cos(ringAngle) * (p.barrelRadius + 5.0),
                y: cy + sin(ringAngle) * (p.barrelRadius + 5.0) * p.barrelSquish)
            var cord = Path()
            cord.move(to: ringCenter)
            let sway = motion.lanyardSway * 10
            cord.addCurve(
                to: CGPoint(x: ringCenter.x + 7 + sway, y: ringCenter.y + p.lanyardDrop),
                control1: CGPoint(x: ringCenter.x + 9 + sway * 0.4, y: ringCenter.y + 3),
                control2: CGPoint(x: ringCenter.x + 2 + sway, y: ringCenter.y + p.lanyardDrop * 0.6))
            context.stroke(cord, with: .color(metalDark),
                           style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
            // Cord tip bead.
            let tip = CGPoint(x: ringCenter.x + 7 + sway, y: ringCenter.y + p.lanyardDrop)
            context.fill(Path(ellipseIn: CGRect(x: tip.x - 2.6, y: tip.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(metalDark))

            // ---- Layer 2: top ring ----
            let ringRect = CGRect(x: ringCenter.x - 5.5, y: ringCenter.y - 5.5, width: 11, height: 11)
            context.stroke(Path(ellipseIn: ringRect), with: .color(metalDark),
                           style: StrokeStyle(lineWidth: 3.6))

            // ---- Layer 3+4: body with the sound window BITTEN OUT of the
            // silhouette — the classic pea-whistle profile: mouthpiece slab
            // enters top-left, a notch opens the top of the round chamber,
            // and the pea shows through the slot.
            let mouthTop = cy - p.barrelRadius * p.barrelSquish - p.mouthThickness * 0.2
            let mouthBottom = mouthTop + p.mouthThickness
            let tipX = cx - p.mouthLength - p.barrelRadius * 0.25
            // Mouthpiece ends just past the chamber's centerline; the window
            // notch spans from there to the right shoulder.
            let junctionX = cx - p.barrelRadius * 0.05
            let notchRight = cx + p.barrelRadius * 0.58
            let notchBottom = cy - p.barrelRadius * 0.12

            var body = Path()
            let barrelRect = CGRect(x: cx - p.barrelRadius,
                                    y: cy - p.barrelRadius * p.barrelSquish,
                                    width: p.barrelRadius * 2,
                                    height: p.barrelRadius * 2 * p.barrelSquish)
            body.addEllipse(in: barrelRect)
            var mouth = Path()
            mouth.move(to: CGPoint(x: tipX + 3, y: mouthTop + 0.5))
            mouth.addLine(to: CGPoint(x: junctionX, y: mouthTop))
            mouth.addLine(to: CGPoint(x: junctionX, y: mouthBottom + p.barrelRadius * 0.2))
            mouth.addLine(to: CGPoint(x: tipX + 3, y: mouthBottom))
            mouth.addQuadCurve(to: CGPoint(x: tipX + 3, y: mouthTop + 0.5),
                               control: CGPoint(x: tipX - 3.6, y: mouthTop + p.mouthThickness / 2))
            mouth.closeSubpath()
            body.addPath(mouth)

            let notch = Path(roundedRect: CGRect(x: junctionX + 2,
                                                 y: mouthTop - 2,
                                                 width: notchRight - junctionX - 2,
                                                 height: notchBottom - (mouthTop - 2)),
                             cornerRadius: 5)

            context.drawLayer { layer in
                // Cartoon silhouette: stroke first at double width, fill over
                // it — the outline survives only outside the union.
                layer.stroke(body, with: .color(outline),
                             style: StrokeStyle(lineWidth: 5.2, lineJoin: .round))
                layer.fill(body, with: .linearGradient(
                    Gradient(colors: [metalLight, tint, metalDark]),
                    startPoint: CGPoint(x: tipX, y: mouthTop),
                    endPoint: CGPoint(x: cx + p.barrelRadius * 0.7, y: cy + p.barrelRadius)))

                // 3/4-view depth along the lower-right rim.
                var rimShadow = Path()
                rimShadow.addArc(center: center, radius: p.barrelRadius * 0.86,
                                 startAngle: .degrees(15), endAngle: .degrees(95), clockwise: false)
                layer.stroke(rimShadow, with: .color(.black.opacity(0.16)),
                             style: StrokeStyle(lineWidth: p.barrelRadius * 0.22, lineCap: .round))

                // Punch the window out of the silhouette.
                layer.blendMode = .clear
                layer.fill(notch, with: .color(.black))
                layer.blendMode = .normal

                // Chamber cavity: the notch's floor, inside the barrel.
                var cavityClip = Path()
                cavityClip.addEllipse(in: barrelRect.insetBy(dx: 1.2, dy: 1.2))
                layer.drawLayer { cavityLayer in
                    cavityLayer.clip(to: cavityClip)
                    let cavity = Path(roundedRect: CGRect(
                        x: junctionX + 2, y: cy - p.barrelRadius * 0.52,
                        width: notchRight - junctionX - 4,
                        height: p.barrelRadius * 0.42), cornerRadius: 3)
                    cavityLayer.fill(cavity, with: .color(.black.opacity(darkScheme ? 0.8 : 0.66)))

                    // ---- Layer 5: the pea, rattling in the chamber ----
                    let peaR = p.barrelRadius * 0.27
                    let peaCenter = CGPoint(
                        x: (junctionX + notchRight) / 2 + motion.peaOffset.width,
                        y: cy - p.barrelRadius * 0.3 + motion.peaOffset.height)
                    let peaRect = CGRect(x: peaCenter.x - peaR, y: peaCenter.y - peaR,
                                         width: peaR * 2, height: peaR * 2)
                    cavityLayer.fill(Path(ellipseIn: peaRect),
                                     with: .color(tint.mix(with: .white, by: 0.5)))
                    cavityLayer.fill(Path(ellipseIn: CGRect(
                        x: peaCenter.x - peaR * 0.55, y: peaCenter.y - peaR * 0.7,
                        width: peaR * 0.66, height: peaR * 0.66)),
                        with: .color(.white.opacity(0.65)))
                }

                // Crisp inner edges where the notch cuts the body.
                layer.clip(to: body)
                layer.stroke(notch, with: .color(outline),
                             style: StrokeStyle(lineWidth: 2.6, lineJoin: .round))
            }

            // Mouthpiece slit at the tip.
            var slit = Path()
            slit.move(to: CGPoint(x: tipX + 0.5, y: mouthTop + p.mouthThickness * 0.45))
            slit.addLine(to: CGPoint(x: tipX + 10, y: mouthTop + p.mouthThickness * 0.45))
            context.stroke(slit, with: .color(.black.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // ---- Layer 6: highlight (3/4-view sheen) ----
            var sheen = Path()
            sheen.addArc(center: center,
                         radius: p.barrelRadius * 0.8,
                         startAngle: .degrees(158), endAngle: .degrees(196), clockwise: false)
            context.stroke(sheen, with: .color(.white.opacity(darkScheme ? 0.3 : 0.45)),
                           style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

            // ---- Layer 7: air puffs from the mouthpiece (completion only) ----
            if motion.puffProgress > 0 {
                let progress = motion.puffProgress
                let alpha = Double(1 - progress) * 0.9
                let reach = 6 + progress * 11
                for (index, dy) in [-4.5, 0.5, 5.0].enumerated() {
                    var puff = Path()
                    let y = mouthTop + p.mouthThickness * 0.35 + dy
                    let x0 = tipX - 3 - reach - CGFloat(index) * 1.6
                    puff.move(to: CGPoint(x: x0, y: y))
                    puff.addLine(to: CGPoint(x: x0 - 5.5 - progress * 3, y: y + (dy < 0 ? -1.6 : dy > 2 ? 1.6 : 0)))
                    context.stroke(puff, with: .color(tint.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension Color {
    /// Simple sRGB mix — enough for shading a mascot.
    func mix(with other: Color, by fraction: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(red: Double(a.redComponent + (b.redComponent - a.redComponent) * fraction),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * fraction),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * fraction))
    }
}
