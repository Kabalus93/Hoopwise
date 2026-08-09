#if DEBUG
import Foundation

/// Read-only inspector for individual session records, for deciding a
/// duplicate merge by hand.
///
/// HOOPWISE_INSPECT_SESSIONS="1C647CC4,123EC903" (id prefixes, any length)
/// writes a full dump of each matching record to the App Group's
/// Library/Caches/session-inspect.txt. It never mutates anything.
@MainActor
enum SessionInspectorDebug {

    static func runIfRequested(dataManager: DataManager) {
        guard let spec = ProcessInfo.processInfo
            .environment["HOOPWISE_INSPECT_SESSIONS"],
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/session-inspect.txt") else { return }

        let prefixes = spec.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }

        var lines: [String] = ["SESSION INSPECTOR — read only, nothing was written", ""]
        for prefix in prefixes {
            let matches = dataManager.sessionEvents.filter {
                $0.id.uuidString.uppercased().hasPrefix(prefix)
            }
            if matches.isEmpty {
                lines.append("no session id starts with \(prefix)")
                lines.append("")
                continue
            }
            for session in matches {
                lines.append(contentsOf: describe(session, dataManager: dataManager))
                lines.append("")
            }
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }

    /// HOOPWISE_APPLY_DEDUPE="survivor=AB82ECB5,delete=A9FA88CE" applies ONE
    /// duplicate resolution that a human has chosen: merge the doomed record
    /// into the survivor using the tested merge, save, delete, and write a
    /// before/after audit to Library/Caches/dedupe-applied.txt.
    ///
    /// The merge is `SessionDedupe.merged` — the same code the plan proposes
    /// and the tests cover — never a second implementation.
    static func applyDedupeIfRequested(dataManager dm: DataManager) {
        guard let spec = ProcessInfo.processInfo.environment["HOOPWISE_APPLY_DEDUPE"],
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/dedupe-applied.txt") else { return }

        var survivorPrefix = "", deletePrefix = ""
        for part in spec.split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let value = pair[1].trimmingCharacters(in: .whitespaces).uppercased()
            if pair[0].hasPrefix("survivor") { survivorPrefix = value }
            if pair[0].hasPrefix("delete") { deletePrefix = value }
        }

        var out: [String] = ["DEDUPE APPLY — \(spec)", ""]
        func find(_ prefix: String) -> SessionEvent? {
            dm.sessionEvents.first { $0.id.uuidString.uppercased().hasPrefix(prefix) }
        }
        guard !survivorPrefix.isEmpty, !deletePrefix.isEmpty,
              let survivor = find(survivorPrefix), let doomed = find(deletePrefix),
              survivor.id != doomed.id else {
            out.append("ABORTED — could not resolve both ids distinctly. Nothing was written.")
            write(out, to: url)
            return
        }

        // ---- BEFORE
        out.append("BEFORE")
        out.append(contentsOf: contractState(for: [survivor.id, doomed.id], dm: dm).map { "  \($0)" })
        out.append("  survivor \(short(survivor.id)) phase=\(survivor.microCycleId.map(short) ?? "none") expected=\(survivor.attendeeIds.count) present=\(survivor.actualAttendeeIds.count)")
        out.append("  doomed   \(short(doomed.id)) phase=\(doomed.microCycleId.map(short) ?? "none") expected=\(doomed.attendeeIds.count) present=\(doomed.actualAttendeeIds.count)")
        out.append("")

        // ---- APPLY
        let merged = SessionDedupe.merged(survivor, absorbing: doomed)
        dm.updateSessionEvent(merged)
        dm.deleteSessionEvent(doomed)

        // ---- AFTER
        out.append("AFTER")
        out.append(contentsOf: contractState(for: [survivor.id, doomed.id], dm: dm).map { "  \($0)" })
        if let kept = dm.sessionEvents.first(where: { $0.id == survivor.id }) {
            out.append("  survivor \(short(kept.id)) phase=\(kept.microCycleId.map(short) ?? "none") expected=\(kept.attendeeIds.count) present=\(kept.actualAttendeeIds.count) title=\(kept.title)")
        } else {
            out.append("  ERROR survivor is gone")
        }
        let deletedStillPresent = dm.sessionEvents.contains { $0.id == doomed.id }
        out.append("  deleted record still in store: \(deletedStillPresent ? "YES — FAILED" : "no")")
        let stillReferenced = dm.contracts.filter { $0.bundleSessionIds.contains(doomed.id) }
        out.append("  contracts still referencing \(short(doomed.id)): \(stillReferenced.isEmpty ? "none" : stillReferenced.map { "#\($0.contractNumber)" }.joined(separator: ", "))")
        write(out, to: url)
    }

    /// Every contract touching these session ids, with the numbers that
    /// matter: the array contents and the remaining count.
    private static func contractState(for sessionIds: [UUID], dm: DataManager) -> [String] {
        let relevant = dm.contracts.filter { contract in
            sessionIds.contains { contract.bundleSessionIds.contains($0) }
        }
        guard !relevant.isEmpty else { return ["no contract references either session"] }
        return relevant.map { contract in
            let ids = contract.bundleSessionIds.map(short).joined(separator: ", ")
            return "contract #\(contract.contractNumber) [\(short(contract.id))] \(contract.kind.rawValue) size=\(contract.bundleSize) remaining=\(contract.bundleRedemptionsRemaining.map(String.init) ?? "n/a") bundleSessionIds=[\(ids)]"
        }
    }

