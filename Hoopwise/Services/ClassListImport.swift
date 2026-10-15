import Foundation

// MARK: - The coach's class list (上课名单)
//
// How coaches at the academy keep their books: one spreadsheet per coach,
// one block per class ("周一 18:30 U6", coach, 人数), then the students in it,
// each with EITHER sessions left (剩余课时) OR months left (剩余时长), and a
// note — "课时与其他班共用" when a student attends two classes on one balance.
// A "长期不来" block lists students who stopped coming; a "总人次" row closes
// the sheet (a student in two classes counts twice).
//
// October 2026 (Luther): the app imports this sheet — students, their
// balances, the classes as programs, and the calendar — and exports the same
// sheet back with live numbers, on iPhone and Mac. Three pure steps here
// (parse → plan → export) and one write (`SwiftDataManager.applyClassListImport`).
//
// MONTHS: the most accurate unit is sessions, so a months balance is entered
// as sessions at FOUR a month (one class a week) and counts down by
// attendance like every other balance. The contract's notes carry the
// `monthsMarker` so the export can print it back in months.

enum ClassList {

    /// Appended to a contract's notes when its balance was entered in months.
    static let monthsMarker = "【按月计 · 4 节/月】"
    static let sessionsPerMonth = 4

    // MARK: Parsed sheet

    struct Entry: Equatable {
        var name: String
        var sessionsLeft: Int?
        var monthsLeft: Double?
        var note: String?
        /// Spreadsheet row, 1-based, for messages the coach can find.
        var row: Int

        /// The balance in sessions — months converted at four a month.
        var sessions: Int? {
            if let sessionsLeft { return sessionsLeft }
            if let monthsLeft { return Int((monthsLeft * Double(ClassList.sessionsPerMonth)).rounded()) }
            return nil
        }
        var isMonthsBased: Bool { sessionsLeft == nil && monthsLeft != nil }
    }

    struct Block: Equatable {
        var title: String
        var weekday: Weekday?
        var hour: Int?
        var minute: Int?
        var ageGroup: AgeGroup?
        var coach: String?
        var declaredCount: Int?
        var entries: [Entry]
        var row: Int
        /// A block with no schedule ("长期不来"): students without a class.
        var isUnscheduled: Bool { weekday == nil || hour == nil }

        /// "周一 18:30 U6" — the canonical spelling the export writes back.
        var canonicalTitle: String {
            guard let weekday, let hour, let minute else { return title }
            let age = ageGroup.map { " \($0.rawValue)" } ?? ""
            return "\(ClassList.chineseWeekday(weekday)) \(String(format: "%02d:%02d", hour, minute))\(age)"
        }
    }

    struct Issue: Equatable, Identifiable {
        var row: Int?
        var message: String
        var id: String { "\(row ?? 0):\(message)" }
    }

    struct Sheet: Equatable {
        var blocks: [Block]
        var declaredTotal: Int?
        /// The coach named on the total row ("<coach> 总人次").
        var totalCoach: String?
        var issues: [Issue]
    }

    // MARK: Parse

    /// Reads a class list from the first sheet that has one. Tolerant of the
    /// layout drifting (header text locates the columns), strict about what
    /// it reports: every count mismatch and unreadable cell becomes an Issue.
    static func parse(_ sheets: [XLSXSheet]) -> Sheet? {
        for sheet in sheets {
            if let parsed = parse(rows: sheet.rows) { return parsed }
        }
        return nil
    }

    static func parse(rows: [[XLSXCell]]) -> Sheet? {
        func text(_ row: [XLSXCell], _ col: Int?) -> String {
            guard let col, col < row.count else { return "" }
            return row[col].stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func number(_ row: [XLSXCell], _ col: Int?) -> Double? {
            let raw = text(row, col)
            guard !raw.isEmpty else { return nil }
            return Double(raw)
        }

        // Header row: the one naming the class and student columns.
        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains { $0.stringValue.contains("课程") } && row.contains { $0.stringValue.contains("学生") }
        }) else { return nil }
        let header = rows[headerIndex].map { $0.stringValue }
        func column(_ keys: [String], fallback: Int) -> Int {
            header.firstIndex { cell in keys.contains { cell.contains($0) } } ?? fallback
        }
        let classCol = column(["课程"], fallback: 0)
        let coachCol = column(["教练"], fallback: 1)
        let studentCol = column(["学生"], fallback: 2)
        let sessionsCol = column(["课时", "节"], fallback: 3)
        let monthsCol = column(["时长", "月"], fallback: 4)
        let noteCol = column(["备注"], fallback: 5)

