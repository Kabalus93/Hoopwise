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
    static let corner: CGFloat = 22
}

private struct AthleteCardWords {
    let zh = LocalizationManager.shared.currentLanguage == .chinese

    func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        f.dateFormat = zh ? "yyyy年M月" : "MMMM yyyy"
        return f.string(from: date)
    }
}

struct AthleteCardFront: View {
    let card: AthleteCardFacts
    private let w = AthleteCardWords()

    private var accent: Color { Color(hex: card.accentHex) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                CardCourtBackground(color: accent, style: .halfCourt)
                HStack(alignment: .top) {
                    Text((card.academy.isEmpty ? card.coach : card.academy).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    if let jersey = card.jersey {
                        Text("\(jersey)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                photo
                    .padding(.top, 62)
            }
            .frame(height: 300)
            .clipped()

            VStack(spacing: 6) {
                Text(card.name)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let second = card.secondName {
                    Text(second)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black.opacity(0.55))
                        .lineLimit(1)
                }
                if let program = card.program {
                    Text([program, card.ageGroup].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.12), in: Capsule())
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                monthStrip
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)
            .frame(maxHeight: .infinity)
            .background(Color.white)
        }
        .frame(width: AthleteCardLayout.size.width, height: AthleteCardLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous)
            .strokeBorder(accent, lineWidth: 5))
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var photo: some View {
        let size: CGFloat = 176
        Group {
            #if canImport(UIKit)
            if let data = card.photo, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                monogram
            }
            #else
            monogram
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 6))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var monogram: some View {
        ZStack {
            accent.opacity(0.85)
            Text(String(card.name.prefix(1)))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var monthStrip: some View {
        VStack(spacing: 8) {
            Text(w.month(card.month).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.black.opacity(0.45))
            HStack(spacing: 0) {
                figure(card.classesExpected > 0 ? "\(card.classesAttended)/\(card.classesExpected)" : "—",
                       w.zh ? "到课" : "Classes")
                Rectangle().fill(.black.opacity(0.1)).frame(width: 1, height: 34)
                figure("\(card.gamesThisMonth)", w.zh ? "比赛" : "Games")
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

struct AthleteCardBack: View {
    let card: AthleteCardFacts
    private let w = AthleteCardWords()

    private var accent: Color { Color(hex: card.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.name)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(w.month(card.month))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 4) {
                header(trainedTitle)
                if card.trained.isEmpty {
                    Text(w.zh ? "参加有计划的课程后，这里会显示练了什么。" : "Shows what classes worked on once they attend planned classes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .multilineTextAlignment(.center)
                } else {
                    AttributeOctagon(values: card.trained, tint: accent)
                        .frame(height: 186)
                        .frame(maxWidth: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                header(card.gamesPlayed > 0
                       ? (w.zh ? "场均 · \(card.gamesPlayed) 场比赛" : "Per game · \(card.gamesPlayed) game\(card.gamesPlayed == 1 ? "" : "s")")
                       : (w.zh ? "比赛" : "Games"))
                if card.gamesPlayed > 0 {
                    HStack(spacing: 0) {
                        stat(.points, w.zh ? "得分" : "PTS")
                        stat(.rebounds, w.zh ? "篮板" : "REB")
                        stat(.assists, w.zh ? "助攻" : "AST")
                        stat(.steals, w.zh ? "抢断" : "STL")
                        stat(.blocks, w.zh ? "盖帽" : "BLK")
                    }
                } else {
                    Text(w.zh ? "还没有比赛记录" : "No games recorded yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                }
            }

            if !card.coachLine.isEmpty {
                Text("“\(card.coachLine)”")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(.black.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer(minLength: 0)

            HStack {
                Text([w.zh ? "\(card.coach)教练" : "Coach \(card.coach)",
                      card.academy.isEmpty ? nil : card.academy].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                Spacer()
                Text("HoopWise")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.black.opacity(0.4))
        }
        .padding(20)
        .frame(width: AthleteCardLayout.size.width, height: AthleteCardLayout.size.height)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AthleteCardLayout.corner, style: .continuous)
            .strokeBorder(accent, lineWidth: 5))
        .environment(\.colorScheme, .light)
    }

    private var trainedTitle: String {
        switch card.trainedScope {
        case .month: w.zh ? "本月训练内容 · \(card.trainedClasses) 节课" : "What we worked on · \(card.trainedClasses) class\(card.trainedClasses == 1 ? "" : "es")"
        case .allTime: w.zh ? "训练内容 · 全部课程" : "What we worked on · all classes"
        case .none: w.zh ? "训练内容" : "What we worked on"
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(.black.opacity(0.5))
    }

    private func stat(_ metric: GameStatsReport.Metric, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", card.perGame[metric] ?? 0))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black.opacity(0.5))
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

    /// Fronts on one page, backs on the next, mirrored left to right so each
    /// back lands on its front when printed double-sided (long-edge flip).
    /// Crop marks at every card edge.
    static func printSheet(_ cards: [AthleteCardFacts]) -> Data? {
        guard !cards.isEmpty else { return nil }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let printScale = printSize.width / AthleteCardLayout.size.width
        return renderer.pdfData { context in
            for start in stride(from: 0, to: cards.count, by: perPage) {
                let batch = Array(cards[start..<min(start + perPage, cards.count)])
                for back in [false, true] {
                    context.beginPage()
                    for (i, card) in batch.enumerated() {
                        let row = i / columns, col = i % columns
                        let placed = back ? columns - 1 - col : col
                        let frame = CGRect(x: margin + CGFloat(placed) * (printSize.width + gutter),
                                           y: margin + CGFloat(row) * (printSize.height + gutter),
                                           width: printSize.width, height: printSize.height)
                        let side: AnyView = back ? AnyView(AthleteCardBack(card: card)) : AnyView(AthleteCardFront(card: card))
                        // 4× the print size: about 290 dpi on paper.
                        image(side, scale: 4 * printScale)?.draw(in: frame)
                        cropMarks(around: frame, in: context.cgContext)
                    }
                }
            }
        }
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
