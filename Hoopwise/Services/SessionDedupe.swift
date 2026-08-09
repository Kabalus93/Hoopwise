import Foundation

// MARK: - Duplicate resolution
//
// A duplicate session with a recorded roll call is somebody's attendance
// history, and attendance is money: an unexcused absence consumes a bundle
// session. So this file NEVER blind-deletes. It produces a PLAN — which record
// survives, which are deleted, and exactly what each deletion carries over —
// and refuses to auto-resolve anything it cannot make provably lossless.
//
// Survivor priority, highest first:
//   1. holds a redeemed bundle slot   (deleting it would move a client's balance)
//   2. carries attendance / roll-call data
//   3. carries notes
//   4. the elder record
//
// If more than one candidate carries data of any kind, the plan proposes the
// merge but marks the group MANUAL REVIEW and the apply step skips it. That is
// the deliberate reading of "merge … and report it as a manual-review case
// rather than auto-resolving": the merge is computed so a human can see what
// it would do, and nothing is written until they say so.

/// What a single record actually contains. Used both to pick the survivor and
/// to prove that deleting a record loses nothing.
struct SessionContent: Equatable {
    var attendanceMarks = 0
    var hasAttendancePhoto = false
    var hasNotes = false
    var holdsRedeemedSlot = false
    var gameCount = 0
    var plannedDrillCount = 0
    var hasRating = false
    var hasManOfTheMatch = false
    var developmentFocusCount = 0
    var completedDrillCount = 0

    /// ANY content at all — deliberately broader than the survivor-priority
    /// categories, because "keep the elder" may only ever apply to records
    /// that are genuinely empty.
    var isEmpty: Bool {
        attendanceMarks == 0 && !hasAttendancePhoto && !hasNotes
            && !holdsRedeemedSlot && gameCount == 0 && plannedDrillCount == 0
            && !hasRating && !hasManOfTheMatch
            && developmentFocusCount == 0 && completedDrillCount == 0
    }

    /// Human-readable inventory, for the report.
    var inventory: [String] {
        var items: [String] = []
        if holdsRedeemedSlot { items.append("redeemed bundle slot") }
        if attendanceMarks > 0 { items.append("\(attendanceMarks) attendance mark\(attendanceMarks == 1 ? "" : "s")") }
        if hasAttendancePhoto { items.append("attendance photo") }
        if hasNotes { items.append("notes") }
        if gameCount > 0 { items.append("\(gameCount) game\(gameCount == 1 ? "" : "s")") }
        if plannedDrillCount > 0 { items.append("\(plannedDrillCount) planned drill\(plannedDrillCount == 1 ? "" : "s")") }
        if completedDrillCount > 0 { items.append("\(completedDrillCount) completed drill\(completedDrillCount == 1 ? "" : "s")") }
        if hasRating { items.append("rating") }
        if hasManOfTheMatch { items.append("man of the match") }
        if developmentFocusCount > 0 { items.append("development focus") }
        return items
    }

    static func of(_ session: SessionEvent, redeemedSessionIds: Set<UUID>) -> SessionContent {
        var content = SessionContent()
        content.attendanceMarks = session.actualAttendeeIds.count
            + session.excusedAbsences.count
            + session.unexcusedAbsences.count
        content.hasAttendancePhoto = session.attendancePhotoPath?.isEmpty == false
        // The auto-close marker is machine bookkeeping, not somebody's note.
        // Counting it as content made almost every duplicate look like it
        // carried coach data, because the Phase 0 amnesty stamped the marker
        // into 142 sessions at once.
        let coachWritten = (SessionLifecycle.strippingAutoCloseMarker(session.notes) ?? "")
            + (session.coachNotes ?? "")
        content.hasNotes = !coachWritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        content.holdsRedeemedSlot = redeemedSessionIds.contains(session.id)
        content.gameCount = session.games.count
        content.plannedDrillCount = session.curriculum.totalDrillCount
        content.hasRating = session.rating != nil
        content.hasManOfTheMatch = session.manOfTheMatchId != nil
        content.developmentFocusCount = session.developmentFocus.count
        content.completedDrillCount = session.drillsCompleted.count
        return content
    }
}

/// One duplicate group's resolution.
struct DedupeDecision: Identifiable {
    enum Outcome: String { case automatic, manualReview }

    let id: UUID                    // the survivor's id
    let label: String               // "Advanced Technique · 1 · 2026-05-24"
    let outcome: Outcome
    /// The record that survives, already carrying everything merged in.
    let survivor: SessionEvent
    /// What each record in the group holds, so the report shows why a group
    /// needs review rather than asserting that it does.
    let inventory: [String]
    /// Records the plan would delete.
    let deletedIds: [UUID]
    /// Why this record was chosen.
    let survivorReason: String
    /// What the deletions hand over, per deleted record.
    let carriedOver: [String]
    /// Why a human has to look. Empty for automatic decisions.
    let reviewReasons: [String]
    /// Visible consequences that are deterministic and explainable, so they
    /// do not block the merge — but must appear in the report. Today this is
    /// the title: the survivor keeps its own, so deleting a differently-titled
    /// duplicate renames what the coach sees on the calendar.
    let notices: [String]
}