        var blocks: [Block] = []
        var issues: [Issue] = []
        var declaredTotal: Int?
        var totalCoach: String?

        for index in rows.indices where index > headerIndex {
            let row = rows[index]
            let line = index + 1
            let classText = text(row, classCol)
            let student = text(row, studentCol)

            if classText.contains("总人次") {
                declaredTotal = number(row, sessionsCol).map { Int($0) }
                let coach = classText.replacingOccurrences(of: "总人次", with: "")
                    .trimmingCharacters(in: .whitespaces)
                totalCoach = coach.isEmpty ? nil : coach
                continue
            }

            if !classText.isEmpty {
                var block = Block(title: classText, coach: nilIfEmpty(text(row, coachCol)),
                                  entries: [], row: line)
                parseTitle(classText, into: &block)
                if student.hasPrefix("人数") {
                    block.declaredCount = number(row, sessionsCol).map { Int($0) }
                }
                if !block.isUnscheduled, block.ageGroup == nil {
                    issues.append(Issue(row: line, message: "\(classText): no age group (U6, U8 …) — choose one before importing"))
                }
                if block.isUnscheduled, !classText.contains("不来") {
                    issues.append(Issue(row: line, message: "\(classText): no weekday and time — its students are imported without a class"))
                }
                blocks.append(block)
                continue
            }

            guard !student.isEmpty, !student.hasPrefix("人数") else { continue }
            guard !blocks.isEmpty else {
                issues.append(Issue(row: line, message: "\(student) is not under any class"))
                continue
            }
            let sessions = number(row, sessionsCol)
            let months = number(row, monthsCol)
            var entry = Entry(name: student,
                              sessionsLeft: sessions.map { Int($0.rounded()) },
                              monthsLeft: months,
                              note: nilIfEmpty(text(row, noteCol)),
                              row: line)
            if sessions != nil && months != nil {
                issues.append(Issue(row: line, message: "\(student): both sessions and months are filled — using sessions"))
                entry.monthsLeft = nil
            } else if sessions == nil && months == nil {
                issues.append(Issue(row: line, message: "\(student): no balance — imported with none"))
            }
            blocks[blocks.count - 1].entries.append(entry)
        }

        // The sheet's own checks.
        for block in blocks {
            if let declared = block.declaredCount, declared != block.entries.count {
                issues.append(Issue(row: block.row,
                                    message: "\(block.title): 人数 says \(declared), \(block.entries.count) students are listed"))
            }
        }
        if let declaredTotal {
            let counted = blocks
                .filter { !$0.isUnscheduled }
                .filter { totalCoach == nil || $0.coach == nil || $0.coach == totalCoach }
                .reduce(0) { $0 + $1.entries.count }
            if counted != declaredTotal {
                issues.append(Issue(row: nil,
                                    message: "总人次 says \(declaredTotal), the classes\(totalCoach.map { " of \($0)" } ?? "") list \(counted)"))
            }
        }
        // One name, two different balances: the sheet treats a repeated name
        // as one student on one balance, so a disagreement is a typo to fix.
        var seen: [String: Entry] = [:]
        for entry in blocks.flatMap(\.entries) {
            if let first = seen[entry.name] {
                if first.sessions != entry.sessions {
                    issues.append(Issue(row: entry.row,
                                        message: "\(entry.name) appears with \(first.sessions.map(String.init) ?? "no") and \(entry.sessions.map(String.init) ?? "no") sessions — the first (row \(first.row)) is used"))
                }
            } else {
                seen[entry.name] = entry
            }
        }

