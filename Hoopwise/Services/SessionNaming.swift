import Foundation

// MARK: - Session names are DERIVED, not stored (Phase 2.3)
//
// A stored title is a snapshot of what a phase was called on the day the
// session was generated. Rename the phase and every existing session keeps
// the old name forever; "Competition & Review · 2" also freezes the language
// the phase was created in, because FEB presets resolve to one locale at
// instantiation. Two sessions describing the same class end up with different
// names depending on which generator made them — which is exactly why merging
// duplicates threatened to rename entries in the coach's calendar.
//
// So the name is computed from the group and the plan, and the stored string
// becomes a LEGACY FALLBACK used only when derivation has nothing to say
// (a session with no program — which after Phase 2.1 is a handful).
//
// Two renderings, because the question differs by surface:
//   · groupFirst — calendar, widget, anywhere the coach is asking "which
//     class is this?"  → the program's display name.
//   · planFirst — inside a program, where the class is a given and the
//     question is "where am I in the plan?"  → "Pre-Season · Session 2 of 6".
enum SessionNaming {

    enum Style { case groupFirst, planFirst }

    /// The name to show. `siblings` are the other sessions in the same phase,
    /// used only for the "of N" count; pass the full session list and it
    /// filters them itself.
    static func name(for session: SessionEvent,
                     programs: [Program],
                     phases: [MicroCycle],
                     allSessions: [SessionEvent],
                     style: Style = .groupFirst) -> String {
        let program = session.programId.flatMap { id in programs.first { $0.id == id } }
        let phase = session.microCycleId.flatMap { id in phases.first { $0.id == id } }

        switch style {
        case .groupFirst:
            guard let program else { return legacyFallback(session) }
            return program.resolvedDisplayName(in: programs)

        case .planFirst:
            guard let phase else {
                // No plan to speak of: fall back to the group, then legacy.
                guard let program else { return legacyFallback(session) }
                return program.resolvedDisplayName(in: programs)
            }
            // A class that did not happen is not a step of the plan: the next
            // one takes its number (its plan moved there — SessionPlanShift).
            let siblings = allSessions
                .filter { $0.microCycleId == phase.id && !SessionLifecycle.didNotHappen($0) }
                .sorted { $0.date < $1.date }
            let position = (siblings.firstIndex { $0.id == session.id }).map { $0 + 1 }
            let isChinese = LocalizationManager.shared.currentLanguage == .chinese
            guard let position else { return phase.title }
            return isChinese
                ? "\(phase.title) · 第 \(position)/\(siblings.count) 次"
                : "\(phase.title) · Session \(position) of \(siblings.count)"
        }
    }

    /// The stored string, used only when nothing can be derived. Strips the
    /// "Private ·" / "Private —" convention, which dies with derived names:
    /// privateness is the program's type now, not a prefix on a string.
    static func legacyFallback(_ session: SessionEvent) -> String {
        let title = session.title.trimmingCharacters(in: .whitespaces)
        for prefix in ["Private · ", "Private — ", "Private - "] where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }
}
