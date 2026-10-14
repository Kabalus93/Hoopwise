import Foundation
import CoreGraphics
import CoreText
import ImageIO

// MARK: - Coach-written wording (device-local)

/// The parent-facing words a coach adds on top of the program's own data.
///
/// DEVICE-LOCAL by decision: stored in UserDefaults on the device that wrote
/// them, not in CloudKit. Syncing them would need new schema fields, and
/// schema changes need explicit approval (CLAUDE.md rule 5).
///
/// EMPTY MEANS SILENT. Every field here is optional prose; the guide omits a
/// section rather than printing text nobody wrote. Overrides (purpose, phase
/// titles and summaries) fall back to the program's own data when empty.
struct ProgramGuideNotes: Codable, Equatable {
    var purpose: String = ""
    /// Keyed by phase id (uuidString).
    var phaseTitles: [String: String] = [:]
    /// Keyed by phase id (uuidString).
    var phaseSummaries: [String: String] = [:]
    var sessionNote: String = ""
    var reviewNote: String = ""
    var coachNote: String = ""
    var homeActivity: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case purpose, phaseTitles, phaseSummaries, sessionNote, reviewNote, coachNote, homeActivity
    }

    /// Tolerant decode: a field added later must not wipe what a coach wrote.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        phaseTitles = try c.decodeIfPresent([String: String].self, forKey: .phaseTitles) ?? [:]
        phaseSummaries = try c.decodeIfPresent([String: String].self, forKey: .phaseSummaries) ?? [:]
        sessionNote = try c.decodeIfPresent(String.self, forKey: .sessionNote) ?? ""
        reviewNote = try c.decodeIfPresent(String.self, forKey: .reviewNote) ?? ""
        coachNote = try c.decodeIfPresent(String.self, forKey: .coachNote) ?? ""
        homeActivity = try c.decodeIfPresent(String.self, forKey: .homeActivity) ?? ""
    }
}

/// UserDefaults-backed storage for `ProgramGuideNotes` and the academy name.
enum ProgramGuideStore {
    private static let notesKey = "programGuide.notes.v1"
    private static let academyKey = "programGuide.academyName"

    static func notes(for programId: UUID) -> ProgramGuideNotes {
        loadAll()[programId.uuidString] ?? ProgramGuideNotes()
    }

    static func save(_ notes: ProgramGuideNotes, for programId: UUID) {
        var all = loadAll()
        all[programId.uuidString] = notes
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
    }

    /// The academy's name as it should appear on documents. There is no
    /// organization-name field in the data model; until there is, the coach
    /// types it once here. Empty falls back to the coach's name.
    static var academyName: String {
        get { UserDefaults.standard.string(forKey: academyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: academyKey) }
    }

    private static func loadAll() -> [String: ProgramGuideNotes] {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let all = try? JSONDecoder().decode([String: ProgramGuideNotes].self, from: data)
        else { return [:] }
        return all
    }
}

enum ProgramGuideError: LocalizedError {
    case imageFailed

    var errorDescription: String? {
        switch self {
        case .imageFailed: return "Could not create the long image."
        }
    }
}

// MARK: - The document

/// Parent-facing program guide: what a child will practise, why, in what
/// order, and how the coach will communicate — rendered from the program's
/// own structured data.
///
/// Two outputs from ONE composition: an A4 PDF (paginated, selectable vector
/// text) and a long single-column JPEG for WeChat. The long image is the same
/// drawing code on one tall page, sized by a measuring pass, then rasterized.
///
/// Rules, same family as the attendance statement and the agreement:
/// - Nothing invented. Sections whose data is missing are omitted, never
///   filled with plausible text. Coach-written fields are printed verbatim.
/// - Goals are labelled as goals. The guide states plainly that they describe
///   what the program teaches, not what a child has achieved.
/// - No money, no photos, no other families' names.
/// - The academy (or coach) is the identity; Hoopwise is a footer credit.
enum ProgramGuideDocument {

    struct Activity: Equatable {
        var name: String
        var purpose: String?
    }

    struct Phase {
        var number: Int
        var title: String
        /// True when the title is a placeholder like "Phase 1" and the coach
        /// has not overridden it. Drives the "make it specific" hint.
        var isGenericTitle: Bool
        var start: Date?
        var end: Date?
        var weeks: Int
        var focus: [String]
        var summary: String?
        var objectives: [String]
        var activities: [Activity]
    }

    struct SessionBlock {
        var label: String
        var minutes: Int
        var activities: [String]
    }

    struct Checkpoint {
        var date: Date
        var label: String
    }

    /// Everything the drawing code needs, resolved up front so the renderer
    /// makes no decisions about data.
    struct Input {
        var isChinese: Bool
        /// Academy name, else the coach's name.
        var identity: String
        var programName: String
        var subtitle: String
        var coachName: String?
        var coachPhone: String?
        var startDate: Date?
        var endDate: Date?
        var schedule: String?
        var venue: String?
        var weeks: Int
        var sessionsPerWeek: Int
        var purpose: String?
        var programGoals: [String]
        var phases: [Phase]
        var sessionBlocks: [SessionBlock]
        /// The planned session the breakdown was read from, printed so the
        /// parent knows it is a real plan, not a template.
        var sessionSampleDate: Date?
        var sessionNote: String?
        var checkpoints: [Checkpoint]
        var reviewNote: String?
        var coachNote: String?
        var homeActivity: String?
        var issued: Date
    }

    // MARK: - Data resolution

