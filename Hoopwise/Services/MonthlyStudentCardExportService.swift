import Foundation
import SwiftUI
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UIKit)
import UIKit
#endif

private extension String {
    static func cardBgKey(_ studentId: UUID) -> String {
        "student_card_bg_\(studentId.uuidString)"
    }
}

enum MonthlyStudentCardExportError: LocalizedError {
    case missingProgram
    case noStudents
    case unsupportedPlatform
    case pdfGenerationFailed

    var errorDescription: String? {
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        switch self {
        case .missingProgram:
            return isChinese ? "无法找到该课程对应的项目。" : "Unable to find the program for this session."
        case .noStudents:
            return isChinese ? "该项目没有可导出的学员。" : "There are no students to export for this program."
        case .unsupportedPlatform:
            return isChinese ? "当前平台暂不支持导出打印卡片。" : "Student card export is not supported on this platform yet."
        case .pdfGenerationFailed:
            return isChinese ? "生成 PDF 失败。" : "Failed to generate the PDF."
        }
    }
}

enum StudentCardPageSide {
    case front
    case back
}

struct MonthlyStudentCardSnapshot: Identifiable {
    let id: UUID
    let student: Student
    let player: Player?
    let program: Program
    let monthDate: Date
    let monthLabel: String
    let trainingStats: TrainingSessionStats
    let monthlyTrainingStats: TrainingSessionStats
    let previousMonthTrainingStats: TrainingSessionStats?
    let trailingThreeMonthStats: [TrainingSessionStats]
    let programContext: ProgramStatsContext
    let performanceMetrics: PerformanceRadarMetrics
    let previousPerformanceMetrics: PerformanceRadarMetrics?
    let effectiveGrade: PerformanceGrade
    let profileImage: CacheImage?
    let backgroundImage: CacheImage?

    enum TrendMetric {
        case ppg
        case apg
        case rpg
        case spg
        case bpg
        case effort
    }

    private static let pinyinSyllables: Set<String> = [
        "an", "ang", "bao", "bei", "bo", "cai", "cao", "chen", "cheng", "chi", "chong", "chuan", "chuang",
        "cong", "da", "dan", "ding", "dong", "fan", "fang", "fei", "feng", "fu", "gao", "guo", "hao", "he",
        "hong", "hu", "hua", "hui", "jia", "jian", "jiang", "jie", "jin", "jing", "juan", "jun", "kai", "ke",
        "kun", "lai", "lei", "li", "lian", "liang", "lin", "ling", "liu", "long", "lu", "luo", "mei", "meng",
        "ming", "na", "ning", "peng", "qi", "qian", "qin", "qing", "qiu", "ran", "rui", "shan", "sheng", "shi",
        "shu", "song", "tao", "ting", "wei", "wen", "wu", "xi", "xian", "xiang", "xiao", "xin", "xing", "xiu",
        "xuan", "xue", "ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yong", "you", "yu", "yue",
        "yun", "zeng", "zhang", "zhao", "zhe", "zheng", "zhi", "zhou", "zhu", "zi"
    ]

    var accentColor: Color {
        Color.avatarColor(student.avatarColor)
    }

    var gradeColor: Color {
        switch effectiveGrade {
        case .A:
            return Color(red: 0.85, green: 0.65, blue: 0.0)
        case .B:
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .C:
            return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .ungraded:
            return .black
        }
    }

    var heightString: String {
        guard let height = player?.heightCm else { return "—" }
        let feet = Int(height / 30.48)
        let inches = Int((height / 2.54).truncatingRemainder(dividingBy: 12))
        return "\(feet)'\(inches)\""
    }

    var effortString: String {
        guard trainingStats.hasStats else { return "—" }
        let effort = trainingStats.rpg + trainingStats.apg + trainingStats.spg + trainingStats.bpg
        return String(format: "%.1f", effort)
    }

