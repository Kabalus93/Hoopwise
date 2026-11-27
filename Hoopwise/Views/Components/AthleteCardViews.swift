import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The athlete card's two sides (Services/AthleteCardFacts.swift has the facts).
// A collectible: 5 : 7, the size of a trading card when printed, always in
// light colours (it is printed and shared, whatever the phone's theme). The
// front is who they are and their month; the back is what their classes
// trained, their games and a word from the coach.

enum AthleteCardLayout {
    /// The card in points (5 : 7). Printed at 2.5 × 3.5 inches.
    static let size = CGSize(width: 360, height: 504)
    static let corner: CGFloat = 14
}

private struct AthleteCardWords {
    let zh = AreaLanguage.isChinese(.playerCard)

    func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        f.dateFormat = zh ? "yyyy年M月" : "MMMM yyyy"
        return f.string(from: date)
    }
}

/// The original card's colours (17 Nov 2026, Luther: "make improvements
/// based on the card I had originally"): cream stock, a saddle-brown frame,
/// the name in capitals over the court, the photo overlapping the header, a
/// diamond, the member-since pill and the six-cell stats grid.
private enum AthleteCardStyle {
    static let stock = AppTheme.cream
    static let frame = AppTheme.saddleBrown
    static let label = AppTheme.neutral600
    static let rule = Color.gray.opacity(0.3)
    static let frameWidth: CGFloat = 5
}

struct AthleteCardFront: View {
    static let headerHeight: CGFloat = 206
    let card: AthleteCardFacts
    private let w = AthleteCardWords()

    private var accent: Color { Color(hex: card.accentHex) }
    /// The gradient's outer colour: the photo's background, else the program's.
    private var headerColor: Color { Color(hex: card.photoBackgroundHex ?? card.accentHex) }
    /// A pale background (white, cream, light grey swatches) takes dark type.
    private var headerIsLight: Bool { AthleteCardFacts.luminance(ofHex: card.photoBackgroundHex ?? card.accentHex) > 0.72 }
    private var headerInk: Color { headerIsLight ? Color.black.opacity(0.8) : .white }

