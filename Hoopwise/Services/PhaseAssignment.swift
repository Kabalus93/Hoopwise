import Foundation

// MARK: - A session's phase comes from its DATE (Phase 2.4)
//
// `microCycleId` used to be write-once truth: set by whichever generator made
// the session, never re-derived, with no UI to change it. Reordering phases
// then had two different meanings — iOS shifted every session's date by the
// delta (a raw TimeInterval add, so a reorder across a DST boundary moved
// sessions by an hour), while Mac swapped phase numbers and moved nothing,
// leaving number order contradicting date order.
//
// Now the plan owns the calendar: a phase has a window, and a session belongs
// to whichever phase's window contains its date. Reorder means RE-WINDOW, and
// the sessions re-derive. Nothing shifts a session's date behind the coach's
// back.
//
// The window test is SessionIntegrity.phaseWindow — calendar days, inclusive
// of both edges — so this rule and the census cannot disagree.
enum PhaseAssignment {

    enum Outcome: Equatable {
        /// Exactly one phase window contains the date.
        case assign(phaseId: UUID)
        /// No window contains it. The existing link is LEFT ALONE rather than
        /// cleared: a plan that does not cover a session is a gap in the plan,
        /// not evidence that the session belongs nowhere.
        case noWindow
        /// Overlapping windows. Keeps the current link when it is one of the
        /// candidates; otherwise reports rather than guessing.
        case ambiguous(candidates: [UUID])
    }

    /// Derives the phase for one session. Pure.
    static func derive(session: SessionEvent,
                       phases: [MicroCycle],
                       calendar: Calendar = .current) -> Outcome {
        guard let programId = session.programId else { return .noWindow }
        let candidates = phases.filter { phase in
            phase.programId == programId
                && phase.startDate != nil && phase.endDate != nil
                && SessionIntegrity.phaseWindow(start: phase.startDate!,
                                                end: phase.endDate!,
                                                contains: session.date,
                                                calendar: calendar)
        }
        switch candidates.count {
        case 0: return .noWindow
        case 1: return .assign(phaseId: candidates[0].id)
        default:
            let ids = candidates.map(\.id)
            if let current = session.microCycleId, ids.contains(current) {
                return .assign(phaseId: current)   // keep a valid existing link
            }
            return .ambiguous(candidates: ids.sorted { $0.uuidString < $1.uuidString })
        }
    }

    // MARK: - Dry run

    struct Change: Identifiable {
        let id: UUID              // session id
        let label: String
        let from: String
        let to: String
        let kind: String          // assigned | corrected | ambiguous | uncovered
    }

    struct Plan {
        var changes: [Change] = []
        var unchanged = 0
        var assigned: Int { changes.filter { $0.kind == "assigned" }.count }
        var corrected: Int { changes.filter { $0.kind == "corrected" }.count }
        var ambiguous: Int { changes.filter { $0.kind == "ambiguous" }.count }
        var uncovered: Int { changes.filter { $0.kind == "uncovered" }.count }
    }

