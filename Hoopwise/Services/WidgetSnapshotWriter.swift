import Foundation
#if os(iOS)
import WidgetKit
#endif

// MARK: - Snapshot writer for the "Next Up" widget
//
// The app-side half: builds the compact snapshot from the shared caches and
// writes it to the App Group whenever relevant data changes (hooked into the
// data manager's refresh paths) — the widget itself is a dumb renderer.
// Compiled into both apps; inert on the Mac, whose target has no App Group.

@MainActor
enum WidgetSnapshotWriter {
    private static var pendingWrite: Task<Void, Never>?

    /// Debounced: refresh storms (bulk edits, roll call) collapse to one
    /// write, and the widget reloads once.
    static func scheduleWrite(dataManager: DataManager) {
        #if os(iOS)
        pendingWrite?.cancel()
        pendingWrite = Task { @MainActor [weak dataManager] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let dataManager else { return }
            writeNow(dataManager: dataManager)
        }
        #endif
    }

    #if os(iOS)
    static func writeNow(dataManager: DataManager) {
        let now = Date()
        let horizon = now.addingTimeInterval(48 * 3600)
        let calendar = Calendar.current

        let upcoming = dataManager.sessionEvents
            .filter { session in
                session.status != .cancelled
                    && session.endTime > now && session.startTime < horizon
            }
            .sorted { $0.startTime < $1.startTime }
            .prefix(8)
            .map { session in
                NextUpSession(id: session.id, title: session.title,
                              start: session.startTime, end: session.endTime,
                              location: session.location)
            }

        let snapshot = NextUpSnapshot(
            generatedAt: now,
            sessions: Array(upcoming),
            highlight: selectHighlight(dataManager: dataManager,
                                       nextSession: upcoming.first, calendar: calendar))
        WidgetShared.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.widgetKind)
    }

    // MARK: Student selection — deterministic, priority order.

    private static func selectHighlight(dataManager: DataManager,
                                        nextSession: NextUpSession?,
                                        calendar: Calendar) -> NextUpStudent? {
        let students = dataManager.students
        guard !students.isEmpty else { return nil }
        let roster: Set<UUID> = nextSession.flatMap { next in
            dataManager.sessionEvents.first { $0.id == next.id }
                .map { Set($0.attendeeIds) }
        } ?? []

        // Ties prefer a student in the next session's roster.
        func best(_ candidates: [(Student, Date?)]) -> Student? {
            guard !candidates.isEmpty else { return nil }
            let sorted = candidates.sorted { lhs, rhs in
                let lhsRoster = roster.contains(lhs.0.id), rhsRoster = roster.contains(rhs.0.id)
                if lhsRoster != rhsRoster { return lhsRoster }
                return (lhs.1 ?? .distantPast) > (rhs.1 ?? .distantPast)
            }
            return sorted.first?.0
        }

        // 1. Noted — most recent note within the window.
        let notedCutoff = calendar.date(byAdding: .day, value: -AttentionRules.notedWindowDays,
                                        to: Date()) ?? Date()
        let noted = students.compactMap { student -> (Student, Date?)? in
            guard let latest = student.parentalTouchpoints.map(\.date).max(),
                  latest >= notedCutoff else { return nil }
            return (student, latest)
        }
        if let pick = best(noted) {
            return makeStudent(pick, reason: .noted)
        }

        // 2. Needs attention — bundle low or attendance drop, shared rules.
        var attention: [(Student, Date?)] = []
        for contract in dataManager.cachedContracts
        where contract.kind == .privateBundle && contract.status == .active
            && (contract.bundleRedemptionsRemaining ?? .max) <= AttentionRules.bundleLowRemaining {
            if let student = students.first(where: { $0.id == contract.studentId }) {
                attention.append((student, nil))
            }
        }
        for student in students {
            let rate = attendanceRate(of: student, dataManager: dataManager)
            if rate.of >= AttentionRules.attendanceMinSessions,
               rate.percent < AttentionRules.attendanceRiskPercent {
                attention.append((student, nil))
            }
        }
        if let pick = best(attention) {
            return makeStudent(pick, reason: .attention)
        }

        // 3. Top attender — the positive fallback.
        let top = students
            .map { ($0, attendanceRate(of: $0, dataManager: dataManager)) }
            .filter { $0.1.of >= AttentionRules.attendanceMinSessions }
            .sorted { lhs, rhs in
                let lhsRoster = roster.contains(lhs.0.id), rhsRoster = roster.contains(rhs.0.id)
                if lhs.1.percent != rhs.1.percent { return lhs.1.percent > rhs.1.percent }
                if lhsRoster != rhsRoster { return lhsRoster }
                return lhs.0.name < rhs.0.name
            }
            .first?.0
        return top.map { makeStudent($0, reason: .streak) }
    }

    private static func attendanceRate(of student: Student,
                                       dataManager: DataManager) -> (percent: Int, of: Int) {
        let relevant = dataManager.sessionEvents.filter {
            $0.date <= Date()
                && ($0.attendeeIds.contains(student.id)
                    || $0.actualAttendeeIds.contains(student.id))
        }
        guard !relevant.isEmpty else { return (100, 0) }
        let attended = relevant.filter { $0.actualAttendeeIds.contains(student.id) }.count
        return (Int(Double(attended) / Double(relevant.count) * 100), relevant.count)
    }

    private static func makeStudent(_ student: Student,
                                    reason: NextUpStudent.Reason) -> NextUpStudent {
        var avatar = student.thumbnailImageData
        if avatar == nil, let full = student.profileImageData {
            avatar = makeProfileThumbnailData(from: full, maxDimension: 120)
        }
        // The snapshot must stay tiny — skip any oversized blob.
        if let data = avatar, data.count > 200_000 { avatar = nil }
        return NextUpStudent(id: student.id,
                             name: student.name,
                             chineseName: student.chineseName,
                             initials: student.initials,
                             reason: reason,
                             avatarJPEG: avatar)
    }
    #endif
}
