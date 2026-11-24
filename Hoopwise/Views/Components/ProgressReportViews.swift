import SwiftUI

// THE PROGRESS REPORT — the page and its share screen (facts in
// Services/ProgressReportFacts.swift). One A4 page for a parent: attendance,
// skills then and now, what the classes worked on, tracked results, games,
// what comes next and the coach's words. Drawn as a SwiftUI page into the PDF
// context (text stays text). Language: Languages by Area → Exported PDFs.

struct ProgressReportPage: View {
    let facts: ProgressReportFacts
    static let size = CGSize(width: 595, height: 842)

    private var zh: Bool { facts.chinese }
    private var tint: Color { Color(hex: facts.accentHex) }
    private let soft = Color.black.opacity(0.55)
    private let hair = Color.black.opacity(0.16)
    private let panel = Color(white: 0.955)

    private var periodText: String {
        let locale = Locale(identifier: zh ? "zh_CN" : "en_US")
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(locale)
        return facts.periodStart.formatted(style) + " – " + facts.periodEnd.formatted(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(tint).frame(height: 4)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(zh ? "成长报告" : "PROGRESS REPORT").font(.system(size: 9, weight: .heavy)).kerning(1.4).foregroundStyle(soft)
                    Text(facts.name).font(.system(size: 26, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    Text([facts.secondName, facts.schoolGrade, facts.program].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(soft).lineLimit(1)
                }
                Spacer()
                Text(periodText).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(soft)
            }
            .padding(.top, 12)
            Rectangle().fill(hair).frame(height: 0.5).padding(.top, 10)

            tiles.padding(.top, 14)

            if !facts.skills.isEmpty { skills.padding(.top, 18) }

            if !facts.workedOn.isEmpty || !facts.results.isEmpty {
                HStack(alignment: .top, spacing: 22) {
                    if !facts.workedOn.isEmpty {
                        block(zh ? "课上练得最多" : "WHAT WE WORKED ON MOST") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(facts.workedOn.enumerated()), id: \.offset) { i, t in
                                    HStack(spacing: 7) {
                                        Text("\(i + 1)").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(soft).frame(width: 10)
                                        Text(t).font(.system(size: 11.5, weight: .semibold))
                                    }
                                }
                            }
                        }
                        .frame(width: 170, alignment: .leading)
                    }
                    if !facts.results.isEmpty {
                        block(zh ? "追踪训练的成绩" : "RESULTS IN TRACKED DRILLS") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(facts.results) { r in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(r.title).font(.system(size: 10.5)).lineLimit(1).minimumScaleFactor(0.75)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if let first = r.first {
                                            Text(first + " → ").font(.system(size: 10.5)).foregroundStyle(soft)
                                        }
                                        Text(r.last).font(.system(size: 11.5, weight: .bold))
                                        Text(r.improved == nil ? " " : (r.improved! ? "↑" : "↓"))
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(r.improved == true ? Color(red: 0.1, green: 0.6, blue: 0.3) : Color(red: 0.8, green: 0.25, blue: 0.2))
                                            .frame(width: 10)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 18)
            }

            if !facts.focus.isEmpty {
                block(zh ? "接下来的重点" : "WHAT WE WORK ON NEXT") {
                    HStack(spacing: 8) {
                        ForEach(facts.focus, id: \.self) { f in
                            Text(f).font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(tint.opacity(0.14)))
                        }
                    }
                }
                .padding(.top, 18)
            }

            if !facts.coachWords.isEmpty {
                block(zh ? "教练的话" : "FROM THE COACH") {
                    Text(facts.coachWords).font(.system(size: 12)).lineSpacing(3).lineLimit(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(panel))
                }
                .padding(.top, 18)
            }

            Spacer(minLength: 0)
            Rectangle().fill(hair).frame(height: 0.5)
            HStack {
                Text(facts.academy).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(soft)
                Spacer()
                Text(facts.coach).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(soft)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 26)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile(zh ? "出勤" : "ATTENDANCE",
                 facts.classesTaken > 0 ? "\(facts.classesPresent)/\(facts.classesTaken)" : "—",
                 facts.attendanceShare.map { "\(Int(($0 * 100).rounded()))%" + (zh ? " 到课" : " of classes") } ?? (zh ? "没有点名记录" : "No roll call on record"))
            if facts.games > 0 {
                tile(zh ? "比赛" : "GAMES", "\(facts.games)",
                     facts.perGame.map { "\(String(format: "%.1f", $0.value)) \($0.label)" }.joined(separator: " · "))
            }
            if facts.playerOfTheSession > 0 {
                tile(zh ? "当堂最佳" : "PLAYER OF THE SESSION", "×\(facts.playerOfTheSession)", zh ? "被教练选中的次数" : "times picked by the coach")
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8.5, weight: .heavy)).kerning(1).foregroundStyle(soft).lineLimit(1)
            Text(value).font(.system(size: 24, weight: .heavy, design: .rounded))
            Text(detail).font(.system(size: 9.5)).foregroundStyle(soft).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(panel))
    }

    private var skills: some View {
        let since = facts.skillsSince.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: zh ? "zh_CN" : "en_US"))) }
        return block(zh ? "技能" : "SKILLS") {
            VStack(spacing: 7) {
                ForEach(facts.skills) { skill in
                    HStack(spacing: 10) {
                        Text(skill.title).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(width: 128, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(panel)
                                Capsule().fill(tint).frame(width: max(4, geo.size.width * CGFloat(skill.now) / 10))
                                if let then = skill.then, then != skill.now {
                                    Rectangle().fill(Color.black.opacity(0.7)).frame(width: 1.5, height: 12)
                                        .offset(x: geo.size.width * CGFloat(then) / 10 - 0.75)
                                }
                            }
                        }
                        .frame(height: 8)
                        Text(skill.then.map { "\($0) → \(skill.now)" } ?? "\(skill.now)")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                        Text(skill.change.map { $0 == 0 ? "–" : ($0 > 0 ? "+\($0)" : "\($0)") } ?? "")
                            .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                            .foregroundStyle((skill.change ?? 0) > 0 ? Color(red: 0.1, green: 0.6, blue: 0.3)
                                             : ((skill.change ?? 0) < 0 ? Color(red: 0.8, green: 0.25, blue: 0.2) : soft))
                            .frame(width: 24, alignment: .trailing)
                    }
                }
                Text(since.map { zh ? "教练按 1–10 评分。黑线是 \($0) 的评分。" : "Rated 1–10 by the coach. The black mark is where each skill stood on \($0)." }
                     ?? (zh ? "教练按 1–10 评分。" : "Rated 1–10 by the coach."))
                    .font(.system(size: 8.5)).foregroundStyle(soft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 8.5, weight: .heavy)).kerning(1.2).foregroundStyle(tint).lineLimit(1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum ProgressReportDocument {
    static func pdf(_ facts: ProgressReportFacts) -> Data {
        let bounds = CGRect(origin: .zero, size: ProgressReportPage.size)
        let renderer = ImageRenderer(content: ProgressReportPage(facts: facts))
        renderer.proposedSize = ProposedViewSize(ProgressReportPage.size)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            renderer.render { size, draw in
                cg.saveGState()
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                draw(cg)
                cg.restoreGState()
            }
        }
    }

    static func image(_ facts: ProgressReportFacts) -> UIImage? {
        let renderer = ImageRenderer(content: ProgressReportPage(facts: facts))
        renderer.proposedSize = ProposedViewSize(ProgressReportPage.size)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// How far back the report looks.
enum ProgressReportPeriod: String, CaseIterable, Identifiable {
    case month, threeMonths, term, all
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .month: chinese ? "近 1 个月" : "1 month"
        case .threeMonths: chinese ? "近 3 个月" : "3 months"
        case .term: chinese ? "本学期" : "This term"
        case .all: chinese ? "全部" : "All time"
        }
    }
    /// The term began on the latest 1 September or 1 March.
    func start(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .all: return .distantPast
        case .term:
            let year = calendar.component(.year, from: now)
            let starts = [(year, 9), (year, 3), (year - 1, 9)].compactMap { calendar.date(from: DateComponents(year: $0.0, month: $0.1, day: 1)) }
            return starts.filter { $0 <= now }.max() ?? now
        }
    }
}

