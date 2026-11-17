import Foundation
import CoreGraphics
import ImageIO

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
    /// The program's age group ("U8"), for the card's diamond.
    let ageBadge: String?
    /// Only when one was given.
    let jersey: Int?
    /// School grade as the app shows it (age and height are not on the card
    /// — Luther, 17 Nov 2026).
    let schoolGrade: String?
    /// The colour behind the child in their profile photo (its corners — the
    /// background-removal swatch, or whatever was behind them): the header's
    /// gradient runs out to it. nil without a photo.
    let photoBackgroundHex: String?
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
            ageBadge: program?.ageGroup.rawValue,
            jersey: player?.jerseyNumber,
            schoolGrade: student.currentSchoolGrade(asOf: now)?.rawValue,
            photoBackgroundHex: student.profileImageData.flatMap(Self.backgroundHex(ofPhoto:)),
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

    /// The average colour of a photo's four corners ("#RRGGBB"), read from a
    /// 32-pixel thumbnail.
    static func backgroundHex(ofPhoto data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let w = image.width, h = image.height
        guard w >= 8, h >= 8 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = 0, g = 0, b = 0, n = 0
        let patch = 3
        for (x0, y0) in [(0, 0), (w - patch, 0), (0, h - patch), (w - patch, h - patch)] {
            for y in y0..<(y0 + patch) {
                for x in x0..<(x0 + patch) {
                    let i = (y * w + x) * 4
                    guard pixels[i + 3] > 0 else { continue }
                    r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2]); n += 1
                }
            }
        }
        guard n > 0 else { return nil }
        return String(format: "#%02X%02X%02X", r / n, g / n, b / n)
    }

    /// Relative luminance (0 black … 1 white) of "#RRGGBB"; 0 when unreadable.
    static func luminance(ofHex hex: String) -> Double {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return 0 }
        func channel(_ shift: UInt32) -> Double {
            let c = Double((value >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
