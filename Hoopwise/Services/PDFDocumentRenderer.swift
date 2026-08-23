import Foundation
import CoreGraphics
import CoreText

// MARK: - PDF Document Renderer
//
// The shared vector document layer. CoreGraphics + CoreText only — no UIKit, no
// AppKit — so it runs identically on both platforms.
//
// This exists because every previous PDF path in the project used
// UIGraphicsPDFRenderer, which is iOS-only. MonthlyStudentCardExportService is
// wrapped end to end in #if os(iOS) and produces nothing on Mac.
//
// It is deliberately built against text and tables first. The hard problems
// here — CJK font cascading, A4 pagination, measuring wrapped text before
// drawing it — are the same ones the play sheet will hit, and they are far
// easier to debug against a table than against a court diagram with a
// perspective transform on top. Once this layer is proven, the play sheet is
// one more drawing routine that hands CGPaths to `draw(path:)`.

/// Page geometry. Points, 72 per inch.
enum PDFPageSize {
    /// 210 × 297 mm. The correct default: the coach operates in China, where
    /// US Letter is not the standard paper size.
    static let a4 = CGSize(width: 595.276, height: 841.890)
    static let usLetter = CGSize(width: 612, height: 792)
}

struct PDFMargins {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    static let standard = PDFMargins(top: 56, left: 56, bottom: 56, right: 56)

    init(top: CGFloat = 56, left: CGFloat = 56, bottom: CGFloat = 56, right: CGFloat = 56) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    init(all: CGFloat) {
        self.init(top: all, left: all, bottom: all, right: all)
    }
}

// MARK: - Fonts

/// Font resolution with CJK coverage.
///
/// A bilingual document mixes Latin and Han glyphs inside a single run, often
/// inside a single line ("出席 / Attendance"). Picking one font family cannot
/// work: Helvetica has no Han glyphs and PingFang's Latin is not what you want
/// for body text.
///
/// Core Text solves this properly with a cascade list — a per-glyph fallback
/// chain evaluated during shaping. Set it once on the descriptor and mixed runs
/// resolve automatically, with no manual range splitting.
enum PDFFont {
    /// Families tried in order for glyphs the base font lacks. PingFang SC is
    /// the system Simplified Chinese face on modern Apple platforms; the others
    /// are fallbacks for older systems and for Traditional text.
    private static let cjkFallbacks = [
        "PingFang SC",
        "Hiragino Sans GB",
        "Heiti SC",
        "STHeiti",
        "Apple SD Gothic Neo"
    ]

    /// Builds a font that renders Latin in `family` and falls back to a CJK
    /// face per-glyph for anything it cannot draw.
    static func bilingual(family: String = "Helvetica", size: CGFloat, bold: Bool = false) -> CTFont {
        let baseName = bold ? boldName(for: family) : family

        let cascade: [CTFontDescriptor] = cjkFallbacks.map { name in
            CTFontDescriptorCreateWithAttributes([
                kCTFontNameAttribute: name as CFString
            ] as CFDictionary)
        }

        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: baseName as CFString,
            kCTFontCascadeListAttribute: cascade as CFArray
        ] as CFDictionary)

        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private static func boldName(for family: String) -> String {
        switch family {
        case "Helvetica": return "Helvetica-Bold"
        case "Times":     return "Times-Bold"
        default:          return family + "-Bold"
        }
    }
}

/// Text appearance.
struct PDFTextStyle {
    var font: CTFont
    var color: CGColor
    var lineSpacing: CGFloat
    var alignment: CTTextAlignment

    init(font: CTFont,
         color: CGColor = CGColor(gray: 0, alpha: 1),
         lineSpacing: CGFloat = 2,
         alignment: CTTextAlignment = .left) {
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
        self.alignment = alignment
    }

    static func title(_ size: CGFloat = 20) -> PDFTextStyle {
        PDFTextStyle(font: PDFFont.bilingual(size: size, bold: true), lineSpacing: 4)
    }

    static func heading(_ size: CGFloat = 13) -> PDFTextStyle {
        PDFTextStyle(font: PDFFont.bilingual(size: size, bold: true), lineSpacing: 3)
    }

