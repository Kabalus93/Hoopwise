import Foundation
import SwiftUI

#if targetEnvironment(macCatalyst)
// MARK: - Claude Desktop connector: the tools (Mac only, November 2026)
//
// Luther: "a connector for me to tell Claude Desktop to do stuff in the app
// instead of clicking through". Ported from the retired Mac app's Whistle
// tool registry (tag mac-app-final), whose rule still holds: the connector
// NEVER touches the database directly — every handler calls the same shared
// business-rule layer the UI calls (SessionCreation, SessionLifecycle,
// setStudentEnrollment, setStudentAttendanceStates → the one redemption
// authority, updateContract…), so a rule that stops a coach stops Claude.
// No delete tools, deliberately. Claude Desktop asks the user before each
// tool call; there is no in-app confirmation card any more.
// Data minimisation is ON by default (assistant.minimized): guardian
// contacts and money amounts never leave the app.

enum ConnectorToolCategory: String, Codable {
    case read, meta
    case sessionWrite = "session"
    case athleteWrite = "athlete"
    case contractWrite = "contract"

    var isWrite: Bool { self != .read && self != .meta }
    /// Contract changes always confirm — no always-allow, ever.
    var supportsAlwaysAllow: Bool { self == .sessionWrite || self == .athleteWrite }
    var allowKey: String { "assistant.alwaysAllow.\(rawValue)" }
}

struct ConnectorToolResult {
    var payload: String          // JSON returned to the model
    var summary: String          // one-line chip label for the UI
    var isError: Bool = false
}

struct ConnectorTool {
    let name: String
    let description: String
    let schema: [String: Any]
    let category: ConnectorToolCategory
    /// Human-readable old → new lines for the confirmation card. Only writes.
    let run: ([String: Any]) throws -> ConnectorToolResult
}

enum ConnectorToolError: LocalizedError {
    case unknownTool(String)
    case badArguments(String)
    case notFound(String)
    case ruleViolation(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name): return "Unknown tool: \(name)"
        case .badArguments(let detail): return "Invalid arguments: \(detail)"
        case .notFound(let detail): return detail
        case .ruleViolation(let rule): return rule
        }
    }
}

@MainActor
final class ConnectorToolRegistry {
    private unowned let dataManager: DataManager
    private(set) var tools: [ConnectorTool] = []

    /// Data-minimization mode (on by default): guardian contacts, money
    /// amounts, and photos never enter prompts — the assistant references
    /// them and deep-links instead.
    var minimized: Bool {
        UserDefaults.standard.object(forKey: "assistant.minimized") == nil
            ? true : UserDefaults.standard.bool(forKey: "assistant.minimized")
    }

    init(dataManager: DataManager) {
        self.dataManager = dataManager
        buildTools()
    }

    func tool(named name: String) -> ConnectorTool? {
        tools.first { $0.name == name }
    }

    func execute(name: String, argumentsJSON: String) -> ConnectorToolResult {
        guard let tool = tool(named: name) else {
            return ConnectorToolResult(payload: "Unknown tool", summary: name, isError: true)
        }
        do {
            let args = try Self.decode(argumentsJSON)
            return try tool.run(args)
        } catch {
            // Relay the actual rule, not a generic error.
            return ConnectorToolResult(payload: error.localizedDescription,
                                       summary: "\(name) failed", isError: true)
        }
    }

