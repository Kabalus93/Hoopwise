import Foundation
import CoreGraphics
import CoreText

// MARK: - Play card
//
// Play Editor v2, Phase D: PRINT AS A FIRST-CLASS OUTPUT.
//
// This is what the editor SHIPS. The video export it replaces produced a file
// that had to be carried into another application to be of any use; a play card
// is handed to an assistant coach on the sideline, or photographed and sent to
// a parent, and it works in the rain.
//
// It is built on `PDFDocumentRenderer` — CoreGraphics and CoreText only, both
// platforms, fully vector — to the same bar as the attendance statement: ink
// and hairlines, one accent, and it must survive being printed in grayscale on
// whatever machine the gym has.
//
// WHAT IT DRAWS IS THE AUTHORING NOTATION, not the published video look. A card
// is read, not watched: the coach needs to see that this line is a screen and
// that one a dribble, which is exactly the distinction the presentation brush
// deliberately throws away. `FrameNotation` is shared with the canvas so the
// printed card and the screen it was authored on cannot disagree about what a
// dashed line means.
enum PlayCardDocument {

    /// One page section: a run of frames under a heading.
    ///
    /// The base play is one section; each read is another, headed by its
    /// condition and carrying ONLY its own frames. Printing whole runs instead
    /// would reprint the shared prefix once per read — three pages of the same
    /// entry to show two counters.
    struct Section {
        /// Nil on the base play: the play needs no condition to happen.
        var condition: String?
        var sequence: FrameSequence
        var openingHolder: UUID?
        /// Frame numbering continues from the base play, so "3a" style
        /// references a coach makes out loud have something to land on.
        var firstFrameNumber: Int
    }

    struct Input {
        var title: String
        /// The play family — Horns, SLOB, whatever the coach filed it under.
        var family: String?
        var date: Date
        var space: CourtSpace
        var entities: [DiagramEntity]
        var sections: [Section]
        /// Printed in the footer. The coach's name, never invented.
        var coachName: String?
    }

    // MARK: - Building the input

    /// Everything the card needs, from the diagram alone.
    static func makeInput(diagram: PlayDiagram,
                          title: String,
                          family: String? = nil,
                          date: Date = Date(),
                          coachName: String? = nil) -> Input {
        var sections: [Section] = []
        var number = 1

        if let root = diagram.rootNode {
            var base = diagram.frameSequence(for: root.id, startingFrom: diagram.homeFormation)
            base.reresolve()
            sections.append(Section(condition: nil, sequence: base,
                                    openingHolder: diagram.openingHolder(for: root.id),
                                    firstFrameNumber: number))
            number += base.frames.count
        }

        // Reads in tree order, each opening where its parent left off.
        for node in diagram.nodes where node.id != diagram.rootNodeId {
            var sequence = diagram.frameSequence(for: node.id,
                                                 startingFrom: diagram.formationEntering(node.id))
            sequence.reresolve()
            guard !sequence.frames.isEmpty else { continue }
            let condition = diagram.nodes
                .compactMap { $0.edges.first { $0.targetId == node.id }?.condition }
                .first
            sections.append(Section(condition: condition ?? node.title,
                                    sequence: sequence,
                                    openingHolder: diagram.openingHolder(for: node.id),
                                    firstFrameNumber: number))
            number += sequence.frames.count
        }

        return Input(title: title, family: family, date: date,
                     space: diagram.space, entities: diagram.entities,
                     sections: sections, coachName: coachName)
    }

