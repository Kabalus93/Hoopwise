import SwiftUI

/// What fills the background of a cut-out photo on a shared or printed card
/// (20 Nov 2026, Luther: the level colour is shown in the app; before sharing
/// or printing the coach chooses to keep it or pick one colour).
enum CardBackdrop: Equatable {
    /// Each athlete's skill level colour (in the card's program).
    case level
    /// One colour for every card.
    case color(String)
}

extension DataManager {
    /// The athlete's card for this month (Services/AthleteCardFacts.swift).
    /// `levelProgram` = the group whose level colours the photo (nil = their
    /// primary program).
    func athleteCard(for student: Student, coachLine: String = "", backdrop: CardBackdrop = .level,
                     levelProgram: UUID? = nil, now: Date = Date()) -> AthleteCardFacts {
        let academy = ProgramGuideStore.academyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let backdropHex: String
        switch backdrop {
        case .level: backdropHex = photoBackdropHex(for: student.id, program: levelProgram)
        case .color(let hex): backdropHex = hex
        }
        return AthleteCardFacts.make(
            student: student, players: players, programs: programs, sessions: sessionEvents, drills: drills,
            categoryHex: ageCategory(for: student)?.colorHex ?? "#007AFF",
            coach: coach.name, academy: academy, coachLine: coachLine, backdropHex: backdropHex, now: now)
    }

    /// Cards for everyone a session expects, plus anyone marked at it — the
    /// roster the session page shows (its stored roster is often empty and
    /// the program's enrolment stands in).
    func athleteCards(forSession session: SessionEvent, backdrop: CardBackdrop = .level) -> [AthleteCardFacts] {
        var ids = AttendanceMath.expectedIds(of: session, programs: programs)
        for id in session.actualAttendeeIds + session.excusedAbsences + session.unexcusedAbsences where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap { id in students.first { $0.id == id } }
            .sorted { $0.primaryDisplayName < $1.primaryDisplayName }
            .map { athleteCard(for: $0, backdrop: backdrop, levelProgram: session.programId) }
    }

    /// Cards for a program's enrolled athletes.
    func athleteCards(forProgram program: Program, backdrop: CardBackdrop = .level) -> [AthleteCardFacts] {
        program.enrolledStudentIds.compactMap { id in students.first { $0.id == id } }
            .sorted { $0.primaryDisplayName < $1.primaryDisplayName }
            .map { athleteCard(for: $0, backdrop: backdrop, levelProgram: program.id) }
    }
}