    func handednessString(loc: ReportLocalization) -> String {
        guard let handedness = player?.handedness else { return "—" }
        return loc.handednessLabel(handedness)
    }

    func formatStat(_ value: Double) -> String {
        guard trainingStats.hasStats else { return "—" }
        if value == 0 {
            return "0.0"
        }
        return String(format: "%.1f", value)
    }

    var primaryCardName: String {
        guard let chineseName = student.chineseName, isLikelyPinyin(student.name) else {
            return student.name
        }
        return chineseName
    }

    var secondaryCardName: String? {
        guard let chineseName = student.chineseName else { return nil }
        return primaryCardName == chineseName ? nil : chineseName
    }

    var primaryCardNameIsLatin: Bool {
        primaryCardName.range(of: "[A-Za-z]", options: .regularExpression) != nil
    }

    func monthlyTrendValues(for metric: TrendMetric) -> [Double] {
        trailingThreeMonthStats.map { statValue(for: metric, in: $0) }
    }

    func deltaValue(for metric: TrendMetric) -> Double? {
        guard monthlyTrainingStats.hasStats || previousMonthTrainingStats?.hasStats == true else {
            return nil
        }
        let previous = previousMonthTrainingStats.map { statValue(for: metric, in: $0) } ?? 0
        return statValue(for: metric, in: monthlyTrainingStats) - previous
    }

    func deltaText(for metric: TrendMetric, loc: ReportLocalization) -> String {
        guard let delta = deltaValue(for: metric) else { return "—" }
        let arrow: String
        switch delta {
        case let value where value > 0.05:
            arrow = "↑"
        case let value where value < -0.05:
            arrow = "↓"
        default:
            arrow = "→"
        }
        let valueText = String(format: "%@%.1f", delta >= 0 ? "+" : "", delta)
        let unit = deltaUnit(for: metric, loc: loc)
        return loc.isChinese ? "\(arrow) \(valueText)\(unit)" : "\(arrow) \(valueText) \(unit)"
    }

    func gamesSummaryText(loc: ReportLocalization) -> String {
        if monthlyTrainingStats.hasStats {
            return loc.isChinese
                ? "本月 \(monthlyTrainingStats.gamesPlayed) 场比赛"
                : "\(monthlyTrainingStats.gamesPlayed) games this month"
        }
        return loc.isChinese ? "本月暂无比赛数据" : "No games this month"
    }

    private func statValue(for metric: TrendMetric, in stats: TrainingSessionStats) -> Double {
        switch metric {
        case .ppg:
            return stats.ppg
        case .apg:
            return stats.apg
        case .rpg:
            return stats.rpg
        case .spg:
            return stats.spg
        case .bpg:
            return stats.bpg
        case .effort:
            guard stats.hasStats else { return 0 }
            return stats.rpg + stats.apg + stats.spg + stats.bpg
        }
    }

    private func deltaUnit(for metric: TrendMetric, loc: ReportLocalization) -> String {
        switch metric {
        case .ppg:
            return loc.isChinese ? "分" : "pts"
        case .apg:
            return loc.isChinese ? "助" : "ast"
        case .rpg:
            return loc.isChinese ? "板" : "reb"
        case .spg:
            return loc.isChinese ? "断" : "stl"
        case .bpg:
            return loc.isChinese ? "帽" : "blk"
        case .effort:
            return loc.isChinese ? "效" : "eff"
        }
    }

    private func isLikelyPinyin(_ value: String) -> Bool {
        guard student.chineseName != nil else { return false }
        if value.range(of: "[āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü]", options: .regularExpression) != nil {
            return true
        }
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let tokens = normalized.split { !$0.isLetter }.map(String.init)
        guard !tokens.isEmpty, tokens.count <= 4 else { return false }
        return tokens.allSatisfy { Self.pinyinSyllables.contains($0) }
    }
}

@MainActor
struct MonthlyStudentCardExportService {
    let dataManager: DataManager