    static func filename(for input: Input) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let safe = input.title.replacingOccurrences(of: "/", with: "-")
        return "Play_\(safe)_\(formatter.string(from: input.date))"
    }

    // MARK: - Palette
    //
    // The page's type takes its ink from the SAME palette the diagrams do, so a
    // caption and the court it describes cannot end up two different greys.

    private static let palette = FrameCardRenderer.Palette.print
    private static var ink: CGColor { palette.ink }
    private static var secondary: CGColor { palette.secondary }
    private static var hairline: CGColor { palette.hairline }
    private static var accent: CGColor { palette.accent }

    /// Frames per page. 2×2 rather than 2×3: a play card is looked at across a
    /// gym, and the diagram is the content — the extra row buys a page back and
    /// costs the thing the page is for.
    private static let columns = 2
    private static let rows = 2
    private static var perPage: Int { columns * rows }

    // MARK: - Render

    @discardableResult
    static func render(_ input: Input, to url: URL? = nil) throws -> URL {
        let renderer = PDFDocumentRenderer(margins: PDFMargins(all: 44))
        renderer.onPageBegin = { doc, page in
            var footer = "HOOPWISE"
            if let coach = input.coachName { footer += " · \(coach)" }
            footer += " · \(dateString(input.date)) · \(page)"
            var style = PDFTextStyle(font: PDFFont.bilingual(size: 7.5), color: secondary)
            style.alignment = .center
            doc.footer(footer, style: style)
        }

        let body: (PDFDocumentRenderer) -> Void = { doc in
            drawHeader(doc, input)
            for (index, section) in input.sections.enumerated() {
                drawSection(doc, input, section, isFirst: index == 0)
            }
        }

        if let url { return try renderer.render(to: url, body) }
        return try renderer.renderToTemporaryFile(named: filename(for: input), body)
    }

    // MARK: - Header

    private static func drawHeader(_ doc: PDFDocumentRenderer, _ input: Input) {
        var kind = PDFTextStyle(font: PDFFont.bilingual(size: 9), color: secondary)
        kind.alignment = .right
        // 16, not 13. CTFrame DROPS a line whose height does not fully fit its
        // box, so a 9pt line in a 13pt band renders as nothing at all — the
        // wordmark and the whole meta line silently vanished. The attendance
        // statement carries the same warning about a 22pt number.
        let band = doc.reserve(height: 16)
        drawInRect(doc, band, "战术图 · Play Card",
                   PDFTextStyle(font: PDFFont.bilingual(size: 9, bold: true), color: accent))
        drawInRect(doc, band, kindLine(input), kind)

        doc.spacer(14)
        doc.text(input.title,
                 style: PDFTextStyle(font: PDFFont.bilingual(size: 24, bold: true),
                                     color: ink, lineSpacing: 3))
        doc.spacer(6)
        doc.rule(color: hairline, width: 0.5)
        doc.spacer(12)
    }

    private static func kindLine(_ input: Input) -> String {
        var parts: [String] = []
        if let family = input.family, !family.isEmpty { parts.append(family) }
        let frames = input.sections.reduce(0) { $0 + $1.sequence.frames.count }
        let duration = input.sections.first?.sequence.duration ?? 0
        parts.append("\(frames) 画面 frames")
        parts.append(String(format: "%.1fs", duration))
        parts.append(dateString(input.date))
        return parts.joined(separator: "   ·   ")
    }

    // MARK: - Sections

    private static func drawSection(_ doc: PDFDocumentRenderer,
                                    _ input: Input,
                                    _ section: Section,
                                    isFirst: Bool) {
        if let condition = section.condition {
            doc.spacer(isFirst ? 0 : 10)
            // A read's heading must not be orphaned at the foot of a page.
            doc.ensureSpace(cellHeight(doc, input) + 26)
            doc.text("如果 If \(condition)",
                     style: PDFTextStyle(font: PDFFont.bilingual(size: 11, bold: true),
                                         color: ink, lineSpacing: 2))
            doc.spacer(8)
        }

        let starts = section.sequence.frameStartTimes
        var index = 0
        while index < section.sequence.frames.count {
            let count = min(perPage, section.sequence.frames.count - index)
            drawRowsOfFrames(doc, input, section, from: index, count: count, starts: starts)
            index += count
        }
    }

    private static func cellWidth(_ doc: PDFDocumentRenderer) -> CGFloat {
        (doc.contentWidth - gutter * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private static let gutter: CGFloat = 16
    private static let captionHeight: CGFloat = 30

    private static func courtHeight(_ doc: PDFDocumentRenderer, _ input: Input) -> CGFloat {
        // The court keeps its real aspect — it is real-world geometry, and a
        // stretched court draws every arc wrong.
        let width = cellWidth(doc)
        return width * (input.space.length / max(input.space.width, 1))
    }

    /// DERIVED from the same numbers the row actually uses. It was a hardcoded
    /// 250 against a real 259, which is the shape of bug where a heading sits
    /// alone at the foot of a page because the guard measured something else.
    private static func cellHeight(_ doc: PDFDocumentRenderer, _ input: Input) -> CGFloat {
        min(courtHeight(doc, input), maxCourtHeight) + captionHeight
    }

    private static let maxCourtHeight: CGFloat = 232

    private static func drawRowsOfFrames(_ doc: PDFDocumentRenderer,
                                         _ input: Input,
                                         _ section: Section,
                                         from start: Int,
                                         count: Int,
                                         starts: [Double]) {
        let width = cellWidth(doc)
        let court = min(courtHeight(doc, input), maxCourtHeight)
        let cell = court + captionHeight

        var drawn = 0
        while drawn < count {
            let inRow = min(columns, count - drawn)
            doc.ensureSpace(cell + 10)
            let band = doc.reserve(height: cell)
            for column in 0..<inRow {
                let index = start + drawn + column
                let x = band.minX + (width + gutter) * CGFloat(column)
                drawFrameCell(doc, input, section,
                              frameIndex: index,
                              starts: starts,
                              in: CGRect(x: x, y: band.minY, width: width, height: cell),
                              courtHeight: court)
            }
            drawn += inRow
            doc.spacer(12)
        }
    }

    /// One frame: its number, its court, its caption.
    private static func drawFrameCell(_ doc: PDFDocumentRenderer,
                                      _ input: Input,
                                      _ section: Section,
                                      frameIndex: Int,
                                      starts: [Double],
                                      in cell: CGRect,
                                      courtHeight: CGFloat) {
        let frame = section.sequence.frames[frameIndex]
        let opensOn = section.sequence.formation(enteringFrame: frameIndex)
        let courtBox = CGRect(x: cell.minX, y: cell.minY, width: cell.width, height: courtHeight)

        // The ball as the frame OPENS. A hair inside, because at the exact
        // instant a pass leaves, the interval that just ended still contains
        // the boundary and the ball would print in the passer's hands.
        let time = (starts.indices.contains(frameIndex) ? starts[frameIndex] : 0) + 0.0001
        let ball = input.entities.contains { if case .ball = $0.kind { return true } else { return false } }
            ? section.sequence.ballPosition(at: time,
                                            ballHome: ballHome(input),
                                            openingHolder: section.openingHolder)
            : nil

        let card = FrameCardRenderer.Cell(space: input.space,
                                          entities: input.entities,
                                          formation: opensOn,
                                          frame: frame,
                                          ball: ball)
        doc.draw(in: courtBox) { context in
            FrameCardRenderer.draw(card, in: courtBox.size, into: context, palette: palette)
        }

        // Number and caption UNDER the court, where the eye lands after the
        // diagram rather than before it.
        let number = section.firstFrameNumber + frameIndex
        let captionBox = CGRect(x: cell.minX, y: cell.minY + courtHeight + 5,
                                width: cell.width, height: captionHeight - 5)
        drawInRect(doc, CGRect(x: captionBox.minX, y: captionBox.minY,
                               width: 16, height: 12),
                   "\(number)",
                   PDFTextStyle(font: PDFFont.bilingual(size: 9, bold: true), color: accent))
        drawInRect(doc, CGRect(x: captionBox.minX + 16, y: captionBox.minY,
                               width: captionBox.width - 16, height: captionBox.height),
                   frame.caption,
                   PDFTextStyle(font: PDFFont.bilingual(size: 8.5), color: ink, lineSpacing: 1.5))
    }

    private static func ballHome(_ input: Input) -> CGPoint {
        for entity in input.entities {
            if case .ball = entity.kind { return entity.homePosition }
        }
        return .zero
    }

    // MARK: - Helpers

    private static func drawInRect(_ doc: PDFDocumentRenderer, _ rect: CGRect,
                                   _ string: String, _ style: PDFTextStyle) {
        let pdfY = doc.pageSize.height - doc.margins.top - rect.minY - rect.height
        doc.drawText(string, style: style,
                     in: CGRect(x: rect.minX, y: pdfY,
                                width: rect.width, height: rect.height))
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
