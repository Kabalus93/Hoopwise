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

    /// The coach's own stylesheet (cellXfs, fonts, fills, borders and the
    /// indexed palette), copied verbatim from their 上课名单 so the export
    /// looks like their file: navy header, light-blue class bands, bordered
    /// student rows, pink low balances, the 长期不来 block and the total row.
    /// `Style` names the cellXfs ids the export uses.
    static let exportStylesheet: String = #"""
<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="0" formatCode="General"/></numFmts><fonts count="5"><font><sz val="11"/><color indexed="8"/><name val="Calibri"/></font><font><sz val="12"/><color indexed="8"/><name val="Helvetica Neue"/></font><font><sz val="15"/><color indexed="8"/><name val="Calibri"/></font><font><b val="1"/><sz val="11"/><color indexed="9"/><name val="Calibri"/></font><font><b val="1"/><sz val="11"/><color indexed="8"/><name val="Calibri"/></font></fonts><fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor indexed="10"/><bgColor auto="1"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor indexed="12"/><bgColor auto="1"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor indexed="13"/><bgColor auto="1"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor indexed="16"/><bgColor auto="1"/></patternFill></fill></fills><borders count="9"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color indexed="11"/></left><right style="thin"><color indexed="11"/></right><top style="thin"><color indexed="11"/></top><bottom style="thin"><color indexed="11"/></bottom><diagonal/></border><border><left style="thin"><color indexed="14"/></left><right style="thin"><color indexed="15"/></right><top style="thin"><color indexed="11"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="15"/></left><right style="thin"><color indexed="15"/></right><top style="thin"><color indexed="11"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="15"/></left><right style="thin"><color indexed="14"/></right><top style="thin"><color indexed="11"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="14"/></left><right style="thin"><color indexed="11"/></right><top style="thin"><color indexed="14"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="11"/></left><right style="thin"><color indexed="11"/></right><top style="thin"><color indexed="14"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="11"/></left><right style="thin"><color indexed="14"/></right><top style="thin"><color indexed="14"/></top><bottom style="thin"><color indexed="14"/></bottom><diagonal/></border><border><left style="thin"><color indexed="11"/></left><right style="thin"><color indexed="11"/></right><top style="thin"><color indexed="14"/></top><bottom style="thin"><color indexed="11"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="0" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf></cellStyleXfs><cellXfs count="31"><xf numFmtId="0" fontId="0" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="0" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="0" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="0" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="49" fontId="3" fillId="2" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="49" fontId="4" fillId="3" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="49" fontId="4" fillId="3" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="4" fillId="3" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="4" fillId="3" borderId="1" applyNumberFormat="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="1" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="49" fontId="0" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="1" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="2" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="3" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="3" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="4" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="49" fontId="3" borderId="5" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="3" borderId="6" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="49" fontId="3" borderId="6" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="3" borderId="6" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="3" borderId="6" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="49" fontId="3" borderId="7" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="8" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="49" fontId="0" borderId="8" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="8" applyNumberFormat="0" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="0" fontId="0" borderId="8" applyNumberFormat="1" applyFont="1" applyFill="0" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="center" vertical="bottom"/></xf><xf numFmtId="49" fontId="4" fillId="5" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="4" fillId="5" borderId="1" applyNumberFormat="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment horizontal="left" vertical="bottom"/></xf><xf numFmtId="0" fontId="4" fillId="5" borderId="1" applyNumberFormat="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="0" fontId="4" fillId="5" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf><xf numFmtId="49" fontId="4" fillId="5" borderId="1" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="0"><alignment vertical="bottom"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles><dxfs count="0"/><tableStyles count="0"/><colors><indexedColors><rgbColor rgb="ff000000"/><rgbColor rgb="ffffffff"/><rgbColor rgb="ffff0000"/><rgbColor rgb="ff00ff00"/><rgbColor rgb="ff0000ff"/><rgbColor rgb="ffffff00"/><rgbColor rgb="ffff00ff"/><rgbColor rgb="ff00ffff"/><rgbColor rgb="ff000000"/><rgbColor rgb="ffffffff"/><rgbColor rgb="ff1f4e78"/><rgbColor rgb="ffbfbfbf"/><rgbColor rgb="ffbdd7ee"/><rgbColor rgb="fffce4d6"/><rgbColor rgb="ff99403d"/><rgbColor rgb="ffaaaaaa"/><rgbColor rgb="fffff2cc"/></indexedColors></colors></styleSheet>
"""#

    enum Style {
        static let column = 1, header = 2
        static let bandText = 3, bandCountLabel = 4, bandCount = 5, bandBlank = 6
        static let rowEdge = 7, rowText = 8, rowNumber = 9, rowBlank = 10, rowLow = 11
        static let ruleFirst = 12, ruleSecond = 13, ruleMiddle = 14, ruleLast = 15
        static let idleTitle = 16, idleBlank = 17, idleCountLabel = 18, idleCount = 19
        static let idleBlankE = 20, idleNote = 21
        static let idleFirstEdge = 22, idleFirstText = 23, idleFirstBlank = 24, idleFirstNumber = 25
        static let totalTitle = 26, totalBlankB = 27, totalBlank = 28, totalCount = 29, totalNote = 30
    }

    /// A balance at or under this many sessions is filled pink — two months
    /// of one class a week, the coach's own threshold in their sheet.
    static let lowBalance = 8

    /// The sheet back, with live numbers, in the coach's layout (October
    /// 2026, Luther: "it's one tab"): ONE worksheet 上课名单 — header, then
    /// every class in week order (all coaches) as a band row with its 人数
    /// counted by formula and one row per student (剩余课时 or 剩余时长,
    /// 备注), then 长期不来 for students who hold a balance but no class, and
    /// a 总人次 row per coach. Remaining = the student's group balances that
    /// apply to the class.
    static func export(programs: [Program],
                       students: [Student],
                       contracts: [Contract],
                       coaches: [StaffCoach],
                       accountCoach: (id: UUID, name: String)?) -> [XLSXSheet] {
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

        var rows: [[XLSXCell]] = []
        var styles: [[Int]] = []
        var heights: [Double?] = []
        func add(_ cells: [XLSXCell], _ style: [Int], height: Double = 13.55) {
            rows.append(cells); styles.append(style); heights.append(height)
        }
        /// D and E for one student, and their styles. `first` = the first row
        /// under 长期不来, which carries that block's own borders.
        func balanceCells(_ b: (sessions: Int, months: Bool)?, first: Bool, idle: Bool)
            -> (cells: [XLSXCell], styles: [Int]) {
            let number = first ? Style.idleFirstNumber : Style.rowNumber
            let blank = first ? Style.idleFirstBlank : Style.rowBlank
            guard let b else { return ([.empty, .empty], [blank, blank]) }
            if b.months {
                let months = Double(b.sessions) / Double(sessionsPerMonth)
                return ([.empty, .number((months * 4).rounded() / 4)], [blank, number])
            }
            let low = !idle && !first && b.sessions <= lowBalance
            return ([.number(Double(b.sessions)), .empty], [low ? Style.rowLow : number, blank])
        }

        add(["课程", "教练", "学生", "剩余课时(节)", "剩余时长(月)", "备注"].map { .text($0) },
            Array(repeating: Style.header, count: 6), height: 57.45)

        let classes = programs
            .filter { $0.programType == .group && $0.status != .archived
                && !$0.recurringDays.isEmpty && $0.defaultSessionTime != nil }
            .sorted { a, b in
                let da = weekdayOrder(a.recurringDays.first), db = weekdayOrder(b.recurringDays.first)
                if da != db { return da < db }
                return (a.defaultSessionTime ?? .distantPast).timeOfDay < (b.defaultSessionTime ?? .distantPast).timeOfDay
            }

        var coachOrder: [String] = []
        var bandCells: [String: [(ref: String, count: Int)]] = [:]
        var seen: Set<UUID> = []
        for program in classes {
            var block = Block(title: program.name, entries: [], row: 0)
            block.weekday = program.recurringDays.first
            if let time = program.defaultSessionTime {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                block.hour = parts.hour
                block.minute = parts.minute
            }
            block.ageGroup = program.ageGroup
            let coach = coachName(program.coachId)
            if !coachOrder.contains(coach) { coachOrder.append(coach) }
            let roster = program.enrolledStudentIds.compactMap { studentsById[$0] }

            let bandRow = rows.count + 1
            let count: XLSXCell = roster.isEmpty
                ? .number(0)
                : .formula("COUNTA(C\(bandRow + 1):C\(bandRow + roster.count))", cached: Double(roster.count))
            add([.text(block.canonicalTitle), .text(coach), .text("人数:"), count, .empty, .empty],
                [Style.bandText, Style.bandText, Style.bandCountLabel, Style.bandCount, Style.bandBlank, Style.bandBlank])
            bandCells[coach, default: []].append(("D\(bandRow)", roster.count))

            for student in roster {
                let shared = seen.contains(student.id)
                seen.insert(student.id)
                let b = balanceCells(balance(of: student.id, in: program.id), first: false, idle: false)
                add([.empty, .empty, .text(student.chineseName ?? student.name)] + b.cells
                        + [shared ? .text("课时与其他班共用") : .empty],
                    [Style.rowEdge, Style.rowEdge, Style.rowText] + b.styles
                        + [shared ? Style.rowText : Style.rowBlank])
            }
        }

        // The rule above 长期不来.
        add(Array(repeating: .empty, count: 6),
            [Style.ruleFirst, Style.ruleSecond, Style.ruleMiddle, Style.ruleMiddle, Style.ruleMiddle, Style.ruleLast])

        // Students holding a balance and no class. Not counted in any total.
        let enrolled = Set(classes.flatMap(\.enrolledStudentIds))
        let idle = students.filter { student in
            !enrolled.contains(student.id) && balance(of: student.id, in: nil).map { $0.sessions > 0 } == true
        }
        let idleNote = coachOrder.count == 1 ? "不计入\(coachOrder[0])总数" : "不计入总人次"
        add([.text("长期不来"), .empty, .text("人数:"), .number(Double(idle.count)), .empty, .text(idleNote)],
            [Style.idleTitle, Style.idleBlank, Style.idleCountLabel, Style.idleCount, Style.idleBlankE, Style.idleNote])
        for (i, student) in idle.enumerated() {
            let first = i == 0
            let b = balanceCells(balance(of: student.id, in: nil), first: first, idle: true)
            add([.empty, .empty, .text(student.chineseName ?? student.name)] + b.cells + [.empty],
                first
                    ? [Style.idleFirstEdge, Style.idleFirstEdge, Style.idleFirstText] + b.styles + [Style.idleFirstBlank]
                    : [Style.rowEdge, Style.rowEdge, Style.rowText] + b.styles + [Style.rowBlank])
        }

        // One 总人次 per coach: the sum of that coach's class counts.
        for coach in coachOrder {
            let cells = bandCells[coach] ?? []
            let total = cells.reduce(0) { $0 + $1.count }
            let formula = cells.map(\.ref).joined(separator: "+")
            add([.text("\(coach) 总人次"), .empty, .empty,
                 formula.isEmpty ? .number(0) : .formula(formula, cached: Double(total)),
                 .empty, .text("同一学生上两节课计两次")],
                [Style.totalTitle, Style.totalBlankB, Style.totalBlank, Style.totalCount, Style.totalBlank, Style.totalNote])
        }

        return [XLSXSheet(name: "上课名单", rows: rows,
                          columnWidths: [22, 8, 12, 14, 14, 24],
                          cellStyles: styles, rowHeights: heights,
                          columnStyle: Style.column, showGridLines: false)]
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
