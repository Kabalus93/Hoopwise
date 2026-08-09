import Foundation

// MARK: - Adopting the standalone sessions (Phase 2.1) — PLAN ONLY
//
// `programId == nil` is doing four jobs today: standalone, private, legacy
// orphan recurring series, and "no Live Activity". Phase 2 gives every session
// a program so those meanings can be separated. This file decides WHERE each
// standalone session should land, and writes nothing.
//
// Three destinations, in order of confidence:
//   1. FINGERPRINT — an existing program already owns sessions with the same
//      shape (title, location, weekday, time-of-day, duration). Confident only
//      when exactly ONE program matches; two candidates means a human decides.
//   2. PRIVATE MICRO-GROUP — the session is private by the ONE rule
//      (SessionPrivacy) and has exactly one identifiable client, so it joins
//      that client's one-person `.privateSessions` program.
//   3. UNASSIGNED — everything else, visibly, in a program the coach can see
//      and triage. Never silent, never guessed.
enum SessionAdoption {

    enum Destination: Equatable {
        case fingerprint(programId: UUID, programName: String, tier: String)
        case privateMicroGroup(studentId: UUID, studentName: String)
        case unassigned(reason: String)

        var bucket: String {
            switch self {
            case .fingerprint: return "fingerprint"
            case .privateMicroGroup: return "private micro-group"
            case .unassigned: return "unassigned"
            }
        }
    }

    struct Decision: Identifiable {
        let id: UUID
        let label: String
        let destination: Destination
    }

    struct Plan {
        var decisions: [Decision] = []

        var fingerprintCount: Int { decisions.filter { $0.destination.bucket == "fingerprint" }.count }
        var privateCount: Int { decisions.filter { $0.destination.bucket == "private micro-group" }.count }
        var unassignedCount: Int { decisions.filter { $0.destination.bucket == "unassigned" }.count }

        /// programName → how many sessions it would absorb.
        var programAbsorption: [String: Int] {
            var counts: [String: Int] = [:]
            for decision in decisions {
                if case .fingerprint(_, let name, _) = decision.destination {
                    counts[name, default: 0] += 1
                }
            }
            return counts
        }

        /// One micro-group is created per distinct client.
        var microGroupClients: [String: Int] {
            var counts: [String: Int] = [:]
            for decision in decisions {
                if case .privateMicroGroup(_, let name) = decision.destination {
                    counts[name, default: 0] += 1
                }
            }
            return counts
        }

        var unassignedReasons: [String: Int] {
            var counts: [String: Int] = [:]
            for decision in decisions {
                if case .unassigned(let reason) = decision.destination {
                    counts[reason, default: 0] += 1
                }
            }
            return counts
        }
    }

    /// The structural fingerprint: what makes two sessions "the same slot".
    private struct Shape: Hashable {
        let title: String
        let location: String
        let weekday: Int
        let minuteOfDay: Int
        let durationMinutes: Int
    }