/// Share an athlete's card: the card as it will be sent (front and back), a
/// line from the coach, then Share image (WeChat) or an A3 print sheet.
struct AthleteCardShareSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let student: Student

    @State private var showingPrintOptions = false
    @State private var coachLine = ""
    @State private var backdrop: CardBackdrop = .level
    @State private var shareItems: [Any]?
    @State private var working = false
    @State private var problem: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var card: AthleteCardFacts { dataManager.athleteCard(for: student, coachLine: coachLine, backdrop: backdrop) }
    /// Only a cut-out photo has a background to choose.
    private var photoIsCutOut: Bool { card.backdropHex != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    if photoIsCutOut {
                        CardBackdropPicker(backdrop: $backdrop,
                                           levelHex: dataManager.photoBackdropHex(for: student.id))
                            .frame(maxWidth: 620)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "教练寄语（可选）" : "A word from the coach (optional)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(isChinese ? "例如：这个月传球进步很大！" : "e.g. Big step forward with passing this month!",
                                  text: $coachLine, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(Color.filmCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityIdentifier("athleteCard.coachLine")
                    }
                    .frame(maxWidth: 620)
                    VStack(spacing: 10) {
                        Button(action: shareImage) {
                            Label(isChinese ? "分享图片" : "Share image", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("athleteCard.shareImage")
                        Button(action: printSheet) {
                            Label(isChinese ? "A3 打印页" : "A3 print sheet", systemImage: "printer")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("athleteCard.print")
                    }
                    .frame(maxWidth: 620)
                    .disabled(working)
                    Button { showingPrintOptions = true } label: {
                        Label(isChinese ? "打印设置与给打印店的说明" : "Printing: settings and notes for the print shop",
                              systemImage: "info.circle")
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("athleteCard.printOptions")
                    .sheet(isPresented: $showingPrintOptions) { CardPrintOptionsSheet() }
                    Text(isChinese ? "卡片只显示应用里记录的内容：本月到课、比赛数据和所上课程的训练重点。"
                                   : "The card shows only what the app has recorded: this month's classes, game stats and what their classes worked on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 620)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .filmRoomPage()
            .navigationTitle(isChinese ? "球员卡" : "Player card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let items = shareItems { ShareSheet(items: items) }
            }
            .alert(isChinese ? "无法生成" : "Couldn't make the card",
                   isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    /// The spread, scaled to the width there is.
    private var preview: some View {
        GeometryReader { proxy in
            let natural = CGSize(width: AthleteCardLayout.size.width * 2 + AthleteCardSpread.gap * 3,
                                 height: AthleteCardLayout.size.height + AthleteCardSpread.gap * 2)
            let scale = min(1, proxy.size.width / natural.width)
            AthleteCardSpread(card: card)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: natural.width * scale, height: natural.height * scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity)
        }
        .aspectRatio((AthleteCardLayout.size.width * 2 + AthleteCardSpread.gap * 3)
                     / (AthleteCardLayout.size.height + AthleteCardSpread.gap * 2), contentMode: .fit)
        .frame(maxWidth: 900)
        .accessibilityElement()
        .accessibilityLabel(isChinese ? "球员卡预览" : "Player card preview")
        .accessibilityIdentifier("athleteCard.preview")
    }

    private var fileStem: String {
        let month = AthleteCardMonth.label(card.month, chinese: isChinese)
        return "\(student.primaryDisplayName.replacingOccurrences(of: "/", with: "-")) - \(month)"
    }

    private func shareImage() {
        working = true
        defer { working = false }
        guard let image = AthleteCardRenderer.shareImage(card), let data = image.pngData() else {
            problem = isChinese ? "生成图片失败" : "The image could not be made."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileStem).png")
        do {
            try data.write(to: url, options: .atomic)
            shareItems = [url]
        } catch {
            problem = error.localizedDescription
        }
    }

    private func printSheet() {
        working = true
        defer { working = false }
        guard let pdf = AthleteCardRenderer.printSheet([card]) else {
            problem = isChinese ? "生成 PDF 失败" : "The PDF could not be made."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileStem) - A3.pdf")
        do {
            try pdf.write(to: url, options: .atomic)
            shareItems = [url]
        } catch {
            problem = error.localizedDescription
        }
    }
}

enum AthleteCardMonth {
    static func label(_ date: Date, chinese: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        f.dateFormat = chinese ? "yyyy年M月" : "MMMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - Choosing the card background

/// "Keep the level colour, or pick one" — the share sheet's row of swatches.
/// The level colour comes first and is the default; its meaning is never
/// written (the card goes to the child and parents).
struct CardBackdropPicker: View {
    @Binding var backdrop: CardBackdrop
    /// This athlete's level colour (or one per athlete on a print sheet: nil).
    var levelHex: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isChinese ? "照片背景" : "Photo background")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button { backdrop = .level } label: {
                        HStack(spacing: 8) {
                            if let levelHex {
                                Circle().fill(Color(hex: levelHex)).frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "circle.hexagongrid.fill").font(.title3)
                            }
                            Text(isChinese ? "保留水平颜色" : "Keep level colour")
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Capsule().fill(Color.filmCard))
                        .overlay(Capsule().strokeBorder(backdrop == .level ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(backdrop == .level ? .isSelected : [])
                    .accessibilityIdentifier("cardBackdrop.level")
                    ForEach(PhotoPalette.all, id: \.self) { hex in
                        Button { backdrop = .color(hex) } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Circle().strokeBorder(backdrop == .color(hex) ? Color.accentColor : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(backdrop == .color(hex) ? .isSelected : [])
                        .accessibilityIdentifier("cardBackdrop.\(hex)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// How the A3 sheet is printed (27 Nov 2026): which way the shop's machine
/// turns the sheet, a lift for a machine that prints dark, and the
/// instructions for the print shop — to read here and to copy into a message.
struct CardPrintOptions: View {
    @State private var flip = CardPrint.flip
    @State private var lighten = CardPrint.lighten
    @State private var copied = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    /// The print shop reads the sheet's language.
    private var sheetChinese: Bool { AreaLanguage.isChinese(.playerCard) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "双面翻转方式" : "The sheet is turned over on its")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $flip) {
                    ForEach(CardPrint.Flip.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cardPrint.flip")
                Text(isChinese ? "横向 A3 一般选短边翻转。正反面对不上、背面倒过来时，换另一种。"
                               : "Short edge is the usual one for a landscape A3. If the backs come out on the wrong cards or upside down, choose the other.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(isChinese ? "打印偏暗时" : "If the print comes out dark")
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $lighten) {
                    ForEach(CardPrint.Lighten.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("cardPrint.lighten")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isChinese ? "给打印店的说明" : "For the print shop")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        UIPasteboard.general.string = CardPrint.instructions(flip: flip, chinese: sheetChinese)
                            .enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                        copied = true
                    } label: {
                        Label(copied ? (isChinese ? "已复制" : "Copied") : (isChinese ? "复制" : "Copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("cardPrint.copy")
                }
                ForEach(Array(CardPrint.instructions(flip: flip, chinese: isChinese).enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 14)
                        Text(line).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cardPrint.instructions")
        }
        .onChange(of: flip) { _, value in CardPrint.flip = value; copied = false }
        .onChange(of: lighten) { _, value in CardPrint.lighten = value }
    }
}

/// The print options on their own, from the single card's share sheet.
struct CardPrintOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                CardPrintOptions().padding(20)
            }
            .navigationTitle(isChinese ? "打印设置" : "Printing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
        }
    }
}

/// Before a print sheet of many cards: keep everyone's level colour, or one
/// colour for all.
struct CardBackdropSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onChoose: (CardBackdrop) -> Void
    @State private var backdrop: CardBackdrop = .level

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(isChinese ? "抠图照片的背景用什么颜色？" : "What colour goes behind the cut-out photos?")
                        .font(.headline)
                    CardBackdropPicker(backdrop: $backdrop, levelHex: nil)
                    Divider()
                    CardPrintOptions()
                }
                .padding(20)
            }
            .navigationTitle(isChinese ? "打印球员卡" : "Print player cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "打印" : "Print") {
                        onChoose(backdrop)
                        dismiss()
                    }
                    .accessibilityIdentifier("cardBackdrop.print")
                }
            }
        }
        .presentationDetents([.large])
    }
}
