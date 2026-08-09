import Foundation

// MARK: - Referential integrity across Program / MicroCycle / SessionEvent
//
// The three entities are joined by loose UUID columns. The SwiftData
// relationships that would give them referential integrity are declared with
// `deleteRule: .cascade` but are NEVER populated — every factory writes only
// the scalar id — so the cascades cannot fire and nothing prevents a pointer
// outliving the row it names. Cleanup consequently lives in the views, and
// the views disagree: of four phase-delete call sites only one deletes the
// phase's sessions, and the Mac program-delete path leaves sessions behind
// entirely.
//
// Before repairing any of that, count it. This file is the detection that did
// not exist. It is deliberately PURE — functions over arrays, no data manager,
// no I/O — so the numbers are reproducible, testable, and identical on both
// platforms.
//
// Repair is a separate decision, taken with these numbers in hand.

/// One category of broken or noteworthy pointer.
struct IntegrityFinding: Identifiable, Equatable {
    /// The record carrying the bad pointer.
    let id: UUID
    /// Human-readable identification of that record (title + date).
    let label: String
    /// What the pointer names that cannot be resolved, when applicable.
    let detail: String
}

/// The census. Counts are per CATEGORY; a record can appear in more than one.
struct IntegrityCensus: Equatable {
    var totalSessions = 0
    var totalPhases = 0
    var totalPrograms = 0

    // MARK: Broken — a pointer naming a row that does not exist.

    /// `programId` names a program that is not in the store.
    var sessionsWithDanglingProgram: [IntegrityFinding] = []
    /// `microCycleId` names a phase that is not in the store.
    var sessionsWithDanglingPhase: [IntegrityFinding] = []
    /// A phase whose `programId` names a program that is not in the store.
    var phasesWithDanglingProgram: [IntegrityFinding] = []

    // MARK: Inconsistent — both rows exist but disagree.

    /// The session's phase belongs to a DIFFERENT program than the session.
    /// Structurally possible today because nothing validates the pair; no UI
    /// can currently produce it, so a non-zero count here means the data
    /// predates a rule or arrived from somewhere unexpected.
    var sessionsWithCrossProgramPhase: [IntegrityFinding] = []
    /// Has a phase but no program — the phase implies a program the session
    /// does not claim.
    var sessionsWithPhaseButNoProgram: [IntegrityFinding] = []
    /// Sits outside its phase's date window. Not broken today (linkage is
    /// write-once), but Phase 2 derives the phase from the date, so this is
    /// the count that will change meaning.
    var sessionsOutsideTheirPhaseWindow: [IntegrityFinding] = []

    // MARK: Legitimate today — counted because the re-anchor changes them.

    /// `programId == nil`. Standalone today, and simultaneously the marker
    /// for "private" in three separate predicates.
    var sessionsWithNoProgram: [IntegrityFinding] = []

    // MARK: Advisory — the reconciler's job, not the census's.

    /// Same program, same calendar day, same start time: candidates for the
    /// dedupe pass. Reported so the repair decision knows the size.
    var sameDayDuplicateGroups: [IntegrityFinding] = []

    /// Everything that is unambiguously broken — the number that must reach
    /// zero and stay there.
    var brokenCount: Int {
        sessionsWithDanglingProgram.count
            + sessionsWithDanglingPhase.count
            + phasesWithDanglingProgram.count
            + sessionsWithCrossProgramPhase.count
    }

    var isClean: Bool { brokenCount == 0 }
}

enum SessionIntegrity {

    /// Runs the census. Pure: same inputs, same output, no side effects.
    static func census(sessions: [SessionEvent],
                       programs: [Program],
                       phases: [MicroCycle]) -> IntegrityCensus {
        var report = IntegrityCensus()
        report.totalSessions = sessions.count
        report.totalPhases = phases.count
        report.totalPrograms = programs.count

        let programIds = Set(programs.map(\.id))
        let phasesById = Dictionary(phases.map { ($0.id, $0) },
                                    uniquingKeysWith: { first, _ in first })

        for session in sessions {
            let label = describe(session)

            if let programId = session.programId {
                if !programIds.contains(programId) {
                    report.sessionsWithDanglingProgram.append(
                        IntegrityFinding(id: session.id, label: label,
                                         detail: "programId \(programId) not found"))
                }
            } else {
                report.sessionsWithNoProgram.append(
                    IntegrityFinding(id: session.id, label: label, detail: "standalone"))
            }

            guard let phaseId = session.microCycleId else { continue }

            guard let phase = phasesById[phaseId] else {
                report.sessionsWithDanglingPhase.append(
                    IntegrityFinding(id: session.id, label: label,
                                     detail: "microCycleId \(phaseId) not found"))
                continue
            }

            if let programId = session.programId {
                if phase.programId != programId {
                    report.sessionsWithCrossProgramPhase.append(
                        IntegrityFinding(id: session.id, label: label,
                                         detail: "phase \(phase.title) belongs to program \(phase.programId), session claims \(programId)"))
                }
            } else {
                report.sessionsWithPhaseButNoProgram.append(
                    IntegrityFinding(id: session.id, label: label,
                                     detail: "phase \(phase.title) implies program \(phase.programId)"))
            }

            if let start = phase.startDate, let end = phase.endDate,
               session.date < start || session.date > end {
                report.sessionsOutsideTheirPhaseWindow.append(
                    IntegrityFinding(id: session.id, label: label,
                                     detail: "phase window \(day(start))…\(day(end))"))
            }
        }

        for phase in phases where !programIds.contains(phase.programId) {
            report.phasesWithDanglingProgram.append(
                IntegrityFinding(id: phase.id,
                                 label: "\(phase.title) (phase \(phase.phaseNumber))",
                                 detail: "programId \(phase.programId) not found"))
        }

        report.sameDayDuplicateGroups = duplicateGroups(in: sessions)
        return report
    }

