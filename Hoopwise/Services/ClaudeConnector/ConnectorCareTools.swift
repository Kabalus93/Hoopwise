import Foundation
import SwiftData

#if targetEnvironment(macCatalyst)
// MARK: - Claude Desktop connector: putting things right (November 2026)
//
// Luther, after Claude Desktop recorded one shared private lesson as two
// sessions, put the drill notes in two athletes' contact logs, and left a
// private client expected (and inferred absent) at another client's lesson:
// "add a delete tool to revert this mess … anticipate such changes". These are
// the tools for checking and undoing, each through the ONE authority the app
// uses for it:
//   delete_session        → deleteSessionEvent (refunds what it consumed)
//   skip_session          → SessionLifecycle .skip → updateSessionEvent (refund + plans move on)
//   complete / reopen     → SessionLifecycle (.start → .complete / .resetToScheduled)
//   refund_session        → refundSessionToBundle (the contract sheet's Refund)
//   remove_from_program   → removeStudentEnrollment (one roster, keeps the rest)
//   list_charges          → the contracts' bundleSessionIds (what redemption recorded)
//   athlete notes, plays  → the stored records, nothing derived
// DELIBERATELY ABSENT: deleting an athlete, a contract or a payment, and any
// money amount (data minimisation) — those stay in the app, by hand.

