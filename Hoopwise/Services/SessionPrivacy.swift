import Foundation

// MARK: - Is this session private? — ONE definition
//
// The survey found four independent answers to this question, three of them
// keyed on `programId == nil`, and they disagreed: a session could be badged
// "Group" by the format vote while the money authority charged a private
// bundle for it. The Hub's copy even claimed in a comment to mirror the money
// authority while omitting its contract check, so every orphan group session
// — including every legacy orphan recurring series — read as private there.
//
// This is now the only implementation. Everything else calls it.
//
// The TARGET rule (Phase 2) is simply: private iff the session's program is
// of type `.privateSessions`. Until Phase 2 gives every session a program,
// program-less sessions fall back to the STRICTEST of the old rules — the
// money authority's, contract check included — because that is the one that
// decides whether a client is charged.
enum SessionPrivacy {

    static func isPrivate(_ session: SessionEvent,
                          programs: [Program],
                          contracts: [Contract]) -> Bool {
        if let programId = session.programId {
            // A named program answers the question outright. A DANGLING
            // programId is not private: it names a group program that no
            // longer exists, and inventing privateness would invent a charge.
            return programs.first { $0.id == programId }?.programType == .privateSessions
        }

        // Interim rule for program-less sessions: an attendee must actually
        // hold an active private contract.
        let roster = Set(session.attendeeIds).union(session.actualAttendeeIds)
        guard !roster.isEmpty else { return false }
        return contracts.contains { contract in
            roster.contains(contract.studentId)
                && contract.status == .active
                && (contract.kind == .privateBundle || contract.kind == .privatePayPerSession)
        }
    }

    /// The badge layer, derived from the same answer. The old attendee
    /// majority vote — private wins ties, school wins outright — is gone: it
    /// was a second opinion that could contradict the money authority.
    static func format(_ session: SessionEvent,
                       programs: [Program],
                       contracts: [Contract]) -> SessionFormat {
        if let programId = session.programId,
           let program = programs.first(where: { $0.id == programId }) {
            return program.format
        }
        return isPrivate(session, programs: programs, contracts: contracts) ? .privateClient : .group
    }
}