    var body: some View {
        VStack(spacing: 0) {
            header
            middle
            monthPill
            statsGrid
        }
        .frame(width: AthleteCardLayout.size.width, height: AthleteCardLayout.size.height, alignment: .top)
        .background(AthleteCardStyle.stock)
        .clipShape(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous)
            .strokeBorder(AthleteCardStyle.frame, lineWidth: AthleteCardStyle.frameWidth))
        .environment(\.colorScheme, .light)
    }

    // The court in the program's colour, the name over it, the number.
    private var header: some View {
        ZStack(alignment: .top) {
            // A radial gradient from the photo (17 Nov 2026, Luther): clear
            // at the photo, the PHOTO'S OWN BACKGROUND colour at the edges
            // (else the program's), the court over it.
            // The photo's centre sits on the header's bottom edge, mid-width;
            // the gradient reaches the far corners.
            RadialGradient(stops: [.init(color: headerColor.opacity(0), location: 0),
                                   .init(color: headerColor.opacity(0), location: 0.2),
                                   .init(color: headerColor, location: 1)],
                           center: UnitPoint(x: 0.5, y: 1), startRadius: 0,
                           endRadius: (pow(AthleteCardLayout.size.width / 2, 2) + pow(Self.headerHeight, 2)).squareRoot())
            CourtArtwork(style: .halfCourt)
            // A light shade under the name so white type reads (none behind
            // dark type on a pale background).
            if !headerIsLight {
                LinearGradient(colors: [.black.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
            }
            VStack(spacing: 4) {
                Text(card.name.uppercased())
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(headerInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let second = card.secondName {
                    Text(second)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(headerInk.opacity(0.88))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 66)
            .padding(.top, 34)
            if let jersey = card.jersey {
                Text("\(jersey)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(headerInk)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(headerInk, lineWidth: 2))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 18)
                    .padding(.top, 18)
            }
        }
        .frame(height: Self.headerHeight)
        .clipped()
    }

    // The diamond | the photo over the header's edge | age, grade, height.
    private var middle: some View {
        ZStack(alignment: .top) {
            photo.offset(y: -58)
            HStack(alignment: .center, spacing: 0) {
                diamond
                    .frame(width: 96, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    // In Chinese the grade names itself ("二年级"), so no label.
                    if let grade = card.schoolGrade { factRow(w.zh ? "" : "GRADE", grade) }
                }
                .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 82)
    }

    @ViewBuilder
    private var diamond: some View {
        if let badge = card.ageBadge {
            ZStack {
                Rectangle()
                    .fill(.white)
                    .frame(width: 50, height: 50)
                    .overlay(Rectangle().stroke(AthleteCardStyle.rule, lineWidth: 1))
                    .rotationEffect(.degrees(45))
                Text(badge)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 72, height: 72)
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AthleteCardStyle.label)
            }
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(minWidth: 30, alignment: .leading)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var photo: some View {
        let size: CGFloat = 116
        Group {
            #if canImport(UIKit)
            if let data = card.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
                    .background(card.backdropHex.map { Color(hex: $0) } ?? .clear)
            } else {
                monogram
            }
            #else
            monogram
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(AthleteCardStyle.frame, lineWidth: 3))
        .background(Circle().fill(.white).frame(width: size + 8, height: size + 8))
    }

    private var monogram: some View {
        ZStack {
            accent.opacity(0.85)
            Text(String(card.name.prefix(1)))
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    /// The card's month (17 Nov 2026, Luther: the month, not "SINCE 2026").
    private var monthPill: some View {
        Text(w.month(card.month).uppercased())
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Capsule().fill(accent))
            .frame(height: 44)
    }

    // PPG APG RPG / STL BLK GAMES — averages over every game.
    private var statsGrid: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AthleteCardStyle.rule).frame(height: 1)
            HStack(spacing: 0) {
                statCell(average(.points), w.zh ? "得分" : "PPG")
                divider
                statCell(average(.assists), w.zh ? "助攻" : "APG")
                divider
                statCell(average(.rebounds), w.zh ? "篮板" : "RPG")
            }
            Rectangle().fill(AthleteCardStyle.rule).frame(height: 1)
            HStack(spacing: 0) {
                statCell(average(.steals), w.zh ? "抢断" : "STL")
                divider
                statCell(average(.blocks), w.zh ? "盖帽" : "BLK")
                divider
                statCell("\(card.gamesPlayed)", w.zh ? "比赛" : "GAMES")
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, AthleteCardStyle.frameWidth)
    }

    private var divider: some View {
        Rectangle().fill(AthleteCardStyle.rule).frame(width: 1)
    }

    private func average(_ metric: GameStatsReport.Metric) -> String {
        guard card.gamesPlayed > 0, let value = card.perGame[metric] else { return "—" }
        return String(format: "%.1f", value)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AthleteCardStyle.label)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AthleteCardBack: View {
    let card: AthleteCardFacts
    private let w = AthleteCardWords()

    private var accent: Color { Color(hex: card.accentHex) }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(w.month(card.month).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(AthleteCardStyle.label)
                Text(card.name)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // THE ATHLETE AGAINST THE GROUP (27 Nov 2026, Luther's markup:
            // "make this a comparison against other players in the group —
            // dots is the group and blue is the athlete"). Once the athlete
            // is rated the octagon is their ratings (the filled shape) over
            // the group's average (the dashed line). It was what the classes
            // worked on with the athlete's ratings dashed over it; an athlete
            // who is not rated yet still gets what their classes worked on.
            VStack(spacing: 2) {
                if !card.evaluation.isEmpty {
                    sectionHeader(w.zh ? "技能" : "Skills")
                    AttributeOctagon(values: card.evaluation, tint: accent,
                                     standing: card.groupEvaluation.isEmpty ? nil : card.groupEvaluation,
                                     standingColor: Color.black.opacity(0.75),
                                     chineseLabels: w.zh)
                        .frame(height: card.groupEvaluation.isEmpty ? 178 : 160)
                        .frame(maxWidth: .infinity)
                    if !card.groupEvaluation.isEmpty {
                        HStack(spacing: 14) {
                            legendItem(swatch: AnyView(RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.35))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(accent, lineWidth: 1.2))),
                                       card.name)
                            legendItem(swatch: AnyView(Capsule().stroke(Color.black.opacity(0.75),
                                style: StrokeStyle(lineWidth: 1.6, dash: [4, 2])).frame(height: 2)),
                                       w.zh ? "本组平均" : "Group average")
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    sectionHeader(w.zh ? "训练内容" : "What we worked on")
                    if card.trained.isEmpty {
                        Text(w.zh ? "参加有计划的课程后，这里会显示练了什么。" : "Shows what classes worked on once they attend planned classes.")
                            .font(.system(size: 12))
                            .foregroundStyle(AthleteCardStyle.label)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        AttributeOctagon(values: card.trained, tint: accent, chineseLabels: w.zh)
                            .frame(height: 178)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            VStack(spacing: 6) {
                sectionHeader(w.zh ? "本月" : "This month")
                HStack(spacing: 0) {
                    figure(card.classesExpected > 0 ? "\(card.classesAttended)/\(card.classesExpected)" : "—",
                           w.zh ? "到课" : "CLASSES")
                    Rectangle().fill(AthleteCardStyle.rule).frame(width: 1, height: 34)
                    figure("\(card.gamesThisMonth)", w.zh ? "比赛" : "GAMES")
                }
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !card.coachLine.isEmpty {
                Text("“\(card.coachLine)”")
                    .font(.system(size: 13, weight: .medium))
                    .italic()
                    .foregroundStyle(.black.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer(minLength: 0)

            // The academy alone (17 Nov 2026, Luther: no coach name, no
            // HoopWise credit).
            if !card.academy.isEmpty {
                Text(card.academy)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AthleteCardStyle.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: AthleteCardLayout.size.width, height: AthleteCardLayout.size.height)
        .background(AthleteCardStyle.stock)
        .clipShape(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous)
            .strokeBorder(AthleteCardStyle.frame, lineWidth: AthleteCardStyle.frameWidth))
        .environment(\.colorScheme, .light)
    }

    private func legendItem(swatch: AnyView, _ label: String) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 14, height: 9)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AthleteCardStyle.label)
                .lineLimit(1)
        }
    }

    /// A centred caps header (no icon).
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(AthleteCardStyle.label)
            .frame(maxWidth: .infinity)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AthleteCardStyle.label)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Front and back side by side: the image shared on WeChat.
struct AthleteCardSpread: View {
    let card: AthleteCardFacts
    static let gap: CGFloat = 24

    var body: some View {
        HStack(spacing: Self.gap) {
            AthleteCardFront(card: card)
            AthleteCardBack(card: card)
        }
        .padding(Self.gap)
        .background(Color(red: 0.94, green: 0.94, blue: 0.95))
        .environment(\.colorScheme, .light)
    }
}

/// The card IN the app (the quick peep): the very two sides that are shared
/// and printed, tap to flip (17 Nov 2026, Luther: "make the in app card match
/// what is going to be exported"). Scaled down when the space is narrower
/// than the card.
struct AthleteCardFlip: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student

    @State private var flipped = false
    @State private var degrees = 0.0
    @State private var available: CGFloat = AthleteCardLayout.size.width

    var body: some View {
        let card = dataManager.athleteCard(for: student)
        let scale = min(1, available / AthleteCardLayout.size.width)
        ZStack {
            AthleteCardFront(card: card)
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(degrees), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            AthleteCardBack(card: card)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(degrees + 180), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        // The flip's animation is set HERE, on the card, keyed to the turn —
        // not by withAnimation at the tap. The Quick Peep's stage strips
        // animations from everything inside it (so a drag never animates the
        // page's layout), and that took the flip with it (25 Nov 2026).
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: degrees)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .scaleEffect(scale)
        .frame(width: AthleteCardLayout.size.width * scale, height: AthleteCardLayout.size.height * scale)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = max(120, $0) }
        .contentShape(Rectangle())
        .onTapGesture {
            flipped.toggle()
            degrees += 180
        }
        .accessibilityElement()
        .accessibilityLabel(LocalizationManager.shared.currentLanguage == .chinese ? "球员卡，轻点翻面" : "Player card, tap to flip")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("athleteCard.flip")
    }
}

#if canImport(UIKit)
/// Renders the card for sharing and printing, through SwiftUI's ImageRenderer
/// (the old exporter hosted the interactive card in an off-screen controller).
@MainActor
enum AthleteCardRenderer {
    static func image<V: View>(_ view: V, scale: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// The WeChat image: front and back side by side.
    static func shareImage(_ card: AthleteCardFacts, scale: CGFloat = 3) -> UIImage? {
        image(AthleteCardSpread(card: card), scale: scale)
    }

    // MARK: A3 print sheets

    /// A3 landscape in points.
    static let pageSize = CGSize(width: 1190.55, height: 841.89)
    /// 2.5 × 3.5 inches.
    static let printSize = CGSize(width: 180, height: 252)
    static let margin: CGFloat = 36
    static let gutter: CGFloat = 14

    static var columns: Int { Int((pageSize.width - 2 * margin + gutter) / (printSize.width + gutter)) }
    static var rows: Int { Int((pageSize.height - 2 * margin + gutter) / (printSize.height + gutter)) }
    static var perPage: Int { columns * rows }

    /// The grid is CENTRED on the page (27 Nov 2026, Luther: the printed
    /// backs sat "on the opposite end of the back page, making it impossible
    /// to cut the cards"). It used to start at the left and top margins with
    /// the spare 57 mm on the right and 89 mm at the bottom, so a sheet turned
    /// over put every back that far from its front. Centred, the card places
    /// are the same on both sides whichever way the sheet is turned.
    static var gridOrigin: CGPoint {
        let width = CGFloat(columns) * printSize.width + CGFloat(columns - 1) * gutter
        let height = CGFloat(rows) * printSize.height + CGFloat(rows - 1) * gutter
        return CGPoint(x: (pageSize.width - width) / 2, y: (pageSize.height - height) / 2)
    }

    /// Where card `index` of a page goes, front or back. The back takes the
    /// place that lies BEHIND its front once the sheet is turned: across the
    /// short edge the columns swap (the back stays upright); across the long
    /// edge the rows swap and the back is printed head down, so that the cut
    /// card still turns over like a page.
    static func frame(index: Int, back: Bool, flip: CardPrint.Flip) -> CGRect {
        var row = index / columns, col = index % columns
        if back {
            switch flip {
            case .shortEdge: col = columns - 1 - col
            case .longEdge: row = rows - 1 - row
            }
        }
        return CGRect(x: gridOrigin.x + CGFloat(col) * (printSize.width + gutter),
                      y: gridOrigin.y + CGFloat(row) * (printSize.height + gutter),
                      width: printSize.width, height: printSize.height)
    }

    /// Fronts on one page, backs on the next, each back behind its front
    /// when printed double-sided the way `flip` says. Crop marks at every
    /// card edge; in the page's spare top and bottom: which side it is, how
    /// to print it, a cross to check the two sides against the light, and a
    /// grey and colour bar for the print shop.
    static func printSheet(_ cards: [AthleteCardFacts], flip: CardPrint.Flip = CardPrint.flip,
                           lighten: CardPrint.Lighten = CardPrint.lighten,
                           chinese: Bool = AreaLanguage.isChinese(.playerCard)) -> Data? {
        guard !cards.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let printScale = printSize.width / AthleteCardLayout.size.width
        let sheets = (cards.count + perPage - 1) / perPage
        return renderer.pdfData { context in
            for start in stride(from: 0, to: cards.count, by: perPage) {
                let batch = Array(cards[start..<min(start + perPage, cards.count)])
                for back in [false, true] {
                    context.beginPage()
                    let cg = context.cgContext
                    for (i, card) in batch.enumerated() {
                        let frame = frame(index: i, back: back, flip: flip)
                        let side: AnyView = back ? AnyView(AthleteCardBack(card: card)) : AnyView(AthleteCardFront(card: card))
                        // 4× the print size: about 290 dpi on paper.
                        if let picture = image(side, scale: 4 * printScale).map({ lighten.applied(to: $0) }) {
                            if back, flip == .longEdge {
                                cg.saveGState()
                                cg.translateBy(x: frame.midX, y: frame.midY)
                                cg.rotate(by: .pi)
                                picture.draw(in: CGRect(x: -frame.width / 2, y: -frame.height / 2,
                                                        width: frame.width, height: frame.height))
                                cg.restoreGState()
                            } else {
                                picture.draw(in: frame)
                            }
                        }
                        cropMarks(around: frame, in: cg)
                    }
                    pageFurniture(in: cg, back: back, sheet: start / perPage + 1, of: sheets, flip: flip, chinese: chinese)
                }
            }
        }
    }

    /// The words and marks outside the cards.
    private static func pageFurniture(in cg: CGContext, back: Bool, sheet: Int, of sheets: Int,
                                      flip: CardPrint.Flip, chinese zh: Bool) {
        let grey = UIColor(white: 0.35, alpha: 1)
        let side = back ? (zh ? "背面" : "BACK") : (zh ? "正面" : "FRONT")
        let title = zh ? "\(side) · 第 \(sheet)/\(sheets) 张 · HoopWise 球员卡"
                       : "\(side) · sheet \(sheet) of \(sheets) · HoopWise player cards"
        (title as NSString).draw(at: CGPoint(x: gridOrigin.x, y: 34),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: grey])
        let how = CardPrint.oneLine(flip: flip, chinese: zh)
        (how as NSString).draw(at: CGPoint(x: gridOrigin.x, y: 50),
                               withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: grey])

        // The same cross at the page's centre on both sides: held to the
        // light, the two must sit on each other.
        let centre = CGPoint(x: pageSize.width / 2, y: gridOrigin.y / 2 + 22)
        cg.saveGState()
        cg.setStrokeColor(grey.cgColor)
        cg.setLineWidth(0.5)
        cg.move(to: CGPoint(x: centre.x - 9, y: centre.y)); cg.addLine(to: CGPoint(x: centre.x + 9, y: centre.y))
        cg.move(to: CGPoint(x: centre.x, y: centre.y - 9)); cg.addLine(to: CGPoint(x: centre.x, y: centre.y + 9))
        cg.strokePath()
        cg.strokeEllipse(in: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10))
        let mirrored = CGPoint(x: centre.x, y: pageSize.height - centre.y)
        cg.move(to: CGPoint(x: mirrored.x - 9, y: mirrored.y)); cg.addLine(to: CGPoint(x: mirrored.x + 9, y: mirrored.y))
        cg.move(to: CGPoint(x: mirrored.x, y: mirrored.y - 9)); cg.addLine(to: CGPoint(x: mirrored.x, y: mirrored.y + 9))
        cg.strokePath()
        cg.strokeEllipse(in: CGRect(x: mirrored.x - 5, y: mirrored.y - 5, width: 10, height: 10))
        cg.restoreGState()

        // The print shop's check, on the front only: eleven greys from white
        // to black (each step must be told from the next) and six colours.
        guard !back else { return }
        let patch: CGFloat = 18, y = pageSize.height - 58
        var x = gridOrigin.x
        for step in 0...10 {
            cg.setFillColor(UIColor(white: 1 - CGFloat(step) / 10, alpha: 1).cgColor)
            cg.fill(CGRect(x: x, y: y, width: patch, height: patch))
            x += patch
        }
        cg.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor)
        cg.setLineWidth(0.4)
        cg.stroke(CGRect(x: gridOrigin.x, y: y, width: patch * 11, height: patch))
        x += 12
        for colour in [UIColor.red, .green, .blue, .cyan, .magenta, .yellow] {
            cg.setFillColor(colour.cgColor)
            cg.fill(CGRect(x: x, y: y, width: patch, height: patch))
            x += patch
        }
        let check = zh ? "色彩检查：11 级灰阶应每一级都能分清（最深两级不应糊成一片）；文件为 sRGB。"
                       : "Colour check: all 11 greys should be told apart (the two darkest must not merge). The file is sRGB."
        (check as NSString).draw(at: CGPoint(x: x + 12, y: y + 4),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: grey])
    }

    private static func cropMarks(around frame: CGRect, in context: CGContext) {
        let length: CGFloat = 7, offset: CGFloat = 3
        context.saveGState()
        context.setStrokeColor(UIColor(white: 0.6, alpha: 1).cgColor)
        context.setLineWidth(0.4)
        for x in [frame.minX, frame.maxX] {
            context.move(to: CGPoint(x: x, y: frame.minY - offset - length)); context.addLine(to: CGPoint(x: x, y: frame.minY - offset))
            context.move(to: CGPoint(x: x, y: frame.maxY + offset)); context.addLine(to: CGPoint(x: x, y: frame.maxY + offset + length))
        }
        for y in [frame.minY, frame.maxY] {
            context.move(to: CGPoint(x: frame.minX - offset - length, y: y)); context.addLine(to: CGPoint(x: frame.minX - offset, y: y))
            context.move(to: CGPoint(x: frame.maxX + offset, y: y)); context.addLine(to: CGPoint(x: frame.maxX + offset + length, y: y))
        }
        context.strokePath()
        context.restoreGState()
    }
}
#endif