    func exportMonthlyCards(for session: SessionEvent) async throws -> URL {
        guard let programId = session.programId,
              dataManager.programs.contains(where: { $0.id == programId }) else {
            throw MonthlyStudentCardExportError.missingProgram
        }
        let snapshots = await buildSnapshots(for: session)
        guard !snapshots.isEmpty else {
            throw MonthlyStudentCardExportError.noStudents
        }
        #if canImport(UIKit)
        return try StudentCardPDFExporter.export(snapshots: snapshots, fileName: fileName(for: snapshots, session: session))
        #else
        throw MonthlyStudentCardExportError.unsupportedPlatform
        #endif
    }

    func buildSnapshots(for session: SessionEvent) async -> [MonthlyStudentCardSnapshot] {
        guard let programId = session.programId,
              let program = dataManager.programs.first(where: { $0.id == programId }) else {
            return []
        }

        let roster = dataManager.students
            .filter { program.enrolledStudentIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !roster.isEmpty else {
            return []
        }

        let monthSessions = monthlySessions(around: session.date)
        let trailingMonthAnchors = trailingMonthDates(endingAt: session.date, count: 3)
        let trailingMonthSessions = trailingMonthAnchors.map { monthlySessions(around: $0) }
        let skillsByStudent = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        let allMonthlyStats = roster.map { TrainingSessionStats.calculate(for: $0.id, from: monthSessions) }
        let programContext = ProgramStatsContext.calculate(from: allMonthlyStats.filter { $0.hasStats })
        let trailingProgramContexts = trailingMonthSessions.map { monthSessions in
            let monthlyStats = roster.map { TrainingSessionStats.calculate(for: $0.id, from: monthSessions) }
            return ProgramStatsContext.calculate(from: monthlyStats.filter { $0.hasStats })
        }
        let allStudents = dataManager.students
        let allSessions = dataManager.sessionEvents
        let monthLabel = monthLabel(for: session.date)

        var snapshots: [MonthlyStudentCardSnapshot] = []
        snapshots.reserveCapacity(roster.count)

        for student in roster {
            let player = dataManager.player(for: student.id)
            let trailingStats = trailingMonthSessions.map { TrainingSessionStats.calculate(for: student.id, from: $0) }
            let monthlyStats = trailingStats.last ?? TrainingSessionStats.calculate(for: student.id, from: monthSessions)
            let previousMonthlyStats = trailingStats.count >= 2 ? trailingStats[trailingStats.count - 2] : nil
            let displayStats = TrainingSessionStats.calculate(for: student.id, from: allSessions)
            let metrics = PerformanceRadarMetrics.compute(
                from: monthlyStats.hasStats ? monthlyStats : nil,
                skills: player?.skills ?? SkillsEvaluation(),
                programContext: programContext
            )
            let previousMetrics: PerformanceRadarMetrics? = {
                guard let previousMonthlyStats else { return nil }
                let previousContext = trailingProgramContexts.count >= 2 ? trailingProgramContexts[trailingProgramContexts.count - 2] : .empty
                return PerformanceRadarMetrics.compute(
                    from: previousMonthlyStats.hasStats ? previousMonthlyStats : nil,
                    skills: player?.skills ?? SkillsEvaluation(),
                    programContext: previousContext
                )
            }()
            let grade = StudentPerformanceGrader.computeGrade(
                for: student,
                allStudents: allStudents,
                sessions: allSessions,
                skills: skillsByStudent
            )
            let profileImage = await loadProfileImage(for: student, player: player)
            let backgroundImage = await loadBackgroundImage(for: student)

            snapshots.append(
                MonthlyStudentCardSnapshot(
                    id: student.id,
                    student: student,
                    player: player,
                    program: program,
                    monthDate: session.date,
                    monthLabel: monthLabel,
                    trainingStats: displayStats,
                    monthlyTrainingStats: monthlyStats,
                    previousMonthTrainingStats: previousMonthlyStats,
                    trailingThreeMonthStats: trailingStats,
                    programContext: programContext,
                    performanceMetrics: metrics,
                    previousPerformanceMetrics: previousMetrics,
                    effectiveGrade: grade,
                    profileImage: profileImage,
                    backgroundImage: backgroundImage
                )
            )
        }

        return snapshots
    }

    private func monthlySessions(around date: Date) -> [SessionEvent] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return dataManager.sessionEvents
            .filter { session in
                session.date >= interval.start &&
                session.date < interval.end &&
                session.status != .cancelled
            }
            .sorted { $0.date < $1.date }
    }

