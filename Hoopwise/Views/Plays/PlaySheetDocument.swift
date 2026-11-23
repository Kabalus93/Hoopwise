import SwiftUI
import UIKit
import PDFKit

// PLAY SHEETS (23 Nov 2026, Luther: "share a play to the team … share a play
// to a player: this highlights what that player does … as PDF or printed. The
// quality of the export here matters. Sheet composition, court sizes").
//
// A4 portrait, vector: every court is the app's own JournalPlayDiagramView
// drawn through ImageRenderer straight into the PDF context (a Canvas of
// paths and text stays vector; only a photo is a bitmap). One composition:
//   header — team colour rule, eyebrow, play name, category · court · steps,
//            when to run it, the idea;
//   roles  — number → who plays it (team sheet) / "Your role" box with the
//            role's standard and drills (player sheet);
//   steps  — a grid of courts, half court two across, full court (upright)
//            three across; the court is as large as lets the part take the
//            fewest pages, never under 75 mm wide; each step's caption over
//            it and its words under it (a player sheet adds "Your job",
//            worded from the drawing by PlayRoleJob);
//   wrinkles / variations — each from a new page;
//   footer — the line legend, academy, page n of m.
// Print rules: lines ≥ 0.5 mm come from the diagram's own scale, the followed
// player is bold orange (reads as bold dark in grayscale), text ≥ 8 pt.

struct PlaySheet {
    struct Step {
        var diagram: JournalPlayDiagram
        var caption: String
        var text: String
    }
    struct Part {
        var kind: JournalPlayPartKind
        var name: String
        var notes: String
        var steps: [Step]
    }
    struct Role: Equatable {
        var number: Int
        var name: String?
    }

    var playName: String
    var category: JournalPlayCategory
    var court: JournalCourtKind
    var situation: String
    var idea: String
    var parts: [Part]
    var teamName: String?
    var teamColor: UIColor
    var academy: String
    var roles: [Role]
    var bubbles: [Int: PlayBubble]
    var showsDefense: Bool
    var chinese: Bool
    /// A player sheet: the role followed, with its standard and drills.
    var focus: Int?
    var focusName: String?
    var focusStandard: String = ""
    var focusDrills: [String] = []

    /// The name a sentence uses for a numbered player.
    func name(_ number: Int) -> String {
        roles.first { $0.number == number }?.name ?? "\(number)"
    }
}

extension PlaySheet {
    /// The parts of a stored play, concept first.
    static func parts(of play: JournalPlay) -> [Part] {
        play.sortedParts.sorted { order($0.kind) < order($1.kind) }.compactMap { part in
            let steps = part.sortedSteps.map { Step(diagram: $0.diagram, caption: $0.caption, text: $0.text) }
            return steps.isEmpty ? nil : Part(kind: part.kind, name: part.name, notes: part.notes, steps: steps)
        }
    }

    private static func order(_ kind: JournalPlayPartKind) -> Int {
        switch kind { case .concept: 0; case .wrinkle: 1; case .variation: 2 }
    }

    static func categoryTitle(_ c: JournalPlayCategory, chinese: Bool) -> String {
        switch c {
        case .transition: chinese ? "转换进攻" : "Transition"
        case .halfCourt: chinese ? "半场进攻" : "Half court"
        case .baselineInbound: chinese ? "底线发球" : "Baseline inbound"
        case .sidelineInbound: chinese ? "边线发球" : "Sideline inbound"
        case .versusMan: chinese ? "对人盯人" : "Against man-to-man"
        case .other: chinese ? "其他" : "Other"
        }
    }
}

@MainActor
enum PlaySheetDocument {
    static let pageSize = CGSize(width: 595.28, height: 841.89)   // A4
    static let margin: CGFloat = 36
    static let gutter: CGFloat = 16
    static let footerHeight: CGFloat = 34
    /// 75 mm: no court printed narrower.
    static let minCourtWidth: CGFloat = 75 / 25.4 * 72