    @MainActor
    static func makeInput(program: Program,
                          dataManager: SwiftDataManager,
                          notes: ProgramGuideNotes,
                          academyName: String,
                          isChinese: Bool,
                          now: Date = Date()) -> Input {
        // Coach: the program's assigned coach first, else the account's own.
        var coachName: String?
        var coachPhone: String?
        if let coachId = program.coachId,
           let staff = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
            if isChinese, let zh = clean(staff.chineseName) {
                coachName = zh
            } else {
                coachName = clean(staff.name)
            }
            coachPhone = clean(staff.phone)
        } else {
            coachName = clean(dataManager.coach.name)
            coachPhone = clean(dataManager.coach.phone)
        }

        let identity = clean(academyName) ?? coachName ?? "Hoopwise"

        let drillsById = Dictionary(dataManager.drills.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let programSessions = dataManager.sessionEvents.filter { $0.programId == program.id }

        // Phases, in order, with dates. A phase without stored dates is
        // placed after the previous one, starting from the program start.
        let programPhases = dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }

        var runningStart: Date? = program.startDate
        var phases: [Phase] = []
        for phase in programPhases {
            let key = phase.id.uuidString
            let start: Date? = phase.startDate ?? runningStart
            var end: Date? = phase.endDate
            if end == nil, let start {
                end = Calendar.current.date(byAdding: .day,
                                            value: max(1, phase.durationWeeks) * 7 - 1,
                                            to: start)
            }
            if let end {
                runningStart = Calendar.current.date(byAdding: .day, value: 1, to: end)
            }

            let overrideTitle = clean(notes.phaseTitles[key])
            let storedTitle = clean(phase.title) ?? (isChinese ? "第\(phase.phaseNumber)阶段" : "Phase \(phase.phaseNumber)")
            phases.append(Phase(
                number: phase.phaseNumber,
                title: overrideTitle ?? storedTitle,
                isGenericTitle: overrideTitle == nil && isGenericTitle(storedTitle),
                start: start,
                end: end,
                weeks: phase.durationWeeks,
                focus: phase.focus.map { focusName($0, isChinese: isChinese) },
                summary: clean(notes.phaseSummaries[key]) ?? clean(phase.description),
                objectives: phase.objectives.compactMap { clean($0) },
                activities: activities(for: phase, sessions: programSessions, drills: drillsById)))
        }

        // A typical session, read from a real planned session: the next one
        // with a plan, else the most recent. No plan anywhere → no section.
        let planned = programSessions.filter {
            $0.curriculum.totalDrillCount > 0 && !SessionLifecycle.didNotHappen($0)
        }
        let upcoming = planned.filter { $0.startTime >= now }.min { $0.startTime < $1.startTime }
        let recent = planned.filter { $0.startTime < now }.max { $0.startTime < $1.startTime }
        var blocks: [SessionBlock] = []
        let sample = upcoming ?? recent
        if let sample {
            let plan = sample.curriculum
            let parts: [(zh: String, en: String, minutes: Int, drills: [UUID])] = [
                ("热身", "Warm-up", plan.warmupMinutes, plan.warmupDrillIds),
                ("技能", "Skills", plan.skillsMinutes, plan.skillDrillIds),
                ("比赛", "Game", plan.gameMinutes, plan.gameDrillIds)
            ]
            for part in parts where part.minutes > 0 || !part.drills.isEmpty {
                let names = part.drills.prefix(3).compactMap { drillsById[$0]?.localizedName }
                blocks.append(SessionBlock(label: isChinese ? part.zh : part.en,
                                           minutes: part.minutes,
                                           activities: names))
            }
        }

        // Checkpoints are FACTS from the plan: when each phase ends.
        let checkpoints: [Checkpoint] = phases.compactMap { phase in
            guard let end = phase.end else { return nil }
            let label = isChinese
                ? "第\(phase.number)阶段结束 · \(phase.title)"
                : "End of phase \(phase.number) · \(phase.title)"
            return Checkpoint(date: end, label: label)
        }

        // Practical schedule.
        let days = program.recurringDays.sorted { $0.rawValue < $1.rawValue }
        var schedule: String?
        if !days.isEmpty {
            let dayNames = days.map { weekdayName($0, isChinese: isChinese) }
                .joined(separator: isChinese ? "、" : ", ")
            if let time = program.defaultSessionTime {
                let endTime = time.addingTimeInterval(TimeInterval(program.defaultSessionDurationMinutes * 60))
                schedule = "\(dayNames) · \(timeString(time))–\(timeString(endTime))"
            } else {
                schedule = dayNames
            }
        }

        let age = isChinese ? program.ageGroup.rawValue : program.ageGroup.displayName
        let subtitle = "\(age) · \(programTypeName(program.programType, isChinese: isChinese))"

