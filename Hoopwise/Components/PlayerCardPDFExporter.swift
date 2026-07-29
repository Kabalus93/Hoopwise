//
//  PlayerCardPDFExporter.swift
//  Hoopwise
//
//  Renders one or many player cards as a print-ready PDF.
//  Layout: NBA-collectible card size (2.5" × 3.5") on A3 landscape (16.54" × 11.69").
//  Two pages per batch — fronts on page N, backs on page N+1, mirrored horizontally
//  so duplex long-edge flip aligns each back with its front.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

@MainActor
struct PlayerCardPDFExporter {

    struct CardData {
        let student: Student
        let player: Player?
        let contract: Contract?
        let trainingStats: TrainingSessionStats?
        let monthlyStats: TrainingSessionStats?
        let programContext: ProgramStatsContext?
        let profileImage: UIImage?
        /// Pre-fetched header background. AsyncImage doesn't have time to
        /// resolve during a synchronous PDF snapshot, so the bg URL gets
        /// downloaded before rendering and the bytes ride along here.
        let headerBackgroundImage: UIImage?
    }

    // MARK: - Page geometry (points, 72 PPI)

    /// A3 landscape: 16.54" × 11.69"
    private static let pageSize = CGSize(width: 1190.55, height: 841.89)
    /// Card on the printed sheet — sized to match the in-app card's
    /// 380×540pt proportions (≈5:7 portrait) shrunk to fit a print-cuttable
    /// trading-card size. 180×256pt = 2.5″ × ~3.56″.
    private static let cardSize = CGSize(width: 180, height: 256)
    /// Outer margin (leaves room for crop marks)
    private static let pageMargin: CGFloat = 32
    /// Spacing between cards in the grid
    private static let gutter: CGFloat = 12
    /// Crop-mark length and color
    private static let cropMarkLength: CGFloat = 8
    private static let cropMarkColor = UIColor(white: 0.65, alpha: 1.0)

    private static var columns: Int {
        let usable = pageSize.width - 2 * pageMargin
        return Int((usable + gutter) / (cardSize.width + gutter))
    }
    private static var rows: Int {
        let usable = pageSize.height - 2 * pageMargin
        return Int((usable + gutter) / (cardSize.height + gutter))
    }
    /// Cards per page (front side); back side gets the same count, mirrored.
    static var cardsPerPage: Int { columns * rows }

    // MARK: - Public API

    /// Render a multi-card sheet (or several) for printing.
    /// The PDF interleaves [fronts page, backs page] so a duplex long-edge flip
    /// produces correctly-aligned trading cards on the printer.
    /// `dataManager` is required so the snapshot can render
    /// `StudentProfileCardView`'s back side, which depends on
    /// `dataManager` for category color, attendance, etc.
    static func generateSheetPDF(
        cards: [CardData],
        dataManager: DataManager
    ) -> Data? {
        guard !cards.isEmpty else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let perPage = cardsPerPage
        let pages = stride(from: 0, to: cards.count, by: perPage).map { startIdx -> [CardData] in
            let endIdx = min(startIdx + perPage, cards.count)
            return Array(cards[startIdx..<endIdx])
        }

        return renderer.pdfData { ctx in
            for batch in pages {
                // Front page
                ctx.beginPage()
                drawCropMarks(in: ctx.cgContext)
                drawCards(batch, side: .front, mirror: false, dataManager: dataManager)

                // Back page (mirrored horizontally for duplex long-edge flip)
                ctx.beginPage()
                drawCropMarks(in: ctx.cgContext)
                drawCards(batch, side: .back, mirror: true, dataManager: dataManager)
            }
        }
    }

    /// Single-card PDF (front on page 1, back on page 2) for per-player digital sharing.
    static func generateSingleCardPDF(
        card: CardData,
        dataManager: DataManager
    ) -> Data? {
        let cardBounds = CGRect(origin: .zero, size: cardSize)
        let renderer = UIGraphicsPDFRenderer(bounds: cardBounds)
        return renderer.pdfData { ctx in
            for side in [StudentCardSide.front, .back] {
                ctx.beginPage()
                if let image = renderCardImage(card, side: side, dataManager: dataManager) {
                    image.draw(in: cardBounds)
                }
            }
        }
    }

    // MARK: - Drawing helpers

