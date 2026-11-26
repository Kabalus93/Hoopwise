import SwiftUI
import UIKit

// TEN MORE POST TEMPLATES (26 Nov 2026, Luther: "be creative and work on a
// total of 10 more remarkable templates"). Each has one idea of its own:
// duotone, scoreboard, magazine cover, holo card, diagonal split, giant
// number, scrapbook, film strip, Swiss grid, neon. Same inputs as the first
// three (AthletePostFacts, the photo, Vision's cut-out when there is one),
// drawn at 1080 px wide in 4:5 or 1:1.

// MARK: - Shared

private let ink = Color(red: 0.07, green: 0.07, blue: 0.09)

/// The stats worth printing: non-zero counted ones (GAMES kept apart).
private extension AthletePostFacts {
    var shown: [Stat] { stats.filter { $0.key != "gp" && $0.value > 0 } }
    var gamesStat: Stat? { stats.first { $0.key == "gp" } }
    var fullName: String { firstName.isEmpty ? lastName : firstName + " " + lastName }
    /// "10 points · 1 assist" — the subtitle line of a film.
    var sentence: String {
        headline.map { s in
            let word = s.word.lowercased()
            let one = s.value == 1 && !s.text.contains(".")
            return "\(s.text) \(one && word.hasSuffix("s") ? String(word.dropLast()) : word)"
        }.joined(separator: " · ")
    }
    /// The big number of the piece: the jersey, else the biggest stat.
    var heroNumber: String { jersey.map(String.init) ?? big?.text ?? "" }
    /// Chinese words on the post (the stat words are written in the post's language).
    var chinese: Bool {
        (stats.first?.word ?? lastName).unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
}

/// The athlete on their own (Vision) or, without a cut-out, the photo fading out.
private struct PostSubject: View {
    let photo: UIImage
    let cutout: UIImage?
    var body: some View {
        if let cutout {
            Image(uiImage: cutout).resizable().scaledToFit()
        } else {
            PostPhotoFill(photo: photo)
                .mask(EllipticalGradient(stops: [.init(color: .black, location: 0),
                                                 .init(color: .black, location: 0.55),
                                                 .init(color: .clear, location: 1)]))
        }
    }
}

private func glow(_ c: Color) -> some ViewModifier { GlowModifier(color: c) }
private struct GlowModifier: ViewModifier {
    let color: Color
    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: 4)
            .shadow(color: color, radius: 14)
            .shadow(color: color.opacity(0.8), radius: 34)
    }
}

// MARK: - 4. Duotone — the photo in the team's two colours, the name up the side

struct DuotonePost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    var body: some View {
        let h = size.height
        ZStack(alignment: .topLeading) {
            facts.color.mix(with: .black, by: 0.7)
            PostPhotoFill(photo: photo)
                .grayscale(1).contrast(1.25).brightness(0.05)
                .colorMultiply(facts.color.mix(with: .white, by: 0.35))
            LinearGradient(colors: [.clear, facts.color.mix(with: .black, by: 0.75).opacity(0.9)],
                           startPoint: .center, endPoint: .bottom)
            // The last name, up the left edge.
            Text(facts.lastName.uppercased())
                .font(postHeavy(h > 1100 ? 300 : 250)).lineLimit(1).fixedSize()
                .foregroundStyle(.white.opacity(0.92))
                .rotationEffect(.degrees(-90), anchor: .topLeading)
                .offset(x: 18, y: h - 40)
            VStack(alignment: .trailing, spacing: 6) {
                Text(facts.eyebrow).font(.system(size: 26, weight: .heavy)).tracking(5)
                if !facts.firstName.isEmpty {
                    Text(facts.firstName.uppercased()).font(postLight(70))
                }
                Spacer()
                ForEach(facts.headline) { s in
                    HStack(alignment: .lastTextBaseline, spacing: 12) {
                        Text(s.label).font(.system(size: 28, weight: .heavy)).tracking(3).opacity(0.85)
                        Text(s.text).font(postHeavy(150))
                    }
                }
                Text(facts.academy.uppercased()).font(.system(size: 20, weight: .bold)).tracking(4).opacity(0.7)
                    .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .frame(width: size.width - 300, height: h - 110, alignment: .topTrailing)
            .offset(x: 240, y: 56)
        }
    }
}