    private static func write(_ lines: [String], to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic)
    }

    private static func describe(_ session: SessionEvent,
                                 dataManager dm: DataManager) -> [String] {
        var out: [String] = []
        func name(_ id: UUID) -> String {
            dm.students.first { $0.id == id }.map { student in
                [student.chineseName, student.name].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: " / ")
            } ?? "unknown student \(short(id))"
        }

        out.append("════ \(short(session.id))  \(session.title)")
        out.append("  full id        \(session.id.uuidString)")
        out.append("  when           \(stamp(session.date)) · \(time(session.startTime))–\(time(session.endTime))")
        out.append("  status         \(session.status.rawValue)")
        out.append("  location       \(session.location ?? "—")")

        let program = session.programId.flatMap { id in dm.programs.first { $0.id == id } }
        out.append("  program        \(program.map { "\($0.name) [\(short($0.id))]" } ?? (session.programId.map { "DANGLING \(short($0))" } ?? "none (standalone)"))")

        let phase = session.microCycleId.flatMap { id in dm.microCycles.first { $0.id == id } }
        out.append("  phase          \(phase.map { "\($0.title) (phase \($0.phaseNumber)) [\(short($0.id))]" } ?? (session.microCycleId.map { "DANGLING \(short($0))" } ?? "none"))")

        out.append("  expected       \(session.attendeeIds.isEmpty ? "—" : session.attendeeIds.map(name).joined(separator: ", "))")
        out.append("  present        \(session.actualAttendeeIds.isEmpty ? "—" : session.actualAttendeeIds.map(name).joined(separator: ", "))")
        out.append("  excused        \(session.excusedAbsences.isEmpty ? "—" : session.excusedAbsences.map(name).joined(separator: ", "))")
        out.append("  unexcused      \(session.unexcusedAbsences.isEmpty ? "—" : session.unexcusedAbsences.map(name).joined(separator: ", "))")
        out.append("  photo          \(session.attendancePhotoPath ?? "—")")

        let notes = session.notes?.replacingOccurrences(of: "\n", with: "\n                 ")
        out.append("  notes          \(notes?.isEmpty == false ? notes! : "—")")
        out.append("  coach notes    \(session.coachNotes ?? "—")")
        out.append("  plan           \(session.curriculum.totalDrillCount) drills · \(session.games.count) games · rating \(session.rating.map(String.init) ?? "—")")

        let coach = session.createdByCoachId.flatMap { id -> String? in
            if dm.coach.id == id { return dm.coach.name }
            return dm.staffCoaches.first { $0.id == id }?.name
        }
        out.append("  created by     \(coach ?? session.createdByCoachId.map { "unknown coach \(short($0))" } ?? "— (not recorded)")")
        out.append("  created at     \(stamp(session.createdAt)) \(time(session.createdAt))")
        out.append("  updated at     \(stamp(session.updatedAt)) \(time(session.updatedAt))")
        out.append("  likely path    \(inferredPath(session, program: program, phase: phase))")

        // Money: every contract that has charged a slot for this session.
        let holders = dm.contracts.filter { $0.bundleSessionIds.contains(session.id) }
        if holders.isEmpty {
            out.append("  bundle slot    none — this record has not been charged")
        } else {
            for contract in holders {
                let position = (contract.bundleSessionIds.firstIndex(of: session.id) ?? 0) + 1
                out.append("  bundle slot    CHARGED to contract #\(contract.contractNumber) [\(short(contract.id))] of \(name(contract.studentId))")
                out.append("                 \(contract.kind.rawValue) · size \(contract.bundleSize) · used \(contract.bundleSessionIds.count) · REMAINING \(contract.bundleRedemptionsRemaining.map(String.init) ?? "n/a")")
                out.append("                 this session is redemption #\(position) of \(contract.bundleSessionIds.count)")
            }
        }
        return out
    }

    /// Evidence-based guess at which creation path produced the record. The
    /// app stores no provenance, so this is inference — the evidence is
    /// printed alongside so it can be judged.
    private static func inferredPath(_ session: SessionEvent,
                                     program: Program?,
                                     phase: MicroCycle?) -> String {
        var evidence: [String] = []
        if let phase, session.title.hasPrefix(phase.title) {
            evidence.append("title is the phase title" + (session.title == phase.title ? "" : " + ordinal"))
        }
        if let program, session.title == program.name {
            evidence.append("title is the program name")
        }
        if session.microCycleId != nil { evidence.append("phase-linked") } else { evidence.append("no phase") }
        if session.createdByCoachId == nil { evidence.append("no createdByCoachId") }
        if SessionLifecycle.wasAutoClosed(session) { evidence.append("auto-closed by Phase 0") }

        let guess: String
        if let phase, session.title.hasPrefix(phase.title) {
            guess = "materializeSessions / backfillSessions (phase generator)"
        } else if let program, session.title == program.name {
            guess = "AddProgramOnboardingView recurring generator, or Mac NewSessionSheet"
        } else {
            guess = "manual creation"
        }
        return "\(guess)  ← \(evidence.joined(separator: "; "))"
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
#endif
