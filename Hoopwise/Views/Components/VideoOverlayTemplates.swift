import SwiftUI
import UIKit
import QuartzCore

// THE VIDEO OVERLAYS (26 Nov 2026). Six animated designs over a clip, built as
// a CALayer tree in the frame's pixels (1080 wide), origin top-left. Each part
// is drawn once by SwiftUI (ImageRenderer, transparent) and moved by Core
// Animation on the clip's timeline (VideoTrack) — the same tree plays over the
// preview and is burnt into the export. No league marks: the academy's name
// stands where a broadcaster's would.

enum VideoOverlayTemplate: String, CaseIterable, Identifiable {
    case lowerThird, statBug, titleCard, countUp, cinema, neonFrame
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .lowerThird: chinese ? "转播字幕条" : "Lower third"
        case .statBug: chinese ? "角标" : "Score bug"
        case .titleCard: chinese ? "片头片尾" : "Title card"
        case .countUp: chinese ? "数字跳动" : "Count-up"
        case .cinema: chinese ? "电影字幕" : "Cinema"
        case .neonFrame: chinese ? "霓虹框" : "Neon"
        }
    }
    var symbol: String {
        switch self {
        case .lowerThird: "rectangle.bottomthird.inset.filled"
        case .statBug: "rectangle.inset.topleft.filled"
        case .titleCard: "rectangle.on.rectangle.angled"
        case .countUp: "number.circle"
        case .cinema: "film"
        case .neonFrame: "lightbulb.max"
        }
    }
}

@MainActor
enum VideoOverlay {
    /// The overlay for a clip of `duration` seconds in a frame of `size`.
    static func layer(_ template: VideoOverlayTemplate, facts: AthletePostFacts,
                      size: CGSize, duration: Double) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: size)
        root.masksToBounds = true
        let b = Builder(facts: facts, size: size, track: VideoTrack(duration: duration), root: root)
        switch template {
        case .lowerThird: b.lowerThird()
        case .statBug: b.statBug()
        case .titleCard: b.titleCard()
        case .countUp: b.countUp()
        case .cinema: b.cinema()
        case .neonFrame: b.neonFrame()
        }
        return root
    }

    /// A SwiftUI view drawn once, at its own size, transparent.
    static func image<V: View>(_ view: V, _ size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.cgImage
    }
}

@MainActor
private struct Builder {
    let facts: AthletePostFacts
    let size: CGSize
    let track: VideoTrack
    let root: CALayer

    var w: CGFloat { size.width }
    var h: CGFloat { size.height }
    var d: Double { track.duration }
    /// A 9:16 story: the platforms' buttons cover the top and the bottom.
    var story: Bool { h > w * 1.6 }
    var safeTop: CGFloat { story ? 230 : 64 }
    var safeBottom: CGFloat { story ? 400 : 72 }
    var color: Color { facts.color }
    var uiColor: UIColor { UIColor(facts.color) }
    var name: String { facts.fullName.uppercased() }
    var stats: [AthletePostFacts.Stat] { Array(facts.shown.prefix(3)) }
    /// Long enough to leave on screen before it ends.
    var exits: Bool { d >= 5 }

    @discardableResult
    func sprite<V: View>(_ view: V, _ frame: CGRect, in parent: CALayer? = nil) -> CALayer {
        let l = CALayer()
        l.frame = frame
        l.contents = VideoOverlay.image(view, frame.size)
        l.contentsGravity = .resize
        (parent ?? root).addSublayer(l)
        return l
    }

    // MARK: 1. Lower third — the broadcast name bar

