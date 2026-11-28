import SwiftUI
import UIKit

// THE POST TEMPLATES (26 Nov 2026, Luther: "NBA-like overlays on the photos, an
// automatic adjustment" — three references: a stat card beside the photo, a
// game line under it, a season poster). Drawn at 1080 px wide, square or 4:5,
// in the program's colour; the numbers come from AthletePostFacts. No league
// marks or logos — the academy's name stands where a league's would.

enum AthletePostTemplate: String, CaseIterable, Identifiable {
    case gameLine, statCard, poster
    // Ten more (26 Nov 2026) — AthletePostTemplatesMore.swift.
    case duotone, scoreboard, magazine, holoCard, diagonal, giantNumber, scrapbook, filmStrip, swiss, neon, torn
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .gameLine: chinese ? "比赛数据" : "Game line"
        case .statCard: chinese ? "数据卡" : "Stat card"
        case .poster: chinese ? "海报" : "Poster"
        case .duotone: chinese ? "双色" : "Duotone"
        case .scoreboard: chinese ? "记分牌" : "Scoreboard"
        case .magazine: chinese ? "杂志封面" : "Cover"
        case .holoCard: chinese ? "收藏卡" : "Holo card"
        case .diagonal: chinese ? "斜切" : "Diagonal"
        case .giantNumber: chinese ? "大号码" : "Big number"
        case .scrapbook: chinese ? "手账" : "Scrapbook"
        case .filmStrip: chinese ? "胶片" : "Film"
        case .swiss: chinese ? "瑞士风格" : "Swiss"
        case .neon: chinese ? "霓虹" : "Neon"
        case .torn: chinese ? "撕纸拼贴" : "Torn paper"
        }
    }
    var symbol: String {
        switch self {
        case .gameLine: "rectangle.bottomthird.inset.filled"
        case .statCard: "rectangle.split.2x1"
        case .poster: "person.crop.rectangle.stack"
        case .duotone: "circle.lefthalf.filled"
        case .scoreboard: "rectangle.grid.3x2"
        case .magazine: "book.closed"
        case .holoCard: "sparkles.rectangle.stack"
        case .diagonal: "line.diagonal"
        case .giantNumber: "number"
        case .scrapbook: "photo.on.rectangle.angled"
        case .filmStrip: "film"
        case .swiss: "square.grid.3x3"
        case .neon: "lightbulb.max"
        case .torn: "scissors"
        }
    }
}

extension AthletePostTemplate {
    /// Templates that stand the athlete out of the photo (Vision cut-out).
    var liftsSubject: Bool { self == .poster || self == .magazine || self == .giantNumber || self == .torn }
}

enum AthletePostAspect: String, CaseIterable, Identifiable {
    case portrait, square
    var id: String { rawValue }
    var size: CGSize { self == .square ? CGSize(width: 1080, height: 1080) : CGSize(width: 1080, height: 1350) }
    var title: String { self == .square ? "1:1" : "4:5" }
}

/// One post, at its real size in points (render at scale 1 = pixels).
struct AthletePostCanvas: View {
    let template: AthletePostTemplate
    let facts: AthletePostFacts
    let photo: UIImage
    var cutout: UIImage?
    let aspect: AthletePostAspect
    /// The athlete alone, cropped to them.
    var figure: UIImage? = nil
    /// The figure is whole down to the feet (else it sits on the bottom edge).
    var figureStands = true
    /// The best close-up of their face (the face index).
    var portrait: PostPortrait? = nil

