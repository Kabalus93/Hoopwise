import SwiftUI

// THE GAME SHEET (24 Nov 2026, Luther: the game's Plan page should be useful,
// and "a printable / shareable one-page game sheet — yes, now"). One A4 page
// for the bench: lineup and planned subs, keys, the defense, the calls by
// situation, the opponent and who guards whom, and ruled space for notes.
// Names only — no photos — so it prints cleanly and can be handed around.
// The page is a SwiftUI view drawn by ImageRenderer straight into the PDF
// context, so its text stays text. Language: Languages by Area → Exported PDFs.

/// Everything the sheet prints, as plain values.
struct GameSheetFacts {
    struct Sub: Identifiable { let id: UUID; let line: String; let when: String }
    struct Threat: Identifiable { let id: UUID; let number: String; let note: String; let guardName: String }
    struct CallGroup: Identifiable { let id: String; let title: String; let plays: [String] }

    var teamName = ""
    var teamColorHex = "#D4A017"
    var title = ""
    var whenLine = ""
    var starters: [String] = []
    var bench: [String] = []
    var subs: [Sub] = []
    var keys: [String] = []
    var defense = ""
    var calls: [CallGroup] = []
    var opponentName = ""
    var opponentNotes = ""
    var threats: [Threat] = []
    var warmUp: [String] = []
    var academy = ""
    var chinese = false

    @MainActor
    static func make(session: SessionEvent, dataManager: DataManager, chinese: Bool) -> GameSheetFacts {
        let plan = session.curriculum.gamePlan ?? GamePlan()
        let team = session.curriculum.teamId.flatMap { id in dataManager.teams.first { $0.id == id } }
        let roster = AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
        func name(_ id: UUID?) -> String {
            guard let id, let s = dataManager.students.first(where: { $0.id == id }) else { return "" }
            return s.primaryName(chinese: chinese)
        }
        var f = GameSheetFacts()
        f.chinese = chinese
        f.teamName = team?.name ?? ""
        f.teamColorHex = team?.colorHex ?? f.teamColorHex
        f.opponentName = plan.opponentName(chinese: chinese)
        f.title = plan.title(team: team?.name ?? (chinese ? "我们" : "Us"), chinese: chinese)
        let day = session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
            .locale(Locale(identifier: chinese ? "zh_CN" : "en_US")))
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_GB")
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: session.startTime)
        let place = (session.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        f.whenLine = [day, time, plan.isHome ? (chinese ? "主场" : "Home") : (chinese ? "客场" : "Away"), place]
            .filter { !$0.isEmpty }.joined(separator: "  ·  ")
        let starters = plan.starters.filter { roster.contains($0) }
        f.starters = starters.map { name($0) }.filter { !$0.isEmpty }
        f.bench = roster.filter { !starters.contains($0) }.map { name($0) }.filter { !$0.isEmpty }
        f.subs = plan.validSubs(roster: roster).map { sub in
            let out = sub.playerOut.map { name($0) } ?? ""
            let line = out.isEmpty ? (chinese ? "\(name(sub.playerIn)) 上场" : "\(name(sub.playerIn)) in")
                                   : (chinese ? "\(name(sub.playerIn)) 换下 \(out)" : "\(name(sub.playerIn)) in for \(out)")
            return Sub(id: sub.id, line: line, when: sub.whenLine)
        }
        f.keys = plan.cleanKeys
        let note = plan.defenseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        f.defense = [plan.defense?.title(chinese: chinese), note.isEmpty ? nil : note].compactMap { $0 }.joined(separator: " — ")
        f.calls = GameCalls.groups(plays: session.curriculum.plays, playbook: team?.playbook).map {
            CallGroup(id: $0.id, title: $0.title(chinese: chinese), plays: $0.plays.map(\.name))
        }
        f.opponentNotes = plan.opponentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        f.threats = plan.cleanThreats.map {
            Threat(id: $0.id, number: $0.label, note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines),
                   guardName: name($0.guardedBy))
        }
        f.warmUp = session.curriculum.warmupDrillIds.compactMap { id in
            dataManager.drills.first { $0.id == id }?.localizedName
        }
        f.academy = ProgramGuideStore.academyName
        return f
    }

    var fileStem: String {
        let raw = "GameSheet_\(title)"
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return raw.components(separatedBy: bad).joined().replacingOccurrences(of: " ", with: "_")
    }
}

