import Foundation
import CoreGraphics
import CoreText

/// Bilingual attendance and account statement for ONE student and ONE contract.
///
/// Scope is deliberately narrow. A statement goes to a client's phone, so it
/// must never contain a second family's names, rates, or balances — there is no
/// multi-student variant and there should not be one.
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
        var durationMinutes: Int
        var venue: String?
        var status: Attendance
        /// Whether this session consumed a bundle slot.
        var deductedFromBundle: Bool
        var note: String?

        enum Attendance {
            case present, absent, excused
        }
    }

    struct Input {
        var studentNameZh: String?
        var studentNameEn: String
        /// Figures are copied in as scalars rather than holding a Contract, so
        /// the document layer stays independent of the domain model and can be
        /// rendered and verified without one.
        var pricePerSession: Double
        var bundleSize: Int
        var sessionsConsumed: Int
        var bundleTotal: Double
        var amountPaid: Double
        var amountOwed: Double
        var travelFee: Double
        var travelBasisLabel: String?
        var contractNumberLabel: String
        var coachName: String
        var currencyCode: String
        var statementDate: Date
        /// Nil covers the whole contract.
        var periodStart: Date?
        var periodEnd: Date?
        var sessions: [SessionLine]
        /// Written by the coach. Never generated.
        var coachNote: String?
        var expiryDate: Date?
    }

    // MARK: - Data Resolution

    /// Builds the input from live data.
    ///
    /// The `deductedFromBundle` flag reads `contract.bundleSessionIds`, which is
    /// the array `redeemPrivateAttendance` writes. It is NOT recomputed from
    /// session properties. If the report re-derived consumption it could
    /// disagree with the app about whether a session was used, and a statement
    /// that contradicts the running total is worse than no statement at all.
    @MainActor
    static func makeInput(studentId: UUID,
                          contract: Contract,
                          dataManager: SwiftDataManager,
                          periodStart: Date? = nil,
                          periodEnd: Date? = nil,
                          coachNote: String? = nil) -> Input? {
        guard let student = dataManager.students.first(where: { $0.id == studentId }) else { return nil }

        let redeemed = Set(contract.bundleSessionIds)

        let events = dataManager.sessionEvents
            .filter { event in
                guard event.date >= contract.enrollmentDate else { return false }
                if let programId = contract.programId, event.programId != programId { return false }
                // Include any session the student was rostered for or attended,
                // so absences appear rather than silently vanishing.
                let involved = event.attendeeIds.contains(studentId)
                    || event.actualAttendeeIds.contains(studentId)
                    || event.excusedAbsences.contains(studentId)
                guard involved else { return false }
                if let periodStart, event.date < periodStart { return false }
                if let periodEnd, event.date > periodEnd { return false }
                return true
            }
            .sorted { $0.date < $1.date }

        let lines: [SessionLine] = events.map { event in
            let status: SessionLine.Attendance
            if event.actualAttendeeIds.contains(studentId) {
                status = .present
            } else if event.excusedAbsences.contains(studentId) {
                status = .excused
            } else {
                status = .absent
            }
            return SessionLine(
                date: event.date,
                startTime: event.startTime,
                durationMinutes: event.durationMinutes,
                venue: event.location,
                status: status,
                deductedFromBundle: redeemed.contains(event.id),
                note: event.notes
            )
        }

        return Input(
            studentNameZh: student.chineseName,
            studentNameEn: student.name,
            pricePerSession: contract.pricePerSession,
            bundleSize: contract.bundleSize,
            sessionsConsumed: contract.bundleSessionIds.count,
            bundleTotal: contract.bundleAmount,
            amountPaid: contract.amountPaid,
            amountOwed: contract.sessionAmountOwed,
            travelFee: contract.hasTravelFee ? contract.travelFeeAmount : 0,
            travelBasisLabel: contract.hasTravelFee
                ? (contract.travelFeeBasis == .perContract ? "每份合同 per contract" : "每节课 per session")
                : nil,
            contractNumberLabel: "\(contract.contractNumber)",
            coachName: dataManager.coach.name,
            currencyCode: dataManager.appSettings.currency.currencyCode,
            statementDate: Date(),
            periodStart: periodStart,
            periodEnd: periodEnd,
            sessions: lines,
            coachNote: coachNote,
            expiryDate: nil
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

    // MARK: - Render

    @discardableResult
    static func render(_ input: Input, to url: URL? = nil) throws -> URL {
        let renderer = PDFDocumentRenderer()
        renderer.onPageBegin = { doc, page in
            doc.footer("HoopWise · \(input.studentNameZh ?? input.studentNameEn) · 第 \(page) 页 / Page \(page)")
        }

        let body: (PDFDocumentRenderer) -> Void = { doc in
            drawHeader(doc, input)
            drawSummary(doc, input)
            drawSessions(doc, input)
            drawFooterBlock(doc, input)
        }

        if let url {
            return try renderer.render(to: url, body)
        }
        return try renderer.renderToTemporaryFile(named: filename(for: input), body)
    }

    // MARK: - Sections

    private static func drawHeader(_ doc: PDFDocumentRenderer, _ input: Input) {
        doc.text("出席与账户结算单", style: .title(19))
        doc.text("Attendance & Account Statement", style: .heading(12))
        doc.spacer(8)

        // Chinese name primary, English secondary — the convention the app's
        // displayName already uses for Chinese-reading clients.
        let name: String
        if let zh = input.studentNameZh, !zh.isEmpty {
            name = "\(zh)  ·  \(input.studentNameEn)"
        } else {
            name = input.studentNameEn
        }
        doc.text(name, style: .heading(14))
        doc.spacer(4)

        doc.text("合同编号 Contract No.: \(input.contractNumberLabel)", style: .body())
        doc.text("教练 Coach: \(input.coachName)", style: .body())
        doc.text("结算日期 Statement date: \(dateString(input.statementDate))", style: .body())
        doc.text("统计区间 Period: \(periodString(input))", style: .body())
        doc.spacer(6)
        doc.rule()
        doc.spacer(10)
    }

    private static func drawSummary(_ doc: PDFDocumentRenderer, _ input: Input) {
        let code = input.currencyCode
        let remaining = max(0, input.bundleSize - input.sessionsConsumed)

        doc.text("账户摘要 / Account Summary", style: .heading(12))
        doc.spacer(6)

        var rows: [[String]] = [
            ["单价 Price per session", money(input.pricePerSession, code)],
            ["购买课时 Sessions purchased", "\(input.bundleSize)"],
            ["已消课时 Sessions consumed", "\(input.sessionsConsumed)"],
            ["剩余课时 Sessions remaining", "\(remaining)"],
            ["套餐总额 Bundle total", money(input.bundleTotal, code)],
            ["已付 Paid", money(input.amountPaid, code)],
            ["应付 Owed", money(input.amountOwed, code)]
        ]

        // Travel appears only when set, and never folded into session money.
        if let basis = input.travelBasisLabel {
            rows.append(["交通补贴 Travel fee (\(basis))", money(input.travelFee, code)])
        }

        if let expiry = input.expiryDate {
            rows.append(["有效期至 Valid until", dateString(expiry)])
        }

        doc.table(
            columns: [
                PDFTableColumn(title: "项目 Item", weight: 2.4),
                PDFTableColumn(title: "金额 / 数量 Value", weight: 1.4, alignment: .right)
            ],
            rows: rows)
        doc.spacer(14)
    }

    private static func drawSessions(_ doc: PDFDocumentRenderer, _ input: Input) {
        doc.text("课程明细 / Session Detail", style: .heading(12))
        doc.spacer(6)

        guard !input.sessions.isEmpty else {
            doc.text("此区间内无课程记录。No sessions recorded in this period.",
                     style: .caption())
            doc.spacer(12)
            return
        }

        let rows: [[String]] = input.sessions.enumerated().map { index, line in
            [
                "\(index + 1)",
                dateString(line.date),
                timeString(line.startTime),
                "\(line.durationMinutes) 分 min",
                line.venue ?? "—",
                statusLabel(line.status),
                line.deductedFromBundle ? "是 Yes" : "否 No",
                line.note ?? ""
            ]
        }

        doc.table(
            columns: [
                PDFTableColumn(title: "#", weight: 0.35, alignment: .center),
                PDFTableColumn(title: "日期 Date", weight: 1.1),
                PDFTableColumn(title: "时间 Time", weight: 0.7),
                PDFTableColumn(title: "时长 Dur.", weight: 0.7),
                PDFTableColumn(title: "地点 Venue", weight: 1.3),
                PDFTableColumn(title: "出席 Status", weight: 1.0),
                PDFTableColumn(title: "扣课 Deducted", weight: 0.85, alignment: .center),
                PDFTableColumn(title: "备注 Note", weight: 1.5)
            ],
            rows: rows,
            cellStyle: .body(8.5))
        doc.spacer(12)
    }

    private static func drawFooterBlock(_ doc: PDFDocumentRenderer, _ input: Input) {
        let remaining = max(0, input.bundleSize - input.sessionsConsumed)

        doc.ensureSpace(70)
        doc.rule()
        doc.spacer(8)
        doc.text("截至 \(dateString(input.statementDate))，剩余课时 \(remaining) 节。",
                 style: .heading(11))
        doc.text("Sessions remaining as of \(dateString(input.statementDate)): \(remaining).",
                 style: .body())

        if let note = input.coachNote, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            doc.spacer(10)
            doc.text("教练备注 / Coach's Note", style: .heading(11))
            doc.spacer(4)
            doc.text(note, style: .body())
        }
    }

    // MARK: - Formatting

    private static func statusLabel(_ status: SessionLine.Attendance) -> String {
        switch status {
        case .present: return "出席 Present"
        case .absent:  return "缺席 Absent"
        case .excused: return "请假 Excused"
        }
    }

    /// Formats with the plain currency symbol. `.currency(code:)` alone renders
    /// CNY as "CN¥" outside a Chinese locale, which reads as a foreign currency
    /// to the client the document is addressed to.
    private static func money(_ amount: Double, _ code: String) -> String {
        let symbol: String
        switch code {
        case "CNY": symbol = "¥"
        case "USD": symbol = "$"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        default:    symbol = code + " "
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let number = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return symbol + number
    }

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