// MARK: - 5. Scoreboard — the numbers in lights under the photo

struct ScoreboardPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private let amber = Color(red: 1, green: 0.69, blue: 0.1)
    private let red = Color(red: 1, green: 0.23, blue: 0.19)

    var body: some View {
        let h = size.height
        let board = h * 0.38
        let cells = Array(facts.headline.prefix(3))
        VStack(spacing: 0) {
            PostPhotoFill(photo: photo)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    Text(facts.fullName.uppercased())
                        .font(postHeavy(96)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                        .padding(.horizontal, 54).padding(.bottom, 26)
                }
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.06)
                // The LED matrix.
                Canvas { context, s in
                    let step: CGFloat = 12
                    var y: CGFloat = step / 2
                    while y < s.height {
                        var x: CGFloat = step / 2
                        while x < s.width {
                            context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)),
                                         with: .color(.white.opacity(0.05)))
                            x += step
                        }
                        y += step
                    }
                }
                VStack(spacing: 18) {
                    HStack {
                        Text(facts.eyebrow).font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(amber)
                            .modifier(glow(amber.opacity(0.6)))
                        Spacer()
                        if let n = facts.jersey {
                            Text("#\(n)").font(.system(size: 40, weight: .bold, design: .monospaced)).foregroundStyle(red)
                                .modifier(glow(red.opacity(0.7)))
                        }
                    }
                    HStack(spacing: 18) {
                        ForEach(cells) { s in
                            VStack(spacing: 8) {
                                Text(s.text)
                                    .font(.system(size: h > 1100 ? 120 : 96, weight: .bold, design: .monospaced))
                                    .foregroundStyle(amber).modifier(glow(amber.opacity(0.7)))
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity, minHeight: board * 0.45)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(.black)
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12), lineWidth: 2)))
                                Text(s.label).font(.system(size: 24, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    HStack {
                        Text(facts.subtitle.uppercased()).lineLimit(1)
                        Spacer()
                        Text(facts.academy.uppercased()).lineLimit(1)
                    }
                    .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 54).padding(.vertical, 30)
            }
            .frame(height: board)
            .overlay(alignment: .top) { Rectangle().fill(facts.color).frame(height: 10) }
        }
    }
}

// MARK: - 6. Magazine cover — a masthead the athlete stands in front of

struct MagazinePost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let cutout: UIImage?
    let size: CGSize

    var body: some View {
        let h = size.height
        let masthead = facts.academy.isEmpty ? "COURTSIDE" : facts.academy.uppercased()
        let lines = Array(facts.shown.prefix(3))
        ZStack(alignment: .topLeading) {
            PostPhotoFill(photo: photo)
            if cutout != nil { Color.black.opacity(0.0) }
            // The masthead behind the athlete when they can be lifted out.
            Text(masthead)
                .font(.system(size: 150, weight: .black, design: .serif)).tracking(-4)
                .lineLimit(1).minimumScaleFactor(0.3)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                .frame(width: size.width - 80)
                .offset(x: 40, y: 36)
            if let cutout {
                Image(uiImage: cutout).resizable().scaledToFill()
                    .frame(width: size.width, height: h, alignment: .top).clipped()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .init(x: 0.5, y: 0.55), endPoint: .bottom)
            // Cover lines.
            VStack(alignment: .leading, spacing: 18) {
                Text(facts.eyebrow)
                    .font(.system(size: 24, weight: .black)).tracking(3)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.85, blue: 0.1)).foregroundStyle(ink)
                ForEach(lines) { s in
                    VStack(alignment: .leading, spacing: -6) {
                        Text(s.text).font(postHeavy(110))
                        Text(s.word.uppercased() + (facts.source == .lastGame ? "" : (facts.chinese ? "" : " A GAME")))
                            .font(.system(size: 24, weight: .heavy)).tracking(2)
                    }
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                }
            }
            .offset(x: 48, y: h * 0.22)
            // The name and the date, bottom.
            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(facts.fullName.uppercased()).font(postHeavy(120)).lineLimit(1).minimumScaleFactor(0.4)
                Text(facts.subtitle.uppercased()).font(.system(size: 26, weight: .semibold)).tracking(3).opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(width: size.width - 330, height: h - 60, alignment: .bottomLeading)
            .offset(x: 48)
            Barcode(seed: facts.fullName + facts.eyebrow)
                .frame(width: 210, height: 110)
                .offset(x: size.width - 258, y: h - 158)
        }
    }
}