    private typealias Op = (CGContext) -> Void

    /// One PDF; several sheets (sheets for everyone) follow one another.
    static func pdf(_ sheets: [PlaySheet]) -> Data {
        var pages: [[Op]] = []
        var sheetOfPage: [Int] = []
        for (i, sheet) in sheets.enumerated() {
            let laid = layout(sheet)
            pages += laid
            sheetOfPage += Array(repeating: i, count: laid.count)
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for (n, ops) in pages.enumerated() {
                context.beginPage()
                let cg = context.cgContext
                for op in ops { op(cg) }
                // Page numbers count within each sheet.
                let sheet = sheets[sheetOfPage[n]]
                let first = sheetOfPage.firstIndex(of: sheetOfPage[n]) ?? 0
                let total = sheetOfPage.filter { $0 == sheetOfPage[n] }.count
                footer(sheet, page: n - first + 1, of: total, in: cg)
            }
        }
    }

    /// The pages stacked as one long JPEG (WeChat), 1242 px wide.
    static func longImage(pdf data: Data, width: CGFloat = 1242) -> Data? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        let scale = width / pageSize.width
        let pageHeight = pageSize.height * scale
        let size = CGSize(width: width, height: pageHeight * CGFloat(document.pageCount))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let cg = ctx.cgContext
                cg.saveGState()
                cg.translateBy(x: 0, y: pageHeight * CGFloat(i + 1))
                cg.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
                if i > 0 {
                    UIColor(white: 0.85, alpha: 1).setFill()
                    ctx.fill(CGRect(x: 0, y: pageHeight * CGFloat(i), width: width, height: 2))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.88)
    }

    /// The first page as an image, for the share sheet's preview.
    static func preview(pdf data: Data, width: CGFloat) -> UIImage? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        let scale = width / pageSize.width
        return page.thumbnail(of: CGSize(width: width, height: pageSize.height * scale), for: .mediaBox)
    }

    // MARK: - Layout

    private static var contentWidth: CGFloat { pageSize.width - 2 * margin }
    private static var bottom: CGFloat { pageSize.height - margin - footerHeight }

    private static func layout(_ sheet: PlaySheet) -> [[Op]] {
        var pages: [[Op]] = [[]]
        var y = margin
        let headerOps = header(sheet, y: &y)
        pages[0] += headerOps

        for (index, part) in sheet.parts.enumerated() {
            if index > 0 {
                // A wrinkle or variation starts a page of its own.
                pages.append([])
                y = margin
                pages[pages.count - 1] += continuation(sheet, y: &y)
            }
            if part.kind != .concept || !part.notes.isEmpty {
                pages[pages.count - 1] += partHeading(part, sheet: sheet, y: &y)
            }
            let width = courtWidth(for: part, sheet: sheet, startingAt: y)
            let cols = columns(sheet.court)
            var row: [(Int, PlaySheet.Step)] = []
            func flushRow() {
                guard !row.isEmpty else { return }
                let height = row.map { cellHeight($0.1, number: $0.0, sheet: sheet, width: width) }.max() ?? 0
                if y + height > bottom, y > margin + 60 {
                    pages.append([])
                    y = margin
                    pages[pages.count - 1] += continuation(sheet, y: &y)
                }
                let rowY = y
                let used = CGFloat(row.count) * width + CGFloat(row.count - 1) * gutter
                let fullWidth = CGFloat(cols) * width + CGFloat(cols - 1) * gutter
                let x0 = margin + (contentWidth - fullWidth) / 2 + (row.count < cols && cols > 1 ? 0 : (fullWidth - used) / 2)
                for (i, (number, step)) in row.enumerated() {
                    let x = x0 + CGFloat(i) * (width + gutter)
                    pages[pages.count - 1].append { cg in
                        drawCell(step, number: number, sheet: sheet, at: CGPoint(x: x, y: rowY), width: width, in: cg)
                    }
                }
                y += height + gutter
                row = []
            }
            for (i, step) in part.steps.enumerated() {
                row.append((i + 1, step))
                if row.count == cols { flushRow() }
            }
            flushRow()
        }
        return pages
    }

    /// Half court two across; an upright full court three across IF three
    /// courts of at least 75 mm fit the page — on A4 they do not (3 × 75 mm
    /// is wider than the sheet: the outer two were cut off, found 23 Nov
    /// 2026), so it is two across there too.
    private static func columns(_ court: JournalCourtKind) -> Int {
        let fits = Int((contentWidth + gutter) / (minCourtWidth + gutter))
        return max(1, min(court == .full ? 3 : 2, fits))
    }

    /// The widest court (up to the column width) with which the part takes
    /// the fewest pages, never under 75 mm.
    private static func courtWidth(for part: PlaySheet.Part, sheet: PlaySheet, startingAt top: CGFloat) -> CGFloat {
        let cols = CGFloat(columns(sheet.court))
        let widest = (contentWidth - (cols - 1) * gutter) / cols
        func pages(_ width: CGFloat) -> Int {
            var y = top, count = 1
            for start in stride(from: 0, to: part.steps.count, by: Int(cols)) {
                let row = part.steps[start..<min(start + Int(cols), part.steps.count)]
                let height = row.enumerated().map { cellHeight($0.element, number: start + $0.offset + 1, sheet: sheet, width: width) }.max() ?? 0
                if y + height > bottom { count += 1; y = margin + 30 }
                y += height + gutter
            }
            return count
        }
        let best = pages(minCourtWidth)
        var width = widest
        while width > minCourtWidth, pages(width) > best { width -= 6 }
        return max(minCourtWidth, min(widest, width))
    }

    // MARK: - Cells

    private static func courtHeight(_ court: JournalCourtKind, width: CGFloat) -> CGFloat {
        width / JournalPlayCourt.aspectRatio(court)
    }

    private static func jobText(_ step: PlaySheet.Step, sheet: PlaySheet) -> String? {
        guard let focus = sheet.focus else { return nil }
        return PlayRoleJob.sentence(for: focus, in: step.diagram, court: sheet.court,
                                    name: sheet.name, chinese: sheet.chinese)
    }

    private static func cellHeight(_ step: PlaySheet.Step, number: Int, sheet: PlaySheet, width: CGFloat) -> CGFloat {
        var h = Font.cellTitle.lineHeight + 5
        h += courtHeight(sheet.court, width: width)
        if let job = jobText(step, sheet: sheet), !job.isEmpty {
            h += 6 + measure(job, Font.job, width: width, maxLines: 4)
        }
        let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { h += 4 + measure(text, Font.body, width: width, maxLines: 6) }
        return h
    }

    private static func drawCell(_ step: PlaySheet.Step, number: Int, sheet: PlaySheet, at origin: CGPoint,
                                 width: CGFloat, in cg: CGContext) {
        var y = origin.y
        let caption = step.caption.trimmingCharacters(in: .whitespaces)
        let title = (sheet.chinese ? "第 \(number) 步" : "Step \(number)") + (caption.isEmpty ? "" : "  ·  \(caption)")
        draw(title, Font.cellTitle, color: .label, at: CGPoint(x: origin.x, y: y), width: width, maxLines: 1)
        y += Font.cellTitle.lineHeight + 5
        let height = courtHeight(sheet.court, width: width)
        let frame = CGRect(x: origin.x, y: y, width: width, height: height)
        let border = UIBezierPath(roundedRect: frame, cornerRadius: 6)
        cg.saveGState()
        UIColor(white: 0.985, alpha: 1).setFill()
        border.fill()
        cg.restoreGState()
        drawCourt(step.diagram, sheet: sheet, in: frame, context: cg)
        cg.saveGState()
        UIColor(white: 0.78, alpha: 1).setStroke()
        border.lineWidth = 0.5
        border.stroke()
        cg.restoreGState()
        y += height
        if let job = jobText(step, sheet: sheet), !job.isEmpty {
            y += 6
            let label = sheet.chinese ? "你的任务：" : "Your job: "
            let text = NSMutableAttributedString(string: label, attributes: attributes(Font.jobLabel, color: UIColor(PlayFocusStyle.color)))
            text.append(NSAttributedString(string: job, attributes: attributes(Font.job, color: .label)))
            y += draw(text, at: CGPoint(x: origin.x, y: y), width: width, maxLines: 4)
        }
        let body = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            y += 4
            draw(body, Font.body, color: .secondaryLabel, at: CGPoint(x: origin.x, y: y), width: width, maxLines: 6)
        }
    }

    /// The app's court, drawn as vectors into the page.
    private static func drawCourt(_ diagram: JournalPlayDiagram, sheet: PlaySheet, in frame: CGRect, context cg: CGContext) {
        let view = JournalPlayDiagramView(diagram: diagram, court: sheet.court)
            .environment(\.playBubbles, sheet.bubbles)
            .environment(\.playFocus, sheet.focus)
            .environment(\.playHidesDefense, !sheet.showsDefense)
            .environment(\.colorScheme, .light)
            .frame(width: frame.width, height: frame.height)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(frame.size)
        renderer.render { size, draw in
            cg.saveGState()
            // ImageRenderer draws y-up; the UIKit page is y-down.
            cg.translateBy(x: frame.minX, y: frame.minY + size.height)
            cg.scaleBy(x: 1, y: -1)
            draw(cg)
            cg.restoreGState()
        }
    }

    // MARK: - Header and headings

    private static func header(_ sheet: PlaySheet, y: inout CGFloat) -> [Op] {
        var ops: [Op] = []
        let x = margin, w = contentWidth
        let top = y
        let color = sheet.teamColor
        ops.append { cg in
            cg.saveGState()
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: top, width: w, height: 4), cornerRadius: 2).fill()
            cg.restoreGState()
        }
        y += 14
        var eyebrow: String
        if let focus = sheet.focus {
            let who = sheet.focusName ?? "\(focus)"
            eyebrow = sheet.chinese ? "球员战术单 · \(who) · \(focus) 号位" : "PLAYER SHEET · \(who.uppercased()) · ROLE \(focus)"
        } else {
            eyebrow = sheet.chinese ? "全队战术单" : "TEAM PLAY SHEET"
        }
        if let team = sheet.teamName, !team.isEmpty { eyebrow = (sheet.chinese ? team : team.uppercased()) + "  ·  " + eyebrow }
        let e = eyebrow, eyY = y
        ops.append { _ in draw(e, Font.eyebrow, color: .secondaryLabel, at: CGPoint(x: x, y: eyY), width: w, maxLines: 1, kern: 1.2) }
        y += Font.eyebrow.lineHeight + 4
        let titleY = y, name = sheet.playName
        let titleH = measure(name, Font.title, width: w, maxLines: 2)
        ops.append { _ in draw(name, Font.title, color: .label, at: CGPoint(x: x, y: titleY), width: w, maxLines: 2) }
        y += titleH + 3
        let steps = sheet.parts.first?.steps.count ?? 0
        let category = PlaySheet.categoryTitle(sheet.category, chinese: sheet.chinese)
        let courtName = sheet.court == .full ? (sheet.chinese ? "全场" : "Full court") : (sheet.chinese ? "半场" : "Half court")
        var meta = [category]
        if courtName != category && !(sheet.court == .half && sheet.category == .halfCourt) { meta.append(courtName) }
        meta.append(sheet.chinese ? "\(steps) 步" : "\(steps) step\(steps == 1 ? "" : "s")")
        let extras = sheet.parts.count - 1
        if extras > 0 { meta.append(sheet.chinese ? "\(extras) 个变化" : "\(extras) option\(extras == 1 ? "" : "s")") }
        let m = meta.joined(separator: "  ·  "), metaY = y
        ops.append { _ in draw(m, Font.meta, color: .secondaryLabel, at: CGPoint(x: x, y: metaY), width: w, maxLines: 1) }
        y += Font.meta.lineHeight + 10

        for (label, value) in [(sheet.chinese ? "何时使用" : "When", sheet.situation),
                               (sheet.chinese ? "思路" : "The idea", sheet.idea)] {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { continue }
            let text = NSMutableAttributedString(string: label + (sheet.chinese ? "：" : "  "), attributes: attributes(Font.label, color: .label))
            text.append(NSAttributedString(string: v, attributes: attributes(Font.body, color: .label)))
            let h = measure(text, width: w, maxLines: 4)
            let ty = y
            ops.append { _ in _ = draw(text, at: CGPoint(x: x, y: ty), width: w, maxLines: 4) }
            y += h + 5
        }

        if let focus = sheet.focus {
            y += 4
            ops += roleBox(sheet, number: focus, y: &y)
        } else if sheet.roles.contains(where: { $0.name != nil }) {
            y += 4
            ops += rolesRow(sheet, y: &y)
        }
        y += 8
        let ruleY = y
        ops.append { cg in
            cg.saveGState()
            UIColor(white: 0.85, alpha: 1).setFill()
            cg.fill(CGRect(x: x, y: ruleY, width: w, height: 0.5))
            cg.restoreGState()
        }
        y += 12
        return ops
    }

    /// "① Leo   ② Mia …" — the team sheet's key.
    private static func rolesRow(_ sheet: PlaySheet, y: inout CGFloat) -> [Op] {
        var ops: [Op] = []
        let label = sheet.chinese ? "号位" : "ROLES"
        let ly = y
        ops.append { _ in draw(label, Font.eyebrow, color: .secondaryLabel, at: CGPoint(x: margin, y: ly + 3), width: 60, maxLines: 1, kern: 1.2) }
        var x = margin + 52
        var rowY = y
        let d: CGFloat = 15
        for role in sheet.roles {
            let name = role.name ?? "—"
            let nameW = ceil(NSAttributedString(string: name, attributes: attributes(Font.body, color: .label)).size().width)
            let itemW = d + 5 + nameW + 16
            if x + itemW > margin + contentWidth { x = margin + 52; rowY += d + 6 }
            let ix = x, iy = rowY, number = role.number
            let tint = lightUI(UIColor(JPalette.play))
            ops.append { cg in
                cg.saveGState()
                lightUI(tint).setFill()
                UIBezierPath(ovalIn: CGRect(x: ix, y: iy, width: d, height: d)).fill()
                cg.restoreGState()
                draw("\(number)", Font.badge, color: .white, at: CGPoint(x: ix, y: iy + (d - Font.badge.lineHeight) / 2), width: d, maxLines: 1, alignment: .center)
                draw(name, Font.body, color: .label, at: CGPoint(x: ix + d + 5, y: iy + (d - Font.body.lineHeight) / 2), width: nameW + 4, maxLines: 1)
            }
            x += itemW
        }
        y = rowY + d + 2
        return ops
    }

    /// The player sheet's box: the role, its standard, the drills that build it.
    private static func roleBox(_ sheet: PlaySheet, number: Int, y: inout CGFloat) -> [Op] {
        var ops: [Op] = []
        let x = margin, w = contentWidth, pad: CGFloat = 10
        var lines: [NSAttributedString] = []
        let head = NSMutableAttributedString(string: sheet.chinese ? "你的号位：\(number)" : "Your role: \(number)",
                                             attributes: attributes(Font.label, color: .label))
        if let name = sheet.focusName { head.append(NSAttributedString(string: "  ·  \(name)", attributes: attributes(Font.body, color: .label))) }
        lines.append(head)
        if !sheet.focusStandard.isEmpty {
            let s = NSMutableAttributedString(string: sheet.chinese ? "标准：" : "Standard: ", attributes: attributes(Font.label, color: .label))
            s.append(NSAttributedString(string: sheet.focusStandard, attributes: attributes(Font.body, color: .label)))
            lines.append(s)
        }
        if !sheet.focusDrills.isEmpty {
            let s = NSMutableAttributedString(string: sheet.chinese ? "练习：" : "Drills: ", attributes: attributes(Font.label, color: .label))
            s.append(NSAttributedString(string: sheet.focusDrills.joined(separator: " · "), attributes: attributes(Font.body, color: .label)))
            lines.append(s)
        }
        let heights = lines.map { measure($0, width: w - 2 * pad - 6, maxLines: 4) }
        let boxH = heights.reduce(0, +) + CGFloat(lines.count - 1) * 3 + 2 * pad
        let top = y
        let tint = UIColor(PlayFocusStyle.color)
        ops.append { cg in
            cg.saveGState()
            tint.withAlphaComponent(0.08).setFill()
            let box = UIBezierPath(roundedRect: CGRect(x: x, y: top, width: w, height: boxH), cornerRadius: 8)
            box.fill()
            tint.setFill()
            cg.fill(CGRect(x: x, y: top, width: 3, height: boxH))
            cg.restoreGState()
            var ly = top + pad
            for (i, line) in lines.enumerated() {
                _ = draw(line, at: CGPoint(x: x + pad + 6, y: ly), width: w - 2 * pad - 6, maxLines: 4)
                ly += heights[i] + 3
            }
        }
        y += boxH
        return ops
    }

    private static func partHeading(_ part: PlaySheet.Part, sheet: PlaySheet, y: inout CGFloat) -> [Op] {
        var ops: [Op] = []
        let x = margin, w = contentWidth
        if part.kind != .concept {
            let kind: String = {
                switch part.kind {
                case .wrinkle: sheet.chinese ? "变化" : "WRINKLE"
                case .variation: sheet.chinese ? "变体" : "VARIATION"
                case .concept: ""
                }
            }()
            let ky = y
            ops.append { _ in draw(kind, Font.eyebrow, color: UIColor(JPalette.play), at: CGPoint(x: x, y: ky), width: w, maxLines: 1, kern: 1.2) }
            y += Font.eyebrow.lineHeight + 2
            let name = part.name, ny = y
            ops.append { _ in draw(name, Font.heading, color: .label, at: CGPoint(x: x, y: ny), width: w, maxLines: 2) }
            y += measure(name, Font.heading, width: w, maxLines: 2) + 4
        }
        let notes = part.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            let ny = y
            ops.append { _ in draw(notes, Font.body, color: .label, at: CGPoint(x: x, y: ny), width: w, maxLines: 5) }
            y += measure(notes, Font.body, width: w, maxLines: 5) + 6
        }
        y += 6
        return ops
    }

    /// A following page's small header: the play's name (and who it is for).
    private static func continuation(_ sheet: PlaySheet, y: inout CGFloat) -> [Op] {
        var text = sheet.playName
        if let focus = sheet.focus { text += "  ·  " + (sheet.focusName ?? "\(focus)") }
        let ty = y
        let color = sheet.teamColor
        let ops: [Op] = [{ cg in
            cg.saveGState()
            color.setFill()
            cg.fill(CGRect(x: margin, y: ty, width: 3, height: Font.label.lineHeight))
            cg.restoreGState()
            draw(text, Font.label, color: .secondaryLabel, at: CGPoint(x: margin + 9, y: ty), width: contentWidth - 9, maxLines: 1)
        }]
        y += Font.label.lineHeight + 14
        return ops
    }

    // MARK: - Footer and legend

    private static func footer(_ sheet: PlaySheet, page: Int, of total: Int, in cg: CGContext) {
        let top = pageSize.height - margin - footerHeight + 10
        cg.saveGState()
        UIColor(white: 0.88, alpha: 1).setFill()
        cg.fill(CGRect(x: margin, y: top, width: contentWidth, height: 0.5))
        cg.restoreGState()
        legend(sheet, at: CGPoint(x: margin, y: top + 7), in: cg)
        let right = sheet.chinese ? "第 \(page) / \(total) 页" : "Page \(page) of \(total)"
        let left = sheet.academy.isEmpty ? "HoopWise" : sheet.academy
        let y2 = top + 7 + 14
        draw(left, Font.footer, color: .tertiaryLabel, at: CGPoint(x: margin, y: y2), width: contentWidth / 2, maxLines: 1)
        draw(right, Font.footer, color: .tertiaryLabel, at: CGPoint(x: margin + contentWidth / 2, y: y2), width: contentWidth / 2, maxLines: 1, alignment: .right)
    }

    /// Cut, dribble, pass, hand-off, screen, shot — drawn as the courts draw them.
    private static func legend(_ sheet: PlaySheet, at origin: CGPoint, in cg: CGContext) {
        let zh = sheet.chinese
        let items: [(String, (CGContext, CGRect) -> Void)] = [
            (zh ? "切入" : "Cut", { cg, r in line(cg, r, dash: nil); arrow(cg, r) }),
            (zh ? "运球" : "Dribble", { cg, r in zigzag(cg, r); arrow(cg, r) }),
            (zh ? "传球" : "Pass", { cg, r in line(cg, r, dash: [3, 2.4]); arrow(cg, r) }),
            (zh ? "手递手" : "Hand-off", { cg, r in handoff(cg, r) }),
            (zh ? "掩护" : "Screen", { cg, r in screen(cg, r) }),
            (zh ? "投篮" : "Shot", { cg, r in line(cg, r, dash: nil, color: UIColor(JPalette.shot)); arrow(cg, r, color: UIColor(JPalette.shot)) }),
        ]
        var x = origin.x
        for (label, glyph) in items {
            let r = CGRect(x: x, y: origin.y + 1, width: 20, height: 7)
            cg.saveGState()
            glyph(cg, r)
            cg.restoreGState()
            let w = ceil(NSAttributedString(string: label, attributes: attributes(Font.footer, color: .label)).size().width)
            draw(label, Font.footer, color: .secondaryLabel, at: CGPoint(x: x + 24, y: origin.y), width: w + 2, maxLines: 1)
            x += 24 + w + 14
        }
        if sheet.focus != nil {
            let r = CGRect(x: x, y: origin.y + 1, width: 20, height: 7)
            cg.saveGState()
            line(cg, r, dash: nil, color: UIColor(PlayFocusStyle.color), width: 1.8)
            cg.restoreGState()
            let label = zh ? "你的路线" : "Your moves"
            draw(label, Font.footer, color: .secondaryLabel, at: CGPoint(x: x + 24, y: origin.y), width: 80, maxLines: 1)
        }
    }

    private static func line(_ cg: CGContext, _ r: CGRect, dash: [CGFloat]?, color: UIColor = .label, width: CGFloat = 0.9) {
        cg.setStrokeColor(light(color))
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        if let dash { cg.setLineDash(phase: 0, lengths: dash) }
        cg.move(to: CGPoint(x: r.minX, y: r.midY))
        cg.addLine(to: CGPoint(x: r.maxX - 3, y: r.midY))
        cg.strokePath()
        cg.setLineDash(phase: 0, lengths: [])
    }

    private static func arrow(_ cg: CGContext, _ r: CGRect, color: UIColor = .label) {
        cg.setFillColor(light(color))
        cg.move(to: CGPoint(x: r.maxX, y: r.midY))
        cg.addLine(to: CGPoint(x: r.maxX - 4, y: r.midY - 2.4))
        cg.addLine(to: CGPoint(x: r.maxX - 4, y: r.midY + 2.4))
        cg.closePath()
        cg.fillPath()
    }

    private static func zigzag(_ cg: CGContext, _ r: CGRect) {
        cg.setStrokeColor(light(.label))
        cg.setLineWidth(0.9)
        cg.setLineJoin(.round)
        cg.move(to: CGPoint(x: r.minX, y: r.midY))
        var x = r.minX
        var up = true
        while x < r.maxX - 6 {
            x += 2
            cg.addLine(to: CGPoint(x: x, y: r.midY + (up ? -2 : 2)))
            up.toggle()
        }
        cg.addLine(to: CGPoint(x: r.maxX - 3, y: r.midY))
        cg.strokePath()
    }

    private static func handoff(_ cg: CGContext, _ r: CGRect) {
        cg.setStrokeColor(light(.label))
        cg.setLineWidth(0.9)
        cg.move(to: CGPoint(x: r.minX, y: r.midY)); cg.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        for dx in [r.maxX - 7, r.maxX - 4] {
            cg.move(to: CGPoint(x: dx, y: r.minY - 0.5)); cg.addLine(to: CGPoint(x: dx, y: r.maxY + 0.5))
        }
        cg.strokePath()
    }

    private static func screen(_ cg: CGContext, _ r: CGRect) {
        cg.setStrokeColor(light(.label))
        cg.setLineWidth(1)
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: r.minX, y: r.midY)); cg.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
        cg.move(to: CGPoint(x: r.maxX - 1, y: r.minY - 1)); cg.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY + 1))
        cg.strokePath()
    }

    /// A colour as it prints: the light appearance's.
    private static func light(_ color: UIColor) -> CGColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
    }

    private static func lightUI(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    // MARK: - Text

    private enum Font {
        static let eyebrow = UIFont.systemFont(ofSize: 8, weight: .semibold)
        static let title = UIFont.systemFont(ofSize: 22, weight: .bold)
        static let heading = UIFont.systemFont(ofSize: 16, weight: .bold)
        static let meta = UIFont.systemFont(ofSize: 10, weight: .medium)
        static let label = UIFont.systemFont(ofSize: 9.5, weight: .semibold)
        static let body = UIFont.systemFont(ofSize: 9, weight: .regular)
        static let cellTitle = UIFont.systemFont(ofSize: 10, weight: .semibold)
        static let job = UIFont.systemFont(ofSize: 9, weight: .medium)
        static let jobLabel = UIFont.systemFont(ofSize: 9, weight: .bold)
        static let badge = UIFont.systemFont(ofSize: 8, weight: .bold)
        static let footer = UIFont.systemFont(ofSize: 8, weight: .regular)
    }

    private static func attributes(_ font: UIFont, color: UIColor, alignment: NSTextAlignment = .left, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = alignment
        style.lineHeightMultiple = 1.08
        // Print in light colours whatever the app's appearance.
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolved, .paragraphStyle: style]
        if kern != 0 { a[.kern] = kern }
        return a
    }

    private static func measure(_ text: String, _ font: UIFont, width: CGFloat, maxLines: Int) -> CGFloat {
        measure(NSAttributedString(string: text, attributes: attributes(font, color: .label)), width: width, maxLines: maxLines)
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat, maxLines: Int) -> CGFloat {
        let font = (text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont) ?? Font.body
        let cap = ceil(font.lineHeight * 1.08 * CGFloat(maxLines)) + 1
        let h = ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
        return min(h, cap)
    }

    private static func draw(_ text: String, _ font: UIFont, color: UIColor, at point: CGPoint, width: CGFloat,
                             maxLines: Int, alignment: NSTextAlignment = .left, kern: CGFloat = 0) {
        let s = NSAttributedString(string: text, attributes: attributes(font, color: color, alignment: alignment, kern: kern))
        _ = draw(s, at: point, width: width, maxLines: maxLines)
    }

    @discardableResult
    private static func draw(_ text: NSAttributedString, at point: CGPoint, width: CGFloat, maxLines: Int) -> CGFloat {
        let h = measure(text, width: width, maxLines: maxLines)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        text.draw(with: CGRect(x: point.x, y: point.y, width: width, height: h), options: options, context: nil)
        return h
    }
}
