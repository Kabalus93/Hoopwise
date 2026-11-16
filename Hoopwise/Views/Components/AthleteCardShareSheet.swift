import SwiftUI

extension DataManager {
    /// The athlete's card for this month (Services/AthleteCardFacts.swift).
    func athleteCard(for student: Student, coachLine: String = "", now: Date = Date()) -> AthleteCardFacts {
        let academy = ProgramGuideStore.academyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return AthleteCardFacts.make(
            student: student, players: players, programs: programs, sessions: sessionEvents, drills: drills,
            categoryHex: ageCategory(for: student)?.colorHex ?? "#007AFF",
            coach: coach.name, academy: academy, coachLine: coachLine, now: now)
    }

    /// Cards for everyone a session expects, plus anyone marked at it — the
    /// roster the session page shows (its stored roster is often empty and
    /// the program's enrolment stands in).
    func athleteCards(forSession session: SessionEvent) -> [AthleteCardFacts] {
        var ids = AttendanceMath.expectedIds(of: session, programs: programs)
        for id in session.actualAttendeeIds + session.excusedAbsences + session.unexcusedAbsences where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap { id in students.first { $0.id == id } }
            .sorted { $0.primaryDisplayName < $1.primaryDisplayName }
            .map { athleteCard(for: $0) }
    }

    /// Cards for a program's enrolled athletes.
    func athleteCards(forProgram program: Program) -> [AthleteCardFacts] {
        program.enrolledStudentIds.compactMap { id in students.first { $0.id == id } }
            .sorted { $0.primaryDisplayName < $1.primaryDisplayName }
            .map { athleteCard(for: $0) }
    }
}

/// Share an athlete's card: the card as it will be sent (front and back), a
/// line from the coach, then Share image (WeChat) or an A3 print sheet.
struct AthleteCardShareSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let student: Student

    @State private var coachLine = ""
    @State private var shareItems: [Any]?
    @State private var working = false
    @State private var problem: String?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var card: AthleteCardFacts { dataManager.athleteCard(for: student, coachLine: coachLine) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isChinese ? "教练寄语（可选）" : "A word from the coach (optional)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(isChinese ? "例如：这个月传球进步很大！" : "e.g. Big step forward with passing this month!",
                                  text: $coachLine, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(Color(.systemGroupedBackground))
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