private struct Barcode: View {
    let seed: String
    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, s in
                var x: CGFloat = 8
                var n = UInt64(abs(seed.hashValue))
                while x < s.width - 8 {
                    let w = CGFloat(n % 3 + 1) * 2
                    context.fill(Path(CGRect(x: x, y: 0, width: w, height: s.height)), with: .color(.black))
                    n = n &* 6364136223846793005 &+ 1442695040888963407
                    x += w + CGFloat(n % 3 + 1) * 2
                }
            }
            Text(Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: ""))
                .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(.black)
        }
        .padding(8)
        .background(.white)
    }
}

// MARK: - 7. Holo card — a collector's card with a foil edge

struct HoloCardPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    var body: some View {
        let h = size.height
        let cardW = size.width * 0.82, cardH = h * 0.88
        let foil = AngularGradient(colors: [facts.color, .cyan, Color(red: 1, green: 0.4, blue: 0.85), .yellow,
                                            .mint, facts.color], center: .center)
        ZStack {
            RadialGradient(colors: [facts.color.mix(with: .black, by: 0.4), .black], center: .center, startRadius: 50, endRadius: 900)
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PostPhotoFill(photo: photo)
                    if let n = facts.jersey {
                        Text("\(n)").font(postHeavy(64)).foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .background(Circle().fill(facts.color))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                            .padding(22)
                    }
                    Text(facts.chinese ? "★ 珍藏" : "★ RARE")
                        .font(.system(size: 24, weight: .black)).tracking(3).foregroundStyle(ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.92)))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(26)
                }
                .frame(height: cardH * 0.62)
                .clipped()
                Text(facts.fullName.uppercased())
                    .font(postHeavy(84)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(facts.color)
                HStack(spacing: 0) {
                    ForEach(facts.headline) { s in
                        VStack(spacing: 2) {
                            Text(s.text).font(postHeavy(96))
                            Text(s.label).font(.system(size: 22, weight: .heavy)).tracking(3).opacity(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxHeight: .infinity)
                HStack {
                    Text(facts.eyebrow)
                    Spacer()
                    Text(facts.academy.uppercased())
                }
                .font(.system(size: 18, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 30).padding(.bottom, 22)
            }
            .background(Color(red: 0.09, green: 0.09, blue: 0.12))
            .overlay(LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .white.opacity(0.18), location: 0.45),
                                            .init(color: .clear, location: 0.55)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing).blendMode(BlendMode.screen))
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 46, style: .continuous).fill(foil))
            .frame(width: cardW, height: cardH)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        }
    }
}

// MARK: - 8. Diagonal split — photo and colour cut on a slant

struct DiagonalPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private struct Slant: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: r.width * 0.66, y: 0))
                p.addLine(to: CGPoint(x: r.width * 0.42, y: r.height))
                p.addLine(to: CGPoint(x: 0, y: r.height))
                p.closeSubpath()
            }
        }
    }

    var body: some View {
        let h = size.height
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [facts.color, facts.color.mix(with: .black, by: 0.5)], startPoint: .top, endPoint: .bottom)
            // The number, huge and faint, behind the stats.
            Text(facts.heroNumber)
                .font(postHeavy(h * 0.62)).foregroundStyle(.white.opacity(0.1)).lineLimit(1).fixedSize()
                .offset(x: size.width * 0.38, y: h * 0.12)
            PostPhotoFill(photo: photo)
                .clipShape(Slant())
            Slant().stroke(.white, lineWidth: 0)
            // A white rule along the cut.
            Path { p in
                p.move(to: CGPoint(x: size.width * 0.66 + 14, y: 0))
                p.addLine(to: CGPoint(x: size.width * 0.42 + 14, y: h))
            }
            .stroke(.white, lineWidth: 10)
            VStack(alignment: .trailing, spacing: 10) {
                Text(facts.eyebrow).font(.system(size: 24, weight: .heavy)).tracking(4).opacity(0.85)
                if !facts.firstName.isEmpty { Text(facts.firstName.uppercased()).font(postLight(64)) }
                Text(facts.lastName.uppercased()).font(postHeavy(108)).lineLimit(1).minimumScaleFactor(0.4)
                Spacer()
                ForEach(facts.headline) { s in
                    VStack(alignment: .trailing, spacing: -8) {
                        Text(s.text).font(postHeavy(140))
                        Text(s.word.uppercased()).font(.system(size: 24, weight: .heavy)).tracking(3).opacity(0.85)
                    }
                }
                Text(facts.academy.uppercased()).font(.system(size: 18, weight: .bold)).tracking(3).opacity(0.7).padding(.top, 8)
            }
            .foregroundStyle(.white)
            .frame(width: size.width * 0.44, height: h - 110, alignment: .topTrailing)
            .offset(x: size.width * 0.56 - 50, y: 56)
        }
    }
}

