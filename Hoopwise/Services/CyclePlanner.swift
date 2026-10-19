import Foundation
import UserNotifications

// MARK: - Cycle planner (October 2026, Luther)
//
// "Generate phases" used to stamp the age group's preset chain from today with
// fixed week counts and ask the coach nothing. The cycle planner asks for the
// DATES (start, and the date the cycle must deliver by — every cycle has one,
// even in a program with no end date), the LEVEL and the EMPHASIS, then:
//
//  1. picks the phase chain: the coach's own templates for the age group, else
//     the federation defaults — from the next age group up at level 4–5, the
//     one below at level 1 (a strong U8 runs the U10 arc);
//  2. stretches it to fit start…target exactly (weeks shared out in proportion,
//     every phase ≥ 1 week; fewer weeks than phases keeps the first ones);
//  3. adds the emphasis to every phase's focus and suggests library activities
//     that match, from the level's age window;
//  4. creates the sessions on the program's weekdays (existing ones in the
//     window are adopted, never duplicated) and a plan for every session that
//     has none, generated IN DATE ORDER so review and new material build up;
//  5. schedules "plan the next cycle" two weeks before the target date — the
//     same moment the attention engine starts showing it.
//
// `plan` is pure (previewed live in the sheet and tested); `apply` writes.

enum CyclePlanner {

    struct Input {
        var program: Program
        var start: Date
        var target: Date
        var level: Int
        var emphasis: [ActivityType]
    }

    struct PlannedPhase: Identifiable, Equatable {
        let id = UUID()
        let template: PhaseTemplate
        let start: Date
        let end: Date
        let weeks: Int
        let focus: [TrainingFocus]
        let sessionCount: Int
        let suggestedActivityIds: [UUID]

        static func == (a: PlannedPhase, b: PlannedPhase) -> Bool {
            a.template == b.template && a.start == b.start && a.end == b.end && a.focus == b.focus
        }
    }

    /// How long before the target the next-cycle reminder starts.
    static let reminderLead: TimeInterval = 14 * 86_400

    // MARK: Plan (pure)

    @MainActor
    static func plan(_ input: Input, templates: [PhaseTemplate]? = nil,
                     calendar cal: Calendar = .current) -> [PlannedPhase] {
        let start = cal.startOfDay(for: input.start)
        let target = cal.startOfDay(for: input.target)
        guard target > start else { return [] }
        let chain = templates ?? self.chain(for: input.program.ageGroup, level: input.level)
        guard !chain.isEmpty else { return [] }

        let days = (cal.dateComponents([.day], from: start, to: target).day ?? 0) + 1
        let totalWeeks = max(1, Int((Double(days) / 7).rounded()))
        let used = Array(chain.prefix(totalWeeks))
        let weeks = shareOut(totalWeeks, weights: used.map { max(1, $0.weeks) })

        let emphasisFocus = input.emphasis.compactMap(trainingFocus)
        let age = DrillPlanGenerator.libraryAge(for: input.program.ageGroup)
        let window = DrillPlanGenerator.ageWeights(age: age, level: input.level)
        var alreadySuggested = Set<UUID>()

        var phases: [PlannedPhase] = []
        var cursor = start
        for (i, template) in used.enumerated() {
            let isLast = i == used.count - 1
            let end = isLast ? target
                : (cal.date(byAdding: .day, value: weeks[i] * 7 - 1, to: cursor) ?? cursor)
            var focus = template.focus
            for f in emphasisFocus where !focus.contains(f) { focus.append(f) }
            let suggestions = suggestedActivities(focus: focus, window: window, excluding: alreadySuggested)
            alreadySuggested.formUnion(suggestions)
            phases.append(PlannedPhase(
                template: template, start: cursor, end: end, weeks: weeks[i], focus: focus,
                sessionCount: sessionDays(from: cursor, to: end, weekdays: input.program.recurringDays, calendar: cal),
                suggestedActivityIds: suggestions))
            cursor = cal.date(byAdding: .day, value: 1, to: end) ?? end
        }
        return phases
    }

    /// The phase chain for an age group at a level. 4–5 work above the age,
    /// 1 below it; the coach's own templates win at every age.
    @MainActor
    static func chain(for group: AgeGroup, level: Int) -> [PhaseTemplate] {
        let order = AgeGroup.allCases
        let i = order.firstIndex(of: group) ?? 0
        let shifted: AgeGroup
        switch level {
        case 4...5: shifted = order[min(order.count - 1, i + 1)]
        case ...1: shifted = order[max(0, i - 1)]
        default: shifted = group
        }
        let chosen = PhaseTemplateStore.shared.defaultPhases(for: shifted)
        return chosen.isEmpty ? PhaseTemplateStore.shared.defaultPhases(for: group) : chosen
    }

    /// Split `total` weeks in proportion to `weights`, each ≥ 1, summing to total.
    static func shareOut(_ total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let sum = Double(weights.reduce(0, +))
        var parts = weights.map { max(1, Int((Double($0) / sum * Double(total)).rounded(.down))) }
        var diff = total - parts.reduce(0, +)
        var k = 0
        while diff != 0 && k < 1000 {
            let j = k % parts.count
            if diff > 0 { parts[j] += 1; diff -= 1 } else if parts[j] > 1 { parts[j] -= 1; diff += 1 }
            k += 1
        }
        return parts
    }

