import Foundation

// THE ATHLETE CARD (16 November 2026, Luther: "the student sharable cards …
// finish this once and for all"; decided: ONE collectible card for the child
// and the parents, shared any time and labelled with the month, as one image
// for WeChat AND as A3 print sheets; the back shows what their classes
// trained — the octagon — never a guessed rating).
//
// Pure: every number on the card is a fact the app has. Nothing is invented —
// no height, no handedness, no grade, no "+2" scores. A missing fact leaves
// its place empty or says so.

struct AthleteCardFacts: Equatable {
    let studentId: UUID
    /// The big name (Chinese first in Chinese) and the small one.
    let name: String
    let secondName: String?
    let photo: Data?
    let program: String?
    let ageGroup: String?
    /// Only when one was given.
    let jersey: Int?
    /// The program's colour (else the age category's).
    let accentHex: String
    /// The month on the card (its first day).
    let month: Date

    /// This month: classes where their attendance was TAKEN (present, excused
    /// or absent — AttendanceMath's rule: unmarked is not absent), and how
    /// many of those they were present at.
    let classesAttended: Int
    let classesExpected: Int
    /// This month's games, and every game.
    let gamesThisMonth: Int
    let gamesPlayed: Int
    /// Per game, over every game: points, rebounds, assists, steals, blocks.
    let perGame: [GameStatsReport.Metric: Double]

    /// What the classes they attended worked on (0…1 per axis, scaled to the
    /// top axis); empty when none of them had a plan.
    let trained: [DrillAttribute: Double]
    /// Whose plans `trained` reads: this month's classes, else every class.
    let trainedScope: TrainedScope
    let trainedClasses: Int

    /// A line from the coach, typed when sharing (never stored).
    let coachLine: String
    let coach: String
    let academy: String

    enum TrainedScope: Equatable { case month, allTime, none }

    /// The month containing `date`.
    static func monthRange(containing date: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
        return start...end
    }

    static func make(student: Student, players: [Player], programs: [Program], sessions: [SessionEvent],
                     drills: [DrillItem], categoryHex: String, coach: String, academy: String,
                     coachLine: String = "", now: Date = Date(), calendar: Calendar = .current) -> AthleteCardFacts {
        let month = monthRange(containing: now, calendar: calendar)
        let player = players.first { $0.studentId == student.id }
        let program = student.programId.flatMap { id in programs.first { $0.id == id } }
            ?? programs.first { $0.enrolledStudentIds.contains(student.id) }

        // The classes this athlete belonged to: expected (the session's own
        // roster, else the program's) or marked either way.
        let theirs = sessions.filter { session in
            guard !SessionLifecycle.didNotHappen(session), session.startTime <= now else { return false }
            return AttendanceMath.expectedIds(of: session, programs: programs).contains(student.id)
                || session.actualAttendeeIds.contains(student.id)
                || session.excusedAbsences.contains(student.id)
                || session.unexcusedAbsences.contains(student.id)
        }
        let thisMonth = theirs.filter { month.contains($0.startTime) }
        let markedThisMonth = thisMonth.filter { session in
            session.actualAttendeeIds.contains(student.id) || session.excusedAbsences.contains(student.id)
                || session.unexcusedAbsences.contains(student.id)
        }
        let attendedThisMonth = thisMonth.filter { $0.actualAttendeeIds.contains(student.id) }

        // What their classes trained: the plans of the classes they were AT.
        func coverage(_ classes: [SessionEvent]) -> (values: [DrillAttribute: Double], count: Int) {
            var total: [DrillAttribute: Double] = [:]
            var planned = 0
            for session in classes {
                let minutes = PlanCoverage.minutes(of: session.curriculum, drills: drills)
                guard minutes.values.contains(where: { $0 > 0 }) else { continue }
                planned += 1
                for (axis, value) in minutes { total[axis, default: 0] += value }
            }
            return (PlanCoverage.normalized(total), planned)
        }
        var trained = coverage(attendedThisMonth)
        var scope = TrainedScope.month
        if trained.count == 0 {
            trained = coverage(theirs.filter { $0.actualAttendeeIds.contains(student.id) })
            scope = trained.count == 0 ? .none : .allTime
        }

        let report = GameStatsReport.player(student.id, sessions: sessions)
        let monthGames = GameStatsReport.playerGames(student.id, in: sessions, in: month).count

        return AthleteCardFacts(
            studentId: student.id,
            name: student.primaryDisplayName,
            secondName: student.secondaryNameLine,
            photo: student.profileImageData,
            program: program.map { $0.name.isEmpty ? $0.resolvedDisplayName(in: programs) : $0.name },
            // Not repeated when the program's name already says it ("Elite U8").
            ageGroup: program.flatMap { p in
                let age = p.ageGroup.rawValue
                return p.name.localizedCaseInsensitiveContains(age) ? nil : age
            },
            jersey: player?.jerseyNumber,
            accentHex: program?.colorHex ?? categoryHex,
            month: month.lowerBound,
            classesAttended: attendedThisMonth.count,
            classesExpected: markedThisMonth.count,
            gamesThisMonth: monthGames,
            gamesPlayed: report.games,
            perGame: report.games > 0 ? report.average : [:],
            trained: trained.values,
            trainedScope: scope,
            trainedClasses: trained.count,
            coachLine: coachLine.trimmingCharacters(in: .whitespacesAndNewlines),
            coach: coach,
            academy: academy)
    }
}