    var body: some View {
        let size = aspect.size
        Group {
            switch template {
            case .gameLine: GameLinePost(facts: facts, photo: photo, size: size)
            case .statCard: StatCardPost(facts: facts, photo: photo, size: size)
            case .poster: PosterPost(facts: facts, photo: photo, cutout: cutout, size: size)
            case .duotone: DuotonePost(facts: facts, photo: photo, size: size)
            case .scoreboard: ScoreboardPost(facts: facts, photo: photo, size: size)
            case .magazine: MagazinePost(facts: facts, photo: photo, cutout: cutout, size: size)
            case .holoCard: HoloCardPost(facts: facts, photo: photo, size: size)
            case .diagonal: DiagonalPost(facts: facts, photo: photo, size: size)
            case .giantNumber: GiantNumberPost(facts: facts, photo: photo, cutout: cutout, size: size)
            case .scrapbook: ScrapbookPost(facts: facts, photo: photo, size: size)
            case .filmStrip: FilmStripPost(facts: facts, photo: photo, size: size)
            case .swiss: SwissPost(facts: facts, photo: photo, size: size)
            case .neon: NeonPost(facts: facts, photo: photo, size: size)
            case .torn: TornPaperPost(facts: facts, photo: photo, cutout: figure ?? cutout, stands: figure == nil || figureStands,
                                      portrait: portrait, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Shared pieces

extension AthletePostFacts {
    var color: Color { Color(hex: colorHex) }
}

func postHeavy(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .default).width(.compressed) }
func postLight(_ size: CGFloat) -> Font { .system(size: size, weight: .light, design: .default).width(.compressed) }

struct PostPhotoFill: View {
    let photo: UIImage
    var body: some View {
        GeometryReader { geo in
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                // Heads are near the top of a sports photo: keep them in.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
        }
    }
}

/// A halftone of dots growing toward the bottom.
struct PostHalftone: View {
    var color: Color
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                let t = y / size.height
                let r = step * 0.42 * max(0, (t - 0.35) / 0.65)
                var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                if r > 0.5 {
                    while x < size.width {
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                        x += step
                    }
                }
                y += step; row += 1
            }
        }
    }
}

// MARK: - 1. Game line — the photo, the name, three numbers under it

private struct GameLinePost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    var body: some View {
        let stats = facts.headline
        ZStack(alignment: .bottom) {
            PostPhotoFill(photo: photo)
            LinearGradient(stops: [.init(color: .clear, location: 0.38),
                                   .init(color: .black.opacity(0.55), location: 0.6),
                                   .init(color: .black.opacity(0.94), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if !facts.firstName.isEmpty {
                        Text(facts.firstName.uppercased()).font(postLight(116)).foregroundStyle(.white.opacity(0.85))
                    }
                    Text(facts.lastName.uppercased()).font(postHeavy(116)).foregroundStyle(.white)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                if !facts.subtitle.isEmpty {
                    Text(facts.subtitle.uppercased())
                        .font(.system(size: 28, weight: .semibold)).tracking(3)
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                if facts.hasStats {
                    HStack(spacing: 22) {
                        ForEach(stats) { s in
                            VStack(spacing: 4) {
                                Text(s.word.uppercased())
                                    .font(.system(size: 26, weight: .heavy)).tracking(2)
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(.white)
                                Text(s.text).font(postHeavy(170)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                        }
                    }
                }
                HStack {
                    Text(facts.eyebrow).font(.system(size: 22, weight: .bold)).tracking(3)
                    Spacer()
                    Text(facts.academy.uppercased()).font(.system(size: 22, weight: .bold)).tracking(3)
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 52)
            Rectangle().fill(facts.color).frame(height: 14)
        }
    }
}

// MARK: - 2. Stat card — the photo beside a white panel of numbers

private struct StatCardPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let size: CGSize

    var body: some View {
        let h = size.height
        let photoRect = CGRect(x: 66, y: h * 0.13, width: 500, height: h * 0.74)
        let panel = CGRect(x: 540, y: h * 0.095, width: 476, height: h * 0.79)
        let stats = Array(facts.stats.prefix(6))
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [facts.color.opacity(0.92), facts.color.mix(with: .black, by: 0.55)],
                           startPoint: .top, endPoint: .bottom)
            PostHalftone(color: .white.opacity(0.1))
            // The photo.
            PostPhotoFill(photo: photo)
                .frame(width: photoRect.width, height: photoRect.height)
                .overlay(Rectangle().strokeBorder(.white, lineWidth: 6))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                .offset(x: photoRect.minX, y: photoRect.minY)
            // The panel.
            VStack(spacing: 10) {
                if !facts.firstName.isEmpty {
                    Text(facts.firstName.uppercased())
                        .font(.system(size: 34, weight: .heavy)).tracking(4).lineLimit(1).minimumScaleFactor(0.5)
                }
                Text(facts.lastName.uppercased())
                    .font(postHeavy(120)).lineLimit(1).minimumScaleFactor(0.4)
                if !facts.subtitle.isEmpty {
                    Text(facts.subtitle.uppercased())
                        .font(.system(size: 24, weight: .semibold)).tracking(2).lineLimit(1).minimumScaleFactor(0.6)
                        .opacity(0.75)
                }
                Rectangle().frame(width: 110, height: 3).opacity(0.5).padding(.vertical, 14)
                if facts.hasStats {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: h * 0.025) {
                        ForEach(stats) { s in
                            VStack(spacing: 0) {
                                Text(s.text).font(postHeavy(h > 1100 ? 116 : 96)).lineLimit(1).minimumScaleFactor(0.5)
                                Text(s.label).font(.system(size: 28, weight: .semibold)).tracking(2)
                            }
                        }
                    }
                } else {
                    Text(facts.eyebrow).font(.system(size: 30, weight: .heavy)).tracking(3)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(facts.color.mix(with: .black, by: 0.15))
            .padding(.horizontal, 36)
            .padding(.top, 54)
            .frame(width: panel.width, height: panel.height)
            .background(Rectangle().fill(.white).shadow(color: .black.opacity(0.3), radius: 30, y: 12))
            .offset(x: panel.minX, y: panel.minY)
            // Top: the academy; bottom: the moment.
            HStack {
                Text(facts.academy.uppercased()).font(.system(size: 24, weight: .heavy)).tracking(4)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 66).padding(.top, 40)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("#" + facts.eyebrow.replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 34, weight: .black).italic()).foregroundStyle(.white)
                }
                .padding(.horizontal, 66).padding(.bottom, 34)
            }
        }
    }
}

// MARK: - 3. Poster — the athlete lifted out over their name, the big number

private struct PosterPost: View {
    let facts: AthletePostFacts
    let photo: UIImage
    let cutout: UIImage?
    let size: CGSize