    private static func drawCards(
        _ cards: [CardData],
        side: StudentCardSide,
        mirror: Bool,
        dataManager: DataManager
    ) {
        let cols = columns
        for (idx, card) in cards.enumerated() {
            let row = idx / cols
            let col = idx % cols
            let placedCol = mirror ? (cols - 1 - col) : col

            let x = pageMargin + CGFloat(placedCol) * (cardSize.width + gutter)
            let y = pageMargin + CGFloat(row) * (cardSize.height + gutter)
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: cardSize)

            if let image = renderCardImage(card, side: side, dataManager: dataManager) {
                image.draw(in: frame)
            }
        }
    }

    private static func renderCardImage(
        _ card: CardData,
        side: StudentCardSide,
        dataManager: DataManager
    ) -> UIImage? {
        StudentReportImageGenerator.generateImage(
            student: card.student,
            player: card.player,
            contract: card.contract,
            trainingStats: card.trainingStats,
            side: side,
            headerImage: card.headerBackgroundImage,
            profileImage: card.profileImage,
            dataManager: dataManager,
            scale: 3.0
        )
    }

    private static func drawCropMarks(in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(cropMarkColor.cgColor)
        ctx.setLineWidth(0.5)

        let cols = columns
        let rws = rows
        // Vertical column boundaries (between cards horizontally)
        for c in 0...cols {
            let x = pageMargin + CGFloat(c) * cardSize.width + CGFloat(max(c - 1, 0)) * gutter + (c == 0 ? 0 : gutter / 2 - cardSize.width)
            // simpler: recompute boundary x as midpoint between adjacent cards or page edge
            let boundaryX: CGFloat
            if c == 0 {
                boundaryX = pageMargin
            } else if c == cols {
                boundaryX = pageMargin + CGFloat(cols) * cardSize.width + CGFloat(cols - 1) * gutter
            } else {
                boundaryX = pageMargin + CGFloat(c) * cardSize.width + CGFloat(c - 1) * gutter + gutter / 2
            }
            _ = x
            // Top & bottom marks at this x
            ctx.move(to: CGPoint(x: boundaryX, y: pageMargin - cropMarkLength))
            ctx.addLine(to: CGPoint(x: boundaryX, y: pageMargin))
            ctx.move(to: CGPoint(x: boundaryX, y: pageSize.height - pageMargin))
            ctx.addLine(to: CGPoint(x: boundaryX, y: pageSize.height - pageMargin + cropMarkLength))
        }
        // Horizontal row boundaries (between cards vertically)
        for r in 0...rws {
            let boundaryY: CGFloat
            if r == 0 {
                boundaryY = pageMargin
            } else if r == rws {
                boundaryY = pageMargin + CGFloat(rws) * cardSize.height + CGFloat(rws - 1) * gutter
            } else {
                boundaryY = pageMargin + CGFloat(r) * cardSize.height + CGFloat(r - 1) * gutter + gutter / 2
            }
            ctx.move(to: CGPoint(x: pageMargin - cropMarkLength, y: boundaryY))
            ctx.addLine(to: CGPoint(x: pageMargin, y: boundaryY))
            ctx.move(to: CGPoint(x: pageSize.width - pageMargin, y: boundaryY))
            ctx.addLine(to: CGPoint(x: pageSize.width - pageMargin + cropMarkLength, y: boundaryY))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Convenience: build CardData[] for a session or program

    /// Compute the calendar-month range that includes `date` (used for radar overlay scope).
    static func currentMonthRange(containing date: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return start...end
    }

    /// Format the current month as a print label (e.g. "May 2026").
    static func monthLabel(for date: Date = Date(), chinese: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        formatter.dateFormat = chinese ? "yyyy年M月" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Build CardData for every enrolled student in a session.
    /// Profile images are read from `student.profileImageData`; the header
    /// background image is left nil here — call `prefetchHeaderImages(...)`
    /// before rendering for sharp print output.
    static func buildCards(
        for studentIds: [UUID],
        students: [Student],
        players: [Player],
        contracts: [Contract],
        sessions: [SessionEvent],
        profileImages: [UUID: UIImage] = [:]
    ) -> [CardData] {
        let monthRange = currentMonthRange()
        let allTrainingStats = studentIds.compactMap { id -> TrainingSessionStats? in
            let s = TrainingSessionStats.calculate(for: id, from: sessions)
            return s.hasStats ? s : nil
        }
        let programCtx = ProgramStatsContext.calculate(from: allTrainingStats)

        return studentIds.compactMap { id -> CardData? in
            guard let student = students.first(where: { $0.id == id }) else { return nil }
            let player = players.first(where: { $0.studentId == id })
            let contract = contracts.first(where: { $0.studentId == id })
            let lifetime = TrainingSessionStats.calculate(for: id, from: sessions)
            let monthly = TrainingSessionStats.calculate(for: id, from: sessions, in: monthRange)
            // Resolve the profile image: explicit override beats inline data.
            let profileImg: UIImage? = {
                if let pi = profileImages[id] { return pi }
                if let data = student.profileImageData { return UIImage(data: data) }
                return nil
            }()
            return CardData(
                student: student,
                player: player,
                contract: contract,
                trainingStats: lifetime,
                monthlyStats: monthly.hasStats ? monthly : nil,
                programContext: programCtx,
                profileImage: profileImg,
                headerBackgroundImage: nil
            )
        }
    }

    /// Concurrently fetches each card's basketball-header URL and returns
    /// a new `[CardData]` with `headerBackgroundImage` populated. Required
    /// for crisp PDFs — without this, the snapshot writer doesn't have
    /// time to wait for `AsyncImage`'s network round-trip and falls back
    /// to the placeholder gradient.
    ///
    /// Cached fetches (`ImageCacheManager`) keep this near-instant after
    /// the first call. Errors are swallowed; the corresponding card just
    /// renders the gradient fallback.
    static func prefetchHeaderImages(for cards: [CardData]) async -> [CardData] {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for card in cards {
                group.addTask {
                    let urlString = StudentProfileHeaderView.basketballURL(for: card.student.id)
                    // CacheImage is typealiased to UIImage on iOS / NSImage
                    // on macOS, so the result already matches the platform.
                    let cached = await ImageCacheManager.shared.loadImage(
                        for: "card-bg-\(card.student.id.uuidString)",
                        from: urlString
                    )
                    return (card.student.id, cached)
                }
            }
            var byId: [UUID: UIImage] = [:]
            for await (id, img) in group {
                if let img = img { byId[id] = img }
            }
            return cards.map { card in
                CardData(
                    student: card.student,
                    player: card.player,
                    contract: card.contract,
                    trainingStats: card.trainingStats,
                    monthlyStats: card.monthlyStats,
                    programContext: card.programContext,
                    profileImage: card.profileImage,
                    headerBackgroundImage: byId[card.student.id]
                )
            }
        }
    }
}

#endif