// MARK: - 9. Giant number — the athlete in front of their number

struct GiantNumberPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let cutout: UIImage?
    let size: CGSize

    var body: some View {
        let h = size.height
        let number = facts.heroNumber
        ZStack {
            LinearGradient(colors: [facts.color.mix(with: .white, by: 0.15), facts.color.mix(with: .black, by: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            Text(number)
                .font(postHeavy(number.count > 2 ? h * 0.52 : h * 0.78))
                .foregroundStyle(.white)
                .lineLimit(1).fixedSize()
                .offset(y: -h * 0.06)
            PostSubject(photo: photo, cutout: cutout)
                .frame(width: size.width * (cutout == nil ? 0.62 : 0.86), height: h * (cutout == nil ? 0.52 : 0.8))
                .offset(y: cutout == nil ? h * 0.13 : h * 0.1)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 6) {
                Spacer()
                Text(facts.jersey == nil ? (facts.big?.word.uppercased() ?? "") : facts.eyebrow)
                    .font(.system(size: 28, weight: .heavy)).tracking(6)
                Text(facts.fullName.uppercased()).font(postHeavy(100)).lineLimit(1).minimumScaleFactor(0.4)
                Text(([facts.jersey == nil ? facts.eyebrow : nil] + facts.headline.map { "\($0.text) \($0.label)" })
                        .compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.system(size: 26, weight: .bold)).tracking(2).opacity(0.85).lineLimit(1).minimumScaleFactor(0.5)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 60).padding(.bottom, 54)
            .frame(width: size.width, height: h)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: h * 0.35)
            }
        }
    }
}

// MARK: - 10. Scrapbook — a taped polaroid and notes on paper