        return Sheet(blocks: blocks, declaredTotal: declaredTotal, totalCoach: totalCoach, issues: issues)
    }

    private static func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    private static let weekdayChars: [Character: Weekday] = [
        "一": .monday, "二": .tuesday, "三": .wednesday, "四": .thursday,
        "五": .friday, "六": .saturday, "日": .sunday, "天": .sunday
    ]

    static func chineseWeekday(_ day: Weekday) -> String {
        switch day {
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        case .sunday: return "周日"
        }
    }

    /// "周一 18:30 U6", "星期六 10:00 U12", "周日15:00 U10".
    static func parseTitle(_ title: String, into block: inout Block) {
        let chars = Array(title)
        for (i, c) in chars.enumerated() where c == "周" || (c == "期" && i > 0 && chars[i - 1] == "星") {
            if i + 1 < chars.count, let day = weekdayChars[chars[i + 1]] {
                block.weekday = day
                break
            }
        }
        if let groups = captures(#"(\d{1,2})\s*[:：]\s*(\d{2})"#, in: title),
           let h = Int(groups[0]), let m = Int(groups[1]), h < 24, m < 60 {
            block.hour = h
            block.minute = m
        }
        if let groups = captures(#"[Uu]\s*(\d{1,2})"#, in: title), let n = Int(groups[0]) {
            // Odd bands round up to the app's even categories (U7 → U8).
            let even = n % 2 == 0 ? n : n + 1
            block.ageGroup = AgeGroup(rawValue: "U\(even)")
        } else if title.contains("成人") || title.lowercased().contains("adult") {
            block.ageGroup = .adult
        }
    }

    /// Capture groups of the first match (Swift 5 mode: no regex literals).
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    // MARK: Plan

    struct Options {
        /// First day sessions may be created on.
        var from: Date
        /// Last day (inclusive).
        var through: Date
        var durationMinutes: Int = 90
        var calendar: Calendar = .current
    }

    struct PlannedStudent: Identifiable, Equatable {
        var id: UUID
        var name: String
        var isNew: Bool
        /// nil = no balance to create (none in the sheet, or one exists).
        var balanceSessions: Int?
        var monthsBased: Bool
        var monthsLeft: Double?
        var keptExistingBalance: Int?
    }

    struct PlannedClass: Identifiable, Equatable {
        var id: UUID
        var block: Block
        var isNew: Bool
        var coachId: UUID?
        var studentIds: [UUID]
        var sessionStarts: [Date]
    }

    struct Plan: Equatable {
        var students: [PlannedStudent]
        var classes: [PlannedClass]
        /// Students in an unscheduled block: created with their balance, not
        /// enrolled anywhere.
        var withoutClass: [UUID]
        var issues: [Issue]
        var options: Options

        var newStudentCount: Int { students.filter(\.isNew).count }
        var newClassCount: Int { classes.filter(\.isNew).count }
        var sessionCount: Int { classes.reduce(0) { $0 + $1.sessionStarts.count } }
        var balanceCount: Int { students.filter { $0.balanceSessions != nil }.count }

        static func == (a: Plan, b: Plan) -> Bool {
            a.students == b.students && a.classes == b.classes && a.withoutClass == b.withoutClass
                && a.issues == b.issues
        }
    }

    /// Decides everything the import will write, and writes nothing.
    /// - Students match an existing student by name or Chinese name; the rest
    ///   are new. A repeated name in the sheet is ONE student (the sheet's
    ///   "shared balance" rule).
    /// - A student who already holds a group session balance keeps it; the
    ///   sheet's number is reported, not added on top — re-importing the same
    ///   sheet must never double a balance.
    /// - A class matches an existing program on weekday + start time + age
    ///   group; otherwise it becomes a new group program (no phases — the
    ///   coach adds those later).
    /// - Sessions fill each class's weekday between `from` and `through`,
    ///   skipping days the program already has a session.
    static func plan(_ sheet: Sheet,
                     students: [Student],
                     contracts: [Contract],
                     programs: [Program],
                     sessions: [SessionEvent],
                     coaches: [StaffCoach],
                     accountCoach: (id: UUID, name: String)?,
                     options: Options) -> Plan {
        var issues = sheet.issues
        let calendar = options.calendar

        // Students, once each.
        var planned: [String: PlannedStudent] = [:]
        var order: [String] = []
        for entry in sheet.blocks.flatMap(\.entries) where planned[entry.name] == nil {
            let key = normalized(entry.name)
            let existing = students.first {
                normalized($0.name) == key || $0.chineseName.map(normalized) == key
            }
            let id = existing?.id ?? UUID()
            let held = existing.flatMap { student in
                contracts.first { $0.studentId == student.id && $0.kind == .group
                    && $0.hasSessionBalance && $0.status == .active }
            }
            var student = PlannedStudent(id: id, name: entry.name, isNew: existing == nil,
                                         balanceSessions: entry.sessions,
                                         monthsBased: entry.isMonthsBased,
                                         monthsLeft: entry.monthsLeft,
                                         keptExistingBalance: nil)
            if let held {
                student.keptExistingBalance = held.bundleRedemptionsRemaining
                student.balanceSessions = nil
                issues.append(Issue(row: entry.row,
                                    message: "\(entry.name) already has a balance (\(held.bundleRedemptionsRemaining ?? 0) left) — kept; the sheet's \(entry.sessions.map(String.init) ?? "—") is not added"))
            }
            planned[entry.name] = student
            order.append(entry.name)
        }

        // Classes.
        var classes: [PlannedClass] = []
        var missingCoaches: [String: [String]] = [:]
        var withoutClass: [UUID] = []
        for block in sheet.blocks {
            let ids = block.entries.compactMap { planned[$0.name]?.id }
            guard !block.isUnscheduled, let weekday = block.weekday,
                  let hour = block.hour, let minute = block.minute else {
                withoutClass.append(contentsOf: ids.filter { !withoutClass.contains($0) })
                continue
            }
            let existing = programs.first { program in
                guard program.status != .archived,
                      program.recurringDays.contains(weekday),
                      let time = program.defaultSessionTime,
                      block.ageGroup == nil || program.ageGroup == block.ageGroup else { return false }
                let parts = calendar.dateComponents([.hour, .minute], from: time)
                return parts.hour == hour && parts.minute == minute
            }
            let coachId = block.coach.flatMap { name in
                coaches.first { $0.name == name || $0.chineseName == name }?.id
                    ?? (accountCoach?.name == name ? accountCoach?.id : nil)
            }
            if let name = block.coach, coachId == nil, existing?.coachId == nil {
                missingCoaches[name, default: []].append(block.canonicalTitle)
            }
            let programId = existing?.id ?? UUID()
            let taken = Set(sessions.filter { $0.programId == programId }
                .map { calendar.startOfDay(for: $0.startTime) })
            let starts = classDates(weekday: weekday, hour: hour, minute: minute,
                                    options: options)
                .filter { !taken.contains(calendar.startOfDay(for: $0)) }
            classes.append(PlannedClass(id: programId, block: block, isNew: existing == nil,
                                        coachId: existing?.coachId ?? coachId,
                                        studentIds: ids, sessionStarts: starts))
        }
        // One line per missing coach, not one per class.
        for name in missingCoaches.keys.sorted() {
            let titles = missingCoaches[name] ?? []
            issues.append(Issue(row: nil,
                                message: "Coach \(name) is not in the app — \(titles.count == 1 ? titles[0] : "\(titles.count) classes") imported without a coach. Add \(name) as a coach (or their Chinese name) first to link them."))
        }

        // A student with a class is not "without class" because another block
        // (长期不来) also lists them.
        let inAClass = Set(classes.flatMap(\.studentIds))
        withoutClass.removeAll { inAClass.contains($0) }

        return Plan(students: order.compactMap { planned[$0] }, classes: classes,
                    withoutClass: withoutClass, issues: issues, options: options)
    }

    static func classDates(weekday: Weekday, hour: Int, minute: Int, options: Options) -> [Date] {
        let calendar = options.calendar
        var dates: [Date] = []
        var day = calendar.startOfDay(for: options.from)
        let last = calendar.startOfDay(for: options.through)
        while day <= last {
            if calendar.component(.weekday, from: day) == weekday.rawValue,
               let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                dates.append(start)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: Export

    /// The sheet back, with live numbers — one worksheet per coach, laid out
    /// exactly like the coach's own (课程 · 教练 · 学生 · 剩余课时 · 剩余时长 ·
    /// 备注), plus 长期不来 for students who hold a balance but no class.
    /// Remaining = the student's group balances that apply to the class.
    static func export(programs: [Program],
                       students: [Student],
                       contracts: [Contract],
                       coaches: [StaffCoach],
                       accountCoach: (id: UUID, name: String)?) -> [XLSXSheet] {
        let header: [XLSXCell] = ["课程", "教练", "学生", "剩余课时(节)", "剩余时长(月)", "备注"].map { .text($0) }
        let widths: [Double] = [18, 10, 12, 14, 14, 22]
        let studentsById = Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        func coachName(_ id: UUID?) -> String {
            guard let id else { return "未分配" }
            if let staff = coaches.first(where: { $0.id == id }) { return staff.chineseName ?? staff.name }
            if let account = accountCoach, account.id == id { return account.name }
            return "未分配"
        }
        func balance(of studentId: UUID, in programId: UUID?) -> (sessions: Int, months: Bool)? {
            let held = contracts.filter {
                $0.studentId == studentId && $0.kind == .group && $0.hasSessionBalance
                    && (programId == nil || $0.programId == nil || $0.programId == programId)
            }
            guard !held.isEmpty else { return nil }
            let left = held.reduce(0) { $0 + ($1.bundleRedemptionsRemaining ?? 0) }
            let months = held.contains { $0.notes?.contains(monthsMarker) == true }
            return (left, months)
        }
        func balanceCells(_ b: (sessions: Int, months: Bool)?) -> [XLSXCell] {
            guard let b else { return [.empty, .empty] }
            if b.months {
                let months = Double(b.sessions) / Double(sessionsPerMonth)
                return [.empty, .number((months * 4).rounded() / 4)]
            }
            return [.number(Double(b.sessions)), .empty]
        }

        let classes = programs
            .filter { $0.programType == .group && $0.status != .archived
                && !$0.recurringDays.isEmpty && $0.defaultSessionTime != nil }
            .sorted { a, b in
                let da = weekdayOrder(a.recurringDays.first), db = weekdayOrder(b.recurringDays.first)
                if da != db { return da < db }
                return (a.defaultSessionTime ?? .distantPast).timeOfDay < (b.defaultSessionTime ?? .distantPast).timeOfDay
            }
        let byCoach = Dictionary(grouping: classes) { coachName($0.coachId) }

        var sheets: [XLSXSheet] = []
        for coach in byCoach.keys.sorted() {
            var rows: [[XLSXCell]] = [header]
            var seen: Set<UUID> = []
            var total = 0
            for program in byCoach[coach] ?? [] {
                var block = Block(title: program.name, entries: [], row: 0)
                block.weekday = program.recurringDays.first
                if let time = program.defaultSessionTime {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    block.hour = parts.hour
                    block.minute = parts.minute
                }
                block.ageGroup = program.ageGroup
                let roster = program.enrolledStudentIds.compactMap { studentsById[$0] }
                rows.append([.text(block.canonicalTitle), .text(coach), .text("人数:"),
                             .number(Double(roster.count)), .empty, .empty])
                total += roster.count
                for student in roster {
                    let shared = seen.contains(student.id)
                    seen.insert(student.id)
                    rows.append([.empty, .empty, .text(student.chineseName ?? student.name)]
                                + balanceCells(balance(of: student.id, in: program.id))
                                + [shared ? .text("课时与其他班共用") : .empty])
                }
            }
            rows.append([.text("\(coach) 总人次"), .empty, .empty, .number(Double(total)), .empty,
                         .text("同一学生上两节课计两次")])
            sheets.append(XLSXSheet(name: "\(coach)上课名单", rows: rows, columnWidths: widths))
        }

        // Students holding a balance and no class.
        let enrolled = Set(classes.flatMap(\.enrolledStudentIds))
        let idle = students.filter { student in
            !enrolled.contains(student.id) && balance(of: student.id, in: nil).map { $0.sessions > 0 } == true
        }
        if !idle.isEmpty {
            var rows: [[XLSXCell]] = [header,
                                      [.text("长期不来"), .empty, .text("人数:"), .number(Double(idle.count)), .empty, .empty]]
            for student in idle {
                rows.append([.empty, .empty, .text(student.chineseName ?? student.name)]
                            + balanceCells(balance(of: student.id, in: nil)) + [.empty])
            }
            sheets.append(XLSXSheet(name: "长期不来", rows: rows, columnWidths: widths))
        }
        return sheets
    }

    /// Monday-first, as the coaches' sheets are ordered.
    private static func weekdayOrder(_ day: Weekday?) -> Int {
        guard let day else { return 99 }
        return day == .sunday ? 7 : day.rawValue - 1
    }

    /// `上课名单_<yyyy-MM-dd>.xlsx`
    static func exportFilename(on date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "上课名单_\(formatter.string(from: date)).xlsx"
    }
}

private extension Date {
    /// Minutes since midnight, for ordering classes by start time.
    var timeOfDay: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: - The write

extension SwiftDataManager {

    /// What an import created, so it can be undone as one step.
    struct ClassListImportResult {
        var createdStudentIds: [UUID] = []
        var createdContractIds: [UUID] = []
        var createdProgramIds: [UUID] = []
        var createdSessionIds: [UUID] = []
        /// (student, program) roster additions to existing programs.
        var addedEnrollments: [(UUID, UUID)] = []
    }

    /// Writes a plan. Every write goes through the existing writers
    /// (addStudent, addContract, addProgram, addStudentEnrollment,
    /// createSession), so the import obeys the same rules as a hand entry.
    @discardableResult
    func applyClassListImport(_ plan: ClassList.Plan) -> ClassListImportResult {
        var result = ClassListImportResult()
        let now = Date()
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: now)
        }()

        for student in plan.students {
            if student.isNew {
                // The sheet's names are hanzi: hanzi is the Chinese name,
                // the name is toned pinyin — the same pair AddStudentView
                // stores when a coach types a Chinese name.
                let romanized = PinyinConverter.romanizedHanziName(name: student.name, chineseName: nil)
                addStudent(Student(id: student.id,
                                   name: romanized?.name ?? student.name,
                                   chineseName: romanized?.chineseName))
                result.createdStudentIds.append(student.id)
            }
            guard let sessions = student.balanceSessions else { continue }
            var note = "Imported from 上课名单 on \(stamp): "
            if student.monthsBased, let months = student.monthsLeft {
                note += "\(months.formatted()) months = \(sessions) sessions at one class a week. \(ClassList.monthsMarker)"
            } else {
                note += "\(sessions) sessions left."
            }
            let next = (allContracts(for: student.id).map(\.contractNumber).max() ?? 0) + 1
            // programId nil: one balance shared by every class the student
            // attends ("课时与其他班共用"). It also keeps addContract's
            // auto-enrolment, which MOVES a student, out of the way.
            let contract = Contract(studentId: student.id, contractNumber: next, kind: .group,
                                    enrollmentDate: now, bundleSize: sessions,
                                    bundlePurchaseDate: now, notes: note)
            addContract(contract)
            result.createdContractIds.append(contract.id)
        }

        for planned in plan.classes {
            let block = planned.block
            if planned.isNew, let weekday = block.weekday, let hour = block.hour, let minute = block.minute {
                let time = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0,
                                                 of: plan.options.from) ?? plan.options.from
                let weeks = max(1, Int((plan.options.through.timeIntervalSince(plan.options.from) / (7 * 86_400)).rounded(.up)))
                let program = Program(id: planned.id, name: block.canonicalTitle, programType: .group,
                                      ageGroup: block.ageGroup ?? .u10, durationWeeks: weeks,
                                      coachId: planned.coachId, status: .active,
                                      startDate: plan.options.from, endDate: plan.options.through,
                                      recurringDays: [weekday], defaultSessionTime: time,
                                      defaultSessionDurationMinutes: plan.options.durationMinutes)
                addProgram(program)
                result.createdProgramIds.append(program.id)
            }
            let before = Set(programs.first { $0.id == planned.id }?.enrolledStudentIds ?? [])
            for studentId in planned.studentIds where !before.contains(studentId) {
                addStudentEnrollment(studentId: studentId, programId: planned.id)
                if !planned.isNew { result.addedEnrollments.append((studentId, planned.id)) }
            }
            let series = UUID()
            for start in planned.sessionStarts {
                let created = createSession(SessionCreation.Intent(
                    group: .program(planned.id), start: start,
                    durationMinutes: plan.options.durationMinutes, seriesId: series))
                result.createdSessionIds.append(created.session.id)
            }
        }
        return result
    }

    /// Reverses an import: its sessions, programs, balances and students, and
    /// the roster additions it made to existing programs. Nothing it did not
    /// create is touched.
    func undoClassListImport(_ result: ClassListImportResult) {
        for id in result.createdSessionIds {
            if let session = sessionEvents.first(where: { $0.id == id }) { deleteSessionEvent(session) }
        }
        for (studentId, programId) in result.addedEnrollments {
            guard var program = programs.first(where: { $0.id == programId }) else { continue }
            program.enrolledStudentIds.removeAll { $0 == studentId }
            updateProgram(program)
        }
        for id in result.createdProgramIds {
            if let program = programs.first(where: { $0.id == id }) { deleteProgram(program) }
        }
        for id in result.createdContractIds {
            if let contract = contracts.first(where: { $0.id == id }) { deleteContract(contract) }
        }
        for id in result.createdStudentIds {
            if let student = students.first(where: { $0.id == id }) { deleteStudent(student) }
        }
    }
}