    /// Sessions sharing program + calendar day + start time, grouped. The
    /// dedupe planner consumes these; the census only counts them.
    ///
    /// Bucketing includes the START TIME on purpose: the legacy
    /// `dedupeProgramSessions` buckets on start-of-day alone and would call a
    /// morning and an afternoon session duplicates.
    static func duplicateSessionGroups(in sessions: [SessionEvent]) -> [[SessionEvent]] {
        let calendar = Calendar.current
        var buckets: [String: [SessionEvent]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            let time = calendar.dateComponents([.hour, .minute], from: session.startTime)
            let key = [
                session.programId?.uuidString ?? "standalone",
                "\(day.timeIntervalSince1970)",
                "\(time.hour ?? -1):\(time.minute ?? -1)",
            ].joined(separator: "|")
            buckets[key, default: []].append(session)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted { $0.id.uuidString < $1.id.uuidString } }
            .sorted { ($0.first?.date ?? .distantPast) < ($1.first?.date ?? .distantPast) }
    }

    /// Groups of sessions sharing program + calendar day + start time. One
    /// finding per GROUP, labelled with how many records are in it.
    private static func duplicateGroups(in sessions: [SessionEvent]) -> [IntegrityFinding] {
        duplicateSessionGroups(in: sessions)
            .compactMap { group -> IntegrityFinding? in
                guard let first = group.first else { return nil }
                return IntegrityFinding(id: first.id,
                                        label: describe(first),
                                        detail: "\(group.count) records share this program/day/time")
            }
            .sorted { $0.label < $1.label }
    }

    static func describe(_ session: SessionEvent) -> String {
        "\(session.title.isEmpty ? "(untitled)" : session.title) · \(day(session.date))"
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Report

    /// Plain-text census, newest concerns first. `sampleLimit` caps the
    /// per-category examples so a large store still produces a readable page.
    static func report(_ census: IntegrityCensus, sampleLimit: Int = 8) -> String {
        var lines: [String] = []
        lines.append("ORPHAN CENSUS")
        lines.append("store: \(census.totalSessions) sessions · \(census.totalPhases) phases · \(census.totalPrograms) programs")
        lines.append("BROKEN TOTAL: \(census.brokenCount)")
        lines.append("")

        func section(_ title: String, _ findings: [IntegrityFinding], verdict: String) {
            lines.append("\(title): \(findings.count)   [\(verdict)]")
            for finding in findings.prefix(sampleLimit) {
                lines.append("    · \(finding.label) — \(finding.detail)")
            }
            if findings.count > sampleLimit {
                lines.append("    … \(findings.count - sampleLimit) more")
            }
        }

        section("sessions with a dangling programId", census.sessionsWithDanglingProgram,
                verdict: "BROKEN — repair to nil")
        section("sessions with a dangling microCycleId", census.sessionsWithDanglingPhase,
                verdict: "BROKEN — repair to nil")
        section("phases with a dangling programId", census.phasesWithDanglingProgram,
                verdict: "BROKEN — orphaned phase")
        section("sessions whose phase belongs to another program", census.sessionsWithCrossProgramPhase,
                verdict: "BROKEN — invariant nothing validates")
        section("sessions with a phase but no program", census.sessionsWithPhaseButNoProgram,
                verdict: "inconsistent")
        section("sessions outside their phase's window", census.sessionsOutsideTheirPhaseWindow,
                verdict: "advisory — Phase 2 derives phase from date")
        section("sessions with no program (standalone)", census.sessionsWithNoProgram,
                verdict: "legitimate today — Phase 2 adopts these")
        section("same program/day/time duplicate groups", census.sameDayDuplicateGroups,
                verdict: "advisory — reconciler dedupe")

        return lines.joined(separator: "\n")
    }
}