struct ScrapbookPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private let paper = Color(red: 0.95, green: 0.93, blue: 0.88)
    private let stampRed = Color(red: 0.78, green: 0.16, blue: 0.16)

    var body: some View {
        let h = size.height
        // Square: a smaller polaroid, the notes in the column beside it.
        let square = h < size.width * 1.1
        let pw = square ? h * 0.58 : size.width * 0.66
        let notes = Array(facts.shown.prefix(3))
        let notesAt = square ? CGPoint(x: pw + 70, y: h * 0.2) : CGPoint(x: size.width * 0.5, y: h * 0.72)
        ZStack(alignment: .topLeading) {
            paper
            // Paper grain.
            Canvas { context, s in
                var n: UInt64 = 7
                for _ in 0..<2600 {
                    n = n &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(n % 1080) / 1080 * s.width
                    n = n &* 6364136223846793005 &+ 1442695040888963407
                    let y = CGFloat(n % 1350) / 1350 * s.height
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(.black.opacity(0.05)))
                }
            }
            // The polaroid.
            VStack(spacing: 0) {
                PostPhotoFill(photo: photo).frame(width: pw - 56, height: pw - 56)
                Text("\(facts.firstName.isEmpty ? facts.lastName : facts.firstName) · \(facts.eyebrow.lowercased().capitalized)")
                    .font(.system(size: 40, weight: .bold, design: .rounded).italic())
                    .foregroundStyle(ink.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.5)
                    .frame(height: 120)
            }
            .padding(.horizontal, 28).padding(.top, 28)
            .background(.white)
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            .overlay(alignment: .top) { tape.rotationEffect(.degrees(-6)).offset(y: -26) }
            .rotationEffect(.degrees(-4))
            .offset(x: 50, y: h * 0.07)
            // Notes on the paper.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { i, s in
                    let number = Text(s.text).font(.system(size: i == 0 ? 120 : 84, weight: .black, design: .rounded))
                        .foregroundStyle(facts.color)
                        .overlay {
                            if i == 0 { Ellipse().stroke(stampRed, lineWidth: 5).padding(-18).rotationEffect(.degrees(-8)) }
                        }
                    let word = Text(s.word.lowercased()).font(.system(size: 34, weight: .semibold, design: .rounded).italic())
                        .foregroundStyle(ink.opacity(0.75))
                    if square {
                        VStack(alignment: .leading, spacing: -6) { number; word }.padding(.bottom, 14)
                    } else {
                        HStack(alignment: .lastTextBaseline, spacing: 10) { number; word }
                    }
                }
            }
            .rotationEffect(.degrees(3))
            .offset(x: notesAt.x, y: notesAt.y)
            // A stamp.
            ZStack {
                Circle().stroke(stampRed, lineWidth: 6)
                Circle().stroke(stampRed, lineWidth: 2).padding(14)
                VStack(spacing: 2) {
                    Text(facts.academy.isEmpty ? "COURTSIDE" : facts.academy.uppercased())
                        .font(.system(size: 15, weight: .black)).tracking(1).lineLimit(3).minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                    Text(facts.lastName.uppercased()).font(.system(size: 30, weight: .black)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(String(Calendar.current.component(.year, from: .now))).font(.system(size: 16, weight: .black)).tracking(4)
                }
                .padding(30)
            }
            .foregroundStyle(stampRed)
            .opacity(0.8)
            .frame(width: 250, height: 250)
            .rotationEffect(.degrees(14))
            .offset(x: square ? size.width - 300 : 70, y: h - 300)
            Text(facts.subtitle)
                .font(.system(size: 30, weight: .semibold, design: .rounded).italic())
                .foregroundStyle(ink.opacity(0.6))
                .offset(x: notesAt.x, y: notesAt.y - 56)
        }
    }

    private var tape: some View {
        Rectangle().fill(Color(red: 0.93, green: 0.88, blue: 0.72).opacity(0.85))
            .frame(width: 190, height: 56)
            .overlay(Rectangle().fill(.white.opacity(0.25)).frame(height: 10), alignment: .top)
    }
}

// MARK: - 11. Film strip — a frame of the game with a subtitle

struct FilmStripPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private let filmOrange = Color(red: 1, green: 0.55, blue: 0.1)

    var body: some View {
        let h = size.height
        let stripH = h * 0.62
        ZStack(alignment: .topLeading) {
            Color.black
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    sprockets
                    PostPhotoFill(photo: photo)
                        .frame(height: stripH - 120)
                        .overlay(alignment: .bottom) {
                            Text("\(facts.fullName) — \(facts.sentence)")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 3)
                                .shadow(color: .black.opacity(0.8), radius: 10)
                                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                                .padding(.horizontal, 60).padding(.bottom, 26)
                        }
                    sprockets
                }
                .background(Color(red: 0.12, green: 0.1, blue: 0.08))
                .padding(.top, h * 0.08)
                Spacer()
                VStack(spacing: 18) {
                    Text(facts.fullName.uppercased())
                        .font(.system(size: 58, weight: .thin)).tracking(18).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.4)
                    Rectangle().fill(filmOrange).frame(width: 90, height: 3)
                    HStack(spacing: 46) {
                        ForEach(facts.headline) { s in
                            VStack(spacing: 2) {
                                Text(s.text).font(.system(size: 64, weight: .light)).foregroundStyle(.white)
                                Text(s.label).font(.system(size: 18, weight: .bold)).tracking(4).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    Text(facts.academy.uppercased() + "  ·  " + facts.subtitle.uppercased())
                        .font(.system(size: 18, weight: .semibold)).tracking(5).foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 60).padding(.bottom, h * 0.06)
            }
        }
    }

    private var sprockets: some View {
        HStack(spacing: 0) {
            Text(facts.eyebrow).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(filmOrange)
                .frame(width: 210)
            HStack(spacing: 22) {
                ForEach(0..<16, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5).fill(.black).frame(width: 30, height: 34)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 60)
        .clipped()
    }
}

// MARK: - 12. Swiss — a grid, thin numbers, one red rule