    private func trailingMonthDates(endingAt date: Date, count: Int) -> [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return (0..<count).compactMap { index in
            calendar.date(byAdding: .month, value: index - (count - 1), to: monthStart)
        }
    }

    private func monthLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        let loc = ReportLocalization()
        formatter.dateFormat = loc.isChinese ? "yyyy年M月" : "MMM yyyy"
        formatter.locale = Locale(identifier: loc.isChinese ? "zh_CN" : "en_US_POSIX")
        return formatter.string(from: date).uppercased()
    }

    private func fileName(for snapshots: [MonthlyStudentCardSnapshot], session: SessionEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: session.date)
        let programName = snapshots.first?.program.name ?? session.title
        let safeProgram = programName.replacingOccurrences(of: "/", with: "-")
        return "\(safeProgram)-student-cards-\(month)"
    }

    private func loadProfileImage(for student: Student, player: Player?) async -> CacheImage? {
        if let data = player?.profileImageData,
           let image = decodeExportImage(from: data, maxPixelSize: 1800) {
            return image
        }
        if let urlString = student.profileImageUrl, !urlString.isEmpty {
            return await loadExportImage(from: urlString, studentId: student.id, maxPixelSize: 1800)
        }
        return nil
    }

    private func loadBackgroundImage(for student: Student) async -> CacheImage? {
        let urlString: String
        if let saved = UserDefaults.standard.string(forKey: .cardBgKey(student.id)),
           !saved.isEmpty,
           StudentProfileHeaderView.curatedImages.contains(saved) {
            urlString = saved
        } else {
            urlString = StudentProfileHeaderView.basketballURL(for: student.id)
        }
        let upgradedURL = upgradedBackgroundURLString(from: urlString)
        return await loadExportImage(from: upgradedURL, studentId: student.id, maxPixelSize: 2800)
    }

    private func loadExportImage(from urlString: String, studentId: UUID, maxPixelSize: CGFloat) async -> CacheImage? {
        if urlString.hasPrefix("file://") || urlString.hasPrefix("/var/") || urlString.hasPrefix("/Users/") {
            let localPath = urlString.replacingOccurrences(of: "file://", with: "")
            if FileManager.default.fileExists(atPath: localPath),
               let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)) {
                return decodeExportImage(from: data, maxPixelSize: maxPixelSize)
            }
        }

        let resolvedURLString = resolvedRemoteURLString(from: urlString, studentId: studentId)
        guard let resolvedURLString,
              let url = URL(string: resolvedURLString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return decodeExportImage(from: data, maxPixelSize: maxPixelSize)
        } catch {
            return nil
        }
    }

    private func resolvedRemoteURLString(from urlString: String, studentId: UUID) -> String? {
        if urlString.hasPrefix("file://") || urlString.hasPrefix("/var/") || urlString.hasPrefix("/Users/") {
            return "\(SupabaseConfig.url)/storage/v1/object/public/profile-images/students/\(studentId.uuidString).jpg"
        }
        return urlString
    }

    private func upgradedBackgroundURLString(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString), let host = components.host else {
            return urlString
        }

        if host.contains("unsplash.com") {
            var queryItems = components.queryItems ?? []
            func upsert(_ name: String, _ value: String) {
                if let index = queryItems.firstIndex(where: { $0.name == name }) {
                    queryItems[index] = URLQueryItem(name: name, value: value)
                } else {
                    queryItems.append(URLQueryItem(name: name, value: value))
                }
            }
            upsert("w", "2400")
            upsert("h", "1200")
            upsert("fit", "crop")
            upsert("q", "90")
            components.queryItems = queryItems
            return components.string ?? urlString
        }

        return urlString
    }

    private func decodeExportImage(from data: Data, maxPixelSize: CGFloat) -> CacheImage? {
        #if canImport(ImageIO)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return CacheImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return CacheImage(data: data)
        }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
        #else
        return CacheImage(data: data)
        #endif
    }
}