    static func sessionDays(from start: Date, to end: Date, weekdays: [Weekday], calendar cal: Calendar) -> Int {
        let wanted = Set(weekdays.map(\.rawValue))
        guard !wanted.isEmpty else { return 0 }
        var n = 0
        var day = start
        while day <= end {
            if wanted.contains(cal.component(.weekday, from: day)) { n += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return n
    }

    /// Up to eight library activities per phase whose type serves its focus,
    /// from Block 2 first (where one idea is taught), in library order.
    static func suggestedActivities(focus: [TrainingFocus], window: [ActivityAge: Double],
                                    excluding: Set<UUID>) -> [UUID] {
        let types = Set(focus.flatMap(activityTypes))
        let pool = ActivityLibrary.shared.plannable.filter {
            window[$0.age] != nil && types.contains($0.type) && !excluding.contains($0.id)
        }
        let ordered = pool.filter { $0.block == .compete } + pool.filter { $0.block != .compete }
        return Array(ordered.prefix(8).map(\.id))
    }

    static func activityTypes(_ f: TrainingFocus) -> [ActivityType] {
        switch f {
        case .shooting: return [.shooting, .layups]
        case .ballHandling: return [.dribbling, .ballMovement]
        case .passing: return [.passing, .teamPlay]
        case .defense: return [.defence, .oneOnOne]
        case .conditioning, .recovery: return [.warmup]
        case .teamPlay: return [.teamPlay, .games]
        case .gamePrep: return [.games]
        }
    }

    static func trainingFocus(_ t: ActivityType) -> TrainingFocus? {
        switch t {
        case .shooting, .layups: return .shooting
        case .dribbling, .ballMovement, .footwork: return .ballHandling
        case .passing: return .passing
        case .defence, .oneOnOne, .rebounding: return .defense
        case .teamPlay, .post, .guards: return .teamPlay
        case .games: return .gamePrep
        case .warmup: return .conditioning
        case .rules: return nil
        }
    }

    /// Types a coach can choose as emphasis.
    static let emphasisChoices: [ActivityType] = [
        .dribbling, .passing, .layups, .shooting, .footwork, .defence, .rebounding, .teamPlay]

    /// The emphasis the data suggests: the weakest evaluated area, and passing
    /// when game stats show few assists.
    static func suggestedEmphasis(students: [Student], players: [Player], games: [SessionGame]) -> [ActivityType] {
        DrillPlanGenerator.dataFocus(students: students, players: players, games: games)
            .filter { emphasisChoices.contains($0) }
    }

    // MARK: Apply (writes)

    struct Result {
        var phases = 0
        var sessionsCreated = 0
        var sessionsPlanned = 0
    }

    @MainActor
    @discardableResult
    static func apply(_ planned: [PlannedPhase], input: Input, dataManager dm: SwiftDataManager) -> Result {
        var result = Result()
        var program = input.program
        if program.skillTargets?.level != input.level {
            var targets = program.skillTargets ?? ProgramSkillTargets()
            targets.level = input.level
            program.skillTargets = targets
            program.updatedAt = Date()
            dm.updateProgram(program)
        }

        let firstNumber = (dm.microCycles.filter { $0.programId == program.id }.map(\.phaseNumber).max() ?? 0) + 1
        for (i, p) in planned.enumerated() {
            var phase = p.template.instantiate(programId: program.id, phaseNumber: firstNumber + i,
                                               startingOn: p.start, suggestedDrillIds: p.suggestedActivityIds)
            phase.durationWeeks = p.weeks
            phase.endDate = p.end
            phase.focus = p.focus
            dm.addMicroCycle(phase)
            result.sessionsCreated += dm.materializeSessions(for: phase)
            result.phases += 1
        }

        // Plans, in date order, for sessions in the cycle that have none.
        let players = dm.students.compactMap { dm.player(for: $0.id) }
        let enrolled = dm.students.filter { program.enrolledStudentIds.contains($0.id) }
        var history = dm.sessionEvents.filter { $0.programId == program.id }
        let cycleStart = Calendar.current.startOfDay(for: input.start)
        let cycleEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: input.target)) ?? input.target
        let toPlan = history
            .filter { $0.startTime >= cycleStart && $0.startTime < cycleEnd
                && $0.curriculum.totalDrillCount == 0 && !SessionLifecycle.didNotHappen($0) }
            .sorted { $0.startTime < $1.startTime }
        let phases = dm.microCycles
        for var session in toPlan {
            let phase = session.microCycleId.flatMap { id in phases.first { $0.id == id } }
            let ctx = DrillPlanGenerator.Context(session: session, program: program, phase: phase,
                                                 enrolledStudents: enrolled, players: players,
                                                 allDrills: dm.drills, programHistory: history)
            session.curriculum = DrillPlanGenerator.generatePlan(in: ctx).curriculum
            dm.updateSessionEvent(session)
            if let i = history.firstIndex(where: { $0.id == session.id }) { history[i] = session }
            result.sessionsPlanned += 1
        }

        scheduleNextCycleReminder(program: program, target: input.target)
        return result
    }

    static func reminderId(_ programId: UUID) -> String { "next-cycle-\(programId.uuidString)" }

    /// One reminder per program, replaced whenever a cycle is planned.
    static func scheduleNextCycleReminder(program: Program, target: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderId(program.id)])
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .second, value: -Int(reminderLead), to: cal.startOfDay(for: target)),
              let fire = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > Date() else { return }
        let zh = LocalizationManager.shared.currentLanguage == .chinese
        let content = UNMutableNotificationContent()
        content.title = zh ? "规划下一周期" : "Plan the next cycle"
        content.body = zh ? "\(program.name) 当前周期两周后结束。" : "\(program.name)'s cycle ends in two weeks."
        content.sound = .default
        content.userInfo = ["programId": program.id.uuidString]
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: reminderId(program.id), content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// The day after a program's last phase ends — where a next cycle starts.
    @MainActor
    static func nextCycleStart(programId: UUID, phases: [MicroCycle]) -> Date? {
        let ends = phases.filter { $0.programId == programId }.compactMap(\.endDate)
        guard let last = ends.max() else { return nil }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: last))
    }
}
