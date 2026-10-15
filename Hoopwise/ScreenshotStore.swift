#if DEBUG
import Foundation

/// App Store screenshot data, isolated from iCloud (DEBUG only).
///
/// HOOPWISE_SCREENSHOT_STORE=1 opens `screenshots.store` in the App Group
/// with CloudKit OFF. On first use it is a byte copy of the synced store;
/// `prune` then deletes everything that is not demo data. The real roster is
/// minors and must never appear in a screenshot, and because the synced store
/// is shared with every device on the account, the pruning must never run on
/// it — hence a separate, unmirrored file.
///
/// Demo data = students WITHOUT a Chinese name (the coach's hand-made samples;
/// every imported real student carries one), the programs those students are
/// enrolled in, and the staff coaches those programs name.
enum ScreenshotStore {
    static var isActive = false

    static var url: URL? {
        guard ProcessInfo.processInfo.environment["HOOPWISE_SCREENSHOT_STORE"] == "1",
              let dir = WidgetShared.containerURL?
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        else { return nil }
        return dir.appendingPathComponent("screenshots.store")
    }

    /// First run: copy the synced store's files. Never overwrites.
    static func seedIfNeeded() {
        guard let url, !FileManager.default.fileExists(atPath: url.path) else { return }
        let dir = url.deletingLastPathComponent()
        for suffix in ["", "-wal", "-shm"] {
            let source = dir.appendingPathComponent("default.store" + suffix)
            let target = dir.appendingPathComponent("screenshots.store" + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.copyItem(at: source, to: target)
            }
        }
    }

    /// Deletes everything that is not demo data. Refuses to run unless the
    /// unmirrored screenshot store is the one open.
    @MainActor
    static func prune(dataManager dm: DataManager) {
        guard isActive else { return }
        let demoStudents = Set(dm.students
            .filter { ($0.chineseName ?? "").isEmpty }
            .map(\.id))
        let demoPrograms = dm.programs.filter { program in
            program.enrolledStudentIds.contains { demoStudents.contains($0) }
        }
        let keptPrograms = Set(demoPrograms.map(\.id))
        let keptCoaches = Set(demoPrograms.compactMap(\.coachId))

        for program in dm.programs where !keptPrograms.contains(program.id) {
            dm.deleteProgram(program)
        }
        for session in dm.sessionEvents where session.programId == nil
            && !session.attendeeIds.contains(where: { demoStudents.contains($0) }) {
            dm.deleteSessionEvent(session)
        }
        for contract in dm.contracts where !demoStudents.contains(contract.studentId) {
            dm.deleteContract(contract)
        }
        for student in dm.students where !demoStudents.contains(student.id) {
            dm.deleteStudent(student)
        }
        for coach in dm.staffCoaches where !keptCoaches.contains(coach.id) {
            dm.deleteStaffCoach(coach)
        }
        stage(dataManager: dm)
        enrich(dataManager: dm)

        // Demo rosters only: a pruned student must not linger as an id.
        for var program in dm.programs {
            let roster = program.enrolledStudentIds.filter { demoStudents.contains($0) }
            if roster != program.enrolledStudentIds {
                program.enrolledStudentIds = roster
                dm.updateProgram(program)
            }
        }
    }

