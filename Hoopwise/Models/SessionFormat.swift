import SwiftUI

/// Whether a Student / SessionEvent / Program represents private 1-on-1 (or
/// small private bundle) coaching versus a group/team format. Surfaced via
/// `FormatBadge` on cards, list rows, and detail headers so coaches can tell
/// the two apart at a glance.
enum SessionFormat: String, Codable, Hashable {
    /// Private clients: pay-per-session or private bundles, or a Program of
    /// type `.privateSessions`.
    case privateClient
    /// Group/team formats: group-billed contracts, or Programs of type
    /// `.group`, `.team`, `.clinic`, `.coachWorkshop`.
    case group
    /// School collaboration: company↔school deal. Always group-style on the
    /// court but billed to the school, not students. Surfaced as a distinct
    /// badge/colour so coaches can spot school sessions on the schedule.
    case school

    var shortLabel: String {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .privateClient: return isCN ? "私教" : "Private"
        case .group:         return isCN ? "团课" : "Group"
        case .school:        return isCN ? "校园" : "School"
        }
    }

    /// SF Symbol that reads at a glance (single silhouette = private; two = group; pillared building = school).
    var icon: String {
        switch self {
        case .privateClient: return "person.fill"
        case .group:         return "person.2.fill"
        case .school:        return "building.columns.fill"
        }
    }

    /// Restrained tint — leans on the existing AppTheme palette so it sits
    /// alongside age-group and contract badges without competing.
    var tint: Color {
        switch self {
        case .privateClient: return AppTheme.avatarPurple
        case .group:         return AppTheme.avatarBlue
        case .school:        return AppTheme.avatarTeal
        }
    }

    /// Whether this format is billed to a third party (the school) rather
    /// than the student/parent. School sessions don't deduct from student
    /// contracts because billing flows through the company-school agreement.
    var billedExternally: Bool {
        self == .school
    }
}

// MARK: - Derivation from domain models

extension Contract {
    var format: SessionFormat {
        switch kind {
        case .privatePayPerSession, .privateBundle: return .privateClient
        case .group:                                return .group
        }
    }
}

extension Program {
    var format: SessionFormat {
        switch programType {
        case .privateSessions:                                    return .privateClient
        case .school:                                             return .school
        case .group, .team, .clinic, .coachWorkshop:              return .group
        }
    }
}

extension DataManager {
    /// Format of a single student, derived from program enrolment first
    /// (school overrides everything) then their current contract.
    /// Falls back to `.group` for students with no active contract — most
    /// pre-contract roster additions are group athletes.
    func studentFormat(_ student: Student) -> SessionFormat {
        // School enrolment wins: a kid in a school program is a "school"
        // student even if they also hold a regular group contract.
        let inSchoolProgram = cachedPrograms.contains { program in
            program.programType == .school && program.enrolledStudentIds.contains(student.id)
        }
        if inSchoolProgram { return .school }
        return currentContract(for: student.id)?.format ?? .group
    }

    /// Format of a SessionEvent — derived from the ONE privateness rule
    /// (SessionPrivacy), so the badge can never contradict the money.
    ///
    /// The attendee majority vote this replaced was a second opinion: it
    /// could badge a session "Group" while `eventIsPrivate` charged a private
    /// bundle for it, because the vote read student formats and the money
    /// authority read the session's own contracts.
    func sessionFormat(_ session: SessionEvent) -> SessionFormat {
        SessionPrivacy.format(session, programs: cachedPrograms, contracts: cachedContracts)
    }
}
