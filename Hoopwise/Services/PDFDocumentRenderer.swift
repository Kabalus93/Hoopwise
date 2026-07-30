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

    fileprivate func attributes() -> [NSAttributedString.Key: Any] {
        var settings = [CTParagraphStyleSetting]()
        var alignmentValue = alignment
        withUnsafeBytes(of: &alignmentValue) { raw in
            settings.append(CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: raw.baseAddress!))
        }
        var spacing = lineSpacing
        withUnsafeBytes(of: &spacing) { raw in
            settings.append(CTParagraphStyleSetting(
                spec: .lineSpacingAdjustment,
                valueSize: MemoryLayout<CGFloat>.size,
                value: raw.baseAddress!))
        }
        let paragraph = CTParagraphStyleCreate(settings, settings.count)

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
final class PDFDocumentRenderer {
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