    var body: some View {
        let h = size.height
        let bigText: String = facts.jersey.map(String.init) ?? facts.big?.text ?? ""
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [facts.color.mix(with: .white, by: 0.55), facts.color.mix(with: .white, by: 0.2), facts.color],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            // The name, over and over, behind everything.
            VStack(alignment: .leading, spacing: -24) {
                ForEach(0..<9, id: \.self) { i in
                    Text(String(repeating: facts.lastName.uppercased() + "  ", count: 4))
                        .font(postHeavy(150)).lineLimit(1).fixedSize()
                        .foregroundStyle(.white.opacity(i % 2 == 0 ? 0.22 : 0.12))
                        .offset(x: i % 2 == 0 ? -40 : -180)
                }
            }
            .frame(width: size.width, height: h, alignment: .topLeading)
            .clipped()
            // A large, faded portrait at the top left.
            PostPhotoFill(photo: photo)
                .saturation(0)
                .opacity(0.28)
                .frame(width: size.width * 0.72, height: h * 0.55)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .leading, endPoint: .trailing))
            // The athlete.
            Group {
                if let cutout {
                    Image(uiImage: cutout).resizable().scaledToFit()
                } else {
                    // No cut-out (Vision found no one): the photo fades
                    // into the poster on every side.
                    PostPhotoFill(photo: photo)
                        .mask(EllipticalGradient(stops: [.init(color: .black, location: 0),
                                                         .init(color: .black, location: 0.55),
                                                         .init(color: .clear, location: 1)]))
                }
            }
            .frame(width: size.width * 0.66, height: h * 0.82, alignment: .bottom)
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .offset(x: 10, y: h * 0.18)
            // The words, right.
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 14) {
                    Rectangle().fill(.white).frame(width: 60, height: 3)
                    Text(facts.eyebrow).font(.system(size: 30, weight: .heavy)).tracking(4).foregroundStyle(.white)
                    Rectangle().fill(.white).frame(width: 60, height: 3)
                }
                Text(facts.lastName.uppercased())
                    .font(.system(size: 92, weight: .black, design: .serif)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.4)
                if !facts.firstName.isEmpty {
                    Text(facts.firstName.uppercased())
                        .font(.system(size: 34, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.9))
                }
                if !bigText.isEmpty {
                    ZStack {
                        Text(bigText).font(postHeavy(h > 1100 ? 300 : 250)).foregroundStyle(.white)
                            .offset(x: 6, y: 6)
                        Text(bigText).font(postHeavy(h > 1100 ? 300 : 250)).foregroundStyle(facts.color.mix(with: .black, by: 0.25))
                    }
                    .padding(.top, 4)
                    if facts.jersey == nil, let big = facts.big {
                        Text(big.word.uppercased()).font(.system(size: 30, weight: .heavy)).tracking(4)
                            .foregroundStyle(.white).padding(.top, -24)
                    }
                }
                Spacer(minLength: 0)
                if facts.hasStats {
                    Text(facts.subtitle.uppercased())
                        .font(.system(size: 22, weight: .heavy)).tracking(4).foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 6)
                    ForEach(Array(facts.stats.filter { $0.key != "gp" && $0.value > 0 }.prefix(4))) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(s.word).font(.system(size: 52, weight: .black, design: .serif))
                            Text(s.text).font(.system(size: 52, weight: .light))
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    }
                }
                Text(facts.academy.uppercased())
                    .font(.system(size: 20, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 14)
            }
            .frame(width: size.width * 0.5, height: h - 120, alignment: .topTrailing)
            .offset(x: size.width * 0.5 - 60, y: 60)
        }
    }
}