    func lowerThird() {
        let barH: CGFloat = 132
        let y = h - safeBottom - barH - 96
        let x: CGFloat = 56
        let barW = w - 2 * x
        let bar = sprite(NameBar(facts: facts, name: name), CGRect(x: x, y: y, width: barW, height: barH))
        track.animate(bar, "transform.translation.x",
                      [(0.35, -w), (0.85, 0)] + (exits ? [(d - 0.75, 0), (d - 0.2, -w)] : []))
        // A colour rule drawn across under the bar.
        let rule = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y + barH + 4))
        path.addLine(to: CGPoint(x: x + barW, y: y + barH + 4))
        rule.path = path.cgPath
        rule.strokeColor = UIColor.white.cgColor
        rule.lineWidth = 6
        root.addSublayer(rule)
        track.animate(rule, "strokeEnd", [(0.7, 0.0), (1.2, 1.0)] + (exits ? [(d - 0.75, 1.0), (d - 0.3, 0.0)] : []))
        if !stats.isEmpty {
            let strip = sprite(StatStrip(stats: stats, color: color),
                               CGRect(x: x + 40, y: y + barH + 14, width: barW - 40, height: 82))
            track.animate(strip, "transform.translation.x",
                          [(0.75, -w), (1.25, 0)] + (exits ? [(d - 0.85, 0), (d - 0.3, -w)] : []))
        }
    }

    // MARK: 2. Score bug — the corner box, its numbers turning over

    func statBug() {
        let bugW: CGFloat = min(640, w - 96), bugH: CGFloat = 124
        let frame = CGRect(x: 48, y: safeTop, width: bugW, height: bugH)
        let holder = CALayer()
        holder.frame = frame
        root.addSublayer(holder)
        sprite(BugBody(facts: facts, name: name), CGRect(origin: .zero, size: frame.size), in: holder)
        track.animate(holder, "transform.translation.x", [(0.2, -bugW - 60), (0.7, 0)])
        track.animate(holder, "opacity", [(0.2, 0.0), (0.5, 1.0)])
        // The stat cell turns over every 2.4 s.
        let cellW: CGFloat = 196
        let cells = stats.isEmpty ? [] : stats
        let period = 2.4
        for (i, s) in cells.enumerated() {
            let cell = sprite(BugCell(stat: s), CGRect(x: bugW - cellW, y: 0, width: cellW, height: bugH), in: holder)
            var keys: [(Double, Any)] = [(0, 0.0)]
            var moves: [(Double, Any)] = [(0, 24.0)]
            var t = 0.9 + Double(i) * period
            while t < d {
                keys += [(t, 0.0), (t + 0.3, 1.0), (t + period - 0.3, 1.0), (t + period, 0.0)]
                moves += [(t, 24.0), (t + 0.3, 0.0), (t + period - 0.3, 0.0), (t + period, -24.0)]
                t += period * Double(cells.count)
            }
            if cells.count == 1 { keys = [(0.9, 0.0), (1.2, 1.0)]; moves = [(0.9, 24.0), (1.2, 0.0)] }
            track.animate(cell, "opacity", keys, timing: .easeInEaseOut)
            track.animate(cell, "transform.translation.y", moves, timing: .easeInEaseOut)
        }
    }

    // MARK: 3. Title card — opens the clip, comes back to close it

    func titleCard() {
        let card = CALayer()
        card.frame = root.bounds
        root.addSublayer(card)
        sprite(TitleCardBackground(color: color), root.bounds, in: card)
        let text = sprite(TitleCardText(facts: facts, name: name, closing: false), root.bounds, in: card)
        track.animate(text, "transform.scale", [(0, 1.12), (0.9, 1.0)])
        track.animate(text, "opacity", [(0, 0.0), (0.4, 1.0)])
        let away = min(2.2, max(1.2, d * 0.3))
        track.animate(card, "transform.translation.y", [(away, 0.0), (away + 0.5, -h)], timing: .easeIn)
        guard d >= 7 else { return }
        let closing = CALayer()
        closing.frame = root.bounds
        root.addSublayer(closing)
        sprite(TitleCardBackground(color: color), root.bounds, in: closing)
        sprite(TitleCardText(facts: facts, name: name, closing: true), root.bounds, in: closing)
        track.animate(closing, "transform.translation.y", [(d - 2.6, h), (d - 2.0, 0.0)])
    }

    // MARK: 4. Count-up — the big number runs up to its value

    func countUp() {
        guard let hero = facts.shown.max(by: { $0.value < $1.value }) else { return nameOnly() }
        // Low in the frame, clear of a face in the middle.
        let centreY = h - safeBottom - (story ? 260 : 300)
        // A glow of the colour behind the number.
        let glowLayer = CAGradientLayer()
        glowLayer.type = .radial
        glowLayer.colors = [uiColor.withAlphaComponent(0.55).cgColor, uiColor.withAlphaComponent(0).cgColor]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        glowLayer.frame = CGRect(x: w / 2 - 520, y: centreY - 460, width: 1040, height: 920)
        root.addSublayer(glowLayer)
        track.animate(glowLayer, "opacity", [(0.6, 0.0), (1.2, 1.0)])
        // The number, counting.
        let numFrame = CGRect(x: 0, y: centreY - 230, width: w, height: 340)
        let num = CALayer()
        num.frame = numFrame
        root.addSublayer(num)
        let decimals = hero.text.contains(".")
        let steps = 24
        let images: [CGImage] = (0...steps).compactMap { i in
            let v = hero.value * Double(i) / Double(steps)
            let text = i == steps ? hero.text : (decimals ? String(format: "%.1f", v) : String(Int(v.rounded(.down))))
            return VideoOverlay.image(BigNumber(text: text), numFrame.size)
        }
        track.frames(num, images, start: 0.9, step: 1.1 / Double(steps))
        track.animate(num, "transform.scale", [(0.8, 0.6), (1.1, 1.08), (2.0, 1.12), (2.2, 1.0)], timing: .easeInEaseOut)
        track.animate(num, "opacity", [(0.8, 0.0), (1.0, 1.0)])
        // Its word, then the name and the other numbers.
        let word = sprite(Caps(text: hero.word.uppercased() + (facts.source == .lastGame ? "" : (facts.chinese ? " · 场均" : " A GAME")),
                               size: 40, tracking: 8),
                          CGRect(x: 0, y: numFrame.maxY + 6, width: w, height: 56))
        track.animate(word, "opacity", [(1.9, 0.0), (2.3, 1.0)])
        let nameLayer = sprite(NameLine(name: name, eyebrow: facts.eyebrow),
                               CGRect(x: 0, y: numFrame.minY - 170, width: w, height: 160))
        track.animate(nameLayer, "opacity", [(0.2, 0.0), (0.6, 1.0)])
        track.animate(nameLayer, "transform.translation.y", [(0.2, -30.0), (0.6, 0.0)])
        let others = facts.shown.filter { $0.key != hero.key }.prefix(2)
        if !others.isEmpty {
            let row = sprite(OtherStats(stats: Array(others)), CGRect(x: 0, y: numFrame.maxY + 80, width: w, height: 120))
            track.animate(row, "opacity", [(2.4, 0.0), (2.8, 1.0)])
            track.animate(row, "transform.translation.y", [(2.4, 30.0), (2.8, 0.0)])
        }
    }

    /// No numbers to show: the name on its own.
    private func nameOnly() {
        let l = sprite(NameLine(name: name, eyebrow: facts.eyebrow),
                       CGRect(x: 0, y: h - safeBottom - 200, width: w, height: 160))
        track.animate(l, "opacity", [(0.3, 0.0), (0.8, 1.0)])
    }

    // MARK: 5. Cinema — letterbox bars and a typed subtitle

    func cinema() {
        let barH = h * (story ? 0.13 : 0.11)
        let top = CALayer()
        top.backgroundColor = UIColor.black.cgColor
        top.frame = CGRect(x: 0, y: 0, width: w, height: barH)
        let bottom = CALayer()
        bottom.backgroundColor = UIColor.black.cgColor
        bottom.frame = CGRect(x: 0, y: h - barH, width: w, height: barH)
        root.addSublayer(top)
        root.addSublayer(bottom)
        track.animate(top, "transform.translation.y", [(0, -barH), (0.8, 0.0)], timing: .easeInEaseOut)
        track.animate(bottom, "transform.translation.y", [(0, barH), (0.8, 0.0)], timing: .easeInEaseOut)
        // In the bars: the occasion above, the name below.
        let head = sprite(Caps(text: [facts.eyebrow, facts.academy.uppercased()].filter { !$0.isEmpty }.joined(separator: "   ·   "),
                               size: 30, tracking: 6, opacity: 0.75),
                          CGRect(x: 0, y: barH - 60, width: w, height: 40))
        track.animate(head, "opacity", [(0.9, 0.0), (1.4, 1.0)])
        let nameLayer = sprite(Caps(text: name, size: 54, tracking: 22, weight: .thin),
                               CGRect(x: 0, y: h - barH + 22, width: w, height: 72))
        track.animate(nameLayer, "opacity", [(1.0, 0.0), (1.6, 1.0)])
        // The subtitle types itself above the bottom bar.
        let sentence = facts.sentence.isEmpty ? facts.subtitle : facts.sentence
        guard !sentence.isEmpty else { return }
        let subFrame = CGRect(x: 40, y: h - barH - 120, width: w - 80, height: 96)
        let sub = CALayer()
        sub.frame = subFrame
        root.addSublayer(sub)
        let chars = Array(sentence)
        let stride = max(1, chars.count / 40)
        var images: [CGImage] = []
        var n = 0
        while n < chars.count {
            n = min(chars.count, n + stride)
            if let img = VideoOverlay.image(Subtitle(text: String(chars[0..<n])), subFrame.size) { images.append(img) }
        }
        if let blank = VideoOverlay.image(Color.clear, subFrame.size) { images.insert(blank, at: 0) }
        track.frames(sub, images, start: 1.8, step: 0.045)
    }

    // MARK: 6. Neon — a tube of light drawn round the frame

    func neonFrame() {
        let tube = UIColor(facts.color.mix(with: .white, by: 0.3))
        let inset: CGFloat = 36
        let rect = root.bounds.insetBy(dx: inset, dy: inset)
        func tubeLayer(_ r: CGRect, _ c: UIColor, _ width: CGFloat) -> CAShapeLayer {
            let s = CAShapeLayer()
            s.path = UIBezierPath(roundedRect: r, cornerRadius: 46).cgPath
            s.fillColor = UIColor.clear.cgColor
            s.strokeColor = c.cgColor
            s.lineWidth = width
            s.lineCap = .round
            s.shadowColor = c.cgColor
            s.shadowRadius = 18
            s.shadowOpacity = 1
            s.shadowOffset = .zero
            root.addSublayer(s)
            return s
        }
        let outer = tubeLayer(rect, tube, 9)
        track.animate(outer, "strokeEnd", [(0.2, 0.0), (1.6, 1.0)], timing: .easeInEaseOut)
        let inner = tubeLayer(rect.insetBy(dx: 18, dy: 18), UIColor(red: 1, green: 0.25, blue: 0.75, alpha: 1), 3)
        track.animate(inner, "strokeEnd", [(0.5, 0.0), (1.9, 1.0)], timing: .easeInEaseOut)
        // The sign: the name flickers on, then the numbers.
        let signY = h - safeBottom - 330
        let sign = sprite(NeonSign(name: facts.lastName.uppercased(), first: facts.firstName.uppercased(), color: facts.color),
                          CGRect(x: 0, y: signY, width: w, height: 230))
        track.animate(sign, "opacity", [(1.5, 0.0), (1.56, 1.0), (1.62, 0.15), (1.7, 1.0), (1.78, 0.4), (1.86, 1.0)],
                      timing: .linear)
        if !stats.isEmpty {
            let row = sprite(NeonStats(stats: stats), CGRect(x: 0, y: signY + 230, width: w, height: 130))
            track.animate(row, "opacity", [(2.1, 0.0), (2.18, 1.0), (2.26, 0.3), (2.4, 1.0)], timing: .linear)
        }
    }
}