/// HOW THE A3 CARD SHEETS ARE PRINTED (27 Nov 2026, Luther: the backs came
/// out off their fronts and the colours "absolutely dark" — "add
/// instructions for printing quality and colour calibrating so this process
/// isn't a headache"). Two device settings and the words for the print shop.
enum CardPrint {
    /// Which way the print shop's machine turns the sheet over.
    enum Flip: String, CaseIterable, Identifiable {
        /// Across the short edge — the usual choice for a landscape sheet.
        case shortEdge
        case longEdge
        var id: String { rawValue }
        func title(chinese zh: Bool) -> String {
            switch self {
            case .shortEdge: zh ? "短边翻转" : "Short edge"
            case .longEdge: zh ? "长边翻转" : "Long edge"
            }
        }
    }

    /// Lifts the cards for a printer that prints dark.
    enum Lighten: String, CaseIterable, Identifiable {
        case off, some, more
        var id: String { rawValue }
        /// Gamma below 1 lifts the mid-tones and leaves black and white alone.
        var gamma: Double {
            switch self {
            case .off: 1
            case .some: 0.85
            case .more: 0.72
            }
        }
        func title(chinese zh: Bool) -> String {
            switch self {
            case .off: zh ? "不调整" : "As it is"
            case .some: zh ? "稍亮" : "A little lighter"
            case .more: zh ? "更亮" : "Lighter"
            }
        }
        #if canImport(UIKit)
        func applied(to image: UIImage) -> UIImage {
            guard self != .off, let input = CIImage(image: image),
                  let filter = CIFilter(name: "CIGammaAdjust") else { return image }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(gamma, forKey: "inputPower")
            guard let output = filter.outputImage,
                  let cg = CIContext().createCGImage(output, from: input.extent) else { return image }
            return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        }
        #endif
    }