struct SwissPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private let swissRed = Color(red: 0.89, green: 0.12, blue: 0.13)
    private let cream = Color(red: 0.96, green: 0.95, blue: 0.92)

    var body: some View {
        let h = size.height
        let col = size.width / 6
        let rows = Array(facts.shown.prefix(h > 1100 ? 4 : 3))
        ZStack(alignment: .topLeading) {
            cream
            // The grid.
            Path { p in
                for i in 1..<6 { p.move(to: CGPoint(x: col * CGFloat(i), y: 0)); p.addLine(to: CGPoint(x: col * CGFloat(i), y: h)) }
            }
            .stroke(.black.opacity(0.06), lineWidth: 1)
            PostPhotoFill(photo: photo)
                .frame(width: col * 3, height: col * 3.6)
                .offset(x: col * 3, y: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(facts.eyebrow).font(.system(size: 22, weight: .bold)).tracking(2).foregroundStyle(swissRed)
                Rectangle().fill(swissRed).frame(width: col * 2.6, height: 6).padding(.vertical, 22)
                ForEach(rows) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(s.text).font(.system(size: h > 1100 ? 150 : 110, weight: .ultraLight)).monospacedDigit()
                        Text(s.label).font(.system(size: 22, weight: .bold))
                    }
                    .foregroundStyle(ink)
                }
            }
            .offset(x: col * 0.35, y: 70)
            VStack(alignment: .leading, spacing: -10) {
                Spacer()
                if !facts.firstName.isEmpty {
                    Text(facts.firstName).font(.system(size: 96, weight: .regular))
                }
                Text(facts.lastName).font(.system(size: 150, weight: .bold)).lineLimit(1).minimumScaleFactor(0.4)
                HStack {
                    Text(facts.subtitle).font(.system(size: 24, weight: .medium))
                    Spacer()
                    Text(facts.academy).font(.system(size: 24, weight: .bold))
                }
                .padding(.top, 24)
            }
            .foregroundStyle(ink)
            .frame(width: size.width - col * 0.7, height: h - 60, alignment: .bottomLeading)
            .offset(x: col * 0.35)
        }
    }
}

// MARK: - 13. Neon — the night court, tubes of light

struct NeonPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    private let magenta = Color(red: 1, green: 0.2, blue: 0.75)
    private let cyan = Color(red: 0.2, green: 0.95, blue: 1)

    var body: some View {
        let h = size.height
        let tube = facts.color.mix(with: .white, by: 0.25)
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.06)
            PostPhotoFill(photo: photo)
                .saturation(0.55).brightness(-0.12).opacity(0.75)
                .mask(RadialGradient(colors: [.black, .black.opacity(0.85), .clear], center: .init(x: 0.5, y: 0.38),
                                     startRadius: 80, endRadius: h * 0.62))
            RoundedRectangle(cornerRadius: 40).stroke(tube, lineWidth: 6)
                .modifier(glow(tube))
                .padding(36)
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    Capsule().fill(magenta).frame(width: 70, height: 4).modifier(glow(magenta))
                    Text(facts.eyebrow).font(.system(size: 26, weight: .heavy)).tracking(6).foregroundStyle(.white)
                        .modifier(glow(magenta))
                    Capsule().fill(magenta).frame(width: 70, height: 4).modifier(glow(magenta))
                }
                Spacer()
                Text(facts.lastName.uppercased())
                    .font(.system(size: 150, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.4)
                    .foregroundStyle(.white).modifier(glow(tube))
                if !facts.firstName.isEmpty {
                    Text(facts.firstName.uppercased()).font(.system(size: 44, weight: .semibold, design: .rounded)).tracking(10)
                        .foregroundStyle(.white).modifier(glow(cyan))
                }
                HStack(spacing: 40) {
                    ForEach(facts.headline) { s in
                        VStack(spacing: 0) {
                            Text(s.text).font(.system(size: 96, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                .modifier(glow(cyan))
                            Text(s.label).font(.system(size: 22, weight: .heavy)).tracking(4).foregroundStyle(magenta)
                                .modifier(glow(magenta.opacity(0.7)))
                        }
                    }
                }
                .padding(.top, 10)
                Text(facts.academy.uppercased()).font(.system(size: 18, weight: .bold)).tracking(5).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 14)
            }
            .padding(.horizontal, 80).padding(.vertical, 84)
        }
    }
}