extension ConnectorToolRegistry {
    private func schema(_ properties: [String: Any], _ required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private var sessionRef: [String: Any] {
        ["session_id": ["type": "string", "description": "ref from list_sessions"],
         "when": ["type": "string", "description": "or: its start (ISO) …"],
         "program": ["type": "string", "description": "… plus its program"]]
    }

    private func name(of id: UUID) -> String {
        dataManager.students.first { $0.id == id }?.displayName ?? Self.ref(id)
    }

    /// What a session's marks are for one athlete.
    private func mark(_ session: SessionEvent, _ id: UUID) -> String {
        if session.actualAttendeeIds.contains(id) { return "present" }
        if session.excusedAbsences.contains(id) { return "excused" }
        if session.unexcusedAbsences.contains(id) { return "absent" }
        return "unmarked"
    }

    private func sessionLine(_ id: UUID) -> [String: Any] {
        guard let session = dataManager.sessionEvents.first(where: { $0.id == id }) else {
            return ["session_id": Self.ref(id), "missing": "this session no longer exists"]
        }
        return ["session_id": Self.ref(id), "date": Self.isoFormatter.string(from: session.startTime),
                "title": session.title, "status": session.status.rawValue]
    }

    private func playContextFor() -> ModelContext { dataManager.modelContext }

    func careTools() -> [ConnectorTool] {
        let athleteRef: [String: Any] = ["type": "string", "description": "ref from search_athletes"]
        let playRef: [String: Any] = ["type": "string", "description": "play_id from list_plays"]
        return [
            // ---------------- CHECKING ----------------
            ConnectorTool(
                name: "list_charges",
                description: "What an athlete's session balances have actually been charged: each private bundle / group balance with size, remaining, and every session deducted (date, title, and how the athlete was marked). Use it to check a balance, find a double charge, or before refund_session. No money amounts.",
                schema: schema(["athlete_id": athleteRef], ["athlete_id"]),
                category: .read,
                run: { [self] args in
                    let student = try findStudent(args)
                    let contracts = dataManager.contracts.filter { $0.studentId == student.id && $0.hasSessionBalance }
                    var seen: [UUID: Int] = [:]
                    for id in contracts.flatMap(\.bundleSessionIds) { seen[id, default: 0] += 1 }
                    let list = contracts.map { contract -> [String: Any] in
                        var item: [String: Any] = [
                            "contract": contract.contractNumber,
                            "kind": contract.kind.rawValue,
                            "status": contract.status.rawValue,
                            "bundle_size": contract.bundleSize,
                            "remaining": contract.bundleRedemptionsRemaining ?? 0,
                            "deducted": contract.bundleSessionIds.map { id -> [String: Any] in
                                var line = sessionLine(id)
                                if let session = dataManager.sessionEvents.first(where: { $0.id == id }) {
                                    line["marked"] = mark(session, student.id)
                                }
                                return line
                            },
                        ]
                        if contract.kind == .group {
                            item["counts_for"] = contract.programId.flatMap { pid in dataManager.programs.first { $0.id == pid }?.name }
                                ?? "every class (shared)"
                        }
                        return item
                    }
                    var payload: [String: Any] = ["athlete": student.displayName, "balances": list]
                    let doubles = seen.filter { $0.value > 1 }.map { sessionLine($0.key) }
                    if !doubles.isEmpty { payload["charged_on_two_balances"] = doubles }
                    return ConnectorToolResult(payload: Self.encode(payload), summary: "read charges for \(student.displayName)")
                }),

            ConnectorTool(
                name: "list_athlete_notes",
                description: "An athlete's contact log (notes and parent touchpoints), newest first, each with its note_id — to read them, or before delete_athlete_note.",
                schema: schema(["athlete_id": athleteRef], ["athlete_id"]),
                category: .read,
                run: { [self] args in
                    let student = try findStudent(args)
                    let notes = student.parentalTouchpoints.sorted { $0.date > $1.date }.map { note -> [String: Any] in
                        ["note_id": Self.ref(note.id), "date": Self.isoFormatter.string(from: note.date),
                         "type": note.type.rawValue, "text": note.notes ?? ""]
                    }
                    return ConnectorToolResult(payload: Self.encode(["athlete": student.displayName, "notes": notes]),
                                               summary: "read \(student.displayName)'s notes")
                }),

            // ---------------- SESSIONS ----------------
            ConnectorTool(
                name: "delete_session",
                description: "DELETE a session — for one created by mistake or twice. Whatever it charged is refunded to the bundles; its marks, games, plan and notes go with it and cannot be brought back. For a class that simply did not happen, use skip_session instead (it stays in the calendar with the reason). Say what will be lost before calling.",
                schema: schema(sessionRef, []),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    let charged = dataManager.contracts.filter { $0.bundleSessionIds.contains(session.id) }.map { name(of: $0.studentId) }
                    let marks = session.actualAttendeeIds.count + session.excusedAbsences.count + session.unexcusedAbsences.count
                    dataManager.deleteSessionEvent(session)
                    return ConnectorToolResult(
                        payload: Self.encode(["deleted": session.title, "date": Self.isoFormatter.string(from: session.startTime),
                                              "refunded": charged, "marks_removed": marks, "games_removed": session.games.count]),
                        summary: "deleted \(session.title)")
                },
                destructive: true),

            ConnectorTool(
                name: "skip_session",
                description: "A scheduled class that will not happen (holiday, weather, venue, coach away…): marked skipped with the reason, kept in the calendar, nothing charged, and its plan moves to the next class (the app may then offer a make-up). reason: holiday | weather | venue | coach | internal | other.",
                schema: schema(sessionRef.merging(["reason": ["type": "string", "enum": SkipReason.allCases.map(\.rawValue)]]) { $1 },
                               ["reason"]),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    guard let reason = SkipReason(rawValue: args["reason"] as? String ?? "") else {
                        throw ConnectorToolError.badArguments("reason: " + SkipReason.allCases.map(\.rawValue).joined(separator: ", "))
                    }
                    var copy = session
                    guard SessionLifecycle.apply(.skip(reason), to: &copy) else {
                        throw ConnectorToolError.ruleViolation("Only a scheduled session can be skipped (this one is \(session.status.rawValue)); reopen_session first if it really did not happen.")
                    }
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["skipped": session.title, "reason": reason.rawValue]),
                                               summary: "skipped \(session.title)")
                }),

            ConnectorTool(
                name: "complete_session",
                description: "Mark a session completed (a class that happened but was never closed, or one recorded after the fact). Attendance is not touched — set it with mark_attendance.",
                schema: schema(sessionRef, []),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    var copy = session
                    if copy.status == .scheduled { SessionLifecycle.apply(.start, to: &copy) }
                    guard SessionLifecycle.apply(.complete, to: &copy) else {
                        throw ConnectorToolError.ruleViolation("A \(session.status.rawValue) session cannot be completed; reopen_session first.")
                    }
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["completed": session.title]), summary: "completed \(session.title)")
                }),

            ConnectorTool(
                name: "reopen_session",
                description: "Put a completed, skipped, cancelled or auto-closed session back to scheduled — the undo for a wrong skip/cancel/complete. Attendance is kept; a skip's plan moves back.",
                schema: schema(sessionRef, []),
                category: .sessionWrite,
                run: { [self] args in
                    let session = try findSession(args)
                    var copy = session
                    guard SessionLifecycle.apply(.resetToScheduled, to: &copy) else {
                        throw ConnectorToolError.ruleViolation("It is already scheduled.")
                    }
                    dataManager.updateSessionEvent(copy, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["reopened": session.title]), summary: "reopened \(session.title)")
                }),

            ConnectorTool(
                name: "refund_session",
                description: "Give one charged session back to an athlete's balance (the contract sheet's Refund) — e.g. a charge for a class they were wrongly expected at, or a goodwill refund. Check list_charges first. The marks stay; an absent mark should usually become excused (mark_attendance) so it is not charged again.",
                schema: schema(["athlete_id": athleteRef].merging(sessionRef) { $1 }, ["athlete_id"]),
                category: .contractWrite,
                run: { [self] args in
                    let student = try findStudent(args)
                    let session = try findSession(args)
                    let held = dataManager.contracts.filter { $0.studentId == student.id && $0.bundleSessionIds.contains(session.id) }
                    guard !held.isEmpty else {
                        throw ConnectorToolError.ruleViolation("\(student.displayName) was not charged for \(session.title) — nothing to refund.")
                    }
                    dataManager.refundSessionToBundle(sessionId: session.id, studentId: student.id)
                    let remaining = dataManager.currentContract(for: student.id)?.bundleRedemptionsRemaining
                    var payload: [String: Any] = ["refunded": session.title, "athlete": student.displayName]
                    if let remaining { payload["remaining_now"] = remaining }
                    return ConnectorToolResult(payload: Self.encode(payload), summary: "refunded \(student.displayName)")
                },
                destructive: true),

            // ---------------- ATHLETES ----------------
            ConnectorTool(
                name: "remove_from_program",
                description: "Take an athlete off ONE program's roster, keeping their other classes. Upcoming sessions that follow the program stop expecting them; past sessions are unchanged. (set_enrollment MOVES them out of every program.)",
                schema: schema(["athlete_id": athleteRef, "program": ["type": "string"]], ["athlete_id", "program"]),
                category: .athleteWrite,
                run: { [self] args in
                    let student = try findStudent(args)
                    let program = try findProgram(args["program"] as? String ?? "")
                    guard program.enrolledStudentIds.contains(student.id) || student.programId == program.id else {
                        throw ConnectorToolError.ruleViolation("\(student.displayName) is not on \(program.name)'s roster.")
                    }
                    dataManager.removeStudentEnrollment(studentId: student.id, programId: program.id)
                    return ConnectorToolResult(payload: Self.encode(["removed": student.displayName, "program": program.name]),
                                               summary: "\(student.displayName) off \(program.name)")
                }),

            ConnectorTool(
                name: "delete_athlete_note",
                description: "Delete one note from an athlete's contact log (note_id from list_athlete_notes) — e.g. a note put there by mistake. It cannot be brought back.",
                schema: schema(["athlete_id": athleteRef, "note_id": ["type": "string"]], ["athlete_id", "note_id"]),
                category: .athleteWrite,
                run: { [self] args in
                    var student = try findStudent(args)
                    let raw = (args["note_id"] as? String ?? "").lowercased()
                    let hits = student.parentalTouchpoints.filter { Self.ref($0.id).hasPrefix(raw) || $0.id.uuidString.lowercased() == raw }
                    guard raw.count >= 6, hits.count == 1, let note = hits.first else {
                        throw ConnectorToolError.notFound("No single note \"\(raw)\" — use list_athlete_notes.")
                    }
                    student.parentalTouchpoints.removeAll { $0.id == note.id }
                    student.updatedAt = Date()
                    dataManager.updateStudent(student)
                    return ConnectorToolResult(payload: Self.encode(["deleted_note": String((note.notes ?? "").prefix(80))]),
                                               summary: "deleted a note on \(student.displayName)")
                },
                destructive: true),

            // ---------------- PLAYS ----------------
            ConnectorTool(
                name: "remove_play_from_session",
                description: "Take a play out of a session's plan (undoes add_play_to_session). The play stays in the library.",
                schema: schema(["play_id": playRef].merging(sessionRef) { $1 }, ["play_id"]),
                category: .sessionWrite,
                run: { [self] args in
                    var session = try findSession(args)
                    let raw = args["play_id"] as? String ?? ""
                    let play = try? JournalPlayAuthoring.find(raw, in: playContextFor())
                    let before = session.curriculum.plays.count
                    session.curriculum.plays.removeAll { ref in
                        play.map { $0.isNamed(by: ref) } ?? (ref.name.caseInsensitiveCompare(raw) == .orderedSame)
                    }
                    guard session.curriculum.plays.count < before else {
                        throw ConnectorToolError.notFound("That play is not in \(session.title)'s plan (plan: \(session.curriculum.plays.map(\.name))).")
                    }
                    session.updatedAt = Date()
                    dataManager.updateSessionEvent(session, keepLiveFields: true)
                    return ConnectorToolResult(payload: Self.encode(["plays_in_plan": session.curriculum.plays.map(\.name)]),
                                               summary: "removed a play from \(session.title)")
                }),

            ConnectorTool(
                name: "delete_play",
                description: "Delete a play from the library with all its parts and steps (e.g. a test or duplicate). Sessions that planned it keep its name, marked no longer in the library. It cannot be brought back.",
                schema: schema(["play_id": playRef], ["play_id"]),
                category: .playWrite,
                run: { [self] args in
                    let context = playContextFor()
                    let play: JournalPlay
                    do { play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: context) } catch {
                        throw ConnectorToolError.notFound(error.localizedDescription)
                    }
                    let name = play.name
                    context.delete(play)
                    try context.save()
                    return ConnectorToolResult(payload: Self.encode(["deleted_play": name]), summary: "deleted play \(name)")
                },
                destructive: true),

            ConnectorTool(
                name: "delete_play_part",
                description: "Delete a wrinkle or variation (part number or name from get_play) with its steps. The concept cannot be deleted — delete the play instead.",
                schema: schema(["play_id": playRef, "part": ["description": "part number from get_play, or its name"]], ["play_id", "part"]),
                category: .playWrite,
                run: { [self] args in
                    let context = playContextFor()
                    do {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: context)
                        let part = try JournalPlayAuthoring.part(args["part"], of: play)
                        guard part.kind != .concept else {
                            throw ConnectorToolError.ruleViolation("The concept is the play itself; use delete_play.")
                        }
                        let name = part.name
                        context.delete(part)
                        try context.save()
                        return ConnectorToolResult(payload: Self.encode(["deleted_part": name, "play": play.name]),
                                                   summary: "deleted \(name) from \(play.name)")
                    } catch let error as JournalPlayAuthoringError {
                        throw ConnectorToolError.badArguments(error.localizedDescription)
                    }
                },
                destructive: true),

            ConnectorTool(
                name: "delete_play_step",
                description: "Delete one step (1-based) from a part of a play; later steps move up. A part keeps at least one step. Later steps are not redrawn — check them with get_play.",
                schema: schema(["play_id": playRef, "part": ["description": "\"concept\" (default), part number, or name"],
                                "step": ["type": "integer"]], ["play_id", "step"]),
                category: .playWrite,
                run: { [self] args in
                    let context = playContextFor()
                    do {
                        let play = try JournalPlayAuthoring.find(args["play_id"] as? String ?? "", in: context)
                        let part = try JournalPlayAuthoring.part(args["part"], of: play)
                        let steps = part.sortedSteps
                        guard let n = JournalPlayAuthoring.int(args["step"]), steps.indices.contains(n - 1) else {
                            throw ConnectorToolError.badArguments("step: 1–\(steps.count) in \(part.name).")
                        }
                        guard steps.count > 1 else {
                            throw ConnectorToolError.ruleViolation("\(part.name) has only this step; a part keeps at least one.")
                        }
                        context.delete(steps[n - 1])
                        try context.save()
                        part.renumberSteps()
                        try context.save()
                        return ConnectorToolResult(payload: Self.encode(["deleted_step": n, "part": part.name, "steps_left": part.sortedSteps.count]),
                                                   summary: "deleted step \(n) of \(part.name)")
                    } catch let error as JournalPlayAuthoringError {
                        throw ConnectorToolError.badArguments(error.localizedDescription)
                    }
                },
                destructive: true),
        ]
    }
}
#endif