struct DedupePlan {
    var decisions: [DedupeDecision] = []
    var automatic: [DedupeDecision] { decisions.filter { $0.outcome == .automatic } }
    var manualReview: [DedupeDecision] { decisions.filter { $0.outcome == .manualReview } }
}

enum SessionDedupe {

    /// Builds the plan. Pure — nothing is written.
    static func plan(groups: [[SessionEvent]],
                     redeemedSessionIds: Set<UUID>) -> DedupePlan {
        var plan = DedupePlan()
        for group in groups where group.count > 1 {
            if let decision = decide(group: group, redeemedSessionIds: redeemedSessionIds) {
                plan.decisions.append(decision)
            }
        }
        return plan
    }

    private static func decide(group: [SessionEvent],
                               redeemedSessionIds: Set<UUID>) -> DedupeDecision? {
        guard !group.isEmpty else { return nil }
        let contents = Dictionary(uniqueKeysWithValues:
            group.map { ($0.id, SessionContent.of($0, redeemedSessionIds: redeemedSessionIds)) })
        let carriers = group.filter { !(contents[$0.id]?.isEmpty ?? true) }

        // Survivor: redeemed slot, then attendance, then notes, then elder.
        let survivorSource: SessionEvent
        let survivorReason: String
        if let redeemed = group.first(where: { contents[$0.id]?.holdsRedeemedSlot == true }) {
            survivorSource = redeemed
            survivorReason = "holds a redeemed bundle slot"
        } else if let attended = group
            .filter({ (contents[$0.id]?.attendanceMarks ?? 0) > 0 })
            .max(by: { (contents[$0.id]?.attendanceMarks ?? 0) < (contents[$1.id]?.attendanceMarks ?? 0) }) {
            survivorSource = attended
            survivorReason = "carries roll-call data (\(contents[attended.id]?.attendanceMarks ?? 0) marks)"
        } else if let noted = group.first(where: { contents[$0.id]?.hasNotes == true }) {
            survivorSource = noted
            survivorReason = "carries notes"
        } else {
            survivorSource = elder(of: group)
            survivorReason = "elder record (no data on any duplicate)"
        }

        let others = group.filter { $0.id != survivorSource.id }
        var survivor = survivorSource
        var carried: [String] = []
        var reviewReasons: [String] = []

        for other in others {
            let content = contents[other.id] ?? SessionContent()

            // INVARIANT: a record holding a redeemed slot is never deleted.
            // Phase 0 made deletion refund the slot, so deleting one here
            // would silently change a client's balance.
            if content.holdsRedeemedSlot {
                reviewReasons.append("\(short(other.id)) also holds a redeemed bundle slot — two slots are charged for one session slot")
            }

            let before = survivor
            merge(other, into: &survivor)
            let handed = describeCarryOver(from: other, before: before, after: survivor, content: content)
            if !handed.isEmpty {
                carried.append("\(short(other.id)): \(handed.joined(separator: ", "))")
            }

            // Contradictions a merge cannot resolve honestly.
            for studentId in Set(other.actualAttendeeIds).intersection(before.unexcusedAbsences)
                .union(Set(other.unexcusedAbsences).intersection(before.actualAttendeeIds)) {
                reviewReasons.append("student \(short(studentId)) is marked present on one record and absent on the other")
            }
            if content.hasNotes && (before.notes?.isEmpty == false) && other.notes != before.notes {
                reviewReasons.append("\(short(other.id)) has different notes text")
            }
        }

        if carriers.count > 1 {
            reviewReasons.append("\(carriers.count) of \(group.count) records carry data — merge proposed, not applied")
        }

        var notices: [String] = []
        for other in others where other.title != survivor.title {
            notices.append("calendar rename: “\(other.title)” disappears, “\(survivor.title)” remains")
        }

        let inventory = group.map { member -> String in
            let items = contents[member.id]?.inventory ?? []
            let role = member.id == survivorSource.id ? "survivor" : "delete  "
            return "\(role) \(short(member.id)) holds: \(items.isEmpty ? "nothing" : items.joined(separator: ", "))"
        }

        return DedupeDecision(
            id: survivor.id,
            label: SessionIntegrity.describe(survivor),
            outcome: reviewReasons.isEmpty ? .automatic : .manualReview,
            survivor: survivor,
            inventory: inventory,
            deletedIds: others.map(\.id),
            survivorReason: survivorReason,
            carriedOver: carried,
            reviewReasons: reviewReasons,
            notices: notices)
    }