    private static func shape(of session: SessionEvent, calendar: Calendar) -> Shape {
        let components = calendar.dateComponents([.hour, .minute], from: session.startTime)
        return Shape(title: session.title,
                     location: session.location ?? "",
                     weekday: calendar.component(.weekday, from: session.date),
                     minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0),
                     durationMinutes: Int(session.endTime.timeIntervalSince(session.startTime) / 60))
    }

    /// Does this session sit in the program's declared weekly slot? All four
    /// of weekday, start time, duration and venue must agree — three out of
    /// four is a different class at the same gym.
    private static func matchesSchedule(_ session: SessionEvent,
                                        of program: Program,
                                        calendar: Calendar) -> Bool {
        guard let programTime = program.defaultSessionTime else { return false }
        let weekday = calendar.component(.weekday, from: session.date)
        // Weekday.rawValue is already Calendar's numbering (1 = Sunday).
        guard program.recurringDays.contains(where: { $0.rawValue == weekday }) else { return false }

        let sessionClock = calendar.dateComponents([.hour, .minute], from: session.startTime)
        let programClock = calendar.dateComponents([.hour, .minute], from: programTime)
        guard sessionClock.hour == programClock.hour,
              sessionClock.minute == programClock.minute else { return false }

        let duration = Int(session.endTime.timeIntervalSince(session.startTime) / 60)
        guard duration == program.defaultSessionDurationMinutes else { return false }

        let venue = (session.location ?? "").trimmingCharacters(in: .whitespaces)
        let programVenue = (program.locationName ?? "").trimmingCharacters(in: .whitespaces)
        guard !venue.isEmpty, !programVenue.isEmpty else { return false }
        return venue == programVenue
    }

    static func plan(sessions: [SessionEvent],
                     programs: [Program],
                     contracts: [Contract],
                     students: [Student],
                     calendar: Calendar = .current) -> Plan {
        var plan = Plan()

        // Index what the programs already own, by shape and by name.
        var shapeOwners: [Shape: Set<UUID>] = [:]
        for session in sessions where session.programId != nil {
            shapeOwners[shape(of: session, calendar: calendar), default: []].insert(session.programId!)
        }
        let programsByName = Dictionary(grouping: programs, by: \.name)
        let programName = Dictionary(uniqueKeysWithValues: programs.map { ($0.id, $0.name) })
        let studentName = Dictionary(uniqueKeysWithValues: students.map {
            ($0.id, [$0.chineseName, $0.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / "))
        })

        for session in sessions where session.programId == nil {
            let label = "\(session.title.isEmpty ? "(untitled)" : session.title) · \(day(session.date))"

            // PRIVATE FIRST. A 1:1 session must never be swept into a group
            // program by a matching shape, slot or title.
            if SessionPrivacy.isPrivate(session, programs: programs, contracts: contracts) {
                let roster = Set(session.attendeeIds).union(session.actualAttendeeIds)
                let clients = contracts
                    .filter { roster.contains($0.studentId) && $0.status == .active
                        && ($0.kind == .privateBundle || $0.kind == .privatePayPerSession) }
                    .map(\.studentId)
                let distinct = Set(clients)
                if distinct.count == 1, let client = distinct.first {
                    plan.decisions.append(Decision(
                        id: session.id, label: label,
                        destination: .privateMicroGroup(studentId: client,
                                                        studentName: studentName[client] ?? "?")))
                } else {
                    plan.decisions.append(Decision(
                        id: session.id, label: label,
                        destination: .unassigned(reason: distinct.isEmpty
                            ? "private but no identifiable client"
                            : "private with \(distinct.count) private-contract attendees")))
                }
                continue
            }

            // Tier 1: an existing program already owns this exact shape.
            let owners = shapeOwners[shape(of: session, calendar: calendar)] ?? []
            if owners.count == 1, let owner = owners.first {
                plan.decisions.append(Decision(
                    id: session.id, label: label,
                    destination: .fingerprint(programId: owner,
                                              programName: programName[owner] ?? "?",
                                              tier: "shape")))
                continue
            }
            if owners.count > 1 {
                plan.decisions.append(Decision(
                    id: session.id, label: label,
                    destination: .unassigned(reason: "ambiguous — \(owners.count) programs own this shape")))
                continue
            }

            // Tier 1b: the program's OWN SCHEDULE matches this session's slot
            // — same weekday, start time, duration and venue. This is what
            // lets a newly created program adopt the series it was created
            // for: it owns no sessions yet, so Tier 1 can never match it.
            let slotMatches = programs.filter { program in
                matchesSchedule(session, of: program, calendar: calendar)
            }
            if slotMatches.count == 1 {
                plan.decisions.append(Decision(
                    id: session.id, label: label,
                    destination: .fingerprint(programId: slotMatches[0].id,
                                              programName: slotMatches[0].name,
                                              tier: "program schedule slot")))
                continue
            }
            if slotMatches.count > 1 {
                plan.decisions.append(Decision(
                    id: session.id, label: label,
                    destination: .unassigned(reason: "ambiguous — \(slotMatches.count) programs share this slot")))
                continue
            }

            // Tier 2: the title is exactly a program's name — the shape the
            // program wizard's recurring generator produces.
            if let named = programsByName[session.title], named.count == 1 {
                plan.decisions.append(Decision(
                    id: session.id, label: label,
                    destination: .fingerprint(programId: named[0].id,
                                              programName: named[0].name,
                                              tier: "title = program name")))
                continue
            }

            plan.decisions.append(Decision(
                id: session.id, label: label,
                destination: .unassigned(reason: owners.isEmpty && programsByName[session.title] == nil
                    ? "no matching program"
                    : "ambiguous title match")))
        }
        return plan
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Report

    static func report(_ plan: Plan, sampleLimit: Int = 6) -> String {
        var lines: [String] = []
        lines.append("ADOPTION DRY RUN (Phase 2.1) — nothing was written")
        lines.append("standalone sessions: \(plan.decisions.count)")
        lines.append("  fingerprint match ....... \(plan.fingerprintCount)")
        lines.append("  private micro-group ..... \(plan.privateCount)  (\(plan.microGroupClients.count) client\(plan.microGroupClients.count == 1 ? "" : "s"))")
        lines.append("  → Unassigned ............ \(plan.unassignedCount)")
        lines.append("")

        if !plan.programAbsorption.isEmpty {
            lines.append("programs absorbing sessions:")
            for (name, count) in plan.programAbsorption.sorted(by: { $0.value > $1.value }) {
                lines.append("    \(count) → \(name)")
            }
            lines.append("")
        }
        if !plan.microGroupClients.isEmpty {
            lines.append("one-person programs to create:")
            for (name, count) in plan.microGroupClients.sorted(by: { $0.value > $1.value }) {
                lines.append("    \(name): \(count) session\(count == 1 ? "" : "s")")
            }
            lines.append("")
        }
        if !plan.unassignedReasons.isEmpty {
            lines.append("Unassigned, by reason:")
            for (reason, count) in plan.unassignedReasons.sorted(by: { $0.value > $1.value }) {
                lines.append("    \(count) — \(reason)")
            }
            lines.append("")
        }

        lines.append("per-session detail:")
        for bucket in ["fingerprint", "private micro-group", "unassigned"] {
            let inBucket = plan.decisions.filter { $0.destination.bucket == bucket }
            guard !inBucket.isEmpty else { continue }
            lines.append("  [\(bucket)] \(inBucket.count)")
            for decision in inBucket.prefix(sampleLimit) {
                switch decision.destination {
                case .fingerprint(_, let name, let tier):
                    lines.append("    · \(decision.label) → \(name)  (\(tier))")
                case .privateMicroGroup(_, let name):
                    lines.append("    · \(decision.label) → \(name)'s private program")
                case .unassigned(let reason):
                    lines.append("    · \(decision.label) — \(reason)")
                }
            }
            if inBucket.count > sampleLimit {
                lines.append("    … \(inBucket.count - sampleLimit) more")
            }
        }
        return lines.joined(separator: "\n")
    }
}