    /// Wire-format tool definitions for the Messages API.
    var wireTools: [[String: Any]] {
        tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.schema] }
    }

    static func decode(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ConnectorToolError.badArguments("not a JSON object") }
        return object
    }

    private static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    // MARK: - Shared lookups

    /// A record's short reference: the first 8 characters of its id. Long
    /// ids get mis-copied by a model (November 2026: three get_session calls
    /// failed on ids list_sessions had just returned); short ones rarely do.
    static func ref(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    /// The id a caller meant: a full id in any case, or a short ref (a unique
    /// prefix of at least 6 characters). nil when nothing or several match.
    private static func resolve(_ raw: String, in ids: [UUID]) -> UUID? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'`<>#")))
        if let id = UUID(uuidString: text), ids.contains(id) { return id }
        let key = text.lowercased().replacingOccurrences(of: "-", with: "")
        guard key.count >= 6 else { return nil }
        let hits = ids.filter { $0.uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(key) }
        return hits.count == 1 ? hits[0] : nil
    }

    private func findStudent(_ args: [String: Any]) throws -> Student {
        let raw = (args["athlete_id"] as? String) ?? (args["query"] as? String) ?? ""
        if let id = Self.resolve(raw, in: dataManager.students.map(\.id)),
           let student = dataManager.students.first(where: { $0.id == id }) {
            return student
        }
        if !raw.isEmpty {
            let matches = dataManager.students.filter {
                NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(raw)
            }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                let names = matches.prefix(6).map { "\($0.displayName) [\(Self.ref($0.id))]" }.joined(separator: ", ")
                throw ConnectorToolError.badArguments(
                    "\(matches.count) athletes match \"\(raw)\": \(names). Pass one ref as athlete_id.")
            }
        }
        throw ConnectorToolError.notFound("No athlete matches \"\(raw)\". Use search_athletes and pass the ref it returns.")
    }

    private func findProgram(_ query: String) throws -> Program {
        let q = query.trimmingCharacters(in: .whitespaces)
        if let id = Self.resolve(q, in: dataManager.programs.map(\.id)),
           let program = dataManager.programs.first(where: { $0.id == id }) { return program }
        if let exact = dataManager.programs.first(where: { $0.name.caseInsensitiveCompare(q) == .orderedSame }) { return exact }
        let hits = dataManager.programs.filter { $0.name.localizedCaseInsensitiveContains(q) }
        if hits.count == 1 { return hits[0] }
        if hits.isEmpty { throw ConnectorToolError.notFound("No program matches \"\(q)\". Use list_programs.") }
        throw ConnectorToolError.badArguments("\(hits.count) programs match \"\(q)\": "
            + hits.prefix(6).map { "\($0.name) [\(Self.ref($0.id))]" }.joined(separator: ", "))
    }

    private static func grade(_ value: Any?) throws -> SchoolGrade? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let chinese = ["初一": "H1", "初二": "H2", "初三": "H3", "高一": "H4", "高二": "H5", "高三": "H6",
                       "小班": "K1", "中班": "K2", "大班": "K3"]
        let key = chinese[raw] ?? raw.uppercased()
        guard let grade = SchoolGrade(rawValue: key) else {
            throw ConnectorToolError.badArguments("school_grade \"\(raw)\" — use K1–K3, P1–P6 or H1–H6")
        }
        return grade
    }

    /// Adds to ONE session's roster. An empty roster means "the program's
    /// enrolment", so the stored roster starts from who is expected now —
    /// otherwise adding one child would leave only that child expected.
    @discardableResult
    private func addToRoster(_ session: SessionEvent, _ ids: [UUID]) throws -> Int {
        guard !SessionLifecycle.didNotHappen(session)
        else { throw ConnectorToolError.ruleViolation("That session was skipped or cancelled") }
        var copy = session
        var roster = AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
        for id in ids where !roster.contains(id) { roster.append(id) }
        copy.attendeeIds = roster
        copy.updatedAt = Date()
        dataManager.updateSessionEvent(copy, keepLiveFields: true)
        return roster.count
    }

    /// Athlete ids or refs (or exact names) → ids; any that resolve to nothing
    /// is an error naming it, so nothing is silently dropped.
    private func resolveAthletes(_ raws: [String]) throws -> [UUID] {
        try raws.map { try findStudent(["athlete_id": $0]).id }
    }

    /// A session by id or ref — or, without one, by `when` (ISO date-time)
    /// plus optional `program`, which is how a coach names a class anyway.
    private func findSession(_ args: [String: Any]) throws -> SessionEvent {
        let sessions = dataManager.sessionEvents
        if let raw = args["session_id"] as? String, !raw.isEmpty {
            if let id = Self.resolve(raw, in: sessions.map(\.id)),
               let session = sessions.first(where: { $0.id == id }) { return session }
            throw ConnectorToolError.notFound(
                "No session with id \"\(raw)\". Pass the ref from list_sessions, or when + program instead.")
        }
        if let starts = Self.parseDate(args["when"] as? String) {
            var hits = sessions.filter { abs($0.startTime.timeIntervalSince(starts)) < 60 }
            if let program = args["program"] as? String, !program.isEmpty {
                let ids = Set(dataManager.programs.filter { $0.name.localizedCaseInsensitiveContains(program) }.map(\.id))
                hits = hits.filter { $0.programId.map(ids.contains) ?? false }
            }
            if hits.count == 1 { return hits[0] }
            if hits.count > 1 {
                let list = hits.map { "\($0.title) [\(Self.ref($0.id))]" }.joined(separator: ", ")
                throw ConnectorToolError.badArguments("\(hits.count) sessions start then: \(list). Add program or pass a ref.")
            }
            throw ConnectorToolError.notFound("No session starts at \(args["when"] as? String ?? "").")
        }
        throw ConnectorToolError.badArguments("Pass session_id (a ref from list_sessions) or when (its start, ISO).")
    }

    private func studentBrief(_ student: Student) -> [String: Any] {
        var brief: [String: Any] = [
            "athlete_id": Self.ref(student.id),
            "name": student.name,
        ]
        if let grade = student.currentSchoolGrade() { brief["school_grade"] = grade.rawValue }
        if let chinese = student.chineseName { brief["chinese_name"] = chinese }
        if let programId = student.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            brief["program"] = program.name
        }
        return brief
    }

    private func sessionBrief(_ session: SessionEvent) -> [String: Any] {
        var brief: [String: Any] = [
            "session_id": Self.ref(session.id),
            "title": session.title,
            "date": Self.isoFormatter.string(from: session.startTime),
            "status": session.status.rawValue,
            "expected_count": AttendanceMath.expectedIds(of: session, programs: dataManager.programs).count,
        ]
        if let location = session.location { brief["location"] = location }
        if let programId = session.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            brief["program"] = program.name
        }
        return brief
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = isoFormatter.date(from: string) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withFullDate]
        return fallback.date(from: string)
    }

    private func attendanceRate(for student: Student) -> (attended: Int, of: Int, rate: Double?) {
        // Shared marked-only math — unrecorded sessions excluded everywhere.
        let rate = AttendanceMath.rate(for: student.id, in: dataManager.sessionEvents)
        guard rate.of > 0 else { return (0, 0, nil) }
        let attended = Int(round(Double(rate.percent) / 100 * Double(rate.of)))
        return (attended, rate.of, Double(rate.percent) / 100)
    }

    // MARK: - Tool definitions

    private func buildTools() {
        let objectSchema: ([String: Any], [String]) -> [String: Any] = { properties, required in
            ["type": "object", "properties": properties, "required": required]
        }

        tools = [
            // ---------------- READ ----------------
            ConnectorTool(
                name: "search_athletes",
                description: "Search the roster by name in English, 中文, or pinyin (e.g. 'cai' finds 蔡一铭). Returns brief matches with athlete_id.",
                schema: objectSchema(["query": ["type": "string", "description": "Name fragment in any script, or empty for all"]], []),
                category: .read,
                run: { [self] args in
                    let query = (args["query"] as? String) ?? ""
                    let matches = dataManager.students.filter {
                        query.isEmpty || NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(query)
                    }
                    let list = matches.prefix(25).map { studentBrief($0) }
                    return ConnectorToolResult(
                        payload: Self.encode(["count": matches.count, "athletes": Array(list)]),
                        summary: "searched athletes · \(matches.count) match\(matches.count == 1 ? "" : "es")")
                }),

            ConnectorTool(
                name: "get_athlete",
                description: "Full profile for one athlete: program, attendance record, contract state, recent sessions. Pass athlete_id from search_athletes.",
                schema: objectSchema(["athlete_id": ["type": "string"]], ["athlete_id"]),
                category: .read,
                run: { [self] args in
                    let student = try findStudent(args)
                    var payload = studentBrief(student)
                    let attendance = attendanceRate(for: student)
                    payload["sessions_attended"] = attendance.attended
                    payload["sessions_relevant"] = attendance.of
                    if let rate = attendance.rate { payload["attendance_rate"] = Int(rate * 100) }
                    let recentNotes = student.parentalTouchpoints.suffix(3).compactMap(\.notes)
                    if !recentNotes.isEmpty { payload["recent_notes"] = Array(recentNotes) }
                    if minimized {
                        payload["guardian_contact"] = "redacted — on the athlete card"
                    }
                    if let contract = dataManager.currentContract(for: student.id) {
                        var contractInfo: [String: Any] = [
                            "kind": contract.kind.rawValue,
                            "status": contract.status.rawValue,
                        ]
                        if contract.kind == .privateBundle {
                            contractInfo["bundle_size"] = contract.bundleSize
                            contractInfo["sessions_remaining"] = contract.bundleRedemptionsRemaining ?? 0
                        }
                        if !minimized {
                            contractInfo["price_per_session"] = contract.pricePerSession
                            contractInfo["amount_paid"] = contract.amountPaid
                        }
                        payload["contract"] = contractInfo
                    }
                    let recent = dataManager.sessionEvents
                        .filter { $0.attendeeIds.contains(student.id) || $0.actualAttendeeIds.contains(student.id) }
                        .sorted { $0.date > $1.date }.prefix(5).map { sessionBrief($0) }
                    payload["recent_sessions"] = Array(recent)
                    return ConnectorToolResult(payload: Self.encode(payload),
                                               summary: "read \(student.displayName)'s profile")
                }),

            ConnectorTool(
                name: "list_sessions",
                description: "List sessions in a date range, optionally filtered by program name or status (scheduled/inProgress/completed/cancelled).",
                schema: objectSchema([
                    "from": ["type": "string", "description": "ISO date, default today"],
                    "to": ["type": "string", "description": "ISO date, default +7 days"],
                    "status": ["type": "string"],
                    "program": ["type": "string"],
                ], []),
                category: .read,
                run: { [self] args in
                    let from = Self.parseDate(args["from"] as? String)
                        ?? Calendar.current.startOfDay(for: Date())
                    let to = Self.parseDate(args["to"] as? String)
                        ?? Calendar.current.date(byAdding: .day, value: 7, to: from)!
                    var sessions = dataManager.sessionEvents.filter { $0.date >= from && $0.date <= to }
                    if let status = args["status"] as? String {
                        sessions = sessions.filter { $0.status.rawValue == status }
                    }
                    if let programQuery = args["program"] as? String {
                        let programIds = Set(dataManager.programs
                            .filter { $0.name.localizedCaseInsensitiveContains(programQuery) }.map(\.id))
                        sessions = sessions.filter { $0.programId.map(programIds.contains) ?? false }
                    }
                    sessions.sort { $0.date < $1.date }
                    return ConnectorToolResult(
                        payload: Self.encode(["count": sessions.count,
                                              "sessions": sessions.prefix(30).map { sessionBrief($0) }]),
                        summary: "listed \(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                }),

            ConnectorTool(
                name: "get_session",
                description: "Full detail for one session: roster with attendance states, plan, location. Identify it by session_id (the short ref list_sessions returns) or by when (its start, ISO) plus optional program.",
                schema: objectSchema([
                    "session_id": ["type": "string", "description": "ref from list_sessions"],
                    "when": ["type": "string", "description": "ISO start date-time, if no session_id"],
                    "program": ["type": "string"],
                ], []),
                category: .read,
                run: { [self] args in
                    let session = try findSession(args)
                    var payload = sessionBrief(session)
                    let roster = AttendanceMath.expectedIds(of: session, programs: dataManager.programs).compactMap { id -> [String: Any]? in
                        guard let student = dataManager.students.first(where: { $0.id == id }) else { return nil }
                        let state: String
                        if session.actualAttendeeIds.contains(id) { state = "present" }
                        else if session.excusedAbsences.contains(id) { state = "excused" }
                        else if session.unexcusedAbsences.contains(id) { state = "absent" }
                        else { state = "unmarked" }
                        return ["name": student.displayName, "athlete_id": Self.ref(id), "attendance": state]
                    }
                    payload["roster"] = roster
                    if let notes = session.notes, !notes.isEmpty { payload["notes"] = notes }
                    return ConnectorToolResult(payload: Self.encode(payload),
                                               summary: "read session \(session.title)")
                }),

            ConnectorTool(
                name: "list_programs",
                description: "All programs with type, status, and enrolled count.",
                schema: objectSchema([:], []),
                category: .read,
                run: { [self] _ in
                    let list = dataManager.programs.map { program -> [String: Any] in
                        ["program_id": Self.ref(program.id),
                         "name": program.name,
                         "type": program.programType.rawValue,
                         "status": program.status.rawValue,
                         "enrolled": program.enrolledStudentIds.count]
                    }
                    return ConnectorToolResult(payload: Self.encode(["programs": list]),
                                               summary: "listed \(list.count) programs")
                }),

            ConnectorTool(
                name: "attendance_stats",
                description: "Attendance rates for a program's roster or the whole active roster. Use to find athletes with low attendance.",
                schema: objectSchema([
                    "program": ["type": "string", "description": "Program name filter, optional"],
                    "below_percent": ["type": "integer", "description": "Only include athletes below this rate"],
                ], []),
                category: .read,
                run: { [self] args in
                    var students = dataManager.students
                    if let programQuery = args["program"] as? String {
                        let programIds = Set(dataManager.programs
                            .filter { $0.name.localizedCaseInsensitiveContains(programQuery) }.map(\.id))
                        students = students.filter { $0.programId.map(programIds.contains) ?? false }
                    }
                    let threshold = (args["below_percent"] as? Int).map { Double($0) / 100 }
                    var rows: [[String: Any]] = []
                    for student in students {
                        let attendance = attendanceRate(for: student)
                        guard let rate = attendance.rate else { continue }
                        if let threshold, rate >= threshold { continue }
                        rows.append(["name": student.displayName,
                                     "athlete_id": Self.ref(student.id),
                                     "attendance_percent": Int(rate * 100),
                                     "attended": attendance.attended,
                                     "of": attendance.of])
                    }
                    rows.sort { ($0["attendance_percent"] as? Int ?? 0) < ($1["attendance_percent"] as? Int ?? 0) }
                    return ConnectorToolResult(payload: Self.encode(["athletes": Array(rows.prefix(40))]),
                                               summary: "attendance stats · \(rows.count) athletes")
                }),

            // ---------------- WRITE ----------------
            ConnectorTool(
                name: "create_session",
                description: "Schedule a session. Provide title, ISO start datetime, duration minutes; optionally program name and athlete_ids for the roster.",
                schema: objectSchema([
                    "title": ["type": "string"],
                    "starts": ["type": "string", "description": "ISO 8601 datetime"],
                    "duration_minutes": ["type": "integer"],
                    "location": ["type": "string"],
                    "program": ["type": "string"],
                    "athlete_ids": ["type": "array", "items": ["type": "string"]],
                ], ["title", "starts"]),
                category: .sessionWrite,
                run: { [self] args in
                    guard let title = args["title"] as? String,
                          let starts = Self.parseDate(args["starts"] as? String)
                    else { throw ConnectorToolError.badArguments("title and a valid ISO 'starts' are required") }
                    let duration = args["duration_minutes"] as? Int ?? 90
                    var programId: UUID?
                    if let programQuery = args["program"] as? String {
                        guard let program = dataManager.programs.first(where: {
                            $0.name.localizedCaseInsensitiveContains(programQuery)
                        }) else { throw ConnectorToolError.notFound("No program matches \"\(programQuery)\"") }
                        programId = program.id
                    }
                    var attendees = try resolveAthletes(args["athlete_ids"] as? [String] ?? [])
                    if attendees.isEmpty, let programId,
                       let program = dataManager.programs.first(where: { $0.id == programId }) {
                        attendees = program.enrolledStudentIds
                    }
                    // Through the shared creation service, so the assistant
                    // gets the same phase derivation, venue default and series
                    // handling as the app — the rule that it never touches the
                    // database except through the business-rule layer.
                    let result = dataManager.createSession(SessionCreation.Intent(
                        group: programId.map { .program($0) } ?? .unassigned,
                        start: starts,
                        durationMinutes: duration,
                        title: title,
                        location: args["location"] as? String,
                        roster: attendees.isEmpty ? nil : attendees,
                        createdByCoachId: dataManager.loggedInCoachId))
                    let session = result.session
                    return ConnectorToolResult(
                        payload: Self.encode(["created": true, "session_id": Self.ref(session.id)]),
                        summary: "created session \(title) ✓")
                }),

            ConnectorTool(
                name: "update_session",
                description: "Edit a session's title, time, duration, location, or roster (athlete_ids replaces the roster).",
                schema: objectSchema([
                    "session_id": ["type": "string"],
                    "title": ["type": "string"],
                    "starts": ["type": "string"],
                    "duration_minutes": ["type": "integer"],
                    "location": ["type": "string"],
                    "athlete_ids": ["type": "array", "items": ["type": "string"]],
                ], ["session_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    let old = session
                    var copy = session
                    if let title = args["title"] as? String { copy.title = title }
                    if let starts = Self.parseDate(args["when"] as? String) {
                        let duration = copy.durationMinutes
                        copy.date = starts; copy.startTime = starts
                        copy.endTime = Calendar.current.date(byAdding: .minute, value: duration, to: starts) ?? starts
                    }
                    if let duration = args["duration_minutes"] as? Int {
                        copy.endTime = Calendar.current.date(byAdding: .minute, value: duration, to: copy.startTime) ?? copy.endTime
                    }
                    if let location = args["location"] as? String { copy.location = location }
                    if let ids = args["athlete_ids"] as? [String] {
                        copy.attendeeIds = try resolveAthletes(ids)
                    }
                    copy.updatedAt = Date()
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(
                        payload: Self.encode(["updated": true, "session_id": Self.ref(session.id)]),
                        summary: "updated session \(copy.title) ✓")
                }),

            ConnectorTool(
                name: "cancel_session",
                description: "Cancel a scheduled or in-progress session. Uses the app's session state machine — an illegal transition is refused.",
                schema: objectSchema(["session_id": ["type": "string"]], ["session_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    let old = session
                    var copy = session
                    // THE shared state machine — same rule that gates the UI button.
                    guard SessionLifecycle.apply(.cancel, to: &copy) else {
                        throw ConnectorToolError.ruleViolation(
                            "Can't cancel a \(session.status.rawValue) session — only scheduled or in-progress sessions cancel")
                    }
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(
                        payload: Self.encode(["cancelled": true]),
                        summary: "cancelled \(session.title) ✓")
                }),

            ConnectorTool(
                name: "create_athlete",
                description: "Add a new athlete. name required (a Chinese name alone is fine as chinese_name — the name then becomes its pinyin). Optional: school_grade, program (ADDS them to that program's roster, keeping any other class), session_id (also puts them on that one session's roster).",
                schema: objectSchema([
                    "name": ["type": "string"],
                    "chinese_name": ["type": "string"],
                    "school_grade": ["type": "string", "description": "School grade: K1–K3 kindergarten, P1–P6 primary (小学一至六年级), H1–H6 secondary (初一=H1, 初二=H2, 初三=H3, 高一=H4, 高二=H5, 高三=H6). It promotes itself each 1 September."],
                    "program": ["type": "string"],
                    "session_id": ["type": "string", "description": "ref from list_sessions"],
                ], []),
                category: .athleteWrite,
                run: { [self] args in
                    let chinese = (args["chinese_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                    var name = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    if name.isEmpty, let chinese, !chinese.isEmpty { name = PinyinConverter.toPinyin(chinese) }
                    guard !name.isEmpty else { throw ConnectorToolError.badArguments("name or chinese_name is required") }
                    let grade = try Self.grade(args["school_grade"])
                    var program: Program?
                    if let query = args["program"] as? String, !query.isEmpty {
                        program = try findProgram(query)
                    }
                    let session = (args["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } != nil
                        ? try findSession(args) : nil
                    var student = Student(id: UUID(), name: name)
                    if let chinese, !chinese.isEmpty { student.chineseName = chinese }
                    if let grade { student.setSchoolGrade(grade) }
                    dataManager.addStudent(student)
                    if let program {
                        // ADDS (never moves): the shared writer keeps both link fields in step.
                        dataManager.addStudentEnrollment(studentId: student.id, programId: program.id)
                    }
                    if let session { try addToRoster(session, [student.id]) }
                    var done = ["created": true, "athlete_id": Self.ref(student.id)] as [String: Any]
                    if let grade { done["school_grade"] = grade.rawValue }
                    if let program { done["program"] = program.name }
                    if let session { done["added_to_session"] = Self.ref(session.id) }
                    return ConnectorToolResult(payload: Self.encode(done), summary: "added \(name) ✓")
                }),

            ConnectorTool(
                name: "add_to_session",
                description: "Put athletes on ONE session's roster (that class only — the program's other sessions are unchanged). athlete_ids are refs from search_athletes.",
                schema: objectSchema([
                    "session_id": ["type": "string", "description": "ref from list_sessions"],
                    "when": ["type": "string"], "program": ["type": "string"],
                    "athlete_ids": ["type": "array", "items": ["type": "string"]],
                ], ["athlete_ids"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    let ids = try resolveAthletes(args["athlete_ids"] as? [String] ?? [])
                    guard !ids.isEmpty else { throw ConnectorToolError.badArguments("athlete_ids is empty") }
                    let count = try addToRoster(session, ids)
                    return ConnectorToolResult(payload: Self.encode(["roster_size": count]),
                                               summary: "added \(ids.count) to \(session.title)")
                }),

            ConnectorTool(
                name: "remove_from_session",
                description: "Take athletes off ONE session's roster (that class only). Their marks for it are kept; use mark_attendance to change those.",
                schema: objectSchema([
                    "session_id": ["type": "string", "description": "ref from list_sessions"],
                    "when": ["type": "string"], "program": ["type": "string"],
                    "athlete_ids": ["type": "array", "items": ["type": "string"]],
                ], ["athlete_ids"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    let ids = Set(try resolveAthletes(args["athlete_ids"] as? [String] ?? []))
                    var copy = session
                    copy.attendeeIds = AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
                        .filter { !ids.contains($0) }
                    copy.updatedAt = Date()
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["roster_size": copy.attendeeIds.count]),
                                               summary: "removed \(ids.count) from \(session.title)")
                }),

            ConnectorTool(
                name: "add_to_program",
                description: "Add an athlete to a program's roster — they are then expected at its upcoming sessions. Keeps every other class they are in.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "program": ["type": "string", "description": "Program name"],
                ], ["athlete_id", "program"]),
                category: .athleteWrite,
                run: { [self] args in
                    let student = try findStudent(args)
                    let program = try findProgram(args["program"] as? String ?? "")
                    dataManager.addStudentEnrollment(studentId: student.id, programId: program.id)
                    return ConnectorToolResult(payload: Self.encode(["enrolled": true, "program": program.name]),
                                               summary: "\(student.displayName) → \(program.name)")
                }),

            ConnectorTool(
                name: "update_athlete",
                description: "Edit an athlete's name, chinese_name or school_grade.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "name": ["type": "string"],
                    "chinese_name": ["type": "string"],
                    "school_grade": ["type": "string", "description": "School grade: K1–K3 kindergarten, P1–P6 primary (小学一至六年级), H1–H6 secondary (初一=H1, 初二=H2, 初三=H3, 高一=H4, 高二=H5, 高三=H6). It promotes itself each 1 September."],
                ], ["athlete_id"]),
                category: .athleteWrite,
                run: { [self] args in
                    var student = try findStudent(args)
                    let old = student
                    if let name = args["name"] as? String, !name.isEmpty { student.name = name }
                    if let chinese = args["chinese_name"] as? String { student.chineseName = chinese }
                    if let grade = try Self.grade(args["school_grade"]) { student.setSchoolGrade(grade) }
                    student.updatedAt = Date()
                    dataManager.updateStudent(student)
                    return ConnectorToolResult(
                        payload: Self.encode(["updated": true]),
                        summary: "updated \(student.displayName) ✓")
                }),

            ConnectorTool(
                name: "set_enrollment",
                description: "MOVE an athlete to one program: it removes them from EVERY other program roster (program null unenrolls them everywhere). To add a class without leaving the others, use add_to_program.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "program": ["type": ["string", "null"], "description": "Program name, or null to unenroll"],
                ], ["athlete_id"]),
                category: .athleteWrite,
                run: { [self] args in
                    let student = try findStudent(args)
                    let oldProgramId = student.programId
                    var newProgramId: UUID?
                    if let programQuery = args["program"] as? String {
                        guard let program = dataManager.programs.first(where: {
                            $0.name.localizedCaseInsensitiveContains(programQuery)
                        }) else { throw ConnectorToolError.notFound("No program matches \"\(programQuery)\"") }
                        newProgramId = program.id
                    }
                    dataManager.setStudentEnrollment(studentId: student.id, programId: newProgramId)
                    return ConnectorToolResult(
                        payload: Self.encode(["updated": true]),
                        summary: "enrollment updated for \(student.displayName) ✓")
                }),

            ConnectorTool(
                name: "record_note",
                description: "Append a dated note to an athlete's notes.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "note": ["type": "string"],
                ], ["athlete_id", "note"]),
                category: .athleteWrite,
                run: { [self] args in
                    var student = try findStudent(args)
                    guard let note = args["note"] as? String, !note.isEmpty
                    else { throw ConnectorToolError.badArguments("note is required") }
                    let old = student
                    student.parentalTouchpoints.append(ParentalTouchpoint(
                        id: UUID(), date: Date(), type: .message, notes: note,
                        followUpNeeded: false, followUpDate: nil))
                    student.updatedAt = Date()
                    dataManager.updateStudent(student)
                    return ConnectorToolResult(payload: Self.encode(["noted": true]),
                                               summary: "noted on \(student.displayName) ✓")
                }),

            ConnectorTool(
                name: "update_contract",
                description: "Edit an athlete's current contract: manual status override, price per session, or bundle size. Bundle size can never go below sessions already consumed. ALWAYS requires user confirmation.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "manual_status": ["type": "string", "description": "active/pending/completed/cancelled, or 'auto' to clear the override"],
                    "price_per_session": ["type": "number"],
                    "bundle_size": ["type": "integer"],
                ], ["athlete_id"]),
                category: .contractWrite,
                run: { [self] args in
                    let student = try findStudent(args)
                    guard let contract = dataManager.currentContract(for: student.id)
                    else { throw ConnectorToolError.notFound("\(student.displayName) has no current contract") }
                    let old = contract
                    var copy = contract
                    var changes: [String] = []
                    if let statusRaw = args["manual_status"] as? String {
                        if statusRaw == "auto" {
                            copy.manualStatus = nil; changes.append("status→auto")
                        } else if let status = ContractStatus(rawValue: statusRaw) {
                            copy.manualStatus = status; changes.append("status→\(statusRaw)")
                        } else {
                            throw ConnectorToolError.badArguments("unknown status \(statusRaw)")
                        }
                    }
                    if let price = args["price_per_session"] as? Double {
                        guard price >= 0 else { throw ConnectorToolError.ruleViolation("price can't be negative") }
                        changes.append("price \(Int(copy.pricePerSession))→\(Int(price))")
                        copy.pricePerSession = price
                    }
                    if let size = args["bundle_size"] as? Int {
                        let consumed = copy.bundleSessionIds.count
                        guard size >= consumed else {
                            throw ConnectorToolError.ruleViolation(
                                "bundle size \(size) is below the \(consumed) sessions already consumed — remaining can never go negative")
                        }
                        changes.append("bundle \(copy.bundleSize)→\(size)")
                        copy.bundleSize = size
                    }
                    guard !changes.isEmpty else {
                        throw ConnectorToolError.badArguments("nothing to change")
                    }
                    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                    let log = "[\(stamp)] Assistant edit: \(changes.joined(separator: ", "))"
                    copy.notes = (copy.notes?.isEmpty == false) ? copy.notes! + "\n" + log : log
                    dataManager.updateContract(copy)
                    return ConnectorToolResult(
                        payload: Self.encode(["updated": true, "changes": changes]),
                        summary: "contract updated ✓")
                }),

            ConnectorTool(
                name: "mark_attendance",
                description: "Mark attendance for one session. marks is a list of {athlete_id, state} with state present | excused | unmarked (absent is never marked: once roll call starts, an unmarked student counts as absent). Or pass all_present: true to mark every expected student who is not present or excused. Present and absent use a session from a balance — the app's one redemption authority decides.",
                schema: objectSchema([
                    "session_id": ["type": "string"],
                    "marks": ["type": "array", "items": ["type": "object", "properties": [
                        "athlete_id": ["type": "string"], "state": ["type": "string"]]]],
                    "all_present": ["type": "boolean"],
                ], ["session_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    guard !SessionLifecycle.didNotHappen(session)
                    else { throw ConnectorToolError.ruleViolation("That session was skipped or cancelled — it takes no attendance") }
                    var states: [UUID: AttendanceTriState] = [:]
                    if args["all_present"] as? Bool == true {
                        for id in AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
                        where !session.actualAttendeeIds.contains(id) && !session.excusedAbsences.contains(id) {
                            states[id] = .present
                        }
                    }
                    for mark in args["marks"] as? [[String: Any]] ?? [] {
                        guard let idString = mark["athlete_id"] as? String
                        else { throw ConnectorToolError.badArguments("each mark needs an athlete_id") }
                        let id = try findStudent(["athlete_id": idString]).id
                        switch mark["state"] as? String {
                        case "present": states[id] = .present
                        case "excused": states[id] = .excused
                        case "unmarked": states[id] = .unmarked
                        default: throw ConnectorToolError.badArguments("state is present, excused or unmarked")
                        }
                    }
                    guard !states.isEmpty else { throw ConnectorToolError.badArguments("nothing to mark") }
                    dataManager.setStudentAttendanceStates(sessionId: session.id, states: states)
                    return ConnectorToolResult(
                        payload: Self.encode(["marked": states.count]),
                        summary: "marked \(states.count) in \(session.title)")
                }),

            // ---------------- META ----------------
            ConnectorTool(
                name: "open_in_app",
                description: "Open a record on screen in the Hoopwise app so the user can see it. record_type: athlete | session; record_id is the athlete_id or session_id.",
                schema: objectSchema([
                    "record_type": ["type": "string"],
                    "record_id": ["type": "string"],
                ], ["record_type", "record_id"]),
                category: .meta,
                run: { [self] args in
                    let raw = args["record_id"] as? String ?? ""
                    switch args["record_type"] as? String {
                    case "athlete":
                        let id = try findStudent(["athlete_id": raw]).id
                        NotificationCenter.default.post(name: .hoopwiseOpenAthleteRequest, object: id)
                    case "session":
                        let id = try findSession(["session_id": raw]).id
                        NotificationCenter.default.post(name: .hoopwiseOpenSessionRequest, object: id)
                    default: throw ConnectorToolError.badArguments("record_type is athlete or session")
                    }
                    return ConnectorToolResult(payload: "{\"opened\": true}", summary: "opened in app")
                }),
        ]
    }

}
#endif