// MARK: - The drawn parts

private struct NameBar: View {
    let facts: AthletePostFacts
    let name: String
    var body: some View {
        HStack(spacing: 0) {
            if let jersey = facts.jersey {
                Text("\(jersey)").font(postHeavy(84)).foregroundStyle(.white)
                    .frame(width: 132).frame(maxHeight: .infinity)
                    .background(Color.black.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(facts.eyebrow).font(.system(size: 22, weight: .heavy)).tracking(4).foregroundStyle(.white.opacity(0.8))
                Text(name).font(postHeavy(72)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
            if !facts.academy.isEmpty {
                Text(facts.academy.uppercased()).font(.system(size: 18, weight: .bold)).tracking(2)
                    .foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.6)
                    .frame(maxWidth: 220, alignment: .trailing).padding(.trailing, 26)
            }
        }
        .background(LinearGradient(colors: [facts.color, facts.color.mix(with: .black, by: 0.35)],
                                   startPoint: .leading, endPoint: .trailing))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 30, topTrailingRadius: 6))
    }
}

private struct StatStrip: View {
    let stats: [AthletePostFacts.Stat]
    let color: Color
    var body: some View {
        HStack(spacing: 34) {
            ForEach(stats) { s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(s.text).font(postHeavy(58)).foregroundStyle(Color(white: 0.08))
                    Text(s.label).font(.system(size: 22, weight: .heavy)).tracking(2).foregroundStyle(color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxHeight: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct BugBody: View {
    let facts: AthletePostFacts
    let name: String
    var body: some View {
        HStack(spacing: 0) {
            Text(facts.jersey.map(String.init) ?? String(name.prefix(1)))
                .font(postHeavy(70)).foregroundStyle(.white)
                .frame(width: 112).frame(maxHeight: .infinity)
                .background(facts.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(facts.lastName.uppercased()).font(postHeavy(50)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                Text(facts.eyebrow).font(.system(size: 18, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 196)
        }
        .background(Color(white: 0.06).opacity(0.88))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.12)).frame(width: 196)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15), lineWidth: 1.5))
    }
}

private struct BugCell: View {
    let stat: AthletePostFacts.Stat
    var body: some View {
        VStack(spacing: 0) {
            Text(stat.text).font(postHeavy(64)).foregroundStyle(.white).monospacedDigit()
            Text(stat.label).font(.system(size: 18, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TitleCardBackground: View {
    let color: Color
    var body: some View {
        ZStack {
            LinearGradient(colors: [color, color.mix(with: .black, by: 0.55)], startPoint: .top, endPoint: .bottom)
            PostHalftone(color: .white.opacity(0.07))
        }
    }
}

private struct TitleCardText: View {
    let facts: AthletePostFacts
    let name: String
    let closing: Bool
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(closing ? facts.subtitle.uppercased() : facts.eyebrow)
                .font(.system(size: 30, weight: .heavy)).tracking(10).foregroundStyle(.white.opacity(0.75))
            if !facts.firstName.isEmpty && !closing {
                Text(facts.firstName.uppercased()).font(postLight(110)).foregroundStyle(.white)
            }
            Text(closing ? facts.lastName.uppercased() : facts.lastName.uppercased())
                .font(postHeavy(closing ? 120 : 210)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.3)
                .padding(.horizontal, 50)
            if !facts.shown.isEmpty {
                HStack(spacing: 50) {
                    ForEach(facts.shown.prefix(closing ? 5 : 3)) { s in
                        VStack(spacing: 0) {
                            Text(s.text).font(postHeavy(closing ? 120 : 96)).foregroundStyle(.white)
                            Text(s.label).font(.system(size: 24, weight: .heavy)).tracking(4).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 20)
            }
            Spacer()
            if !facts.academy.isEmpty {
                Text(facts.academy.uppercased()).font(.system(size: 24, weight: .bold)).tracking(6).foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 90)
            }
        }
    }
}

private struct BigNumber: View {
    let text: String
    var body: some View {
        Text(text).font(postHeavy(320)).foregroundStyle(.white).monospacedDigit()
            .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Caps: View {
    let text: String
    var size: CGFloat
    var tracking: CGFloat
    var weight: Font.Weight = .heavy
    var opacity: Double = 1
    var body: some View {
        Text(text).font(.system(size: size, weight: weight)).tracking(tracking)
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1).minimumScaleFactor(0.4)
            .shadow(color: .black.opacity(0.5), radius: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
    }
}

private struct NameLine: View {
    let name: String
    let eyebrow: String
    var body: some View {
        VStack(spacing: 4) {
            Text(eyebrow).font(.system(size: 26, weight: .heavy)).tracking(8).foregroundStyle(.white.opacity(0.8))
            Text(name).font(postHeavy(100)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4)
        }
        .shadow(color: .black.opacity(0.5), radius: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 50)
    }
}

private struct OtherStats: View {
    let stats: [AthletePostFacts.Stat]
    var body: some View {
        HStack(spacing: 70) {
            ForEach(stats) { s in
                VStack(spacing: 0) {
                    Text(s.text).font(postHeavy(84)).foregroundStyle(.white)
                    Text(s.label).font(.system(size: 22, weight: .heavy)).tracking(4).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Subtitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 40, weight: .medium)).foregroundStyle(.white)
            .shadow(color: .black, radius: 3).shadow(color: .black.opacity(0.6), radius: 10)
            .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NeonSign: View {
    let name: String
    let first: String
    let color: Color
    var body: some View {
        let tube = color.mix(with: .white, by: 0.3)
        VStack(spacing: 0) {
            if !first.isEmpty {
                Text(first).font(.system(size: 40, weight: .semibold, design: .rounded)).tracking(16)
                    .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.92))
                    .modifier(GlowModifier(color: Color(red: 1, green: 0.25, blue: 0.75)))
            }
            Text(name).font(.system(size: 150, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4)
                .modifier(GlowModifier(color: tube))
                .padding(.horizontal, 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NeonStats: View {
    let stats: [AthletePostFacts.Stat]
    var body: some View {
        let cyan = Color(red: 0.2, green: 0.95, blue: 1)
        HStack(spacing: 60) {
            ForEach(stats) { s in
                VStack(spacing: 0) {
                    Text(s.text).font(.system(size: 76, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .modifier(GlowModifier(color: cyan))
                    Text(s.label).font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(5)
                        .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.85))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
