import Foundation
import CoreGraphics
import CoreText

/// Bilingual attendance statement for ONE student and ONE contract — a
/// client-facing one-pager, not an internal ledger.
///
/// Scope is deliberately narrow. A statement goes to a client's phone, so it
/// must never contain a second family's names, rates, or balances — there is no
/// multi-student variant and there should not be one.
///
/// NO MONEY on this document, ever. It states attendance; the agreement and
/// the conversation state price. A currency symbol here turns a calm statement
/// into an invoice.
///
/// Fully vector: no attendance photos, no images of any kind. Beyond keeping
/// the file small enough to send over WeChat, it keeps a minor's photograph out
/// of a document that will be forwarded.
enum AttendanceStatementDocument {

    /// One row of the session table, resolved before rendering so the drawing
    /// code makes no decisions about the data.
    struct SessionLine {
        var date: Date
        var startTime: Date
        var venue: String?
        var note: String?
    }

    struct Input {
        var studentNameZh: String?
        var studentNameEn: String
        /// Figures are copied in as scalars rather than holding a Contract, so
        /// the document layer stays independent of the domain model and can be
        /// rendered and verified without one.
        var bundleSize: Int
        var contractNumberLabel: String
        var coachName: String
        /// Optional contact printed in the footer. Existing Coach field only —
        /// never invented.
        var coachPhone: String?
        var statementDate: Date
        /// Nil covers the whole contract.
        var periodStart: Date?
        var periodEnd: Date?
        /// DEDUCTED sessions only — the rows ARE the consumption record.
        var sessions: [SessionLine]
        /// Written by the coach. Never generated.
        var coachNote: String?

        /// Consumed DERIVES from the rows, always. The table and the summary
        /// number cannot disagree because they are the same thing.
        var sessionsConsumed: Int { sessions.count }
        var sessionsRemaining: Int { max(0, bundleSize - sessionsConsumed) }
    }

    // MARK: - Data Resolution