/// The page: A4 portrait, always light.
struct GameSheetPage: View {
    let facts: GameSheetFacts
    static let size = CGSize(width: 595, height: 842)

    private var zh: Bool { facts.chinese }
    private var tint: Color { Color(hex: facts.teamColorHex) }
    private let soft = Color.black.opacity(0.55)
    private let hair = Color.black.opacity(0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(tint).frame(height: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(zh ? "比赛计划单" : "GAME SHEET")
                    .font(.system(size: 9, weight: .heavy)).kerning(1.4).foregroundStyle(soft)
                Text(facts.title).font(.system(size: 24, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                Text(facts.whenLine).font(.system(size: 10.5, weight: .medium)).foregroundStyle(soft).lineLimit(1)
            }
            .padding(.top, 12)
            Rectangle().fill(hair).frame(height: 0.5).padding(.top, 10)

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    block(zh ? "首发" : "STARTERS") {
                        if facts.starters.isEmpty { blank(5) } else { numbered(facts.starters) }
                    }
                    if !facts.bench.isEmpty {
                        block(zh ? "替补" : "BENCH") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(facts.bench.prefix(12).enumerated()), id: \.offset) { _, n in
                                    Text(n).font(.system(size: 11)).lineLimit(1)
                                }
                            }
                        }
                    }
                    if !facts.subs.isEmpty {
                        block(zh ? "计划换人" : "PLANNED SUBS") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(facts.subs.prefix(8)) { sub in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(sub.line).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                                        if !sub.when.isEmpty {
                                            Text(sub.when).font(.system(size: 9.5)).foregroundStyle(soft).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !facts.warmUp.isEmpty {
                        block(zh ? "赛前热身" : "PRE-GAME WARM-UP") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(facts.warmUp.prefix(6).enumerated()), id: \.offset) { _, n in
                                    Text(n).font(.system(size: 10.5)).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .frame(width: 180, alignment: .leading)

                VStack(alignment: .leading, spacing: 14) {
                    block(zh ? "比赛要点" : "KEYS TO THE GAME") {
                        if facts.keys.isEmpty { blank(3) } else { numbered(facts.keys.prefix(6).map { $0 }, size: 12.5, bold: true, lines: 2) }
                    }
                    if !facts.defense.isEmpty {
                        block(zh ? "防守" : "DEFENSE") {
                            Text(facts.defense).font(.system(size: 12, weight: .semibold)).lineLimit(3)
                        }
                    }
                    if !facts.calls.isEmpty {
                        block(zh ? "战术口令" : "CALLS") {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(facts.calls) { group in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(group.title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(soft)
                                            .frame(width: 92, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                                        Text(group.plays.joined(separator: "  ·  ")).font(.system(size: 11, weight: .medium))
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    block((zh ? "对手：" : "OPPONENT: ") + facts.opponentName.uppercased()) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !facts.opponentNotes.isEmpty {
                                Text(facts.opponentNotes).font(.system(size: 10.5)).lineLimit(6)
                            }
                            if !facts.threats.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(facts.threats.prefix(8)) { t in
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(t.number.isEmpty ? "—" : t.number).font(.system(size: 11, weight: .heavy))
                                                .frame(width: 30, alignment: .leading)
                                            Text(t.note).font(.system(size: 10.5)).lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            if !t.guardName.isEmpty {
                                                Text("← " + t.guardName).font(.system(size: 10.5, weight: .semibold))
                                                    .lineLimit(1).frame(width: 110, alignment: .trailing)
                                            }
                                        }
                                    }
                                }
                            }
                            if facts.opponentNotes.isEmpty && facts.threats.isEmpty { blank(3) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)

            // Whatever room is left is for the pen.
            VStack(alignment: .leading, spacing: 6) {
                Text(zh ? "记录" : "NOTES").font(.system(size: 8.5, weight: .heavy)).kerning(1.2).foregroundStyle(soft)
                GeometryReader { geo in
                    let rows = max(0, Int(geo.size.height / 22))
                    VStack(spacing: 0) {
                        ForEach(0..<rows, id: \.self) { _ in
                            Rectangle().fill(hair).frame(height: 0.5).frame(height: 22, alignment: .bottom)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .frame(maxHeight: .infinity)

            HStack {
                Text(facts.academy).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(soft)
                Spacer()
                Text(facts.teamName).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(soft)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 26)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 8.5, weight: .heavy)).kerning(1.2).foregroundStyle(tint)
                .lineLimit(1)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numbered(_ items: [String], size: CGFloat = 12, bold: Bool = true, lines: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(i + 1)").font(.system(size: size - 2, weight: .heavy)).foregroundStyle(soft)
                        .frame(width: 12, alignment: .leading)
                    Text(text).font(.system(size: size, weight: bold ? .semibold : .regular)).lineLimit(lines)
                }
            }
        }
    }

    /// Lines to write on when nothing was planned.
    private func blank(_ rows: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                Rectangle().fill(hair).frame(height: 0.5).frame(height: 20, alignment: .bottom)
            }
        }
    }
}

@MainActor
enum GameSheetDocument {
    /// One vector A4 page.
    static func pdf(_ facts: GameSheetFacts) -> Data {
        let bounds = CGRect(origin: .zero, size: GameSheetPage.size)
        let renderer = ImageRenderer(content: GameSheetPage(facts: facts))
        renderer.proposedSize = ProposedViewSize(GameSheetPage.size)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            renderer.render { size, draw in
                cg.saveGState()
                // ImageRenderer draws y-up; the UIKit page is y-down.
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                draw(cg)
                cg.restoreGState()
            }
        }
    }

    /// The same page as a picture (for WeChat).
    static func image(_ facts: GameSheetFacts) -> UIImage? {
        let renderer = ImageRenderer(content: GameSheetPage(facts: facts))
        renderer.proposedSize = ProposedViewSize(GameSheetPage.size)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Preview, then PDF / picture / print.
struct GameSheetShareSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let session: SessionEvent
    @State private var sharing: [Any]?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var facts: GameSheetFacts {
        let stored = dataManager.sessionEvents.first { $0.id == session.id } ?? session
        return GameSheetFacts.make(session: stored, dataManager: dataManager, chinese: AreaLanguage.isChinese(.exports))
    }

    var body: some View {
        let facts = facts
        NavigationStack {
            GeometryReader { geo in
                let scale = min((geo.size.width - 32) / GameSheetPage.size.width,
                                (geo.size.height - 24) / GameSheetPage.size.height)
                GameSheetPage(facts: facts)
                    .compositingGroup()
                    .scaleEffect(scale)
                    .frame(width: GameSheetPage.size.width * scale, height: GameSheetPage.size.height * scale)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(isChinese ? "比赛计划单预览" : "Game sheet preview")
                    .accessibilityIdentifier("gameSheet.preview")
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    action(isChinese ? "PDF" : "PDF", "doc.richtext", id: "gameSheet.pdf") {
                        let url = file(facts.fileStem + ".pdf")
                        try? GameSheetDocument.pdf(facts).write(to: url)
                        sharing = [url]
                    }
                    action(isChinese ? "图片" : "Image", "photo", id: "gameSheet.image") {
                        guard let data = GameSheetDocument.image(facts)?.jpegData(compressionQuality: 0.92) else { return }
                        let url = file(facts.fileStem + ".jpg")
                        try? data.write(to: url)
                        sharing = [url]
                    }
                    action(isChinese ? "打印" : "Print", "printer", id: "gameSheet.print") {
                        let controller = UIPrintInteractionController.shared
                        let info = UIPrintInfo(dictionary: nil)
                        info.outputType = .general
                        info.jobName = facts.title
                        controller.printInfo = info
                        controller.printingItem = GameSheetDocument.pdf(facts)
                        controller.present(animated: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle(isChinese ? "比赛计划单" : "Game sheet")
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

    private func action(_ title: String, _ symbol: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(id)
    }

    private func file(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GameSheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