    static func plan(sessions: [SessionEvent],
                     phases: [MicroCycle],
                     calendar: Calendar = .current) -> Plan {
        var plan = Plan()
        let title = Dictionary(phases.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        for session in sessions where session.programId != nil {
            let label = SessionIntegrity.describe(session)
            let current = session.microCycleId
            switch derive(session: session, phases: phases, calendar: calendar) {
            case .assign(let phaseId):
                if current == phaseId { plan.unchanged += 1; continue }
                plan.changes.append(Change(
                    id: session.id, label: label,
                    from: current.flatMap { title[$0] } ?? "—",
                    to: title[phaseId] ?? "?",
                    kind: current == nil ? "assigned" : "corrected"))
            case .noWindow:
                if current == nil { plan.unchanged += 1; continue }
                plan.changes.append(Change(
                    id: session.id, label: label,
                    from: current.flatMap { title[$0] } ?? "—",
                    to: "kept — no phase window covers this date",
                    kind: "uncovered"))
            case .ambiguous(let candidates):
                plan.changes.append(Change(
                    id: session.id, label: label,
                    from: current.flatMap { title[$0] } ?? "—",
                    to: candidates.compactMap { title[$0] }.joined(separator: " / "),
                    kind: "ambiguous"))
            }
        }
        return plan
    }

    static func report(_ plan: Plan, sampleLimit: Int = 8) -> String {
        var lines = ["PHASE DERIVATION DRY RUN (2.4) — nothing was written"]
        lines.append("  unchanged .......... \(plan.unchanged)")
        lines.append("  newly assigned ..... \(plan.assigned)")
        lines.append("  corrected .......... \(plan.corrected)")
        lines.append("  left (no window) ... \(plan.uncovered)")
        lines.append("  ambiguous .......... \(plan.ambiguous)")
        lines.append("")
        for kind in ["corrected", "assigned", "ambiguous", "uncovered"] {
            let inKind = plan.changes.filter { $0.kind == kind }
            guard !inKind.isEmpty else { continue }
            lines.append("[\(kind)] \(inKind.count)")
            for change in inKind.prefix(sampleLimit) {
                lines.append("    · \(change.label): \(change.from) → \(change.to)")
            }
            if inKind.count > sampleLimit { lines.append("    … \(inKind.count - sampleLimit) more") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Re-windowing an undated plan (dry run)

    /// What giving a program's phases real windows would do to its sessions.
    ///
    /// Programs created through the wizard's phased branch get "Phase 1…N"
    /// with NO dates, so date-derivation cannot function for them at all —
    /// their sessions keep whatever link a generator wrote. Laying contiguous
    /// windows from the program's start date makes derivation possible, but
    /// it can also move sessions between phases, so it gets its own report.
    static func rewindowReport(program: Program,
                               phases: [MicroCycle],
                               sessions: [SessionEvent],
                               calendar: Calendar = .current) -> String {
        let mine = phases.filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        let mySessions = sessions.filter { $0.programId == program.id }
            .sorted { $0.date < $1.date }
        guard let start = program.startDate else {
            return "RE-WINDOW DRY RUN — “\(program.name)” has no start date, so windows cannot be laid out. Nothing to propose."
        }

        let proposed = rewindowed(mine, programStart: start, calendar: calendar)
        let titleOf = Dictionary(phases.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

        var lines = ["RE-WINDOW DRY RUN — “\(program.name)” — nothing was written"]
        lines.append("  program starts \(day(start)) · \(mine.count) phases · \(mySessions.count) sessions")
        lines.append("")
        lines.append("proposed windows:")
        for phase in proposed {
            lines.append("    \(phase.phaseNumber). \(phase.title)  \(day(phase.startDate!))…\(day(phase.endDate!))  (\(phase.durationWeeks)w)")
        }
        let planEnd = proposed.last?.endDate
        lines.append("")

        var moved = 0, unchanged = 0, outside = 0
        var detail: [String] = []
        for session in mySessions {
            let outcome = derive(session: session, phases: proposed, calendar: calendar)
            let current = session.microCycleId.flatMap { titleOf[$0] } ?? "—"
            switch outcome {
            case .assign(let phaseId):
                let next = proposed.first { $0.id == phaseId }?.title ?? "?"
                if session.microCycleId == phaseId { unchanged += 1 }
                else { moved += 1; detail.append("    · \(day(session.date)): \(current) → \(next)") }
            case .noWindow:
                outside += 1
                detail.append("    · \(day(session.date)): \(current) → OUTSIDE the plan (kept)")
            case .ambiguous:
                detail.append("    · \(day(session.date)): \(current) → ambiguous (kept)")
            }
        }
        lines.append("effect on sessions: \(unchanged) unchanged · \(moved) move phase · \(outside) fall outside the plan")
        if let planEnd { lines.append("  plan covers \(day(start))…\(day(planEnd)); sessions run to \(day(mySessions.last?.date ?? start))") }
        lines.append("")
        lines.append(contentsOf: detail.prefix(30))
        if detail.count > 30 { lines.append("    … \(detail.count - 30) more") }
        return lines.joined(separator: "\n")
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Reorder = re-window

    /// Reordering a plan renumbers the phases AND recomputes their windows,
    /// contiguously from the program's start date, each phase keeping its own
    /// `durationWeeks`. Sessions are NOT moved — they re-derive from the new
    /// windows.
    ///
    /// This replaces two incompatible implementations: iOS shifted every
    /// session's date by the delta (DST-unsafe), Mac swapped phase numbers and
    /// left the dates contradicting them.
    static func rewindowed(_ phases: [MicroCycle],
                           programStart: Date,
                           calendar: Calendar = .current) -> [MicroCycle] {
        var cursor = calendar.startOfDay(for: programStart)
        return phases
            .sorted { $0.phaseNumber < $1.phaseNumber }
            .enumerated()
            .map { index, phase in
                var updated = phase
                updated.phaseNumber = index + 1
                updated.startDate = cursor
                let end = calendar.date(byAdding: .day,
                                        value: max(1, phase.durationWeeks) * 7 - 1,
                                        to: cursor) ?? cursor
                updated.endDate = end
                cursor = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                updated.updatedAt = Date()
                return updated
            }
    }

    /// Moves one phase to a new position and re-windows the whole plan.
    static func reordered(_ phases: [MicroCycle],
                          moving phaseId: UUID,
                          to destinationIndex: Int,
                          programStart: Date,
                          calendar: Calendar = .current) -> [MicroCycle] {
        var ordered = phases.sorted { $0.phaseNumber < $1.phaseNumber }
        guard let from = ordered.firstIndex(where: { $0.id == phaseId }) else { return phases }
        let clamped = max(0, min(destinationIndex, ordered.count - 1))
        let moved = ordered.remove(at: from)
        ordered.insert(moved, at: clamped)
        for index in ordered.indices { ordered[index].phaseNumber = index + 1 }
        return rewindowed(ordered, programStart: programStart, calendar: calendar)
    }
}
