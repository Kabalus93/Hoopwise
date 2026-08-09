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
