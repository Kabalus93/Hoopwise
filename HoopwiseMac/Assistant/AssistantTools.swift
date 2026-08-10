import Foundation
import SwiftUI

// MARK: - The Whistle's tool registry
//
// The assistant NEVER touches the database directly: every handler calls the
// same shared business-rule layer the UI calls (SessionLifecycle,
// setStudentEnrollment, setStudentAttendanceState-adjacent mutations,
// updateContract…). A rule that would stop a human in the UI stops the
// assistant identically, for free. Writes are previewed by the engine before
// execution; contract writes are never always-allowable.

enum AssistantToolCategory: String, Codable {
    case read, meta
    case sessionWrite = "session"
    case athleteWrite = "athlete"
    case contractWrite = "contract"

    var isWrite: Bool { self != .read && self != .meta }
    /// Contract changes always confirm — no always-allow, ever.
    var supportsAlwaysAllow: Bool { self == .sessionWrite || self == .athleteWrite }
    var allowKey: String { "assistant.alwaysAllow.\(rawValue)" }
}

struct AssistantToolResult {
    var payload: String          // JSON returned to the model
    var summary: String          // one-line chip label for the UI
    var isError: Bool = false
}

struct AssistantTool {
    let name: String
    let description: String
    let schema: [String: Any]
    let category: AssistantToolCategory
    /// Human-readable old → new lines for the confirmation card. Only writes.
    var preview: (([String: Any]) -> [String])?
    let run: ([String: Any]) throws -> AssistantToolResult
}

enum AssistantToolError: LocalizedError {
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
final class AssistantToolRegistry {
    private unowned let dataManager: DataManager
    private(set) var tools: [AssistantTool] = []

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

    func tool(named name: String) -> AssistantTool? {
        tools.first { $0.name == name }
    }

    func execute(name: String, argumentsJSON: String) -> AssistantToolResult {
        guard let tool = tool(named: name) else {
            return AssistantToolResult(payload: "Unknown tool", summary: name, isError: true)
        }
        do {
            let args = try Self.decode(argumentsJSON)
            return try tool.run(args)
        } catch {
            // Relay the actual rule, not a generic error.
            return AssistantToolResult(payload: error.localizedDescription,
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
        else { throw AssistantToolError.badArguments("not a JSON object") }
        return object
    }

    private static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    // MARK: - Shared lookups

    private func findStudent(_ args: [String: Any]) throws -> Student {
        if let idString = args["athlete_id"] as? String, let id = UUID(uuidString: idString),
           let student = dataManager.students.first(where: { $0.id == id }) {
            return student
        }
        if let query = (args["athlete_id"] as? String) ?? (args["query"] as? String) {
            let matches = dataManager.students.filter {
                NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(query)
            }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                throw AssistantToolError.badArguments(
                    "\(matches.count) athletes match \"\(query)\" — use search_athletes and pass an exact athlete_id")
            }
        }
        throw AssistantToolError.notFound("No athlete matches — use search_athletes first")
    }

    private func findSession(_ args: [String: Any]) throws -> SessionEvent {
        guard let idString = args["session_id"] as? String, let id = UUID(uuidString: idString),
              let session = dataManager.sessionEvents.first(where: { $0.id == id })
        else { throw AssistantToolError.notFound("No session with that id — use list_sessions first") }
        return session
    }

    private func studentBrief(_ student: Student) -> [String: Any] {
        var brief: [String: Any] = [
            "athlete_id": student.id.uuidString,
            "name": student.name,
        ]
        if let chinese = student.chineseName { brief["chinese_name"] = chinese }
        if let programId = student.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            brief["program"] = program.name
        }
        return brief
    }

    private func sessionBrief(_ session: SessionEvent) -> [String: Any] {
        var brief: [String: Any] = [
            "session_id": session.id.uuidString,
            "title": session.title,
            "date": Self.isoFormatter.string(from: session.startTime),
            "status": session.status.rawValue,
            "attendee_count": session.attendeeIds.count,
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
            AssistantTool(
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
                    return AssistantToolResult(
                        payload: Self.encode(["count": matches.count, "athletes": Array(list)]),
                        summary: "searched athletes · \(matches.count) match\(matches.count == 1 ? "" : "es")")
                }),

            AssistantTool(
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
                    return AssistantToolResult(payload: Self.encode(payload),
                                               summary: "read \(student.displayName)'s profile")
                }),

