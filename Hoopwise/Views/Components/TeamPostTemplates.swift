import SwiftUI

// TEAM POST TEMPLATES (28 Nov 2026, Luther, four club posts as reference:
// a score bar over a game photo, a "<team> AT <opponent>" game-day poster,
// a cream celebration collage). Drawn at their real size (1080 wide), the
// team's colour, the academy where a league's marks would stand — no league
// or club marks (App Review 4.1). Each kind has its own templates.

enum TeamPostTemplate: String, CaseIterable, Identifiable {
    case scoreBar, bigScore, matchup, countdown, season, record
    var id: String { rawValue }

    var kind: TeamPostFacts.Kind {
        switch self {
        case .scoreBar, .bigScore: .final
        case .matchup, .countdown: .gameDay
        case .season, .record: .season
        }
    }

    static func of(_ kind: TeamPostFacts.Kind) -> [TeamPostTemplate] { allCases.filter { $0.kind == kind } }

    func title(chinese: Bool) -> String {
        switch self {
        case .scoreBar: chinese ? "比分条" : "Score bar"
        case .bigScore: chinese ? "大比分" : "Big score"
        case .matchup: chinese ? "对阵" : "Matchup"
        case .countdown: chinese ? "开赛时间" : "Tip-off"
        case .season: chinese ? "赛季拼贴" : "Season collage"
        case .record: chinese ? "战绩" : "Record"
        }
    }

    var symbol: String {
        switch self {
        case .scoreBar: "rectangle.bottomthird.inset.filled"
        case .bigScore: "textformat.123"
        case .matchup: "person.2.fill"
        case .countdown: "clock"
        case .season: "rectangle.stack"
        case .record: "chart.bar.fill"
        }
    }

    /// Wants the players lifted out of the photo.
    var liftsSubject: Bool { self == .matchup || self == .countdown }
}

struct TeamPostCanvas: View {
    let template: TeamPostTemplate
    let facts: TeamPostFacts
    /// The photo, or nil (the team's colour stands in).
    let photo: UIImage?
    /// More photos from the team's media (the collage).
    var more: [UIImage] = []
    var cutout: UIImage?
    let aspect: AthletePostAspect