    /// Builds the input from live data.
    ///
    /// The session rows ARE `contract.bundleSessionIds` — the array
    /// `redeemPrivateAttendance` writes — resolved to their events. Nothing is
    /// recomputed from attendance arrays, and the consumed count derives from
    /// these rows, so the statement can never contradict itself: rows shown =
    /// sessions consumed, by construction. (The stored counter and the rows
    /// could historically drift apart; the document sides with the rows it
    /// prints.)
    @MainActor
    static func makeInput(studentId: UUID,
                          contract: Contract,
                          dataManager: SwiftDataManager,
                          periodStart: Date? = nil,
                          periodEnd: Date? = nil,
                          coachNote: String? = nil) -> Input? {
        guard let student = dataManager.students.first(where: { $0.id == studentId }) else { return nil }

        let lines: [SessionLine] = contract.bundleSessionIds
            .compactMap { id in dataManager.sessionEvents.first(where: { $0.id == id }) }
            .filter { event in
                if let periodStart, event.date < periodStart { return false }
                if let periodEnd, event.date > periodEnd { return false }
                return true
            }
            .sorted { $0.date < $1.date }
            .map { event in
                SessionLine(date: event.date,
                            startTime: event.startTime,
                            venue: event.location,
                            note: event.notes)
            }

        return Input(
            studentNameZh: student.chineseName,
            studentNameEn: student.name,
            bundleSize: contract.bundleSize,
            contractNumberLabel: "\(contract.contractNumber)",
            coachName: dataManager.coach.name,
            coachPhone: dataManager.coach.phone?.isEmpty == false ? dataManager.coach.phone : nil,
            statementDate: Date(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessions: lines,
            coachNote: coachNote
        )
    }

    // MARK: - Filename

    /// `Attendance_<name>_Contract<N>_<yyyy-MM-dd>.pdf`
    ///
    /// Student name first so a folder sorts by family, contract number so
    /// successive bundles stay distinct, and an ISO date so versions of the
    /// same statement sort chronologically.
    static func filename(for input: Input) -> String {
        let name = (input.studentNameZh ?? input.studentNameEn)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "Attendance_\(name)_Contract\(input.contractNumberLabel)_\(formatter.string(from: input.statementDate))"
    }

    // MARK: - Palette

    /// Near-black ink and one accent, used exactly twice (wordmark, remaining
    /// number). The document is printed and WeChat-forwarded — everything but
    /// the accent must survive grayscale untouched.
    private static let ink = CGColor(gray: 0.10, alpha: 1)
    private static let secondary = CGColor(gray: 0.45, alpha: 1)
    private static let hairline = CGColor(gray: 0.82, alpha: 1)
    /// The app identity accent (light-mode blue — the dark-mode lime is
    /// illegible on paper).
    private static let accent = CGColor(red: 0, green: 0.478, blue: 1.0, alpha: 1)

    // MARK: - Render

    @discardableResult
    static func render(_ input: Input, to url: URL? = nil) throws -> URL {
        let renderer = PDFDocumentRenderer(margins: PDFMargins(all: 56))
        renderer.onPageBegin = { doc, _ in
            var thanks = "感谢信任 · Thank you for training with us"
            if let phone = input.coachPhone {
                thanks += " · \(input.coachName) \(phone)"
            }
            var style = PDFTextStyle(font: PDFFont.bilingual(size: 8),
                                     color: secondary)
            style.alignment = .center
            doc.footer(thanks, style: style)
        }

        let body: (PDFDocumentRenderer) -> Void = { doc in
            drawHeader(doc, input)
            drawSummaryStrip(doc, input)
            drawSessionTable(doc, input)
            drawClosing(doc, input)
        }

        if let url {
            return try renderer.render(to: url, body)
        }
        return try renderer.renderToTemporaryFile(named: filename(for: input), body)
    }

    // MARK: - Header

    private static func drawHeader(_ doc: PDFDocumentRenderer, _ input: Input) {
        // Wordmark left, document kind right — one quiet band.
        let wordmark = PDFTextStyle(font: PDFFont.bilingual(size: 9, bold: true),
                                    color: accent)
        var kind = PDFTextStyle(font: PDFFont.bilingual(size: 9), color: secondary)
        kind.alignment = .right
        let band = doc.reserve(height: 14)
        drawInRect(doc, band, "HOOPWISE", wordmark)
        drawInRect(doc, band, "出勤结算单 · Attendance Statement", kind)

        doc.spacer(22)

        // The student is the hero.
        let name: String
        if let zh = input.studentNameZh, !zh.isEmpty, zh != input.studentNameEn {
            name = "\(zh) · \(input.studentNameEn)"
        } else {
            name = input.studentNameEn
        }
        doc.text(name, style: PDFTextStyle(font: PDFFont.bilingual(size: 28, bold: true),
                                           color: ink, lineSpacing: 4))
        doc.spacer(8)

        // Metadata in one quiet line, not a form-field stack.
        let meta = [
            "教练 Coach \(input.coachName)",
            "合同 Contract No. \(input.contractNumberLabel)",
            "结算日期 Date \(dateString(input.statementDate))",
            "区间 Period \(periodString(input))"
        ].joined(separator: "   ·   ")
        doc.text(meta, style: PDFTextStyle(font: PDFFont.bilingual(size: 8),
                                           color: secondary, lineSpacing: 3))
        doc.spacer(20)
    }

    // MARK: - Summary strip

    private static func drawSummaryStrip(_ doc: PDFDocumentRenderer, _ input: Input) {
        doc.rule(color: hairline, width: 0.5)
        doc.spacer(14)

        let band = doc.reserve(height: 48)
        let third = band.width / 3

        let stats: [(String, String, CGColor)] = [
            ("\(input.bundleSize)", "购买 Purchased", ink),
            ("\(input.sessionsConsumed)", "已消 Consumed", ink),
            ("\(input.sessionsRemaining)", "剩余 Remaining", accent)
        ]
        for (index, stat) in stats.enumerated() {
            let x = band.minX + third * CGFloat(index)
            var number = PDFTextStyle(font: PDFFont.bilingual(size: 22, bold: true),
                                      color: stat.2)
            number.alignment = .center
            var label = PDFTextStyle(font: PDFFont.bilingual(size: 8), color: secondary)
            label.alignment = .center
            // CTFrame drops a line whose height doesn't FULLY fit the box —
            // a 22pt line needs comfortably more than its point size.
            drawInRect(doc, CGRect(x: x, y: band.minY, width: third, height: 32),
                       stat.0, number)
            drawInRect(doc, CGRect(x: x, y: band.minY + 34, width: third, height: 12),
                       stat.1, label)
        }

        doc.spacer(14)
        doc.rule(color: hairline, width: 0.5)
        doc.spacer(22)
    }

    // MARK: - Session table

    /// Column widths as fractions of the content width:
    /// # · 日期 Date · 时间 Time · 地点 Venue · 备注 Note
    private static let columnFractions: [CGFloat] = [0.055, 0.185, 0.115, 0.365, 0.28]

    private static func drawSessionTable(_ doc: PDFDocumentRenderer, _ input: Input) {
        guard !input.sessions.isEmpty else {
            doc.text("此区间内无已消课时。No sessions consumed in this period.",
                     style: PDFTextStyle(font: PDFFont.bilingual(size: 9.5),
                                         color: secondary))
            doc.spacer(12)
            return
        }

        // Comfortable ~7mm rows; tighten slightly past 12 rows so ~16 still
        // fit one page. Never below legibility — past what fits, page 2
        // continues the table with a repeated header.
        let rowHeight: CGFloat = input.sessions.count > 12 ? 17.5 : 20
        let cellStyle = PDFTextStyle(font: PDFFont.bilingual(size: 9.5),
                                     color: ink, lineSpacing: 1.5)
        let noteStyle = PDFTextStyle(font: PDFFont.bilingual(size: 8.5),
                                     color: ink, lineSpacing: 1.5)

        drawTableHeader(doc)

        for (index, line) in input.sessions.enumerated() {
            let widths = columnFractions.map { $0 * doc.contentWidth }

            // Note wraps to at most two lines; the row grows to hold them.
            let note = line.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let noteWidth = widths[4] - 8
            let noteHeight = note.isEmpty ? 0 : doc.measure(note, style: noteStyle, width: noteWidth).height
            let twoLines = doc.measure("字\n字", style: noteStyle, width: noteWidth).height
            let effectiveNoteHeight = min(noteHeight, twoLines)
            let height = max(rowHeight, effectiveNoteHeight + 8)

            // Keep the closing block off a lonely page: break early enough
            // that at least the row fits above the bottom margin.
            if height + 4 > doc.remainingHeight {
                doc.newPage()
                drawTableHeader(doc)
            }

            let band = doc.reserve(height: height)
            var x = band.minX
            let values = [
                "\(index + 1)",
                dateString(line.date),
                timeString(line.startTime),
                middleTruncated(line.venue?.isEmpty == false ? line.venue! : "—",
                                style: cellStyle, width: widths[3] - 8, doc: doc),
                note
            ]
            for (column, width) in widths.enumerated() {
                var style = column == 4 ? noteStyle : cellStyle
                style.alignment = column == 0 ? .center : .left
                let single = doc.measure("字", style: style, width: 1000).height
                let contentHeight = column == 4 ? min(max(single, effectiveNoteHeight), height - 4) : single
                let y = band.minY + (height - contentHeight) / 2
                drawInRect(doc, CGRect(x: x + 4, y: y, width: width - 8,
                                       height: contentHeight),
                           values[column], style)
                x += width
            }
            hairlineAt(doc, y: band.maxY)
        }
        doc.spacer(4)
    }

    private static func drawTableHeader(_ doc: PDFDocumentRenderer) {
        let titles = ["#", "日期 Date", "时间 Time", "地点 Venue", "备注 Note"]
        var style = PDFTextStyle(font: PDFFont.bilingual(size: 8, bold: true),
                                 color: secondary)
        let band = doc.reserve(height: 18)
        var x = band.minX
        for (index, fraction) in columnFractions.enumerated() {
            let width = fraction * doc.contentWidth
            style.alignment = index == 0 ? .center : .left
            drawInRect(doc, CGRect(x: x + 4, y: band.minY + 4,
                                   width: width - 8, height: 12),
                       titles[index], style)
            x += width
        }
        hairlineAt(doc, y: band.maxY)
    }

    // MARK: - Closing

    private static func drawClosing(_ doc: PDFDocumentRenderer, _ input: Input) {
        doc.ensureSpace(64)
        doc.spacer(18)
        doc.text("截至 \(dateString(input.statementDate))，剩余课时 \(input.sessionsRemaining) 节。",
                 style: PDFTextStyle(font: PDFFont.bilingual(size: 11, bold: true),
                                     color: ink, lineSpacing: 3))
        doc.spacer(2)
        doc.text("Sessions remaining as of \(dateString(input.statementDate)): \(input.sessionsRemaining).",
                 style: PDFTextStyle(font: PDFFont.bilingual(size: 9.5),
                                     color: secondary, lineSpacing: 3))

        if let note = input.coachNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            doc.spacer(12)
            doc.text("教练备注 / Coach's Note", style: PDFTextStyle(
                font: PDFFont.bilingual(size: 9.5, bold: true), color: ink))
            doc.spacer(3)
            doc.text(note, style: PDFTextStyle(font: PDFFont.bilingual(size: 9.5),
                                               color: ink, lineSpacing: 2))
        }
    }