            AssistantTool(
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
                    return AssistantToolResult(
                        payload: Self.encode(["count": sessions.count,
                                              "sessions": sessions.prefix(30).map { sessionBrief($0) }]),
                        summary: "listed \(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                }),

            AssistantTool(
                name: "get_session",
                description: "Full detail for one session: roster with attendance states, plan, location.",
                schema: objectSchema(["session_id": ["type": "string"]], ["session_id"]),
                category: .read,
                run: { [self] args in
                    let session = try findSession(args)
                    var payload = sessionBrief(session)
                    let roster = session.attendeeIds.compactMap { id -> [String: Any]? in
                        guard let student = dataManager.students.first(where: { $0.id == id }) else { return nil }
                        let state: String
                        if session.actualAttendeeIds.contains(id) { state = "present" }
                        else if session.excusedAbsences.contains(id) { state = "excused" }
                        else if session.unexcusedAbsences.contains(id) { state = "absent" }
                        else { state = "unmarked" }
                        return ["name": student.displayName, "athlete_id": id.uuidString, "attendance": state]
                    }
                    payload["roster"] = roster
                    if let notes = session.notes, !notes.isEmpty { payload["notes"] = notes }
                    return AssistantToolResult(payload: Self.encode(payload),
                                               summary: "read session \(session.title)")
                }),

            AssistantTool(
                name: "list_programs",
                description: "All programs with type, status, and enrolled count.",
                schema: objectSchema([:], []),
                category: .read,
                run: { [self] _ in
                    let list = dataManager.programs.map { program -> [String: Any] in
                        ["program_id": program.id.uuidString,
                         "name": program.name,
                         "type": program.programType.rawValue,
                         "status": program.status.rawValue,
                         "enrolled": program.enrolledStudentIds.count]
                    }
                    return AssistantToolResult(payload: Self.encode(["programs": list]),
                                               summary: "listed \(list.count) programs")
                }),

            AssistantTool(
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
                                     "athlete_id": student.id.uuidString,
                                     "attendance_percent": Int(rate * 100),
                                     "attended": attendance.attended,
                                     "of": attendance.of])
                    }
                    rows.sort { ($0["attendance_percent"] as? Int ?? 0) < ($1["attendance_percent"] as? Int ?? 0) }
                    return AssistantToolResult(payload: Self.encode(["athletes": Array(rows.prefix(40))]),
                                               summary: "attendance stats · \(rows.count) athletes")
                }),

            // ---------------- WRITE ----------------
            AssistantTool(
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
                preview: { args in
                    var lines = ["Create session \"\(args["title"] as? String ?? "?")\""]
                    if let starts = args["starts"] as? String { lines.append("Starts \(starts)") }
                    if let duration = args["duration_minutes"] as? Int { lines.append("Duration \(duration) min") }
                    if let location = args["location"] as? String { lines.append("At \(location)") }
                    if let ids = args["athlete_ids"] as? [String] { lines.append("Roster: \(ids.count) athletes") }
                    if let program = args["program"] as? String { lines.append("Program: \(program)") }
                    return lines
                },
                run: { [self] args in
                    guard let title = args["title"] as? String,
                          let starts = Self.parseDate(args["starts"] as? String)
                    else { throw AssistantToolError.badArguments("title and a valid ISO 'starts' are required") }
                    let duration = args["duration_minutes"] as? Int ?? 90
                    var programId: UUID?
                    if let programQuery = args["program"] as? String {
                        guard let program = dataManager.programs.first(where: {
                            $0.name.localizedCaseInsensitiveContains(programQuery)
                        }) else { throw AssistantToolError.notFound("No program matches \"\(programQuery)\"") }
                        programId = program.id
                    }
                    var attendees = (args["athlete_ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
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
                    registerUndo(name: "Assistant: Create Session") { manager in
                        manager.undoSessionCreation(result)
                    }
                    return AssistantToolResult(
                        payload: Self.encode(["created": true, "session_id": session.id.uuidString]),
                        summary: "created session \(title) ✓")
                }),

            AssistantTool(
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
                preview: { [self] args in
                    var lines: [String] = []
                    if let session = try? findSession(args) {
                        lines.append("Edit session \"\(session.title)\"")
                        if let title = args["title"] as? String, title != session.title {
                            lines.append("Title → \(title)")
                        }
                    }
                    if let starts = args["starts"] as? String { lines.append("Starts → \(starts)") }
                    if let duration = args["duration_minutes"] as? Int { lines.append("Duration → \(duration) min") }
                    if let location = args["location"] as? String { lines.append("Location → \(location)") }
                    if let ids = args["athlete_ids"] as? [String] { lines.append("Roster → \(ids.count) athletes") }
                    return lines.isEmpty ? ["Edit session"] : lines
                },
                run: { [self] args in
                    let session = try findSession(args)
                    let old = session
                    var copy = session
                    if let title = args["title"] as? String { copy.title = title }
                    if let starts = Self.parseDate(args["starts"] as? String) {
                        let duration = copy.durationMinutes
                        copy.date = starts; copy.startTime = starts
                        copy.endTime = Calendar.current.date(byAdding: .minute, value: duration, to: starts) ?? starts
                    }
                    if let duration = args["duration_minutes"] as? Int {
                        copy.endTime = Calendar.current.date(byAdding: .minute, value: duration, to: copy.startTime) ?? copy.endTime
                    }
                    if let location = args["location"] as? String { copy.location = location }
                    if let ids = args["athlete_ids"] as? [String] {
                        copy.attendeeIds = ids.compactMap(UUID.init(uuidString:))
                    }
                    copy.updatedAt = Date()
                    dataManager.updateSessionEvent(copy)
                    registerUndo(name: "Assistant: Edit Session") { $0.updateSessionEvent(old) }
                    return AssistantToolResult(
                        payload: Self.encode(["updated": true, "session_id": session.id.uuidString]),
                        summary: "updated session \(copy.title) ✓")
                }),

            AssistantTool(
                name: "cancel_session",
                description: "Cancel a scheduled or in-progress session. Uses the app's session state machine — an illegal transition is refused.",
                schema: objectSchema(["session_id": ["type": "string"]], ["session_id"]),
                category: .sessionWrite,
                preview: { [self] args in
                    if let session = try? findSession(args) {
                        return ["Cancel \"\(session.title)\"",
                                Self.isoFormatter.string(from: session.startTime),
                                "Status: \(session.status.rawValue) → cancelled"]
                    }
                    return ["Cancel session"]
                },
                run: { [self] args in
                    let session = try findSession(args)
                    let old = session
                    var copy = session
                    // THE shared state machine — same rule that gates the UI button.
                    guard SessionLifecycle.apply(.cancel, to: &copy) else {
                        throw AssistantToolError.ruleViolation(
                            "Can't cancel a \(session.status.rawValue) session — only scheduled or in-progress sessions cancel")
                    }
                    dataManager.updateSessionEvent(copy)
                    registerUndo(name: "Assistant: Cancel Session") { $0.updateSessionEvent(old) }
                    return AssistantToolResult(
                        payload: Self.encode(["cancelled": true]),
                        summary: "cancelled \(session.title) ✓")
                }),

            AssistantTool(
                name: "create_athlete",
                description: "Add a new athlete to the roster. Name required; chinese_name and program optional.",
                schema: objectSchema([
                    "name": ["type": "string"],
                    "chinese_name": ["type": "string"],
                    "program": ["type": "string"],
                ], ["name"]),
                category: .athleteWrite,
                preview: { args in
                    var lines = ["Add athlete \(args["name"] as? String ?? "?")"]
                    if let chinese = args["chinese_name"] as? String { lines.append("中文名 \(chinese)") }
                    if let program = args["program"] as? String { lines.append("Enroll in \(program)") }
                    return lines
                },
                run: { [self] args in
                    guard let name = args["name"] as? String, !name.isEmpty
                    else { throw AssistantToolError.badArguments("name is required") }
                    var student = Student(id: UUID(), name: name)
                    student.chineseName = args["chinese_name"] as? String
                    dataManager.addStudent(student)
                    if let programQuery = args["program"] as? String,
                       let program = dataManager.programs.first(where: {
                           $0.name.localizedCaseInsensitiveContains(programQuery)
                       }) {
                        // THE shared enrollment writer — keeps both link fields in step.
                        dataManager.setStudentEnrollment(studentId: student.id, programId: program.id)
                    }
                    return AssistantToolResult(
                        payload: Self.encode(["created": true, "athlete_id": student.id.uuidString]),
                        summary: "added \(name) ✓")
                }),

            AssistantTool(
                name: "update_athlete",
                description: "Edit an athlete's name, chinese_name, or notes.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "name": ["type": "string"],
                    "chinese_name": ["type": "string"],
                ], ["athlete_id"]),
                category: .athleteWrite,
                preview: { [self] args in
                    var lines: [String] = []
                    if let student = try? findStudent(args) {
                        lines.append("Edit \(student.displayName)")
                        if let name = args["name"] as? String, name != student.name { lines.append("Name → \(name)") }
                        if let chinese = args["chinese_name"] as? String { lines.append("中文名 → \(chinese)") }
                    }
                    return lines.isEmpty ? ["Edit athlete"] : lines
                },
                run: { [self] args in
                    var student = try findStudent(args)
                    let old = student
                    if let name = args["name"] as? String, !name.isEmpty { student.name = name }
                    if let chinese = args["chinese_name"] as? String { student.chineseName = chinese }
                    student.updatedAt = Date()
                    dataManager.updateStudent(student)
                    registerUndo(name: "Assistant: Edit Athlete") { $0.updateStudent(old) }
                    return AssistantToolResult(
                        payload: Self.encode(["updated": true]),
                        summary: "updated \(student.displayName) ✓")
                }),

            AssistantTool(
                name: "set_enrollment",
                description: "Enroll an athlete in a program (or unenroll with program null). Goes through the app's single enrollment writer.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "program": ["type": ["string", "null"], "description": "Program name, or null to unenroll"],
                ], ["athlete_id"]),
                category: .athleteWrite,
                preview: { [self] args in
                    let who = (try? findStudent(args))?.displayName ?? "athlete"
                    if let program = args["program"] as? String { return ["Enroll \(who) in \(program)"] }
                    return ["Unenroll \(who) from their program"]
                },
                run: { [self] args in
                    let student = try findStudent(args)
                    let oldProgramId = student.programId
                    var newProgramId: UUID?
                    if let programQuery = args["program"] as? String {
                        guard let program = dataManager.programs.first(where: {
                            $0.name.localizedCaseInsensitiveContains(programQuery)
                        }) else { throw AssistantToolError.notFound("No program matches \"\(programQuery)\"") }
                        newProgramId = program.id
                    }
                    dataManager.setStudentEnrollment(studentId: student.id, programId: newProgramId)
                    registerUndo(name: "Assistant: Enrollment") { manager in
                        manager.setStudentEnrollment(studentId: student.id, programId: oldProgramId)
                    }
                    return AssistantToolResult(
                        payload: Self.encode(["updated": true]),
                        summary: "enrollment updated for \(student.displayName) ✓")
                }),

            AssistantTool(
                name: "record_note",
                description: "Append a dated note to an athlete's notes.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "note": ["type": "string"],
                ], ["athlete_id", "note"]),
                category: .athleteWrite,
                preview: { [self] args in
                    let who = (try? findStudent(args))?.displayName ?? "athlete"
                    return ["Add note to \(who)", (args["note"] as? String ?? "")]
                },
                run: { [self] args in
                    var student = try findStudent(args)
                    guard let note = args["note"] as? String, !note.isEmpty
                    else { throw AssistantToolError.badArguments("note is required") }
                    let old = student
                    student.parentalTouchpoints.append(ParentalTouchpoint(
                        id: UUID(), date: Date(), type: .message, notes: note,
                        followUpNeeded: false, followUpDate: nil))
                    student.updatedAt = Date()
                    dataManager.updateStudent(student)
                    registerUndo(name: "Assistant: Note") { $0.updateStudent(old) }
                    return AssistantToolResult(payload: Self.encode(["noted": true]),
                                               summary: "noted on \(student.displayName) ✓")
                }),

            AssistantTool(
                name: "update_contract",
                description: "Edit an athlete's current contract: manual status override, price per session, or bundle size. Bundle size can never go below sessions already consumed. ALWAYS requires user confirmation.",
                schema: objectSchema([
                    "athlete_id": ["type": "string"],
                    "manual_status": ["type": "string", "description": "active/pending/completed/cancelled, or 'auto' to clear the override"],
                    "price_per_session": ["type": "number"],
                    "bundle_size": ["type": "integer"],
                ], ["athlete_id"]),
                category: .contractWrite,
                preview: { [self] args in
                    guard let student = try? findStudent(args),
                          let contract = dataManager.currentContract(for: student.id)
                    else { return ["Edit contract"] }
                    var lines = ["Contract #\(contract.contractNumber) — \(student.displayName)"]
                    if let status = args["manual_status"] as? String { lines.append("Status → \(status)") }
                    if let price = args["price_per_session"] as? Double {
                        lines.append("Price \(Int(contract.pricePerSession)) → \(Int(price))")
                    }
                    if let size = args["bundle_size"] as? Int {
                        lines.append("Bundle \(contract.bundleSize) → \(size) (consumed: \(contract.bundleSessionIds.count))")
                    }
                    return lines
                },
                run: { [self] args in
                    let student = try findStudent(args)
                    guard let contract = dataManager.currentContract(for: student.id)
                    else { throw AssistantToolError.notFound("\(student.displayName) has no current contract") }
                    let old = contract
                    var copy = contract
                    var changes: [String] = []
                    if let statusRaw = args["manual_status"] as? String {
                        if statusRaw == "auto" {
                            copy.manualStatus = nil; changes.append("status→auto")
                        } else if let status = ContractStatus(rawValue: statusRaw) {
                            copy.manualStatus = status; changes.append("status→\(statusRaw)")
                        } else {
                            throw AssistantToolError.badArguments("unknown status \(statusRaw)")
                        }
                    }
                    if let price = args["price_per_session"] as? Double {
                        guard price >= 0 else { throw AssistantToolError.ruleViolation("price can't be negative") }
                        changes.append("price \(Int(copy.pricePerSession))→\(Int(price))")
                        copy.pricePerSession = price
                    }
                    if let size = args["bundle_size"] as? Int {
                        let consumed = copy.bundleSessionIds.count
                        guard size >= consumed else {
                            throw AssistantToolError.ruleViolation(
                                "bundle size \(size) is below the \(consumed) sessions already consumed — remaining can never go negative")
                        }
                        changes.append("bundle \(copy.bundleSize)→\(size)")
                        copy.bundleSize = size
                    }
                    guard !changes.isEmpty else {
                        throw AssistantToolError.badArguments("nothing to change")
                    }
                    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
                    let log = "[\(stamp)] Assistant edit: \(changes.joined(separator: ", "))"
                    copy.notes = (copy.notes?.isEmpty == false) ? copy.notes! + "\n" + log : log
                    dataManager.updateContract(copy)
                    registerUndo(name: "Assistant: Edit Contract") { $0.updateContract(old) }
                    return AssistantToolResult(
                        payload: Self.encode(["updated": true, "changes": changes]),
                        summary: "contract updated ✓")
                }),

            // ---------------- META ----------------
            AssistantTool(
                name: "open_in_app",
                description: "Navigate the app to a record so the user can see it. record_type: athlete | session | sales | today. Pass the record's id for athlete.",
                schema: objectSchema([
                    "record_type": ["type": "string"],
                    "record_id": ["type": "string"],
                ], ["record_type"]),
                category: .meta,
                run: { args in
                    let type = args["record_type"] as? String ?? "today"
                    let center = NotificationCenter.default
                    switch type {
                    case "athlete":
                        center.post(name: .macSidebarSelection, object: SidebarSection.athletes.rawValue)
                        if let idString = args["record_id"] as? String, let id = UUID(uuidString: idString) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                center.post(name: .macOpenAthlete, object: id)
                            }
                        }
                    case "session":
                        center.post(name: .macSidebarSelection, object: SidebarSection.sessions.rawValue)
                    case "sales":
                        center.post(name: .macSidebarSelection, object: SidebarSection.sales.rawValue)
                    default:
                        center.post(name: .macSidebarSelection, object: SidebarSection.today.rawValue)
                    }
                    return AssistantToolResult(payload: "{\"opened\": true}", summary: "opened \(type) in app")
                }),
        ]
    }

    /// Every assistant mutation is one undo step on the main window's stack,
    /// tagged as assistant-originated, so ⌘Z works on its actions exactly
    /// like the user's own.
    private func registerUndo(name: String, undo: @escaping (DataManager) -> Void) {
        guard let undoManager = NSApp.mainWindow?.undoManager else { return }
        undoManager.registerUndo(withTarget: dataManager) { manager in
            undo(manager)
        }
        undoManager.setActionName(name)
    }
}
