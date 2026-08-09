#if DEBUG
import Foundation

/// Headless evidence hooks for AttentionRules v2 — device verification via
/// `devicectl device process launch -e`, results pulled from the App Group's
/// Library/Caches (the established no-root channel).
///
/// HOOPWISE_ATTENTION_REPORT=1   before/after bucket counts + attendance
///                               invariance across the amnesty migration.
/// HOOPWISE_ATTENTION_SELFTEST=1 scratch-data checks: auto-close → ledger →
///                               recovery item → aged out at +49h; re-engage
///                               fires once (edge, not level). All scratch
///                               records are deleted and edge state restored.
@MainActor
enum AttentionDebugReport {

    static func runIfRequested(dataManager: DataManager) {
        let env = ProcessInfo.processInfo.environment
        var lines: [String] = []
        if env["HOOPWISE_ATTENTION_REPORT"] != nil {
            lines += report(dataManager: dataManager)
        }
        if env["HOOPWISE_ATTENTION_SELFTEST"] != nil {
            lines += selftest(dataManager: dataManager)
        }
        guard !lines.isEmpty else { return }
        guard let url = WidgetShared.containerURL?
            .appendingPathComponent("Library/Caches/attention-report.txt") else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: url, options: .atomic)
    }

    // MARK: - Before/after report

    private static func report(dataManager dm: DataManager) -> [String] {
        let now = Date()
        var out = ["==== ATTENTION REPORT @ \(stamp(now))"]

        // ---- V1 buckets, computed with the RETIRED predicates so the
        // "before" is exactly what the old card would have shown.
        let cal = Calendar.current
        let closeOutSessions = dm.sessionEvents.filter {
            $0.endTime < now && ($0.status == .scheduled || $0.status == .inProgress)
        }.count
        let overdue = dm.overdueReminders.count
        let bundleLow = dm.students.filter {
            guard let c = dm.currentContract(for: $0.id), c.kind == .privateBundle else { return false }
            return (c.bundleRedemptionsRemaining ?? .max) <= 3
        }.count
        var lastAttendance: [UUID: Date] = [:]
        for s in dm.sessionEvents where s.status == .completed || s.endTime < now {
            for id in s.actualAttendeeIds where (lastAttendance[id] ?? .distantPast) < s.endTime {
                lastAttendance[id] = s.endTime
            }
        }
        let dormantCutoff = cal.date(byAdding: .day, value: -14, to: now)!
        let dormant = dm.students.filter { student in
            guard let c = dm.currentContract(for: student.id), c.format == .privateClient else { return false }
            if let last = lastAttendance[student.id], last >= dormantCutoff { return false }
            let hasAnyPast = lastAttendance[student.id] != nil
            if !hasAnyPast && student.createdAt >= dormantCutoff { return false }
            return true
        }.count
        let twoWeeks = cal.date(byAdding: .day, value: 14, to: now)!
        let unplanned14d = dm.sessionEvents.filter {
            $0.date >= now && $0.date <= twoWeeks && $0.status == .scheduled
                && $0.curriculum.totalDrillCount == 0
        }.count
        let phaseless = dm.programs.filter { program in
            (program.status == .active || program.status == .draft)
                && dm.microCycles.first(where: { $0.programId == program.id }) == nil
                && (dm.sessionEvents.contains { $0.programId == program.id && $0.date >= now && $0.date <= twoWeeks }
                    || (program.startDate ?? .distantFuture) <= twoWeeks)
        }.count
        let upcoming = dm.upcomingReminders.count
        let v1Total = closeOutSessions + overdue + bundleLow + dormant + unplanned14d + phaseless + upcoming
        out.append("V1 buckets: closeOutSessions=\(closeOutSessions) overdueReminders=\(overdue) bundleLow=\(bundleLow) dormant=\(dormant) unplanned14d=\(unplanned14d) phaselessPrograms=\(phaseless) upcomingReminders=\(upcoming) TOTAL=\(v1Total)")

        // ---- Attendance invariance across the amnesty: three athletes with
        // real history, marked-only math, before vs after the migration.
        let sampled = dm.students
            .map { ($0, AttendanceMath.rate(for: $0.id, in: dm.sessionEvents, asOf: now)) }
            .filter { $0.1.of > 0 }
            .sorted { $0.0.name < $1.0.name }
            .prefix(3)
        for (student, rate) in sampled {
            out.append("attendance BEFORE amnesty: \(student.name) = \(rate.percent)% of \(rate.of) marked")
        }

        // ---- The amnesty migration (idempotent; force bypasses throttle).
        let result = AttentionEngine.runAutomation(dataManager: dm, now: now, force: true)
        out.append("amnesty: auto-closed \(result.closedNow) sessions (\(result.amnestyClosed) older than the recovery window, \(result.closedNow - result.amnestyClosed) become roll-call recovery)")

        for (student, before) in sampled {
            let after = AttendanceMath.rate(for: student.id, in: dm.sessionEvents, asOf: now)
            let ok = after == before ? "UNCHANGED" : "CHANGED(!)"
            out.append("attendance AFTER amnesty: \(student.name) = \(after.percent)% of \(after.of) marked → \(ok)")
        }

        // ---- V2 list.
        let items = AttentionEngine.items(dataManager: dm, now: now)
        let byCategory = Dictionary(grouping: items, by: \.category)
        out.append("V2 buckets: closeOut=\(byCategory[.closeOut]?.count ?? 0) reEngage=\(byCategory[.reEngage]?.count ?? 0) plan=\(byCategory[.plan]?.count ?? 0) TOTAL=\(items.count)")
        for item in items {
            out.append("  item [\(item.kind.rawValue)] \(item.title) — \(item.subtitle) (deadline \(stamp(item.deadline)))")
        }
        out.append("V1 → V2: \(v1Total) → \(items.count)")
        return out
    }

    // MARK: - Selftest (scratch data, cleaned up, state restored)

    private static func selftest(dataManager dm: DataManager) -> [String] {
        let now = Date()
        var out = ["==== ATTENTION SELFTEST @ \(stamp(now))"]
        func check(_ name: String, _ pass: Bool) { out.append("  \(pass ? "PASS" : "FAIL") \(name)") }

        // -- Auto-close → ledger → recovery → aged out.
        let scratch = SessionEvent(
            sessionType: .training, title: "ZZZ Attention Selftest",
            date: now.addingTimeInterval(-20 * 3600),
            startTime: now.addingTimeInterval(-21 * 3600),
            endTime: now.addingTimeInterval(-20 * 3600))
        dm.addSessionEvent(scratch)
        AttentionEngine.runAutomation(dataManager: dm, now: now, force: true)
        let closed = dm.sessionEvents.first { $0.id == scratch.id }
        check("auto-closes on run", closed?.status == .completed)
        check("carries auto-close marker", closed.map { SessionLifecycle.wasAutoClosed($0) } ?? false)
        check("appears in ledger",
              AttentionEngine.ledger(dataManager: dm, now: now).contains { $0.sessionId == scratch.id })
        let itemsNow = AttentionEngine.items(dataManager: dm, now: now)
        check("roll-call recovery item present",
              itemsNow.contains { $0.key == "recovery:\(scratch.id)" })

        // Future-dated checks fire edges with a future clock — snapshot the
        // edge state and restore it so real athletes' cooldowns stay real.
        let savedState = AttentionEngine.loadState()
        let later = now.addingTimeInterval(49 * 3600)
        let itemsLater = AttentionEngine.items(dataManager: dm, now: later)
        check("recovery item gone at +49h",
              !itemsLater.contains { $0.key == "recovery:\(scratch.id)" })
        AttentionEngine.saveState(savedState)

        // -- Re-engage: edge, not level.
        var student = Student(name: "ZZZ Selftest Athlete")
        student.createdAt = now.addingTimeInterval(-30 * 24 * 3600)   // not "new"
        dm.addStudent(student)
        var absSessions: [SessionEvent] = []
        for day in 1...3 {
            var s = SessionEvent(
                sessionType: .training, title: "ZZZ Selftest Miss \(day)",
                date: now.addingTimeInterval(TimeInterval(-day * 24 * 3600)),
                startTime: now.addingTimeInterval(TimeInterval(-day * 24 * 3600)),
                endTime: now.addingTimeInterval(TimeInterval(-day * 24 * 3600) + 3600))
            s.status = .completed
            s.unexcusedAbsences = [student.id]
            dm.addSessionEvent(s)
            absSessions.append(s)
        }
        let misses = AttendanceMath.consecutiveMisses(for: student.id, in: dm.sessionEvents, asOf: now)
        check("threshold crossed (3 consecutive misses)", misses >= 3)
        let first = AttentionEngine.items(dataManager: dm, now: now)
            .filter { $0.kind == .reengage && $0.studentId == student.id }
        let second = AttentionEngine.items(dataManager: dm, now: now)
            .filter { $0.kind == .reengage && $0.studentId == student.id }
        check("fires exactly once", first.count == 1)
        check("re-run still exactly one (edge, not level)", second.count == 1 && second.first?.key == first.first?.key)

        // -- Cleanup: scratch records out, edge state scrubbed of scratch.
        if let closed { dm.deleteSessionEvent(closed) }
        for s in absSessions { dm.deleteSessionEvent(s) }
        dm.deleteStudent(student)
        var state = AttentionEngine.loadState()
        state.reengageLastFired.removeValue(forKey: student.id)
        state.snoozedUntil = state.snoozedUntil.filter { !$0.key.contains(student.id.uuidString) }
        state.dismissed = state.dismissed.filter { !$0.contains(student.id.uuidString) }
        AttentionEngine.saveState(state)
        out.append("  cleanup done (scratch session + athlete removed, edge state restored)")
        return out
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
#endif