    // MARK: - Drawing helpers

    /// Cursor-space rect (what `reserve` hands out: y measured from the top
    /// content edge) → the renderer's bottom-up page space.
    private static func drawInRect(_ doc: PDFDocumentRenderer, _ rect: CGRect,
                                   _ string: String, _ style: PDFTextStyle) {
        let pdfY = doc.pageSize.height - doc.margins.top - rect.minY - rect.height
        doc.drawText(string, style: style,
                     in: CGRect(x: rect.minX, y: pdfY,
                                width: rect.width, height: rect.height))
    }

    /// A full-width hairline at a cursor-space y, independent of the cursor.
    private static func hairlineAt(_ doc: PDFDocumentRenderer, y: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0.25))
        path.addLine(to: CGPoint(x: doc.contentWidth, y: 0.25))
        doc.draw(path: path,
                 in: CGRect(x: doc.margins.left, y: y - 0.5,
                            width: doc.contentWidth, height: 0.5),
                 stroke: hairline, lineWidth: 0.5)
    }

    /// Middle truncation for one-line cells: the venue keeps its head and tail
    /// (义蓬…中心) instead of wrapping or losing its distinguishing end.
    private static func middleTruncated(_ string: String, style: PDFTextStyle,
                                        width: CGFloat, doc: PDFDocumentRenderer) -> String {
        guard doc.measure(string, style: style, width: 10_000).width > width else { return string }
        let characters = Array(string)
        // Keep head and tail, shrinking symmetrically until "head…tail" fits.
        for keep in stride(from: characters.count - 1, through: 2, by: -1) {
            let front = (keep + 1) / 2
            let back = keep - front
            let candidate = String(characters.prefix(front)) + "…" + String(characters.suffix(back))
            if doc.measure(candidate, style: style, width: 10_000).width <= width {
                return candidate
            }
        }
        return String(characters.prefix(1)) + "…"
    }

    // MARK: - Formatting

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func periodString(_ input: Input) -> String {
        switch (input.periodStart, input.periodEnd) {
        case let (start?, end?):
            return "\(dateString(start)) – \(dateString(end))"
        case let (start?, nil):
            return "\(dateString(start)) – \(dateString(input.statementDate))"
        case let (nil, end?):
            return "– \(dateString(end))"
        case (nil, nil):
            return "全部合同期间 Entire contract"
        }
    }
}
