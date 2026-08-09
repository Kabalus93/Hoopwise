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