#if canImport(UIKit)
@MainActor
struct StudentCardPDFExporter {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let pageMargin: CGFloat = 18
    static let interItemSpacing: CGFloat = 12
    static let gridRows = 2
    static let gridColumns = 3
    static let cardsPerPage = gridRows * gridColumns
    static let cardAspectRatio: CGFloat = StudentCollectibleCardFrontView.baseSize.height / StudentCollectibleCardFrontView.baseSize.width
    static let printRenderScale: CGFloat = 450.0 / 72.0

    static func export(snapshots: [MonthlyStudentCardSnapshot], fileName: String) throws -> URL {
        guard !snapshots.isEmpty else {
            throw MonthlyStudentCardExportError.noStudents
        }

        let availableWidth = pageSize.width - (pageMargin * 2) - (interItemSpacing * CGFloat(gridColumns - 1))
        let availableHeight = pageSize.height - (pageMargin * 2) - (interItemSpacing * CGFloat(gridRows - 1))
        let widthConstrainedCardWidth = availableWidth / CGFloat(gridColumns)
        let heightConstrainedCardWidth = (availableHeight / CGFloat(gridRows)) / cardAspectRatio
        let cardWidth = min(widthConstrainedCardWidth, heightConstrainedCardWidth)
        let cardHeight = cardWidth * cardAspectRatio
        let cardSize = CGSize(width: cardWidth, height: cardHeight)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("pdf")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let chunks = snapshots.chunked(into: cardsPerPage)

        do {
            try renderer.writePDF(to: outputURL) { context in
                for chunk in chunks {
                    context.beginPage()
                    renderPage(chunk, side: .front, cardSize: cardSize, in: context)
                }
                for chunk in chunks {
                    context.beginPage()
                    renderPage(chunk, side: .back, cardSize: cardSize, in: context)
                }
            }
        } catch {
            throw MonthlyStudentCardExportError.pdfGenerationFailed
        }

        return outputURL
    }

    private static func renderPage(_ snapshots: [MonthlyStudentCardSnapshot], side: StudentCardPageSide, cardSize: CGSize, in context: UIGraphicsPDFRendererContext) {
        guard let image = renderPageImage(snapshots, side: side, cardSize: cardSize) else {
            return
        }

        UIColor.white.setFill()
        context.cgContext.fill(CGRect(origin: .zero, size: pageSize))
        image.draw(in: CGRect(origin: .zero, size: pageSize))
    }

    private static func renderPageImage(_ snapshots: [MonthlyStudentCardSnapshot], side: StudentCardPageSide, cardSize: CGSize) -> UIImage? {
        let view = MonthlyStudentCardPDFPageView(
            snapshots: snapshots,
            side: side,
            pageSize: pageSize,
            cardSize: cardSize,
            pageMargin: pageMargin,
            interItemSpacing: interItemSpacing,
            rows: gridRows,
            columns: gridColumns
        )
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .white
        controller.view.isOpaque = true
        controller.view.bounds = CGRect(origin: .zero, size: pageSize)
        controller.view.frame = CGRect(origin: .zero, size: pageSize)
        controller.view.contentScaleFactor = printRenderScale
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = printRenderScale
        let renderer = UIGraphicsImageRenderer(size: pageSize, format: format)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: pageSize))
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
#endif