    static func body(_ size: CGFloat = 10.5) -> PDFTextStyle {
        PDFTextStyle(font: PDFFont.bilingual(size: size))
    }

    static func caption(_ size: CGFloat = 8.5) -> PDFTextStyle {
        PDFTextStyle(font: PDFFont.bilingual(size: size),
                     color: CGColor(gray: 0.4, alpha: 1))
    }

    /// USE AFTER SCOPE, FIXED (Phase D). `CTParagraphStyleSetting` stores a RAW
    /// POINTER to the value; `withUnsafeBytes(of:)` only guarantees that
    /// pointer inside its own closure. The previous shape appended the setting
    /// from inside the closure and then called `CTParagraphStyleCreate` after
    /// it returned, so CoreText read two pointers into stack memory that had
    /// already gone out of scope.
    ///
    /// It "worked" for a year because the stack usually still held the right
    /// bytes. It was found the first time this layer was exercised under a test
    /// process, where it aborted in malloc — and it was never the play card's
    /// bug: the attendance statement and the training agreement, the two
    /// documents that go to clients, were built on it.
    ///
    /// The pointers must be live AT THE MOMENT OF THE CALL, so the create
    /// happens INSIDE both scopes. CTParagraphStyleCreate copies the values, so
    /// nothing has to outlive it.
    fileprivate func attributes() -> [NSAttributedString.Key: Any] {
        var alignmentValue = alignment
        var spacing = lineSpacing
        let paragraph: CTParagraphStyle = withUnsafePointer(to: &alignmentValue) { alignmentPointer in
            withUnsafePointer(to: &spacing) { spacingPointer in
                let settings = [
                    CTParagraphStyleSetting(
                        spec: .alignment,
                        valueSize: MemoryLayout<CTTextAlignment>.size,
                        value: UnsafeRawPointer(alignmentPointer)),
                    CTParagraphStyleSetting(
                        spec: .lineSpacingAdjustment,
                        valueSize: MemoryLayout<CGFloat>.size,
                        value: UnsafeRawPointer(spacingPointer))
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }

        return [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
            kCTParagraphStyleAttributeName as NSAttributedString.Key: paragraph
        ]
    }
}

// MARK: - Table

/// One column of a table.
struct PDFTableColumn {
    var title: String
    /// Relative width. Columns are laid out proportionally across the content
    /// width, so these need not sum to anything in particular.
    var weight: CGFloat
    var alignment: CTTextAlignment

    init(title: String, weight: CGFloat = 1, alignment: CTTextAlignment = .left) {
        self.title = title
        self.weight = weight
        self.alignment = alignment
    }
}

// MARK: - Renderer

/// Draws a paginated vector PDF.
///
/// Flow model: content is appended top-down and the cursor advances. When a
/// block does not fit in the remaining height, a page break happens before it,
/// so blocks are never split mid-element. Tables are the exception — they split
/// by row and repeat their header.
/// NONISOLATED, DELIBERATELY. The project compiles with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which made this class — pure
/// CoreGraphics and CoreText, not a pixel of UI — implicitly main-actor
/// isolated, and with it its deinit. An isolated deinit routes through
/// `swift_task_deinitOnExecutorImpl`, and in the test process that aborted in
/// malloc the moment a renderer was released: constructing one and dropping it
/// was enough. It is why this layer had no tests until Phase D — the first test
/// that touched it could not survive its own teardown.
///
/// Rendering a document is not main-thread work and pinning it there was never
/// intended; saying so out loud fixes the crash and makes the layer testable.
nonisolated final class PDFDocumentRenderer {
    let pageSize: CGSize
    let margins: PDFMargins

    private var context: CGContext?
    /// Distance from the top of the page to the next drawing position.
    private var cursorY: CGFloat = 0
    private var pageIndex = 0

    /// Called after each page begins, for headers/footers. Receives the
    /// 1-based page number.
    var onPageBegin: ((PDFDocumentRenderer, Int) -> Void)?

    init(pageSize: CGSize = PDFPageSize.a4, margins: PDFMargins = .standard) {
        self.pageSize = pageSize
        self.margins = margins
    }

    // MARK: Geometry

    var contentWidth: CGFloat { pageSize.width - margins.left - margins.right }
    var contentHeight: CGFloat { pageSize.height - margins.top - margins.bottom }
    var remainingHeight: CGFloat { max(0, contentHeight - cursorY) }
    var currentPage: Int { pageIndex }

    /// Top-down y to PDF's bottom-up y.
    private func flipped(_ topDownY: CGFloat) -> CGFloat {
        pageSize.height - margins.top - topDownY
    }

    // MARK: Rendering

    /// Renders to `url`. The closure appends content; pagination is automatic.
    @discardableResult
    func render(to url: URL, _ body: (PDFDocumentRenderer) -> Void) throws -> URL {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw PDFRenderError.couldNotCreateContext(url)
        }
        self.context = context
        pageIndex = 0

        beginPage()
        body(self)
        context.endPDFPage()
        context.closePDF()

        self.context = nil
        return url
    }

    /// Renders to a temporary file with the given base name.
    @discardableResult
    func renderToTemporaryFile(named name: String, _ body: (PDFDocumentRenderer) -> Void) throws -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe).pdf")
        return try render(to: url, body)
    }

    private func beginPage() {
        guard let context else { return }
        context.beginPDFPage(nil)
        pageIndex += 1
        cursorY = 0
        onPageBegin?(self, pageIndex)
    }

    /// Forces a page break.
    func newPage() {
        guard let context else { return }
        context.endPDFPage()
        beginPage()
    }

    /// Breaks if `height` will not fit in what remains.
    func ensureSpace(_ height: CGFloat) {
        if height > remainingHeight && cursorY > 0 {
            newPage()
        }
    }

    // MARK: Primitives

    func spacer(_ height: CGFloat) {
        cursorY += height
    }

    /// Measures wrapped text without drawing it.
    func measure(_ text: String, style: PDFTextStyle, width: CGFloat? = nil) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let constraint = CGSize(width: width ?? contentWidth, height: .greatestFiniteMagnitude)
        let attributed = NSAttributedString(string: text, attributes: style.attributes())
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil, constraint, nil)
        // Suggested sizes round down often enough to clip the final line.
        return CGSize(width: ceil(size.width), height: ceil(size.height) + 1)
    }

    /// Draws wrapped text at the cursor, breaking the page first if needed.
    @discardableResult
    func text(_ string: String,
              style: PDFTextStyle,
              indent: CGFloat = 0,
              width: CGFloat? = nil) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let boxWidth = (width ?? contentWidth) - indent
        let size = measure(string, style: style, width: boxWidth)
        ensureSpace(size.height)
        drawText(string, style: style,
                 in: CGRect(x: margins.left + indent,
                            y: flipped(cursorY + size.height),
                            width: boxWidth,
                            height: size.height))
        cursorY += size.height
        return size.height
    }

    /// Draws text into an explicit rect in PDF (bottom-up) coordinates.
    /// Used by the table renderer and available for custom layout.
    func drawText(_ string: String, style: PDFTextStyle, in rect: CGRect) {
        guard let context, !string.isEmpty else { return }
        let attributed = NSAttributedString(string: string, attributes: style.attributes())
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    // MARK: - Inline Runs

    /// A piece of an inline row.
    enum InlineItem {
        case text(String)
        /// A checkbox drawn as vector geometry. `nil` is unticked-and-unrecorded,
        /// `true` draws a tick, `false` draws an empty box.
        case checkbox(Bool?)
    }

    /// Draws text and checkboxes on one line, advancing horizontally.
    ///
    /// Checkboxes are STROKED PATHS, not glyphs. U+25A1 and U+2611 are absent
    /// from PingFang SC, so as characters they fell through the cascade to
    /// whatever face happened to have them — Hiragino on this Mac. Font
    /// availability differs between iOS and macOS, so a glyph resolving
    /// differently per platform would break the identical-output guarantee for
    /// a signed document. Drawing the box removes the dependency, and it sizes
    /// and aligns to the text rather than to some designer's idea of a box.
    func inlineRow(_ items: [InlineItem],
                   style: PDFTextStyle,
                   indent: CGFloat = 0,
                   itemSpacing: CGFloat = 3) {
        guard let context else { return }
        let font = style.font
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let lineHeight = ascent + descent + style.lineSpacing
        let boxSide = CTFontGetCapHeight(font) * 0.95

        ensureSpace(lineHeight)
        let baselineY = flipped(cursorY + ascent)
        var x = margins.left + indent

        for item in items {
            switch item {
            case .text(let string):
                guard !string.isEmpty else { continue }
                let attributed = NSAttributedString(string: string, attributes: style.attributes())
                let line = CTLineCreateWithAttributedString(attributed)
                context.textPosition = CGPoint(x: x, y: baselineY)
                CTLineDraw(line, context)
                x += CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) + itemSpacing

            case .checkbox(let state):
                let rect = CGRect(x: x, y: baselineY, width: boxSide, height: boxSide)
                context.saveGState()
                context.setStrokeColor(style.color)
                context.setLineWidth(max(0.6, boxSide * 0.07))
                context.stroke(rect)
                if state == true {
                    // Tick drawn inside the box, inset so it reads as a mark
                    // rather than filling the frame.
                    let inset = boxSide * 0.22
                    context.setLineWidth(max(0.8, boxSide * 0.12))
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    context.move(to: CGPoint(x: rect.minX + inset,
                                             y: rect.midY))
                    context.addLine(to: CGPoint(x: rect.minX + boxSide * 0.42,
                                                y: rect.minY + inset))
                    context.addLine(to: CGPoint(x: rect.maxX - inset,
                                                y: rect.maxY - inset))
                    context.strokePath()
                }
                context.restoreGState()
                x += boxSide + itemSpacing
            }
        }

        cursorY += lineHeight
    }

    /// Horizontal rule at the cursor.
    func rule(color: CGColor = CGColor(gray: 0.8, alpha: 1), width lineWidth: CGFloat = 0.5) {
        guard let context else { return }
        ensureSpace(lineWidth + 2)
        let y = flipped(cursorY)
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.move(to: CGPoint(x: margins.left, y: y))
        context.addLine(to: CGPoint(x: margins.left + contentWidth, y: y))
        context.strokePath()
        context.restoreGState()
        cursorY += lineWidth + 2
    }

    /// Draws an arbitrary path — the hook the play sheet will use to hand over
    /// court geometry. `rect` is the top-down box to fit it into; the path is
    /// expected to already be in that box's coordinate space.
    func draw(path: CGPath, in rect: CGRect, stroke: CGColor, lineWidth: CGFloat = 1,
              dash: [CGFloat]? = nil) {
        guard let context else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: flipped(rect.minY + rect.height))
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        if let dash { context.setLineDash(phase: 0, lengths: dash) }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// Hands the raw context to `body` with the origin at the BOTTOM-LEFT of
    /// `rect` — top-down box in, PDF coordinates out — with the graphics state
    /// saved and restored around it.
    ///
    /// `draw(path:in:)` covers a stroked path and nothing else, which is enough
    /// for a table rule and not enough for a court: a diagram fills regions,
    /// strokes hairlines, fills pucks and sets type, all in one coordinate
    /// space. This is the hook the play card uses, and the reason it exists
    /// here rather than as a second renderer.
    func draw(in rect: CGRect, _ body: (CGContext) -> Void) {
        guard let context else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: flipped(rect.minY + rect.height))
        body(context)
        context.restoreGState()
    }

    /// Reserves a top-down box at the cursor and returns it, for callers that
    /// draw their own content (diagrams, images).
    func reserve(height: CGFloat, width: CGFloat? = nil) -> CGRect {
        ensureSpace(height)
        let box = CGRect(x: margins.left, y: cursorY,
                         width: width ?? contentWidth, height: height)
        cursorY += height
        return box
    }

    // MARK: Table

    /// Draws a table, splitting across pages by row and repeating the header.
    ///
    /// Row heights are measured from actual wrapped content, so a long note in
    /// one cell grows its row rather than overflowing it.
    func table(columns: [PDFTableColumn],
               rows: [[String]],
               headerStyle: PDFTextStyle? = nil,
               cellStyle: PDFTextStyle? = nil,
               cellPadding: CGFloat = 5,
               headerBackground: CGColor? = CGColor(gray: 0.94, alpha: 1),
               gridColor: CGColor = CGColor(gray: 0.82, alpha: 1)) {
        guard !columns.isEmpty else { return }
        let header = headerStyle ?? .heading(9.5)
        let cell = cellStyle ?? .body(9.5)

        let totalWeight = columns.reduce(0) { $0 + $1.weight }
        let widths = columns.map { contentWidth * ($0.weight / max(totalWeight, 0.0001)) }

        func rowHeight(_ values: [String], style: PDFTextStyle) -> CGFloat {
            var tallest: CGFloat = 0
            for (index, width) in widths.enumerated() {
                let value = index < values.count ? values[index] : ""
                let size = measure(value, style: style, width: width - cellPadding * 2)
                tallest = max(tallest, size.height)
            }
            return tallest + cellPadding * 2
        }

        let headerHeight = rowHeight(columns.map(\.title), style: header)

        func drawRow(_ values: [String], style: PDFTextStyle, height: CGFloat, background: CGColor?) {
            guard let context else { return }
            let top = cursorY
            let bottomY = flipped(top + height)

            if let background {
                context.saveGState()
                context.setFillColor(background)
                context.fill(CGRect(x: margins.left, y: bottomY,
                                    width: contentWidth, height: height))
                context.restoreGState()
            }

            var x = margins.left
            for (index, width) in widths.enumerated() {
                let value = index < values.count ? values[index] : ""
                var cellStyle = style
                cellStyle.alignment = columns[index].alignment
                drawText(value, style: cellStyle,
                         in: CGRect(x: x + cellPadding,
                                    y: bottomY + cellPadding,
                                    width: width - cellPadding * 2,
                                    height: height - cellPadding * 2))
                x += width
            }

            // Grid.
            context.saveGState()
            context.setStrokeColor(gridColor)
            context.setLineWidth(0.5)
            context.stroke(CGRect(x: margins.left, y: bottomY,
                                  width: contentWidth, height: height))
            var divider = margins.left
            for width in widths.dropLast() {
                divider += width
                context.move(to: CGPoint(x: divider, y: bottomY))
                context.addLine(to: CGPoint(x: divider, y: bottomY + height))
            }
            context.strokePath()
            context.restoreGState()

            cursorY += height
        }

        // A header alone at the bottom of a page reads as a mistake, so require
        // room for the header plus at least one row before starting.
        let firstRowHeight = rows.first.map { rowHeight($0, style: cell) } ?? 0
        ensureSpace(headerHeight + firstRowHeight)
        drawRow(columns.map(\.title), style: header, height: headerHeight, background: headerBackground)

        for row in rows {
            let height = rowHeight(row, style: cell)
            if height > remainingHeight {
                newPage()
                drawRow(columns.map(\.title), style: header,
                        height: headerHeight, background: headerBackground)
            }
            drawRow(row, style: cell, height: height, background: nil)
        }
    }

    // MARK: Header / Footer

    /// Draws text at a fixed distance from the bottom of the page, outside the
    /// flow. Intended for `onPageBegin`.
    func footer(_ string: String, style: PDFTextStyle? = nil) {
        let footerStyle = style ?? .caption()
        let height = measure(string, style: footerStyle).height
        drawText(string, style: footerStyle,
                 in: CGRect(x: margins.left,
                            y: margins.bottom - height - 6,
                            width: contentWidth,
                            height: height))
    }
}

enum PDFRenderError: LocalizedError {
    case couldNotCreateContext(URL)

    var errorDescription: String? {
        switch self {
        case .couldNotCreateContext(let url):
            return "Could not create a PDF context at \(url.path)."
        }
    }
}
