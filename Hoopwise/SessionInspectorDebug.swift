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

    /// HOOPWISE_APPLY_PLAN_RESHAPE=1 — writes the reshape the dry run
    /// describes, using the SAME `proposedElitePlan` computation so what was
    /// reviewed and what is written cannot diverge.
    ///
    /// Idempotent: if "Summer Block" already exists for the program it
    /// reports and writes nothing, so a second run cannot create a duplicate
    /// phase.
    static func applyPlanReshapeIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_APPLY_PLAN_RESHAPE"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/plan-reshape.txt") else { return }

        let programName = "Elite U10 Development"
        var out = ["APPLY PLAN RESHAPE — “\(programName)”", ""]
        guard let program = dm.programs.first(where: { $0.name == programName }) else {
            out.append("ABORTED — no such program. Nothing written.")
            write(out, to: url)
            return
        }
        if dm.microCycles.contains(where: { $0.programId == program.id && $0.title == "Summer Block" }) {
            out.append("already applied — “Summer Block” exists. Nothing written.")
            write(out, to: url)
            return
        }

        func phaseLines() -> [String] {
            dm.microCycles.filter { $0.programId == program.id }
                .sorted { $0.phaseNumber < $1.phaseNumber }
                .map { "    \($0.phaseNumber). \($0.title)  \(dayString($0.startDate))…\(dayString($0.endDate))  (\($0.durationWeeks)w)" }
        }
        func sessionsPerPhase() -> [String] {
            let mine = dm.sessionEvents.filter { $0.programId == program.id }
            let titles = Dictionary(dm.microCycles.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            var counts: [String: Int] = [:]
            for session in mine { counts[session.microCycleId.flatMap { titles[$0] } ?? "— unphased", default: 0] += 1 }
            return counts.sorted { $0.key < $1.key }.map { "    \($0.key): \($0.value)" }
        }

        out.append("BEFORE")
        out.append("  program start \(dayString(program.startDate))")
        out.append(contentsOf: phaseLines())
        out.append("  sessions per phase:")
        out.append(contentsOf: sessionsPerPhase())
        out.append("")

        let (_, proposed) = proposedElitePlan(dm: dm)
        guard !proposed.isEmpty else {
            out.append("ABORTED — proposal came back empty. Nothing written.")
            write(out, to: url)
            return
        }

        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 1
        var updatedProgram = program
        updatedProgram.startDate = Calendar.current.date(from: components)
        updatedProgram.updatedAt = Date()
        dm.updateProgram(updatedProgram)

        let existingIds = Set(dm.microCycles.filter { $0.programId == program.id }.map(\.id))
        var added = 0, updated = 0
        for phase in proposed {
            if existingIds.contains(phase.id) { dm.updateMicroCycle(phase); updated += 1 }
            else { dm.addMicroCycle(phase); added += 1 }
        }
        out.append("wrote: program start → 2026-05-01 · \(updated) phases re-windowed · \(added) phase added")

        // Links are derived, so let the reconciler place the sessions.
        let reconciled = SessionReconciler.run(dataManager: dm, force: true)
        out.append("reconciler: \(reconciled.summary)")
        out.append("")

        out.append("AFTER")
        out.append("  program start \(dayString(dm.programs.first { $0.id == program.id }?.startDate))")
        out.append(contentsOf: phaseLines())
        out.append("  sessions per phase:")
        out.append(contentsOf: sessionsPerPhase())

        let census = SessionIntegrity.census(sessions: dm.sessionEvents,
                                             programs: dm.programs, phases: dm.microCycles)
        let derivation = PhaseAssignment.plan(sessions: dm.sessionEvents, phases: dm.microCycles)
        out.append("")
        out.append("  census: \(dm.sessionEvents.count) sessions · BROKEN \(census.brokenCount) · window violations \(census.sessionsOutsideTheirPhaseWindow.count)")
        out.append("  derivation outstanding: assigned \(derivation.assigned) · corrected \(derivation.corrected) · ambiguous \(derivation.ambiguous) · left \(derivation.uncovered)")
        write(out, to: url)
    }

    /// HOOPWISE_EXTEND_PLAN_DRYRUN=1 — the authorised plan reshape for
    /// Elite U10 Development, as a DRY RUN:
    ///   · program start 2026-05-08 → 2026-05-01 (so the 05-01 session is covered)
    ///   · Phase 1 stretched 2w → 3w to absorb the earlier start, leaving
    ///     Phases 2–5 on exactly the dates they already have
    ///   · a sixth phase "Summer Block" appended for the rest of the season
    ///
    /// Whole-week durations cannot land exactly on 2026-09-11: 8 weeks ends
    /// 09-10 and would leave the final session outside the plan by one day,
    /// so Summer Block is 9 weeks and ends 09-17.
    static func extendPlanDryRunIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_EXTEND_PLAN_DRYRUN"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/extend-plan.txt") else { return }
        let (text, _) = proposedElitePlan(dm: dm)
        write([text], to: url)
    }

    /// Shared by the dry run and the apply step, so what is reported and what
    /// is written cannot diverge.
    static func proposedElitePlan(dm: DataManager) -> (report: String, phases: [MicroCycle]) {
        let programName = "Elite U10 Development"
        guard let program = dm.programs.first(where: { $0.name == programName }) else {
            return ("EXTEND PLAN — no program named “\(programName)”", [])
        }
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 1
        let newStart = Calendar.current.date(from: components)!

        var existing = dm.microCycles.filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        guard !existing.isEmpty else { return ("EXTEND PLAN — no phases", []) }
        existing[0].durationWeeks = 3      // absorb the earlier start

        let summer = MicroCycle(programId: program.id,
                                phaseNumber: existing.count + 1,
                                title: "Summer Block",
                                durationWeeks: 9)
        let proposed = PhaseAssignment.rewindowed(existing + [summer],
                                                  programStart: newStart)

        var lines = ["EXTEND PLAN DRY RUN — “\(programName)” — nothing was written"]
        lines.append("  program start \(dayString(program.startDate)) → 2026-05-01")
        lines.append("  Phase 1: 2 weeks → 3 weeks · appending “Summer Block” (9 weeks)")
        lines.append("")
        lines.append("proposed windows:")
        for phase in proposed {
            lines.append("    \(phase.phaseNumber). \(phase.title)  \(dayString(phase.startDate))…\(dayString(phase.endDate))  (\(phase.durationWeeks)w)")
        }
        lines.append("")

        let titleOf = Dictionary(dm.microCycles.map { ($0.id, $0.title) },
                                 uniquingKeysWith: { a, _ in a })
        let sessions = dm.sessionEvents.filter { $0.programId == program.id }
            .sorted { $0.date < $1.date }
        var landing: [String: Int] = [:]
        var outside = 0
        var moves: [String] = []
        for session in sessions {
            let current = session.microCycleId.flatMap { titleOf[$0] } ?? "—"
            switch PhaseAssignment.derive(session: session, phases: proposed) {
            case .assign(let phaseId):
                let next = proposed.first { $0.id == phaseId }?.title ?? "?"
                landing[next, default: 0] += 1
                moves.append("    · \(dayString(session.date)): \(current) → \(next)\(current == next ? "" : "   [MOVED]")")
            case .noWindow:
                outside += 1
                moves.append("    · \(dayString(session.date)): \(current) → still outside the plan")
            case .ambiguous:
                moves.append("    · \(dayString(session.date)): \(current) → ambiguous")
            }
        }
        lines.append("sessions landing per phase:")
        for phase in proposed {
            lines.append("    \(phase.title): \(landing[phase.title] ?? 0)")
        }
        lines.append("    still outside: \(outside)")
        lines.append("")
        lines.append("per session (\(sessions.count)):")
        lines.append(contentsOf: moves)
        return (lines.joined(separator: "\n"), proposed)
    }

    private static func dayString(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// HOOPWISE_REWINDOW_DRYRUN="<program name>" — what laying contiguous
    /// windows on that program's dateless phases would do to its sessions.
    /// Read-only.
    static func rewindowDryRunIfRequested(dataManager dm: DataManager) {
        guard let name = ProcessInfo.processInfo.environment["HOOPWISE_REWINDOW_DRYRUN"],
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/rewindow.txt") else { return }
        guard let program = dm.programs.first(where: { $0.name == name }) else {
            write(["RE-WINDOW DRY RUN — no program named “\(name)”"], to: url)
            return
        }
        let text = PhaseAssignment.rewindowReport(program: program,
                                                  phases: dm.microCycles,
                                                  sessions: dm.sessionEvents)
        write([text], to: url)
    }

    /// HOOPWISE_APPLY_ALL_MERGES=1 — executes every AUTO-resolvable duplicate
    /// group. Manual-review groups are skipped, always.
    ///
    /// Safe to run only now that names are derived: the survivor's stored
    /// title no longer decides what the coach sees, so a merge can no longer
    /// rename a calendar entry.
    ///
    /// Each merge uses SessionDedupe.merged — the same code the plan proposes
    /// and the tests cover — then saves the survivor and deletes the sibling
    /// through deleteSessionEvent, so any prepaid slot is refunded and no
    /// contract keeps a reference to a record that no longer exists.
    static func applyAllMergesIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_APPLY_ALL_MERGES"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/merges-applied.txt") else { return }

        let redeemed = SessionDedupe.redeemedSessionIds(in: dm.contracts)
        let plan = SessionDedupe.plan(
            groups: SessionIntegrity.duplicateSessionGroups(in: dm.sessionEvents),
            redeemedSessionIds: redeemed)

        var out = ["APPLY DUPLICATE MERGES", ""]
        out.append("BEFORE: \(dm.sessionEvents.count) sessions · \(plan.decisions.count) groups (\(plan.automatic.count) auto, \(plan.manualReview.count) review)")
        out.append("")

        var merged = 0, deleted = 0, refunded = 0
        for decision in plan.automatic {
            let slotsBefore = dm.contracts.reduce(0) { $0 + $1.bundleSessionIds.count }
            dm.updateSessionEvent(decision.survivor)
            for doomedId in decision.deletedIds {
                guard let doomed = dm.sessionEvents.first(where: { $0.id == doomedId }) else { continue }
                dm.deleteSessionEvent(doomed)
                deleted += 1
            }
            let slotsAfter = dm.contracts.reduce(0) { $0 + $1.bundleSessionIds.count }
            if slotsAfter != slotsBefore { refunded += slotsBefore - slotsAfter }
            merged += 1
            out.append("[merged] \(decision.label) — kept \(short(decision.id)), removed \(decision.deletedIds.map(short).joined(separator: ", "))")
        }

        for decision in plan.manualReview {
            out.append("[SKIPPED — review] \(decision.label): \(decision.reviewReasons.joined(separator: "; "))")
        }

        // Re-detect, so the report states the true remaining state.
        let after = SessionDedupe.plan(
            groups: SessionIntegrity.duplicateSessionGroups(in: dm.sessionEvents),
            redeemedSessionIds: SessionDedupe.redeemedSessionIds(in: dm.contracts))
        let census = SessionIntegrity.census(sessions: dm.sessionEvents,
                                             programs: dm.programs,
                                             phases: dm.microCycles)
        out.append("")
        out.append("AFTER: \(dm.sessionEvents.count) sessions · \(after.decisions.count) groups remaining")
        out.append("  merged \(merged) groups, deleted \(deleted) records, bundle slots released \(refunded)")
        out.append("  census BROKEN TOTAL: \(census.brokenCount) · window violations: \(census.sessionsOutsideTheirPhaseWindow.count)")
        write(out, to: url)
    }

    /// HOOPWISE_CREATE_MICROGROUPS=1 — Phase 2.1's second half: one
    /// `.privateSessions` program per private client, and their standalone
    /// 1:1 sessions re-homed onto it.
    ///
    /// After this, `SessionPrivacy` answers "is it private?" from the program
    /// type for these sessions — the Phase 2 target rule — instead of the
    /// interim contract check. Redemption is unaffected: eventIsPrivate stays
    /// true either way, so no bundle behaviour changes.
    ///
    /// Idempotent per client, and it adopts ONLY the sessions the dry-run
    /// assigned to that client.
    static func createMicroGroupsIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_CREATE_MICROGROUPS"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/microgroups.txt") else { return }

        var out = ["CREATE PRIVATE MICRO-GROUPS (Phase 2.1)", ""]
        let plan = SessionAdoption.plan(sessions: dm.sessionEvents,
                                        programs: dm.programs,
                                        contracts: dm.contracts,
                                        students: dm.students)

        // client → the sessions the plan assigned to them.
        var byClient: [UUID: [UUID]] = [:]
        for decision in plan.decisions {
            if case .privateMicroGroup(let studentId, _) = decision.destination {
                byClient[studentId, default: []].append(decision.id)
            }
        }
        out.append("plan assigns \(plan.decisions.filter { $0.destination.bucket == "private micro-group" }.count) sessions across \(byClient.count) clients")
        out.append("")

        for (studentId, sessionIds) in byClient.sorted(by: { $0.value.count > $1.value.count }) {
            guard let student = dm.students.first(where: { $0.id == studentId }) else { continue }
            let display = [student.chineseName, student.name].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: " / ")
            let name = "Private · \(display)"

            // Age band: the student's own birthdate first, then whatever band
            // their existing programs carry, and only then a flagged default.
            var bandSource = "birthdate"
            var band = student.ageGroup
            if band == nil {
                let enrolled = dm.programs
                    .filter { $0.enrolledStudentIds.contains(studentId) }
                    .map(\.ageGroup)
                band = enrolled.first
                bandSource = enrolled.isEmpty ? "DEFAULTED — no birthdate, no enrolment" : "existing enrolment"
            }
            let ageGroup = band ?? .adult

            let program: Program
            if let existing = dm.programs.first(where: { $0.name == name }) {
                program = existing
                out.append("\(name) — already exists [\(short(existing.id))]")
            } else {
                // No recurringDays and no defaultSessionTime: private sessions
                // have no fixed weekly slot, and leaving those set would let
                // the adoption slot-tier match unrelated sessions later.
                let created = Program(name: name,
                                      programType: .privateSessions,
                                      ageGroup: ageGroup,
                                      enrolledStudentIds: [studentId],
                                      createdByCoachId: dm.loggedInCoachId ?? dm.coach.id,
                                      status: .active,
                                      recurringDays: [],
                                      defaultSessionTime: nil,
                                      usesPhases: false)
                dm.addProgram(created)
                program = created
                out.append("\(name) [\(short(created.id))] — band \(ageGroup.rawValue) (\(bandSource))")
            }

            // Enrol through the one writer, then adopt.
            dm.setStudentEnrollment(studentId: studentId, programId: program.id)
            var adopted = 0
            for sessionId in sessionIds {
                guard var session = dm.sessionEvents.first(where: { $0.id == sessionId }),
                      session.programId == nil else { continue }
                session.programId = program.id
                dm.updateSessionEvent(session)
                adopted += 1
            }
            out.append("    adopted \(adopted) session\(adopted == 1 ? "" : "s")")
        }

        out.append("")
        out.append("AFTER")
        out.append("  programs: \(dm.programs.count)  ·  private-type: \(dm.programs.filter { $0.programType == .privateSessions }.count)")
        out.append("  standalone sessions remaining: \(dm.sessionEvents.filter { $0.programId == nil }.count)")
        write(out, to: url)
    }

    /// HOOPWISE_ADOPT_FRIDAY=1 — the authorised Phase 2.1 adoption for the
    /// Friday U10 class, in one auditable pass:
    ///   1. delete the duplicate program 酷迅 · U10 (owns no sessions)
    ///   2. enrol the historical attendees who are not already on the roster
    ///   3. re-home the "Training" / "Road to Elite Fridays" sessions onto
    ///      Elite U10 Development
    /// Phase links are NOT set — date-derived phase assignment is 2.4.
    /// Duplicate resolution is NOT run: adoption may create new
    /// same-program/day/time pairs and those join the PENDING merge plan.
    static func adoptFridaySeriesIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_ADOPT_FRIDAY"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/adopt-friday.txt") else { return }

        let targetName = "Elite U10 Development"
        let duplicateName = "酷迅 · U10"
        let seriesTitles = ["Training", "Road to Elite Fridays"]
        var out = ["ADOPT FRIDAY SERIES → \(targetName)", ""]

        guard let target = dm.programs.first(where: { $0.name == targetName }) else {
            out.append("ABORTED — no program named “\(targetName)”. Nothing written.")
            write(out, to: url)
            return
        }

        func seriesSessions() -> [SessionEvent] {
            dm.sessionEvents.filter {
                $0.programId == nil
                    && seriesTitles.contains($0.title.trimmingCharacters(in: .whitespaces))
            }
        }

        out.append("BEFORE")
        out.append("  \(targetName) [\(short(target.id))]: \(dm.sessionEvents.filter { $0.programId == target.id }.count) sessions · \(target.enrolledStudentIds.count) enrolled")
        out.append("  standalone series sessions: \(seriesSessions().count)")
        if let duplicate = dm.programs.first(where: { $0.name == duplicateName }) {
            let owned = dm.sessionEvents.filter { $0.programId == duplicate.id }.count
            out.append("  duplicate \(duplicateName) [\(short(duplicate.id))]: \(owned) sessions")
        }
        out.append("")

        // 1. Delete the duplicate — but never one that owns sessions, since
        // deleteProgram cascades to them.
        if let duplicate = dm.programs.first(where: { $0.name == duplicateName }) {
            let owned = dm.sessionEvents.filter { $0.programId == duplicate.id }
            if owned.isEmpty {
                dm.deleteProgram(duplicate)
                out.append("deleted duplicate program \(duplicateName) [\(short(duplicate.id))]")
            } else {
                out.append("REFUSED to delete \(duplicateName): it owns \(owned.count) sessions")
            }
        }

        // 2. Enrol the historical attendees who are missing, through the ONE
        // enrolment writer (student.programId and program.enrolledStudentIds
        // drift when written separately).
        var historical = Set<UUID>()
        for session in seriesSessions() {
            historical.formUnion(session.attendeeIds)
            historical.formUnion(session.actualAttendeeIds)
        }
        let alreadyEnrolled = Set(dm.programs.first { $0.id == target.id }?.enrolledStudentIds ?? [])
        let toEnrol = historical.subtracting(alreadyEnrolled)
        for studentId in toEnrol {
            dm.setStudentEnrollment(studentId: studentId, programId: target.id)
        }
        let enrolledNames = dm.students.filter { toEnrol.contains($0.id) }.map { student in
            [student.chineseName, student.name].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: "/")
        }
        out.append("enrolled \(toEnrol.count): " + (enrolledNames.isEmpty ? "—" : enrolledNames.joined(separator: ", ")))

        // 3. Adopt. programId only — the phase stays nil for 2.4.
        var adopted = 0
        for session in seriesSessions() {
            var updated = session
            updated.programId = target.id
            dm.updateSessionEvent(updated)
            adopted += 1
        }
        out.append("adopted \(adopted) sessions onto [\(short(target.id))] (programId only; phase left for 2.4)")
        out.append("")

        let after = dm.programs.first { $0.id == target.id }
        out.append("AFTER")
        out.append("  \(targetName): \(dm.sessionEvents.filter { $0.programId == target.id }.count) sessions · \(after?.enrolledStudentIds.count ?? 0) enrolled")
        out.append("  standalone series sessions remaining: \(seriesSessions().count)")
        out.append("  duplicate program present: \(dm.programs.contains { $0.name == duplicateName } ? "YES — FAILED" : "no")")
        write(out, to: url)
    }

    /// HOOPWISE_PROGRAM_PROFILE=1 lists every program with the fields the
    /// adoption slot-tier reads, so a "2 programs share this slot" verdict
    /// can be traced to the two programs in question. Read-only.
    static func programProfileIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_PROGRAM_PROFILE"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/program-profile.txt") else { return }

        var lines = ["PROGRAM PROFILE — read only", ""]
        for program in dm.programs.sorted(by: { $0.name < $1.name }) {
            let days = program.recurringDays.map { $0.displayName.prefix(3) }.joined(separator: ",")
            let clock = program.defaultSessionTime.map { time($0) } ?? "—"
            let sessions = dm.sessionEvents.filter { $0.programId == program.id }.count
            lines.append("\(program.name) [\(short(program.id))]")
            lines.append("   band \(program.ageGroup.rawValue) · type \(program.programType.rawValue) · \(program.status.rawValue)\(program.usesPhases ? " · phased" : " · planless")")
            lines.append("   slot \(days.isEmpty ? "—" : days) \(clock) · \(program.defaultSessionDurationMinutes)min · venue “\(program.locationName ?? "—")”")
            lines.append("   \(sessions) session\(sessions == 1 ? "" : "s") · \(program.enrolledStudentIds.count) enrolled")
            let enrolled = dm.students.filter { program.enrolledStudentIds.contains($0.id) }
            let names = enrolled.map { student in
                [student.chineseName, student.name].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: "/")
            }
            if !names.isEmpty { lines.append("   roster " + names.joined(separator: ", ")) }
            lines.append("")
        }
        write(lines, to: url)
    }

    /// HOOPWISE_SEED_FRIDAY_PROGRAM=1 — the one authorised Phase 2.1 write so
    /// far: create the Friday U10 group at 酷迅 that the "Training" and
    /// "Road to Elite Fridays" series belong to, seeded from those sessions'
    /// historical attendees. Adopts NOTHING; the sessions stay standalone
    /// until the adoption migration runs.
    ///
    /// Idempotent: if a program with this name already exists it reports and
    /// does nothing.
    static func seedFridayProgramIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_SEED_FRIDAY_PROGRAM"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/seed-program.txt") else { return }

        let name = "酷迅 · U10"
        var out = ["SEED PROGRAM — \(name)", ""]

        if let existing = dm.programs.first(where: { $0.name == name }) {
            out.append("already exists [\(short(existing.id))] with \(existing.enrolledStudentIds.count) athletes — nothing written")
            write(out, to: url)
            return
        }

        // Roster from the historical attendees of BOTH series. "Training"
        // has none recorded, so in practice this is Road to Elite's eight.
        let seriesTitles = ["Training", "Road to Elite Fridays"]
        var rosterIds = Set<UUID>()
        var sourceCount = 0
        for session in dm.sessionEvents where session.programId == nil {
            let title = session.title.trimmingCharacters(in: .whitespaces)
            guard seriesTitles.contains(title) else { continue }
            sourceCount += 1
            rosterIds.formUnion(session.attendeeIds)
            rosterIds.formUnion(session.actualAttendeeIds)
        }
        let roster = dm.students.filter { rosterIds.contains($0.id) }

        var components = DateComponents()
        components.year = 2026; components.month = 1; components.day = 1
        components.hour = 18; components.minute = 30
        let sessionTime = Calendar.current.date(from: components) ?? Date()

        let program = Program(
            name: name,
            programType: .group,
            ageGroup: .u10,
            description: nil,
            enrolledStudentIds: roster.map(\.id),
            createdByCoachId: dm.loggedInCoachId ?? dm.coach.id,
            status: .active,
            recurringDays: [.friday],
            defaultSessionTime: sessionTime,
            defaultSessionDurationMinutes: 90,
            locationId: dm.locations.first(where: { $0.name == "酷迅" })?.id,
            locationName: "酷迅",
            usesPhases: false)
        dm.addProgram(program)

        out.append("created [\(short(program.id))]")
        out.append("   band \(program.ageGroup.rawValue) · Fri 18:30 · 90 min · 酷迅 · active · planless")
        out.append("   seeded from \(sourceCount) standalone sessions across \(seriesTitles.joined(separator: " + "))")
        out.append("   roster \(roster.count): " + roster.map { student in
            [student.chineseName, student.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        }.joined(separator: ", "))
        out.append("")
        out.append("no sessions adopted — the adoption migration is a separate, gated step")
        write(out, to: url)
    }

    /// HOOPWISE_SERIES_REPORT=1 profiles the STANDALONE sessions grouped by
    /// title: cadence, time slot, venue, date range, and the historical
    /// roster with each athlete's age band. Read-only. This is what decides
    /// whether two titles are one class renamed or two different classes,
    /// and what age band a program seeded from them should carry.
    static func seriesReportIfRequested(dataManager dm: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_SERIES_REPORT"] != nil,
              let url = WidgetShared.containerURL?
                .appendingPathComponent("Library/Caches/series-report.txt") else { return }

        let calendar = Calendar.current
        let standalone = dm.sessionEvents.filter { $0.programId == nil }
        let byTitle = Dictionary(grouping: standalone) { $0.title }

        var lines = ["STANDALONE SERIES PROFILE — read only", ""]
        for (title, group) in byTitle.sorted(by: { $0.value.count > $1.value.count }) {
            let sorted = group.sorted { $0.date < $1.date }
            let weekdays = Set(sorted.map { calendar.component(.weekday, from: $0.date) })
                .map { weekdayName($0) }.sorted()
            let times = Set(sorted.map { time($0.startTime) }).sorted()
            let venues = Set(sorted.map { $0.location ?? "—" }).sorted()
            let durations = Set(sorted.map { Int($0.endTime.timeIntervalSince($0.startTime) / 60) })

            // Historical roster: everyone ever expected at or present in one.
            var rosterIds = Set<UUID>()
            for session in sorted {
                rosterIds.formUnion(session.attendeeIds)
                rosterIds.formUnion(session.actualAttendeeIds)
            }
            let roster = dm.students.filter { rosterIds.contains($0.id) }

            lines.append("“\(title)” — \(sorted.count) session\(sorted.count == 1 ? "" : "s")")
            lines.append("   dates      \(stamp(sorted.first!.date)) → \(stamp(sorted.last!.date))")
            lines.append("   weekday    \(weekdays.joined(separator: ", "))")
            lines.append("   time       \(times.joined(separator: ", "))  durations \(durations.sorted().map(String.init).joined(separator: "/"))min")
            lines.append("   venue      \(venues.joined(separator: " | "))")
            let rosterNames: [String] = roster.map { student in
                let display = [student.chineseName, student.name]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
                if let band = ageBand(of: student, dm: dm) {
                    return display + " [" + band + "]"
                }
                return display
            }
            let rosterLine = rosterNames.isEmpty
                ? "none recorded"
                : "\(rosterNames.count): " + rosterNames.joined(separator: ", ")
            lines.append("   roster     " + rosterLine)
            lines.append("")
        }

        // Overlap between the two candidate series, which is what tells you
        // whether they are one class renamed.
        let titles = byTitle.keys.sorted()
        if titles.count > 1 {
            lines.append("ROSTER OVERLAP between series:")
            for i in titles.indices {
                for j in titles.indices where j > i {
                    let a = rosterIds(for: titles[i], in: byTitle)
                    let b = rosterIds(for: titles[j], in: byTitle)
                    guard !a.isEmpty || !b.isEmpty else { continue }
                    let shared = a.intersection(b)
                    lines.append("   “\(titles[i])” ∩ “\(titles[j])” = \(shared.count) of \(a.count)/\(b.count)")
                }
            }
        }
        write(lines, to: url)
    }

    private static func rosterIds(for title: String,
                                  in byTitle: [String: [SessionEvent]]) -> Set<UUID> {
        var ids = Set<UUID>()
        for session in byTitle[title] ?? [] {
            ids.formUnion(session.attendeeIds)
            ids.formUnion(session.actualAttendeeIds)
        }
        return ids
    }

    /// An athlete's age band, taken from the programs they belong to (the
    /// app records the band on the program, not the student).
    private static func ageBand(of student: Student, dm: DataManager) -> String? {
        let bands = dm.programs
            .filter { $0.enrolledStudentIds.contains(student.id) }
            .map { $0.ageGroup.rawValue }
        return Set(bands).sorted().joined(separator: "+").isEmpty
            ? nil : Set(bands).sorted().joined(separator: "+")
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return weekday < names.count ? names[weekday] : "?"
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
