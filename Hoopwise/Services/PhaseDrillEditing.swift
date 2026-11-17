import Foundation

// CHANGING A PHASE'S PLANS IN ONE GO (18 Nov 2026, Luther: "when editing a
// phase, I want to be able to remove planned drills from all sessions or some
// within the phase, add a recurring exercise to all or a select number of
// sessions"). Pure: which sessions may change, what the phase's plans use, and
// a curriculum with a drill taken out or put in. The sheet writes the result
// through updateSessionEvent (keepLiveFields).
//
// ONLY UPCOMING SESSIONS CHANGE — scheduled, not yet started, not skipped or
// cancelled. A class that ran (or is running, or did not happen) keeps its
// plan as the record, the same rule ProgramSessionSync follows.

enum PhaseDrillEditing {
    enum Block: String, CaseIterable, Identifiable {
        case warmup, skills
        var id: String { rawValue }
    }

    /// What the phase's plans use: one drill, the sessions it is in.
    struct Usage: Equatable, Identifiable {
        let drillId: UUID
        let sessionIds: [UUID]
        var id: UUID { drillId }
    }

    /// The phase's sessions a bulk edit may change, soonest first.
    static func editableSessions(_ sessions: [SessionEvent], phaseId: UUID, now: Date = Date()) -> [SessionEvent] {
        sessions
            .filter { $0.microCycleId == phaseId }
            .filter { $0.status == .scheduled && !SessionLifecycle.didNotHappen($0) && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Every drill the sessions' plans hold (warm-up and skills), the most
    /// used first, then in the order they first appear.
    static func usage(in sessions: [SessionEvent]) -> [Usage] {
        var order: [UUID] = []
        var where_: [UUID: [UUID]] = [:]
        for session in sessions {
            let ids = session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds
            for id in ids {
                if where_[id] == nil { order.append(id) }
                if !(where_[id]?.contains(session.id) ?? false) { where_[id, default: []].append(session.id) }
            }
        }
        return order.enumerated()
            .sorted { a, b in
                let ca = where_[a.element]?.count ?? 0, cb = where_[b.element]?.count ?? 0
                return ca != cb ? ca > cb : a.offset < b.offset
            }
            .map { Usage(drillId: $0.element, sessionIds: where_[$0.element] ?? []) }
    }

    /// The plan without `drillId`, from both blocks.
    static func removing(_ drillId: UUID, from curriculum: SessionCurriculum) -> SessionCurriculum {
        var c = curriculum
        c.warmupDrillIds.removeAll { $0 == drillId }
        c.skillDrillIds.removeAll { $0 == drillId }
        return c
    }

    /// The plan with `drillId` at the end of `block` — unchanged when the
    /// drill is already in the plan (either block), so a recurring drill is
    /// never doubled.
    static func adding(_ drillId: UUID, to curriculum: SessionCurriculum, block: Block) -> SessionCurriculum {
        guard !curriculum.warmupDrillIds.contains(drillId), !curriculum.skillDrillIds.contains(drillId) else {
            return curriculum
        }
        var c = curriculum
        switch block {
        case .warmup: c.warmupDrillIds.append(drillId)
        case .skills: c.skillDrillIds.append(drillId)
        }
        return c
    }
}