    /// Union attendance, append notes, and fill any empty field on the
    /// survivor from the record being deleted. Nothing on the survivor is
    /// overwritten — that is what makes the deletion lossless.
    private static func merge(_ other: SessionEvent, into survivor: inout SessionEvent) {
        survivor.actualAttendeeIds = union(survivor.actualAttendeeIds, other.actualAttendeeIds)
        survivor.excusedAbsences = union(survivor.excusedAbsences, other.excusedAbsences)
        survivor.unexcusedAbsences = union(survivor.unexcusedAbsences, other.unexcusedAbsences)
        survivor.attendeeIds = union(survivor.attendeeIds, other.attendeeIds)
        survivor.drillsCompleted = union(survivor.drillsCompleted, other.drillsCompleted)

        survivor.notes = joinText(survivor.notes, other.notes)
        survivor.coachNotes = joinText(survivor.coachNotes, other.coachNotes)

        if survivor.attendancePhotoPath == nil { survivor.attendancePhotoPath = other.attendancePhotoPath }
        if survivor.rating == nil { survivor.rating = other.rating }
        if survivor.manOfTheMatchId == nil { survivor.manOfTheMatchId = other.manOfTheMatchId }
        if survivor.location == nil { survivor.location = other.location }
        if survivor.microCycleId == nil { survivor.microCycleId = other.microCycleId }
        if survivor.createdByCoachId == nil { survivor.createdByCoachId = other.createdByCoachId }
        if survivor.headerImageURL == nil { survivor.headerImageURL = other.headerImageURL }
        if survivor.developmentFocus.isEmpty { survivor.developmentFocus = other.developmentFocus }
        if survivor.games.isEmpty { survivor.games = other.games }
        if survivor.curriculum.totalDrillCount == 0 && other.curriculum.totalDrillCount > 0 {
            survivor.curriculum = other.curriculum
        }
        // The survivor keeps the earliest creation date in the group.
        if other.createdAt < survivor.createdAt { survivor.createdAt = other.createdAt }
    }

    private static func describeCarryOver(from other: SessionEvent,
                                          before: SessionEvent,
                                          after: SessionEvent,
                                          content: SessionContent) -> [String] {
        var handed: [String] = []
        let newMarks = (after.actualAttendeeIds.count + after.excusedAbsences.count + after.unexcusedAbsences.count)
            - (before.actualAttendeeIds.count + before.excusedAbsences.count + before.unexcusedAbsences.count)
        if newMarks > 0 { handed.append("\(newMarks) attendance mark\(newMarks == 1 ? "" : "s")") }
        if before.notes != after.notes { handed.append("notes") }
        if before.coachNotes != after.coachNotes { handed.append("coach notes") }
        if before.attendancePhotoPath == nil && after.attendancePhotoPath != nil { handed.append("attendance photo") }
        if before.rating == nil && after.rating != nil { handed.append("rating") }
        if before.manOfTheMatchId == nil && after.manOfTheMatchId != nil { handed.append("man of the match") }
        if before.games.isEmpty && !after.games.isEmpty { handed.append("\(after.games.count) game\(after.games.count == 1 ? "" : "s")") }
        if before.curriculum.totalDrillCount == 0 && after.curriculum.totalDrillCount > 0 {
            handed.append("\(after.curriculum.totalDrillCount) planned drills")
        }
        if before.microCycleId == nil && after.microCycleId != nil { handed.append("phase link") }
        if handed.isEmpty && content.isEmpty { handed.append("nothing (record was empty)") }
        return handed
    }

    private static func elder(of group: [SessionEvent]) -> SessionEvent {
        group.sorted {
            $0.createdAt == $1.createdAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.createdAt < $1.createdAt
        }[0]
    }

    private static func union(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return (lhs + rhs).filter { seen.insert($0).inserted }
    }

    private static func joinText(_ lhs: String?, _ rhs: String?) -> String? {
        let left = lhs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let right = rhs?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if right.isEmpty { return lhs }
        if left.isEmpty { return rhs }
        if left.contains(right) { return lhs }
        return left + "\n" + right
    }

    private static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)) }

    // MARK: - Report

    static func report(_ plan: DedupePlan) -> String {
        var lines: [String] = []
        lines.append("DEDUPE DRY RUN — nothing was written")
        lines.append("groups: \(plan.decisions.count)   auto-resolvable: \(plan.automatic.count)   manual review: \(plan.manualReview.count)")
        lines.append("")

        for decision in plan.decisions {
            lines.append("[\(decision.outcome == .automatic ? "AUTO" : "REVIEW")] \(decision.label)")
            for line in decision.inventory { lines.append("    \(line)") }
            lines.append("    survivor \(short(decision.id)) — \(decision.survivorReason)")
            lines.append("    delete   \(decision.deletedIds.map(short).joined(separator: ", "))")
            if decision.carriedOver.isEmpty {
                lines.append("    carries  nothing")
            } else {
                for line in decision.carriedOver { lines.append("    carries  \(line)") }
            }
            for notice in decision.notices { lines.append("    ℹ \(notice)") }
            for reason in decision.reviewReasons { lines.append("    ⚠ \(reason)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