struct ProgressReportSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let student: Student

    @State private var period: ProgressReportPeriod = .term
    @State private var coachWords = ""
    @State private var focus: [DrillAttribute]?
    @State private var sharing: [Any]?
    /// A report that left this sheet is logged once in the family contacts.
    @State private var logged = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var skills: SkillsEvaluation? { dataManager.players.first { $0.studentId == student.id }?.skills }
    private var chosenFocus: [DrillAttribute] { focus ?? skills.map(AthleteFocus.current) ?? [] }

    private var facts: ProgressReportFacts {
        let coach = dataManager.coach.name
        var start = period.start()
        if period == .all {
            start = dataManager.sessionEvents.map(\.startTime).min() ?? Date()
        }
        return ProgressReportFacts.make(student: student, players: dataManager.players, programs: dataManager.programs,
                                        sessions: dataManager.sessionEvents, drills: dataManager.drills,
                                        from: start, coachWords: coachWords, focus: chosenFocus,
                                        coach: coach, academy: ProgramGuideStore.academyName,
                                        chinese: AreaLanguage.isChinese(.exports))
    }

    var body: some View {
        let facts = facts
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker(isChinese ? "时间范围" : "Period", selection: $period) {
                        ForEach(ProgressReportPeriod.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("report.period")

                    GeometryReader { geo in
                        let scale = min(1, geo.size.width / ProgressReportPage.size.width)
                        ProgressReportPage(facts: facts)
                            .compositingGroup()
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: ProgressReportPage.size.width * scale, height: ProgressReportPage.size.height * scale, alignment: .topLeading)
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                            .frame(maxWidth: .infinity)
                    }
                    .aspectRatio(ProgressReportPage.size.width / ProgressReportPage.size.height, contentMode: .fit)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isChinese ? "成长报告预览" : "Progress report preview")
                    .accessibilityIdentifier("report.preview")

                    VStack(alignment: .leading, spacing: 8) {
                        Text(isChinese ? "接下来的重点（最多两项）" : "WHAT WE WORK ON NEXT (UP TO TWO)")
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(DrillAttribute.allCases, id: \.self) { axis in
                                let on = chosenFocus.contains(axis)
                                Button { toggle(axis) } label: {
                                    Text(axis.title)
                                        .font(.subheadline.weight(on ? .semibold : .regular))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("report.focus.\(axis.rawValue)")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                        Text(isChinese ? "教练的话" : "A WORD FROM THE COACH")
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 6)
                        TextField(isChinese ? "写给家长的话（只在这份报告里，不保存）" : "A few lines for the parents (on this report only, not saved)",
                                  text: $coachWords, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.filmCard))
                            .accessibilityIdentifier("report.words")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(FilmRoomPageBackground())
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    action("PDF", "doc.richtext", id: "report.pdf") {
                        let url = file(facts.fileStem + ".pdf")
                        try? ProgressReportDocument.pdf(facts).write(to: url)
                        sharing = [url]
                    }
                    action(isChinese ? "图片" : "Image", "photo", id: "report.image") {
                        guard let data = ProgressReportDocument.image(facts)?.jpegData(compressionQuality: 0.92) else { return }
                        let url = file(facts.fileStem + ".jpg")
                        try? data.write(to: url)
                        sharing = [url]
                    }
                    action(isChinese ? "打印" : "Print", "printer", id: "report.print") {
                        let controller = UIPrintInteractionController.shared
                        let info = UIPrintInfo(dictionary: nil)
                        info.outputType = .general
                        info.jobName = facts.fileStem
                        controller.printInfo = info
                        controller.printingItem = ProgressReportDocument.pdf(facts)
                        controller.present(animated: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle(isChinese ? "成长报告" : "Progress report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                ShareSheet(items: sharing ?? [])
            }
        }
    }

    private func toggle(_ axis: DrillAttribute) {
        var list = chosenFocus
        if let i = list.firstIndex(of: axis) { list.remove(at: i) }
        else { list.append(axis); if list.count > AthleteFocus.most { list.removeFirst() } }
        focus = list
    }

    private func action(_ title: String, _ symbol: String, id: String, run: @escaping () -> Void) -> some View {
        Button {
            run()
            if !logged {
                logged = true
                dataManager.logParentContact(studentId: student.id, type: .reportCard,
                                             note: isChinese ? "成长报告" : "Progress report")
            }
        } label: {
            Label(title, systemImage: symbol).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(id)
    }

    private func file(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ProgressReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