    static var flip: Flip {
        get { Flip(rawValue: UserDefaults.standard.string(forKey: "cards.print.flip") ?? "") ?? .shortEdge }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cards.print.flip") }
    }
    static var lighten: Lighten {
        get { Lighten(rawValue: UserDefaults.standard.string(forKey: "cards.print.lighten") ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "cards.print.lighten") }
    }

    /// The line printed on every sheet.
    static func oneLine(flip: Flip, chinese zh: Bool) -> String {
        zh ? "A3 横向 · 实际大小 100%（不要“适合页面”）· 双面打印，\(flip.title(chinese: true)) · 250–300 克铜版纸或哑粉纸 · 先打一张对光检查十字"
           : "A3 landscape · actual size 100 % (no “fit to page”) · double-sided, flip on the \(flip.title(chinese: false).lowercased()) · 250–300 gsm coated or matte card · print one sheet first and check the crosses against the light"
    }

    /// The full instructions, to read in the app and to send with the file.
    static func instructions(flip: Flip, chinese zh: Bool) -> [String] {
        zh ? [
            "纸张：A3，横向。250–300 克铜版纸或哑粉纸（普通 80 克纸会透、会软）。",
            "大小：实际大小 / 100%。不要选“适合页面”或“缩放以适合”——缩小后正反面和裁切线都会错位。",
            "双面：双面打印，\(flip.title(chinese: true))。如果打印店的机器只能另一种翻法，在这里改成另一种再导出。",
            "先打一张：对着光看，纸张上下两个十字的正反面应当重合；每张卡四角的裁切线也应正反对齐。对不上就不要整批打。",
            "颜色：文件是 sRGB。请用彩色、照片/图像模式打印，关闭“省墨”“鲜艳”“自动增强”。",
            "偏暗时：看正面底部的灰阶条——11 级应每级都能分清。最深的几级糊在一起，说明机器偏深：请店家调低浓度（密度），或在这里选“稍亮 / 更亮”重新导出。",
            "裁切：沿每张卡四角的短线裁。卡片是 63.5 × 88.9 毫米（标准球星卡大小）。",
        ] : [
            "Paper: A3, landscape. 250–300 gsm coated or matte card (plain 80 gsm paper shows through and goes limp).",
            "Size: actual size / 100 %. Never “fit to page” or “scale to fit” — a shrunk sheet puts the two sides and the crop marks out of line.",
            "Two sides: double-sided, flip on the \(flip.title(chinese: false).lowercased()). If the shop’s machine can only turn the other way, change it here and export again.",
            "One sheet first: hold it to the light. The two crosses at the top and bottom must sit on each other front and back, and so must the crop marks at each card’s corners. If they don’t, don’t print the batch.",
            "Colour: the file is sRGB. Print in colour, photo / image mode, with “toner save”, “vivid” and “auto enhance” off.",
            "If it comes out dark: look at the grey bar under the fronts — all 11 steps should be told apart. If the darkest ones merge, the machine prints heavy: ask the shop to lower the density, or choose “A little lighter / Lighter” here and export again.",
            "Cutting: cut along the short lines at each card’s corners. A card is 63.5 × 88.9 mm (2.5 × 3.5 in, the standard trading card).",
        ]
    }
}