    /// Makes the demo presentable on the day the screenshots are taken:
    /// - shifts each demo program (sessions, phases, schedule days) by whole
    ///   days so one of its classes falls TODAY — the home screen is otherwise
    ///   an empty state on non-class days;
    /// - points the coach's photo at this container (the stored file URL is
    ///   absolute to the device that wrote it).
    /// Idempotent: a program that already has a class today is left alone.
    @MainActor
    private static func stage(dataManager dm: DataManager) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for program in dm.programs {
            let sessions = dm.sessionEvents.filter { $0.programId == program.id }
            guard !sessions.contains(where: { calendar.isDate($0.startTime, inSameDayAs: today) }),
                  let next = sessions.filter({ $0.startTime >= today }).min(by: { $0.startTime < $1.startTime }),
                  let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: next.startTime),
                                                     to: today).day, days != 0
            else { continue }
            func shift(_ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }

            for var session in sessions {
                session.startTime = shift(session.startTime)
                session.endTime = shift(session.endTime)
                session.date = shift(session.date)
                if calendar.isDate(session.startTime, inSameDayAs: today) {
                    // Today's class has not been taken yet.
                    session.status = .scheduled
                    session.actualAttendeeIds = []
                    session.excusedAbsences = []
                    session.unexcusedAbsences = []
                }
                dm.updateSessionEvent(session)
            }
            for var phase in dm.microCycles where phase.programId == program.id {
                phase.startDate = phase.startDate.map(shift)
                phase.endDate = phase.endDate.map(shift)
                dm.updateMicroCycle(phase)
            }
            var moved = program
            moved.startDate = program.startDate.map(shift)
            moved.endDate = program.endDate.map(shift)
            moved.recurringDays = program.recurringDays.compactMap { day in
                let raw = ((day.rawValue - 1 + days) % 7 + 7) % 7 + 1
                return Weekday(rawValue: raw)
            }
            dm.updateProgram(moved)
        }

        enrichCoachPhoto(dataManager: dm)
    }

    /// Demo content for the screenshots, on the unmirrored store only. The
    /// coach's own sample students and program are kept; they get what a
    /// program a few weeks in actually has — named phases, prepaid balances,
    /// attendance history, today's roll call in progress, and two private
    /// clients with payments. Idempotent: it runs once (phase titles still
    /// generic) and every write goes through the app's own writers, so the
    /// balances are deducted by the real redemption rules.
    @MainActor
    private static func enrich(dataManager dm: DataManager) {
        guard let program = dm.programs.first else { return }
        var phases = dm.microCycles.filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
        guard phases.first.map({ $0.title.hasPrefix("Phase") }) == true else { return }

        let words: [(String, String, [String])] = [
            ("Control the Ball, Control Your Body",
             "The foundations for confident play: both hands, balanced stops, pivots, catching and finishing close to the basket.",
             ["Dribble with either hand, eyes up", "Stop with balance on a signal", "Finish close to the basket"]),
            ("Find Space, Make Decisions",
             "Choices against a defender: when to dribble, when to pass, and how to move into space after the ball is gone.",
             ["Protect the ball under pressure", "Pass and move into space", "Read 2-on-1 situations"]),
            ("Play Together, Apply Your Skills",
             "Small-sided games: spacing, moving after a pass, defending an opponent and reacting when possession changes.",
             ["Keep good spacing", "Defend your player", "Transition both ways"])
        ]
        for (index, phase) in phases.enumerated() where index < words.count {
            var named = phase
            named.title = words[index].0
            named.description = words[index].1
            named.objectives = words[index].2
            dm.updateMicroCycle(named)
            phases[index] = named
        }

        let roster = program.enrolledStudentIds
        let now = Date()
        for studentId in roster {
            if var contract = dm.contracts.first(where: { $0.studentId == studentId && $0.kind == .group }) {
                contract.bundleSize = 24
                contract.bundlePurchaseDate = Calendar.current.date(byAdding: .month, value: -1, to: now)
                // Joined before the first class, so "Done" counts the history.
                contract.enrollmentDate = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
                contract.programId = nil
                dm.updateContract(contract)
            }
        }

        // History: every class before today, nearly everyone present.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let sessions = dm.sessionEvents.filter { $0.programId == program.id }
            .sorted { $0.startTime < $1.startTime }
        for (n, session) in sessions.enumerated() where session.startTime < today {
            for (i, studentId) in roster.enumerated() {
                let excused = (n + i) % 7 == 3
                dm.setStudentAttendanceState(sessionId: session.id, studentId: studentId,
                                             state: excused ? .excused : .present)
            }
            if var closed = dm.sessionEvents.first(where: { $0.id == session.id }),
               SessionLifecycle.apply(.complete, to: &closed) {
                dm.updateSessionEvent(closed)
            }
        }
        // Today: roll call in progress — present, excused, and one left in
        // the middle (shown as absent).
        if let todays = sessions.first(where: { calendar.isDate($0.startTime, inSameDayAs: today) }) {
            if roster.count > 0 { dm.setStudentAttendanceState(sessionId: todays.id, studentId: roster[0], state: .present) }
            if roster.count > 1 { dm.setStudentAttendanceState(sessionId: todays.id, studentId: roster[1], state: .excused) }
        }

        // Private clients: the demo students not in the program.
        for student in dm.students where !roster.contains(student.id) {
            let bought = calendar.date(byAdding: .day, value: -6, to: now) ?? now
            let next = (dm.allContracts(for: student.id).map(\.contractNumber).max() ?? 0) + 1
            let bundle = Contract(studentId: student.id, contractNumber: next, kind: .privateBundle,
                                  enrollmentDate: bought, pricePerSession: 300, bundleSize: 10,
                                  bundlePurchaseDate: bought,
                                  payments: [ContractPayment(date: bought, amount: 3000)])
            dm.addContract(bundle)
        }
    }

    @MainActor
    private static func enrichCoachPhoto(dataManager dm: DataManager) {
        var coach = dm.coach
        if let stored = coach.profileImageUrl, let name = URL(string: stored)?.lastPathComponent,
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let local = documents.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: local.path), stored != local.absoluteString {
                coach.profileImageUrl = local.absoluteString
                coach.profileImageData = coach.profileImageData ?? (try? Data(contentsOf: local))
                dm.updateCoach(coach)
            }
        }
    }
}
#endif