        return Input(
            isChinese: isChinese,
            identity: identity,
            programName: clean(program.name) ?? "—",
            subtitle: subtitle,
            coachName: coachName,
            coachPhone: coachPhone,
            startDate: program.startDate,
            endDate: program.endDate ?? phases.last?.end,
            schedule: schedule,
            venue: clean(program.locationName),
            weeks: program.durationWeeks,
            sessionsPerWeek: program.recurringDays.count,
            purpose: clean(notes.purpose) ?? clean(program.description),
            programGoals: program.objectives.compactMap { clean($0) },
            phases: phases,
            sessionBlocks: blocks,
            sessionSampleDate: blocks.isEmpty ? nil : sample?.startTime,
            sessionNote: clean(notes.sessionNote),
            checkpoints: checkpoints,
            reviewNote: clean(notes.reviewNote),
            coachNote: clean(notes.coachNote),
            homeActivity: clean(notes.homeActivity),
            issued: now)
    }

    /// What is still generic or missing, in the coach's language, so the
    /// preview can say what would make the guide specific.
    static func gaps(in input: Input) -> [String] {
        let zh = input.isChinese
        var gaps: [String] = []
        let generic = input.phases.filter(\.isGenericTitle).count
        if generic > 0 {
            gaps.append(zh ? "\(generic) 个阶段仍是通用名称" : "\(generic) phase\(generic == 1 ? " still has a" : "s still have") generic name\(generic == 1 ? "" : "s")")
        }
        let noSummary = input.phases.filter { $0.summary == nil }.count
        if noSummary > 0 {
            gaps.append(zh ? "\(noSummary) 个阶段没有说明" : "\(noSummary) phase\(noSummary == 1 ? " has" : "s have") no description")
        }
        if input.purpose == nil {
            gaps.append(zh ? "缺少计划简介" : "No program introduction")
        }
        if input.phases.isEmpty {
            gaps.append(zh ? "计划还没有阶段" : "The program has no phases yet")
        }
        return gaps
    }

    /// `ProgramGuide_<name>_<yyyy-MM-dd>`
    static func filename(for input: Input) -> String {
        let name = input.programName
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "ProgramGuide_\(name)_\(formatter.string(from: input.issued))"
    }

    // MARK: - Layout

    struct Layout {
        var pageSize: CGSize
        var margins: PDFMargins
        /// Type and spacing multiplier. The phone image is read at roughly
        /// its own width on a phone, so it needs larger type than A4.
        var scale: CGFloat

        static let a4 = Layout(pageSize: PDFPageSize.a4,
                               margins: PDFMargins(top: 54, left: 56, bottom: 66, right: 56),
                               scale: 1)

        static func phone(height: CGFloat) -> Layout {
            Layout(pageSize: CGSize(width: 414, height: height),
                   margins: PDFMargins(top: 34, left: 26, bottom: 54, right: 26),
                   scale: 1.18)
        }
    }

    // MARK: - Palette

    /// White page, near-black ink, ONE accent (the Hoopwise blue) used for
    /// structure only: the title rule, phase markers and the timeline.
    private static let ink = CGColor(gray: 0.11, alpha: 1)
    private static let secondary = CGColor(gray: 0.42, alpha: 1)
    private static let ruleColor = CGColor(gray: 0.86, alpha: 1)
    private static let panelFill = CGColor(gray: 0.965, alpha: 1)
    private static let white = CGColor(gray: 1, alpha: 1)
    private static let accent = CGColor(red: 0, green: 0.478, blue: 1.0, alpha: 1)

    // MARK: - Render

    /// A4, paginated, vector text.
    @discardableResult
    static func renderPDF(_ input: Input, to url: URL? = nil) throws -> URL {
        let layout = Layout.a4
        let renderer = PDFDocumentRenderer(pageSize: layout.pageSize, margins: layout.margins)
        renderer.onPageBegin = { doc, page in
            drawFooter(doc, input, layout, page: page)
        }
        let body: (PDFDocumentRenderer) -> Void = { doc in
            compose(doc, input, layout)
        }
        if let url {
            return try renderer.render(to: url, body)
        }
        return try renderer.renderToTemporaryFile(named: filename(for: input), body)
    }

    /// One long single-column JPEG for WeChat. Pass 1 measures the content on
    /// a tall scratch page; pass 2 draws it on a page exactly that tall; the
    /// page is then rasterized.
    static func renderLongImage(_ input: Input) throws -> URL {
        let temp = FileManager.default.temporaryDirectory

        let probeLayout = Layout.phone(height: 14_400)
        let probe = PDFDocumentRenderer(pageSize: probeLayout.pageSize, margins: probeLayout.margins)
        var used: CGFloat = 0
        var pages = 1
        let probeURL = temp.appendingPathComponent("program-guide-probe.pdf")
        try probe.render(to: probeURL) { doc in
            compose(doc, input, probeLayout)
            used = doc.cursorPosition
            pages = doc.currentPage
        }
        try? FileManager.default.removeItem(at: probeURL)

        let probeContentHeight = probeLayout.pageSize.height
            - probeLayout.margins.top - probeLayout.margins.bottom
        let contentHeight = CGFloat(pages - 1) * probeContentHeight + used
        let base = Layout.phone(height: 100)
        let layout = Layout.phone(height: ceil(contentHeight) + base.margins.top + base.margins.bottom + 8)

        let renderer = PDFDocumentRenderer(pageSize: layout.pageSize, margins: layout.margins)
        renderer.onPageBegin = { doc, _ in
            drawFooter(doc, input, layout, page: nil)
        }
        let pdfURL = temp.appendingPathComponent("program-guide-long.pdf")
        try renderer.render(to: pdfURL) { doc in
            compose(doc, input, layout)
        }

        let imageURL = temp.appendingPathComponent(filename(for: input) + ".jpg")
        let result = try rasterize(pdfURL: pdfURL, to: imageURL)
        try? FileManager.default.removeItem(at: pdfURL)
        return result
    }

    private static func rasterize(pdfURL: URL, to outURL: URL) throws -> URL {
        guard let document = CGPDFDocument(pdfURL as CFURL),
              let page = document.page(at: 1) else { throw ProgramGuideError.imageFailed }
        let box = page.getBoxRect(.mediaBox)
        // ~2.6x for crisp text, capped so a very long program cannot ask
        // for a bitmap the phone cannot allocate.
        let maxPixels: CGFloat = 36_000_000
        let scale = min(2.6, (maxPixels / max(1, box.width * box.height)).squareRoot())
        let width = Int((box.width * scale).rounded(.down))
        let height = Int((box.height * scale).rounded(.down))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ProgramGuideError.imageFailed }

        context.setFillColor(white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        guard let image = context.makeImage() else { throw ProgramGuideError.imageFailed }
        try? FileManager.default.removeItem(at: outURL)
        guard let destination = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                                "public.jpeg" as CFString, 1, nil)
        else { throw ProgramGuideError.imageFailed }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProgramGuideError.imageFailed }
        return outURL
    }

    // MARK: - Composition

    private static func compose(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        drawMasthead(doc, input, layout)
        drawTitle(doc, input, layout)
        drawFacts(doc, input, layout)
        drawPurpose(doc, input, layout)
        if !input.phases.isEmpty {
            drawJourney(doc, input, layout)
            drawPhases(doc, input, layout)
        }
        drawTypicalSession(doc, input, layout)
        drawProgress(doc, input, layout)
        drawCoachNote(doc, input, layout)
        drawHomeActivity(doc, input, layout)
    }

    // MARK: Masthead and title

    private static func drawMasthead(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        let s = layout.scale
        let band = doc.reserve(height: 14 * s)
        drawInRect(doc, CGRect(x: band.minX, y: band.minY, width: band.width * 0.62, height: band.height),
                   input.identity, style(9.5, layout, bold: true))
        drawInRect(doc, band, "训练计划指南 · Program Guide",
                   style(8.5, layout, color: secondary, align: .right))
        doc.spacer(6 * s)
        hairline(doc)
        doc.spacer(28 * s)
    }

    private static func drawTitle(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        let s = layout.scale
        let bar = doc.reserve(height: 3 * s, width: 28 * s)
        fill(doc, bar, accent)
        doc.spacer(12 * s)
        doc.text(input.programName, style: style(26, layout, bold: true, spacing: 4))
        doc.spacer(6 * s)
        doc.text(input.subtitle, style: style(11, layout, color: secondary))
        doc.spacer(22 * s)
    }

    // MARK: Practical facts

    private static func drawFacts(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        let s = layout.scale
        var rows: [(label: String, value: String)] = []
        if let coach = input.coachName { rows.append(("教练 Coach", coach)) }
        if let dates = rangeString(input.startDate, input.endDate, isChinese: input.isChinese) {
            rows.append(("日期 Dates", dates))
        }
        if let schedule = input.schedule { rows.append(("时间 Schedule", schedule)) }
        if let venue = input.venue { rows.append(("地点 Venue", venue)) }
        if let length = lengthLine(input) { rows.append(("周期 Length", length)) }
        guard !rows.isEmpty else { return }

        let pad = 14 * s
        let labelWidth = 86 * s
        let valueWidth = doc.contentWidth - pad * 2 - labelWidth
        let labelStyle = style(8.5, layout, color: secondary)
        let valueStyle = style(10.5, layout)
        let rowGap = 7 * s

        let heights = rows.map { row in
            max(doc.measure(row.value, style: valueStyle, width: valueWidth).height,
                doc.measure(row.label, style: labelStyle, width: labelWidth).height)
        }
        let total = heights.reduce(0, +) + rowGap * CGFloat(rows.count - 1) + pad * 2
        let panel = doc.reserve(height: total)
        fill(doc, panel, panelFill, radius: 8 * s)

        var y = panel.minY + pad
        for (index, row) in rows.enumerated() {
            let height = heights[index]
            drawInRect(doc, CGRect(x: panel.minX + pad, y: y + 1.5 * s, width: labelWidth, height: height),
                       row.label, labelStyle)
            drawInRect(doc, CGRect(x: panel.minX + pad + labelWidth, y: y, width: valueWidth, height: height),
                       row.value, valueStyle)
            y += height + rowGap
        }
        doc.spacer(28 * s)
    }

    // MARK: Purpose

    private static func drawPurpose(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        guard input.purpose != nil || !input.programGoals.isEmpty else { return }
        let s = layout.scale
        sectionHeading(doc, "关于本计划", "About this program", layout)
        if let purpose = input.purpose {
            doc.text(purpose, style: bodyStyle(layout))
            doc.spacer(10 * s)
        }
        if !input.programGoals.isEmpty {
            subLabel(doc, "计划目标", "Program goals", layout)
            for goal in input.programGoals {
                bullet(doc, goal, layout)
            }
        }
        doc.spacer(24 * s)
    }

    // MARK: Journey

    /// The program at a glance: one bar, one segment per phase, width by
    /// length, shade deepening as the program builds.
    private static func drawJourney(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        let s = layout.scale
        let phases = input.phases
        sectionHeading(doc, "训练进程", "How the program builds", layout, minFollowing: 80)

        let totalWeeks = max(1, phases.reduce(0) { $0 + max(1, $1.weeks) })
        let gap = 3 * s
        let usable = doc.contentWidth - gap * CGFloat(phases.count - 1)
        let widths = phases.map { usable * CGFloat(max(1, $0.weeks)) / CGFloat(totalWeeks) }
        let barHeight = 22 * s
        let titleStyle = style(8.5, layout, bold: true)
        let metaStyle = style(7.5, layout, color: secondary)
        let showLabels = widths.allSatisfy { $0 >= 44 * s }

        var labelHeight: CGFloat = 0
        if showLabels {
            for (index, phase) in phases.enumerated() {
                let width = widths[index] - 2
                let titleHeight = doc.measure(phase.title, style: titleStyle, width: width).height
                let metaHeight = rangeString(phase.start, phase.end, isChinese: input.isChinese)
                    .map { doc.measure($0, style: metaStyle, width: width).height } ?? 0
                labelHeight = max(labelHeight, titleHeight + metaHeight + 2 * s)
            }
        }

        let box = doc.reserve(height: barHeight + (showLabels ? 6 * s + labelHeight : 0))
        var x = box.minX
        for (index, phase) in phases.enumerated() {
            let width = widths[index]
            let segment = CGRect(x: x, y: box.minY, width: width, height: barHeight)
            let progress: CGFloat = phases.count > 1 ? CGFloat(index) / CGFloat(phases.count - 1) : 1
            let alpha = 0.22 + 0.78 * progress
            fill(doc, segment, accent.copy(alpha: alpha) ?? accent, radius: 4 * s)

            let numberStyle = style(9.5, layout, bold: true, color: alpha > 0.55 ? white : ink, align: .center)
            let numberHeight = doc.measure("\(phase.number)", style: numberStyle).height
            drawInRect(doc, CGRect(x: segment.minX, y: segment.minY + (barHeight - numberHeight) / 2,
                                   width: width, height: numberHeight),
                       "\(phase.number)", numberStyle)

            if showLabels {
                var labelY = box.minY + barHeight + 6 * s
                let titleHeight = doc.measure(phase.title, style: titleStyle, width: width - 2).height
                drawInRect(doc, CGRect(x: segment.minX + 1, y: labelY, width: width - 2, height: titleHeight),
                           phase.title, titleStyle)
                labelY += titleHeight + 2 * s
                if let range = rangeString(phase.start, phase.end, isChinese: input.isChinese) {
                    let metaHeight = doc.measure(range, style: metaStyle, width: width - 2).height
                    drawInRect(doc, CGRect(x: segment.minX + 1, y: labelY, width: width - 2, height: metaHeight),
                               range, metaStyle)
                }
            }
            x += width + gap
        }
        doc.spacer(28 * s)
    }

    // MARK: Phases

    private static func drawPhases(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        let s = layout.scale
        let isChinese = input.isChinese
        sectionHeading(doc, "训练阶段", "The phases", layout, minFollowing: 90)

        let indent = 34 * s
        let textWidth = doc.contentWidth - indent
        let titleStyle = style(14, layout, bold: true, spacing: 3)
        let metaStyle = style(9, layout, color: secondary)
        let focusStyle = style(9, layout, bold: true, color: accent)
        let numberStyle = style(10, layout, bold: true, color: white, align: .center)

        for (index, phase) in input.phases.enumerated() {
            var metaParts = [isChinese ? "第\(phase.number)阶段" : "Phase \(phase.number)"]
            if let range = rangeString(phase.start, phase.end, isChinese: isChinese) { metaParts.append(range) }
            if phase.weeks > 0 {
                metaParts.append(isChinese ? "\(phase.weeks) 周" : "\(phase.weeks) week\(phase.weeks == 1 ? "" : "s")")
            }
            let meta = metaParts.joined(separator: " · ")
            let focusLine = phase.focus.joined(separator: "  ·  ")

            let titleHeight = doc.measure(phase.title, style: titleStyle, width: textWidth).height
            let metaHeight = doc.measure(meta, style: metaStyle, width: textWidth).height
            let focusHeight = focusLine.isEmpty ? 0 : doc.measure(focusLine, style: focusStyle, width: textWidth).height
            let headerHeight = titleHeight + 3 * s + metaHeight + (focusHeight > 0 ? 4 * s + focusHeight : 0)

            // Keep the header with the start of its description.
            let summaryLead = phase.summary.map {
                min(doc.measure($0, style: bodyStyle(layout), width: textWidth).height, 40 * s)
            } ?? 0
            doc.ensureSpace(headerHeight + 10 * s + summaryLead)

            let header = doc.reserve(height: headerHeight)
            let diameter = 22 * s
            let firstLine = doc.measure("字", style: titleStyle, width: textWidth).height
            let badge = CGRect(x: header.minX, y: header.minY + max(0, (firstLine - diameter) / 2),
                               width: diameter, height: diameter)
            fillCircle(doc, badge, accent)
            let numberHeight = doc.measure("\(phase.number)", style: numberStyle).height
            drawInRect(doc, CGRect(x: badge.minX, y: badge.minY + (diameter - numberHeight) / 2,
                                   width: diameter, height: numberHeight),
                       "\(phase.number)", numberStyle)

            var y = header.minY
            drawInRect(doc, CGRect(x: header.minX + indent, y: y, width: textWidth, height: titleHeight),
                       phase.title, titleStyle)
            y += titleHeight + 3 * s
            drawInRect(doc, CGRect(x: header.minX + indent, y: y, width: textWidth, height: metaHeight),
                       meta, metaStyle)
            y += metaHeight
            if focusHeight > 0 {
                y += 4 * s
                drawInRect(doc, CGRect(x: header.minX + indent, y: y, width: textWidth, height: focusHeight),
                           focusLine, focusStyle)
            }
            doc.spacer(10 * s)

            if let summary = phase.summary {
                doc.text(summary, style: bodyStyle(layout), indent: indent)
                doc.spacer(10 * s)
            }
            if !phase.objectives.isEmpty {
                subLabel(doc, "练习重点", "What your child will practise", layout, indent: indent)
                for objective in phase.objectives {
                    bullet(doc, objective, layout, indent: indent)
                }
                doc.spacer(6 * s)
            }
            if !phase.activities.isEmpty {
                subLabel(doc, "示例活动", "Example activities", layout, indent: indent)
                for activity in phase.activities {
                    let line = activity.purpose.map { "\(activity.name) — \($0)" } ?? activity.name
                    bullet(doc, line, layout, indent: indent)
                }
            }

            if index < input.phases.count - 1 {
                doc.spacer(10 * s)
                hairline(doc, indent: indent)
                doc.spacer(18 * s)
            }
        }

        doc.spacer(16 * s)
        let disclaimer = isChinese
            ? "以上目标描述的是本计划要教的内容，并非孩子已经取得的成绩。"
            : "The goals above describe what the program teaches. They are not a record of what your child has already achieved."
        doc.text(disclaimer, style: style(9, layout, color: secondary))
        doc.spacer(28 * s)
    }

    // MARK: Typical session

    private static func drawTypicalSession(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        guard !input.sessionBlocks.isEmpty || input.sessionNote != nil else { return }
        let s = layout.scale
        let isChinese = input.isChinese
        sectionHeading(doc, "一节课的样子", "A typical session", layout, minFollowing: 80)

        if !input.sessionBlocks.isEmpty {
            let totalMinutes = input.sessionBlocks.reduce(0) { $0 + $1.minutes }
            if totalMinutes > 0 {
                let barHeight = 8 * s
                let box = doc.reserve(height: barHeight)
                let gap = 2 * s
                let usable = box.width - gap * CGFloat(input.sessionBlocks.count - 1)
                var x = box.minX
                for (index, block) in input.sessionBlocks.enumerated() {
                    let width = usable * CGFloat(block.minutes) / CGFloat(totalMinutes)
                    let progress: CGFloat = input.sessionBlocks.count > 1
                        ? CGFloat(index) / CGFloat(input.sessionBlocks.count - 1) : 1
                    fill(doc, CGRect(x: x, y: box.minY, width: width, height: barHeight),
                         accent.copy(alpha: 0.25 + 0.6 * progress) ?? accent, radius: 2 * s)
                    x += width + gap
                }
                doc.spacer(12 * s)
            }

            let labelWidth = 104 * s
            let detailWidth = doc.contentWidth - labelWidth
            let headStyle = style(10, layout, bold: true)
            let detailStyle = style(10, layout, color: secondary)
            for block in input.sessionBlocks {
                let head = isChinese ? "\(block.label) · \(block.minutes) 分钟" : "\(block.label) · \(block.minutes) min"
                let detail = block.activities.joined(separator: isChinese ? "、" : ", ")
                let headHeight = doc.measure(head, style: headStyle, width: labelWidth).height
                let detailHeight = detail.isEmpty ? 0 : doc.measure(detail, style: detailStyle, width: detailWidth).height
                let height = max(headHeight, detailHeight)
                let row = doc.reserve(height: height)
                drawInRect(doc, CGRect(x: row.minX, y: row.minY, width: labelWidth, height: height), head, headStyle)
                if !detail.isEmpty {
                    drawInRect(doc, CGRect(x: row.minX + labelWidth, y: row.minY, width: detailWidth, height: height),
                               detail, detailStyle)
                }
                doc.spacer(6 * s)
            }
            if let date = input.sessionSampleDate {
                let source = isChinese
                    ? "取自 \(dateString(date, isChinese: true)) 的训练计划"
                    : "From the plan for \(dateString(date, isChinese: false))"
                doc.text(source, style: style(8.5, layout, color: secondary))
            }
        }

        if let note = input.sessionNote {
            doc.spacer(10 * s)
            doc.text(note, style: bodyStyle(layout))
        }
        doc.spacer(28 * s)
    }

    // MARK: Progress

    private static func drawProgress(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        guard !input.checkpoints.isEmpty || input.reviewNote != nil else { return }
        let s = layout.scale
        sectionHeading(doc, "进度与反馈", "Progress and feedback", layout, minFollowing: 70)

        if let note = input.reviewNote {
            doc.text(note, style: bodyStyle(layout))
            doc.spacer(12 * s)
        }
        if !input.checkpoints.isEmpty {
            subLabel(doc, "阶段节点", "Checkpoints", layout)
            let dateWidth = 104 * s
            let labelWidth = doc.contentWidth - dateWidth
            let dateStyle = style(10, layout, bold: true)
            let labelStyle = style(10, layout)
            for checkpoint in input.checkpoints {
                let date = dateString(checkpoint.date, isChinese: input.isChinese)
                let height = max(doc.measure(date, style: dateStyle, width: dateWidth).height,
                                 doc.measure(checkpoint.label, style: labelStyle, width: labelWidth).height)
                let row = doc.reserve(height: height)
                drawInRect(doc, CGRect(x: row.minX, y: row.minY, width: dateWidth, height: height), date, dateStyle)
                drawInRect(doc, CGRect(x: row.minX + dateWidth, y: row.minY, width: labelWidth, height: height),
                           checkpoint.label, labelStyle)
                doc.spacer(5 * s)
            }
        }
        doc.spacer(28 * s)
    }

    // MARK: Coach's note and home activity

    private static func drawCoachNote(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        guard let note = input.coachNote else { return }
        let s = layout.scale
        sectionHeading(doc, "教练寄语", "A note from the coach", layout, minFollowing: 50)

        let pad = 16 * s
        let textStyle = style(10.5, layout, spacing: 3)
        let signatureStyle = style(9.5, layout, bold: true, color: secondary)
        let width = doc.contentWidth - pad * 2
        let textHeight = doc.measure(note, style: textStyle, width: width).height
        let signature = input.coachName.map { "— \($0)" }
        let signatureHeight = signature.map { doc.measure($0, style: signatureStyle, width: width).height } ?? 0
        let total = pad * 2 + textHeight + (signatureHeight > 0 ? 8 * s + signatureHeight : 0)

        if total <= doc.contentHeight {
            let panel = doc.reserve(height: total)
            fill(doc, panel, panelFill, radius: 8 * s)
            fill(doc, CGRect(x: panel.minX, y: panel.minY + pad, width: 3 * s, height: total - pad * 2), accent)
            drawInRect(doc, CGRect(x: panel.minX + pad, y: panel.minY + pad, width: width, height: textHeight),
                       note, textStyle)
            if let signature {
                drawInRect(doc, CGRect(x: panel.minX + pad, y: panel.minY + pad + textHeight + 8 * s,
                                       width: width, height: signatureHeight),
                           signature, signatureStyle)
            }
        } else {
            // Longer than a page: plain flowing text, which paginates.
            doc.text(note, style: textStyle)
            if let signature {
                doc.spacer(8 * s)
                doc.text(signature, style: signatureStyle)
            }
        }
        doc.spacer(28 * s)
    }

    private static func drawHomeActivity(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout) {
        guard let activity = input.homeActivity else { return }
        sectionHeading(doc, "在家可以练", "Try at home", layout, minFollowing: 40)
        doc.text(activity, style: bodyStyle(layout))
        doc.spacer(28 * layout.scale)
    }

    // MARK: Footer

    private static func drawFooter(_ doc: PDFDocumentRenderer, _ input: Input, _ layout: Layout, page: Int?) {
        var left = input.identity
        if let coach = input.coachName, coach != input.identity { left += " · \(coach)" }
        if let phone = input.coachPhone { left += " · \(phone)" }
        let leftStyle = style(7.5, layout, color: secondary)
        let rightStyle = style(7.5, layout, color: secondary, align: .right)
        let right = page.map { "Hoopwise · \($0)" } ?? "Hoopwise"

        let height = doc.measure(left, style: leftStyle, width: doc.contentWidth * 0.75).height
        let y = doc.margins.bottom - height - 16 * layout.scale
        doc.drawText(left, style: leftStyle,
                     in: CGRect(x: doc.margins.left, y: y, width: doc.contentWidth * 0.75, height: height))
        doc.drawText(right, style: rightStyle,
                     in: CGRect(x: doc.margins.left, y: y, width: doc.contentWidth, height: height))
    }

    // MARK: - Building blocks

    private static func style(_ size: CGFloat, _ layout: Layout, bold: Bool = false,
                              color: CGColor? = nil, spacing: CGFloat = 2,
                              align: CTTextAlignment = .left) -> PDFTextStyle {
        PDFTextStyle(font: PDFFont.bilingual(size: size * layout.scale, bold: bold),
                     color: color ?? ink,
                     lineSpacing: spacing * layout.scale,
                     alignment: align)
    }

    private static func bodyStyle(_ layout: Layout) -> PDFTextStyle {
        style(10.5, layout, spacing: 3)
    }

    /// Chinese heading in ink, English beside it in grey — one line, two
    /// languages, one reading order. Breaks the page first if the heading
    /// would be stranded without its first lines.
    private static func sectionHeading(_ doc: PDFDocumentRenderer, _ zh: String, _ en: String,
                                       _ layout: Layout, minFollowing: CGFloat = 60) {
        let s = layout.scale
        let zhStyle = style(13, layout, bold: true)
        let enStyle = style(13, layout, color: secondary)
        let zhWidth = doc.measure(zh, style: zhStyle, width: 10_000).width
        let height = doc.measure("\(zh)  \(en)", style: zhStyle).height
        doc.ensureSpace(height + 10 * s + minFollowing * s)
        let band = doc.reserve(height: height)
        drawInRect(doc, CGRect(x: band.minX, y: band.minY, width: zhWidth + 2, height: height), zh, zhStyle)
        let enX = band.minX + zhWidth + 8 * s
        drawInRect(doc, CGRect(x: enX, y: band.minY, width: max(10, band.maxX - enX), height: height), en, enStyle)
        doc.spacer(10 * s)
    }

    private static func subLabel(_ doc: PDFDocumentRenderer, _ zh: String, _ en: String,
                                 _ layout: Layout, indent: CGFloat = 0) {
        let s = layout.scale
        let labelStyle = style(8.5, layout, bold: true, color: secondary)
        let text = "\(zh) · \(en)"
        let height = doc.measure(text, style: labelStyle, width: doc.contentWidth - indent).height
        doc.ensureSpace(height + 30 * s)
        doc.text(text, style: labelStyle, indent: indent)
        doc.spacer(5 * s)
    }

    private static func bullet(_ doc: PDFDocumentRenderer, _ text: String, _ layout: Layout,
                               indent: CGFloat = 0) {
        let s = layout.scale
        let textStyle = bodyStyle(layout)
        let gutter = 14 * s
        let width = doc.contentWidth - indent - gutter
        let height = doc.measure(text, style: textStyle, width: width).height
        let row = doc.reserve(height: height)
        drawInRect(doc, CGRect(x: row.minX + indent, y: row.minY, width: gutter, height: height),
                   "•", style(10.5, layout, color: accent, spacing: 3))
        drawInRect(doc, CGRect(x: row.minX + indent + gutter, y: row.minY, width: width, height: height),
                   text, textStyle)
        doc.spacer(4 * s)
    }

    /// Cursor-space rect (what `reserve` hands out: y from the top content
    /// edge) → the renderer's bottom-up page space.
    private static func drawInRect(_ doc: PDFDocumentRenderer, _ rect: CGRect,
                                   _ string: String, _ style: PDFTextStyle) {
        let pdfY = doc.pageSize.height - doc.margins.top - rect.minY - rect.height
        doc.drawText(string, style: style,
                     in: CGRect(x: rect.minX, y: pdfY, width: rect.width, height: rect.height))
    }

    /// Fills a cursor-space rect. Zero-width rects are skipped and the corner
    /// radius is clamped: CGPath(roundedRect:) traps when a corner is wider
    /// than half the rect.
    private static func fill(_ doc: PDFDocumentRenderer, _ rect: CGRect, _ color: CGColor,
                             radius: CGFloat = 0) {
        guard rect.width > 0.5, rect.height > 0.5 else { return }
        doc.draw(in: rect) { context in
            let local = CGRect(origin: .zero, size: rect.size)
            let corner = min(radius, local.width / 2, local.height / 2)
            context.setFillColor(color)
            if corner > 0 {
                context.addPath(CGPath(roundedRect: local, cornerWidth: corner,
                                       cornerHeight: corner, transform: nil))
                context.fillPath()
            } else {
                context.fill(local)
            }
        }
    }

    private static func fillCircle(_ doc: PDFDocumentRenderer, _ rect: CGRect, _ color: CGColor) {
        doc.draw(in: rect) { context in
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(origin: .zero, size: rect.size))
        }
    }

    private static func hairline(_ doc: PDFDocumentRenderer, indent: CGFloat = 0) {
        let width = doc.contentWidth - indent
        let box = doc.reserve(height: 0.5)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0.25))
        path.addLine(to: CGPoint(x: width, y: 0.25))
        doc.draw(path: path,
                 in: CGRect(x: box.minX + indent, y: box.minY, width: width, height: 0.5),
                 stroke: ruleColor, lineWidth: 0.5)
    }

    // MARK: - Data helpers

    private static func clean(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// "Phase 1", "phase 2", "第3阶段", "阶段4" — a placeholder, not a name.
    static func isGenericTitle(_ title: String) -> Bool {
        let stripped = title.lowercased()
            .replacingOccurrences(of: "phase", with: "")
            .replacingOccurrences(of: "阶段", with: "")
            .replacingOccurrences(of: "第", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty || Int(stripped) != nil
    }

    /// The phase's own suggested drills, else the drills its sessions
    /// actually used (skills and game first, most used first). At most four.
    private static func activities(for phase: MicroCycle, sessions: [SessionEvent],
                                   drills: [UUID: DrillItem]) -> [Activity] {
        var ordered = phase.suggestedDrillIds
        if ordered.isEmpty {
            var counts: [UUID: Int] = [:]
            var firstSeen: [UUID] = []
            for session in sessions where session.microCycleId == phase.id {
                for id in session.curriculum.skillDrillIds + session.curriculum.gameDrillIds {
                    if counts[id] == nil { firstSeen.append(id) }
                    counts[id, default: 0] += 1
                }
            }
            ordered = firstSeen.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        }

        var seen = Set<UUID>()
        var result: [Activity] = []
        for id in ordered {
            guard !seen.contains(id), let drill = drills[id] else { continue }
            seen.insert(id)
            result.append(Activity(name: drill.localizedName,
                                   purpose: firstSentence(drill.localizedDescription)))
            if result.count == 4 { break }
        }
        return result
    }

    /// The first sentence of a drill description, capped, so an activity
    /// line says what it is for without reprinting the coaching manual.
    private static func firstSentence(_ text: String) -> String? {
        guard let trimmed = clean(text) else { return nil }
        var cut: String.Index?
        for mark in ["。", "！", "？", ". ", "! ", "? "] {
            if let range = trimmed.range(of: mark) {
                let end = mark.count > 1 ? trimmed.index(after: range.lowerBound) : range.upperBound
                if cut == nil || end < cut! { cut = end }
            }
        }
        var sentence = cut.map { String(trimmed[..<$0]) } ?? trimmed
        if sentence.count > 140 {
            sentence = String(sentence.prefix(137)) + "…"
        }
        return sentence
    }

    private static func lengthLine(_ input: Input) -> String? {
        var parts: [String] = []
        let phaseCount = input.phases.count
        if input.isChinese {
            if input.weeks > 0 { parts.append("\(input.weeks) 周") }
            if phaseCount > 0 { parts.append("\(phaseCount) 个阶段") }
            if input.sessionsPerWeek > 0 { parts.append("每周 \(input.sessionsPerWeek) 次") }
        } else {
            if input.weeks > 0 { parts.append("\(input.weeks) week\(input.weeks == 1 ? "" : "s")") }
            if phaseCount > 0 { parts.append("\(phaseCount) phase\(phaseCount == 1 ? "" : "s")") }
            if input.sessionsPerWeek > 0 {
                parts.append("\(input.sessionsPerWeek) session\(input.sessionsPerWeek == 1 ? "" : "s") a week")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func focusName(_ focus: TrainingFocus, isChinese: Bool) -> String {
        guard isChinese else { return focus.displayName }
        switch focus {
        case .shooting:     return "投篮"
        case .ballHandling: return "运球"
        case .passing:      return "传球"
        case .defense:      return "防守"
        case .conditioning: return "体能"
        case .teamPlay:     return "团队配合"
        case .gamePrep:     return "比赛准备"
        case .recovery:     return "恢复"
        }
    }

    private static func programTypeName(_ type: ProgramType, isChinese: Bool) -> String {
        guard isChinese else { return type.displayName }
        switch type {
        case .group:           return "小组训练"
        case .privateSessions: return "私教课"
        case .coachWorkshop:   return "教练工作坊"
        case .team:            return "球队训练"
        case .clinic:          return "训练营"
        case .school:          return "校园课程"
        }
    }

    private static func weekdayName(_ day: Weekday, isChinese: Bool) -> String {
        guard isChinese else { return day.displayName }
        switch day {
        case .sunday:    return "周日"
        case .monday:    return "周一"
        case .tuesday:   return "周二"
        case .wednesday: return "周三"
        case .thursday:  return "周四"
        case .friday:    return "周五"
        case .saturday:  return "周六"
        }
    }

    // MARK: - Formatting

    private static func dateString(_ date: Date, isChinese: Bool, year: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isChinese ? "zh_CN" : "en_US")
        if isChinese {
            formatter.dateFormat = year ? "yyyy年M月d日" : "M月d日"
        } else {
            formatter.dateFormat = year ? "MMM d, yyyy" : "MMM d"
        }
        return formatter.string(from: date)
    }

    private static func rangeString(_ start: Date?, _ end: Date?, isChinese: Bool) -> String? {
        switch (start, end) {
        case let (start?, end?):
            return "\(dateString(start, isChinese: isChinese, year: false)) – \(dateString(end, isChinese: isChinese))"
        case let (start?, nil):
            return isChinese ? "\(dateString(start, isChinese: true)) 起" : "From \(dateString(start, isChinese: false))"
        default:
            return nil
        }
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