    var body: some View {
        let size = aspect.size
        Group {
            switch template {
            case .scoreBar: ScoreBarPost(f: facts, photo: photo, size: size)
            case .bigScore: BigScorePost(f: facts, photo: photo, size: size)
            case .matchup: MatchupPost(f: facts, photo: photo, cutout: cutout, size: size, tipOff: false)
            case .countdown: MatchupPost(f: facts, photo: photo, cutout: cutout, size: size, tipOff: true)
            case .season: SeasonCollagePost(f: facts, photos: ([photo].compactMap { $0 } + more), size: size)
            case .record: RecordPost(f: facts, photo: photo, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

private extension TeamPostFacts {
    var color: Color { Color(hex: colorHex) }
    func day(_ format: String) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        f.dateFormat = format
        return f.string(from: date)
    }
    var finalWord: String { isFinal ? (chinese ? "终场" : "FINAL") : (chinese ? "比赛中" : "LIVE") }
}

/// The photo, or the team colour with a soft court of light when there is none.
private struct TeamPhoto: View {
    let photo: UIImage?
    let color: Color
    var body: some View {
        if let photo {
            PostPhotoFill(photo: photo)
        } else {
            LinearGradient(colors: [color, color.mix(with: .black, by: 0.6)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// A round badge: the colour and the letters.
private struct PostTeamBadge: View {
    let letters: String
    let color: Color
    let side: CGFloat
    var body: some View {
        Circle().fill(color)
            .overlay(Circle().strokeBorder(.white, lineWidth: side * 0.05))
            .overlay {
                Text(letters).font(postHeavy(side * 0.42)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.4).padding(side * 0.14)
            }
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

// MARK: - Final score

/// The game photo full bleed, a score bar across the foot: badge · ours ·
/// FINAL · theirs · badge.
private struct ScoreBarPost: View {
    let f: TeamPostFacts
    let photo: UIImage?
    let size: CGSize
    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .bottom) {
            TeamPhoto(photo: photo, color: f.color)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .init(x: 0.5, y: 0.5), endPoint: .bottom)
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [f.color.mix(with: .black, by: 0.15), f.color.mix(with: .black, by: 0.55)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.78, height: h * 0.12)
                    HStack(spacing: 0) {
                        Text("\(f.ours)").font(postHeavy(h * 0.11)).frame(maxWidth: .infinity)
                        Text(f.finalWord).font(postHeavy(h * 0.045)).tracking(2).opacity(0.9)
                        Text("\(f.theirs)").font(postHeavy(h * 0.11)).frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.white)
                    .frame(width: w * 0.56)
                    HStack {
                        PostTeamBadge(letters: f.shortName, color: f.color, side: h * 0.115)
                        Spacer()
                        PostTeamBadge(letters: TeamPostFacts.initials(f.opponent), color: Color(white: 0.22), side: h * 0.115)
                    }
                    .frame(width: w * 0.9)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(f.teamName.uppercased()).font(.system(size: 30, weight: .black)).tracking(2)
                        Text((f.isHome ? "vs " : "@ ") + f.opponent + " · " + f.day(f.chinese ? "M月d日" : "d MMM"))
                            .font(.system(size: 24, weight: .semibold)).opacity(0.85)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(f.won ? (f.chinese ? "胜利" : "WIN") : (f.tied ? (f.chinese ? "平局" : "TIE") : (f.chinese ? "终场比分" : "FINAL SCORE")))
                            .font(.system(size: 40, weight: .black, design: .default).width(.condensed)).tracking(1)
                        Text(f.academy.uppercased()).font(.system(size: 20, weight: .bold)).tracking(2).opacity(0.8)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 56)
            }
            .padding(.bottom, h * 0.05)
        }
    }
}

/// The photo in black and white, the result huge over it in the team colour.
private struct BigScorePost: View {
    let f: TeamPostFacts
    let photo: UIImage?
    let size: CGSize
    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            TeamPhoto(photo: photo, color: f.color).grayscale(1).contrast(1.2)
            LinearGradient(colors: [f.color.opacity(0.15), f.color.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                Text(f.day(f.chinese ? "M月d日" : "d MMM").uppercased() + " · " + f.finalWord)
                    .font(.system(size: 28, weight: .heavy)).tracking(3)
                Spacer()
                Text(f.won ? (f.chinese ? "胜" : "W") : (f.tied ? (f.chinese ? "平" : "T") : (f.chinese ? "负" : "L")))
                    .font(postHeavy(h * 0.2)).opacity(0.35)
                    .padding(.bottom, -h * 0.07)
                Text("\(f.ours)–\(f.theirs)")
                    .font(postHeavy(h * 0.27)).lineLimit(1).minimumScaleFactor(0.4)
                Text(f.teamName.uppercased() + "  " + (f.isHome ? "VS" : "@") + "  " + f.opponent.uppercased())
                    .font(.system(size: 34, weight: .black)).tracking(2).lineLimit(1).minimumScaleFactor(0.5)
                Rectangle().fill(.white).frame(width: w * 0.2, height: 6).padding(.vertical, 22)
                Text(f.academy.uppercased()).font(.system(size: 22, weight: .bold)).tracking(3).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(60)
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }
}

// MARK: - Game day

/// The team's name huge across the top, the players lifted out in the middle
/// on a burst, "AT" / "VS" and the time, the opponent huge across the foot.
private struct MatchupPost: View {
    let f: TeamPostFacts
    let photo: UIImage?
    let cutout: UIImage?
    let size: CGSize
    let tipOff: Bool
    var body: some View {
        let w = size.width, h = size.height
        let square = h < w * 1.1
        let paper = Color(white: 0.93)
        ZStack(alignment: .top) {
            f.color
            PostHalftone(color: .black.opacity(0.18))
            if let cutout {
                // A burst behind the players.
                Star(points: 8, inner: 0.55)
                    .stroke(.white.opacity(0.55), lineWidth: 5)
                    .frame(width: w * 0.62, height: w * 0.62)
                    .offset(y: h * 0.27)
                Image(uiImage: cutout).resizable().scaledToFit()
                    .frame(width: w * 0.86, height: h * (square ? 0.56 : 0.58), alignment: .bottom)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .offset(y: h * 0.17)
            } else if let photo {
                PostPhotoFill(photo: photo)
                    .frame(width: w * 0.66, height: h * (square ? 0.44 : 0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(paper, lineWidth: 10))
                    .rotationEffect(.degrees(-2))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .offset(y: h * (square ? 0.25 : 0.24))
            }
            VStack(spacing: 0) {
                Text(f.teamName.uppercased())
                    .font(postHeavy(h * (square ? 0.17 : 0.16))).foregroundStyle(paper)
                    .lineLimit(1).minimumScaleFactor(0.25)
                    .padding(.horizontal, 24)
                if tipOff {
                    Text(f.day(f.chinese ? "M月d日 EEEE" : "EEEE d MMM").uppercased())
                        .font(.system(size: 30, weight: .heavy)).tracking(3).foregroundStyle(.white)
                } else if !f.venue.isEmpty {
                    Text(f.venue.uppercased())
                        .font(.system(size: 28, weight: .heavy)).tracking(3).foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 40)
                }
                Spacer()
                HStack(alignment: .lastTextBaseline) {
                    Text(f.versusWord).font(.system(size: tipOff ? 40 : 46, weight: .black).width(.condensed))
                    Spacer()
                    Text(f.day("HH:mm")).font(.system(size: tipOff ? 96 : 46, weight: .black).width(.condensed))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 90)
                Text(f.opponent.uppercased())
                    .font(postHeavy(h * (square ? 0.17 : 0.16))).foregroundStyle(paper)
                    .lineLimit(1).minimumScaleFactor(0.25)
                    .padding(.horizontal, 24)
                Text(f.academy.uppercased())
                    .font(.system(size: 20, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 26)
            }
            .padding(.top, 18)
            .frame(width: w, height: h)
        }
    }
}

/// An n-pointed star (the burst).
private struct Star: Shape {
    let points: Int
    let inner: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<(points * 2) {
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : r * inner
            let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Season

/// Cream paper, the team's name in a script over a row of words, photos in
/// black and white bands staggered down the page, the record in the middle.
private struct SeasonCollagePost: View {
    let f: TeamPostFacts
    let photos: [UIImage]
    let size: CGSize
    var body: some View {
        let w = size.width, h = size.height
        let square = h < w * 1.1
        let cream = Color(red: 0.95, green: 0.92, blue: 0.85)
        let ink = f.color.mix(with: .black, by: 0.35)
        let bands = square ? 2 : 3
        let bandH = h * (square ? 0.22 : 0.195)
        ZStack(alignment: .top) {
            cream
            VStack(spacing: 10) {
                Text(range).font(.system(size: 34, weight: .bold, design: .serif)).foregroundStyle(ink)
                Text(f.teamName)
                    .font(.system(size: h * 0.09, weight: .black, design: .serif).italic())
                    .foregroundStyle(f.color)
                    .shadow(color: ink, radius: 0, x: 3, y: 3)
                    .lineLimit(1).minimumScaleFactor(0.3).padding(.horizontal, 40)
                HStack {
                    ForEach(words, id: \.self) { Text($0).frame(maxWidth: .infinity) }
                }
                .font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(ink)
                .padding(.horizontal, 90)
                VStack(spacing: 18) {
                    ForEach(0..<bands, id: \.self) { i in
                        Group {
                            if photos.isEmpty {
                                f.color.opacity(0.25)
                            } else {
                                PostPhotoFill(photo: photos[i % photos.count]).grayscale(1).contrast(1.15)
                            }
                        }
                        .frame(width: w * (i == 1 ? 0.86 : 0.7), height: bandH)
                        .clipped()
                        .shadow(color: .black.opacity(0.3), radius: 10, x: 6, y: 6)
                        .offset(x: [-w * 0.04, 0, w * 0.05][i % 3])
                    }
                }
                .padding(.top, 16)
                .overlay {
                    VStack(spacing: 0) {
                        Text(f.record).font(postHeavy(h * 0.15)).foregroundStyle(.white)
                        Text(f.chinese ? "胜 – 负" : "WIN – LOSS").font(.system(size: 24, weight: .heavy)).tracking(4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 40).padding(.vertical, 14)
                    .background(f.color.opacity(0.92))
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
                }
                HStack {
                    Text(f.academy.uppercased()).lineLimit(1).minimumScaleFactor(0.5)
                    Rectangle().fill(ink).frame(height: 2)
                    Text(stats).lineLimit(1).fixedSize()
                }
                .font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(ink)
                .padding(.horizontal, 90).padding(.top, 18)
            }
            .padding(.top, h * 0.05)
        }
    }

    private var range: String {
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: f.chinese ? "zh_CN" : "en_US")
        f2.dateFormat = f.chinese ? "yyyy年M月" : "MMM yyyy"
        guard let a = f.firstDate, let b = f.lastDate else { return "" }
        let x = f2.string(from: a), y = f2.string(from: b)
        return x == y ? x : "\(x) – \(y)"
    }
    private var words: [String] {
        f.chinese ? ["我们的", "赛季", "一场", "一场", "打出来"] : ["THE", "SEASON", "SO", "FAR"]
    }
    private var stats: String {
        f.chinese ? String(format: "场均得分 %.1f · 失分 %.1f", f.pointsFor, f.pointsAgainst)
                  : String(format: "%.1f PTS FOR · %.1f AGAINST", f.pointsFor, f.pointsAgainst)
    }
}

/// The record huge, the last results as W/L tiles, points for and against.
private struct RecordPost: View {
    let f: TeamPostFacts
    let photo: UIImage?
    let size: CGSize
    var body: some View {
        let w = size.width, h = size.height
        ZStack(alignment: .topLeading) {
            TeamPhoto(photo: photo, color: f.color)
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(f.color).frame(width: 18, height: h)
            VStack(alignment: .leading, spacing: 10) {
                Text(f.teamName.uppercased()).font(.system(size: 34, weight: .black)).tracking(3)
                Spacer()
                Text(f.chinese ? "赛季战绩" : "SEASON RECORD").font(.system(size: 28, weight: .heavy)).tracking(4).opacity(0.85)
                Text(f.record).font(postHeavy(h * 0.24)).lineLimit(1).minimumScaleFactor(0.4).padding(.vertical, -h * 0.03)
                HStack(spacing: 10) {
                    ForEach(Array(f.recent.enumerated()), id: \.offset) { _, r in
                        Text(f.chinese ? (r == "W" ? "胜" : r == "L" ? "负" : "平") : r)
                            .font(.system(size: 34, weight: .black))
                            .frame(width: 70, height: 70)
                            .background(RoundedRectangle(cornerRadius: 12).fill(r == "W" ? f.color : Color.white.opacity(0.18)))
                    }
                }
                HStack(spacing: 40) {
                    stat(String(format: "%.1f", f.pointsFor), f.chinese ? "场均得分" : "PTS FOR")
                    stat(String(format: "%.1f", f.pointsAgainst), f.chinese ? "场均失分" : "PTS AGAINST")
                    stat("\(f.games)", f.chinese ? "场比赛" : "GAMES")
                }
                .padding(.top, 20)
                Text(f.academy.uppercased()).font(.system(size: 20, weight: .bold)).tracking(3).opacity(0.75).padding(.top, 20)
            }
            .foregroundStyle(.white)
            .padding(.leading, 70).padding(.vertical, 60).padding(.trailing, 50)
            .frame(width: w, height: h, alignment: .topLeading)
        }
    }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(postHeavy(80))
            Text(label).font(.system(size: 20, weight: .heavy)).tracking(2).opacity(0.8)
        }
    }
}
