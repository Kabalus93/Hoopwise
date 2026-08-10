import Foundation

// MARK: - One way to create a session (Phase 2.5)
//
// Nine places built a SessionEvent by hand, and they disagreed about every
// derived field. The 2026-08-09 census made the cost concrete: a private
// session booked on the phone landed with no program, a hand-typed venue
// ("Kuxun Main court" for a gym the store already knew as 酷迅) and no phase —
// three of the four jobs `programId == nil` used to do, minted fresh by a UI
// that Phase 2 had already taught the rest of the app to stop assuming.
//
// The divergences, before this file:
//   · programId — two sheets hardcoded nil "because private", which is exactly
//     the encoding Phase 1 replaced with the program's TYPE.
//   · phase link — only the two generators set one, so a session created inside
//     a phased program's window sat unphased until a reconciler pass.
//   · seriesId — only the two generators stamped one, so the recurring batches
//     the wizards produce fell back to 2.2's fragile structural fingerprint.
//   · roster — the program wizard created sessions with NO attendees at all.
//   · venue — free text at every site, never defaulted from the program.
//
// So creation becomes a two-step: `plan` decides everything, purely, and the
// manager performs the writes. Nothing here touches the database, which is why
// it can be tested without one.
//
// ATTENDANCE IS NOT HERE. `actualAttendeeIds` passes straight through for the
// one caller that pre-marks, but changing an attendance STATE — and therefore
// charging a bundle — stays with setStudentAttendanceState / the redemption
// authority. Creation must never be a second way to spend a client's sessions.
enum SessionCreation {

    /// Who the session is for.
    ///
    /// `programId == nil` used to mean four things at once. It still exists —
    /// a one-off scrimmage or a summer camp genuinely belongs to no program —
    /// but it now means ONLY that, and a caller has to say so. That is the
    /// whole change: not the absence of the value, the absence of its
    /// ambiguity.
    enum Group: Equatable {
        /// A named program — group or private micro-group alike.
        case program(UUID)
        /// A 1:1 with this client. Resolves to their private micro-group,
        /// creating one when they have none.
        case privateClient(UUID)
        /// A deliberate one-off. The census counts these, and the adoption
        /// planner offers them for triage; nothing infers privateness from it.
        case unassigned
    }

    struct Intent {
        var group: Group
        var sessionType: SessionType = .training
        var start: Date
        var durationMinutes: Int
        /// A title the coach actually typed. nil — or the derived name handed
        /// straight back — means "no override", and the stored column keeps
        /// its Phase 2.3 role as a legacy fallback.
        var title: String?
        /// nil takes the program's venue, which is what stops a coach retyping
        /// a gym's name into a fourth spelling.
        var location: String?
        /// nil takes the program's enrolment.
        var roster: [UUID]?
        /// An explicit phase link, for the generators that are generating FOR
        /// a phase. It overrides date derivation because a plan is allowed to
        /// have no dates — 16 links in the live store are exactly that — and
        /// deriving would silently drop them.
        var phase: UUID?
        var status: SessionEventStatus = .scheduled
        var notes: String?
        var curriculum: SessionCurriculum = SessionCurriculum()
        var developmentFocus: [TrainingFocus] = []
        /// One id shared by every session of a generated run (Phase 2.2).
        var seriesId: UUID?
        /// Pre-marked attendance. A passthrough only — see the note above.
        var actualAttendeeIds: [UUID] = []
        var createdByCoachId: UUID?

        init(group: Group,
             sessionType: SessionType = .training,
             start: Date,
             durationMinutes: Int,
             title: String? = nil,
             location: String? = nil,
             roster: [UUID]? = nil,
             phase: UUID? = nil,
             status: SessionEventStatus = .scheduled,
             notes: String? = nil,
             curriculum: SessionCurriculum = SessionCurriculum(),
             developmentFocus: [TrainingFocus] = [],
             seriesId: UUID? = nil,
             actualAttendeeIds: [UUID] = [],
             createdByCoachId: UUID? = nil) {
            self.group = group
            self.sessionType = sessionType
            self.start = start
            self.durationMinutes = durationMinutes
            self.title = title
            self.location = location
            self.roster = roster
            self.phase = phase
            self.status = status
            self.notes = notes
            self.curriculum = curriculum
            self.developmentFocus = developmentFocus
            self.seriesId = seriesId
            self.actualAttendeeIds = actualAttendeeIds
            self.createdByCoachId = createdByCoachId
        }
    }

    /// Everything the write step must do, decided up front so it can be
    /// reviewed, tested, and undone as one unit.
    struct Plan {
        var event: SessionEvent
        /// A private micro-group that does not exist yet.
        var programToCreate: Program?
        /// An existing private program found in a non-active status. A client
        /// coming back reactivates the program they had; spawning
        /// "Private · Frank 2" beside the archived original would split their
        /// history across two containers.
        var reactivate: Program?
        /// Set only when the client has no program pointer at all. A client
        /// who trains in a group keeps pointing at that group: a private
        /// micro-group is a 1:1 container, and moving the pointer would quietly
        /// remove them from the squad they train with (setStudentEnrollment
        /// clears every other program's roster by design).
        var enroll: Enrollment?

        struct Enrollment: Equatable {
            let studentId: UUID
            let programId: UUID
        }
    }

    // MARK: - Planning

    static func plan(_ intent: Intent,
                     programs: [Program],
                     phases: [MicroCycle],
                     students: [Student],
                     sessions: [SessionEvent],
                     defaultCoachId: UUID? = nil,
                     calendar: Calendar = .current) -> Plan {

        // 1. Resolve the group to a concrete program, creating or reactivating
        //    a private micro-group when the client has none active.
        var programToCreate: Program?
        var reactivate: Program?
        var enroll: Plan.Enrollment?
        let program: Program

        switch intent.group {
        case .unassigned:
            return Plan(event: bareEvent(intent, programId: nil, phaseId: nil,
                                         location: intent.location,
                                         roster: intent.roster ?? [],
                                         title: intent.title ?? "",
                                         defaultCoachId: defaultCoachId),
                        programToCreate: nil, reactivate: nil, enroll: nil)

        case .program(let id):
            guard let found = programs.first(where: { $0.id == id }) else {
                // A program that vanished between picking it and saving. The
                // normalizer in addSessionEvent would strip the pointer anyway;
                // being explicit here keeps the event honest.
                return Plan(event: bareEvent(intent, programId: nil,
                                             phaseId: nil, location: intent.location,
                                             roster: intent.roster ?? [],
                                             title: intent.title ?? "",
                                             defaultCoachId: defaultCoachId),
                            programToCreate: nil, reactivate: nil, enroll: nil)
            }
            program = found

        case .privateClient(let clientId):
            let owned = privatePrograms(for: clientId, in: programs)
            if let active = owned.first(where: { $0.status == .active }) {
                program = active
            } else if let dormant = owned.first {
                var revived = dormant
                revived.status = .active
                revived.updatedAt = Date()
                reactivate = revived
                program = revived
            } else {
                let created = newMicroGroup(for: clientId,
                                            students: students,
                                            programs: programs,
                                            coachId: defaultCoachId)
                programToCreate = created
                program = created
                let student = students.first { $0.id == clientId }
                if student?.programId == nil {
                    enroll = Plan.Enrollment(studentId: clientId, programId: created.id)
                }
            }
        }

        // 2. Derived fields. Venue and roster come from the program unless the
        //    caller was explicit.
        let location = intent.location ?? program.locationName
        let roster = intent.roster ?? program.enrolledStudentIds

        // 3. Phase from the DATE (2.4), through the one window rule. A draft
        //    event carries the program so `derive` can see it.
        let draft = bareEvent(intent, programId: program.id, phaseId: nil,
                              location: location, roster: roster,
                              title: "", defaultCoachId: defaultCoachId)
        var phaseId: UUID? = intent.phase
        if phaseId == nil, program.usesPhases {
            if case .assign(let id) = PhaseAssignment.derive(session: draft,
                                                             phases: phases,
                                                             calendar: calendar) {
                phaseId = id
            }
        }

        // 4. The stored title. Phase 2.3 made names derived, so the column is
        //    a fallback: store what the coach typed, and otherwise store the
        //    derived name so a session that later loses its program still reads
        //    as something.
        let linked = bareEvent(intent, programId: program.id, phaseId: phaseId,
                               location: location, roster: roster,
                               title: "", defaultCoachId: defaultCoachId)
        let typed = intent.title?.trimmingCharacters(in: .whitespaces)
        let title: String
        if let typed, !typed.isEmpty {
            title = typed
        } else {
            // Only when nothing was typed: a generator creating a run of 50
            // would otherwise pay for a full-store name derivation per session.
            let allPrograms = programToCreate.map { programs + [$0] } ?? programs
            title = SessionNaming.name(for: linked,
                                       programs: allPrograms,
                                       phases: phases,
                                       allSessions: sessions + [linked],
                                       style: .groupFirst)
        }

        var event = linked
        event.title = title
        return Plan(event: event,
                    programToCreate: programToCreate,
                    reactivate: reactivate,
                    enroll: enroll)
    }

    /// Every private program the client belongs to, ACTIVE OR NOT, oldest
    /// first. Status is deliberately not filtered here: a returning client
    /// must land back in the program they already have.
    static func privatePrograms(for clientId: UUID, in programs: [Program]) -> [Program] {
        programs
            .filter { $0.programType == .privateSessions && $0.enrolledStudentIds.contains(clientId) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The one-person program, in the shape the Phase 2.1 migration used: no
    /// recurring days and no default session time, so the adoption planner's
    /// slot tier can never match it against an unrelated class.
    static func newMicroGroup(for clientId: UUID,
                              students: [Student],
                              programs: [Program],
                              coachId: UUID?) -> Program {
        let student = students.first { $0.id == clientId }
        let display = [student?.chineseName, student?.name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")

        // Band: the student's own birthdate first, then whatever band their
        // existing programs carry, and only then a flagged default.
        var band = student?.ageGroup
        if band == nil {
            band = programs.first { $0.enrolledStudentIds.contains(clientId) }?.ageGroup
        }

        return Program(name: "Private · \(display.isEmpty ? "Athlete" : display)",
                       programType: .privateSessions,
                       ageGroup: band ?? .adult,
                       enrolledStudentIds: [clientId],
                       createdByCoachId: coachId,
                       status: .active,
                       recurringDays: [],
                       defaultSessionTime: nil,
                       usesPhases: false)
    }

    // MARK: - Assembly

    private static func bareEvent(_ intent: Intent,
                                  programId: UUID?,
                                  phaseId: UUID?,
                                  location: String?,
                                  roster: [UUID],
                                  title: String,
                                  defaultCoachId: UUID?) -> SessionEvent {
        let end = Calendar.current.date(byAdding: .minute,
                                        value: max(1, intent.durationMinutes),
                                        to: intent.start) ?? intent.start
        return SessionEvent(
            microCycleId: phaseId,
            programId: programId,
            seriesId: intent.seriesId,
            sessionType: intent.sessionType,
            title: title,
            date: intent.start,
            startTime: intent.start,
            endTime: end,
            location: (location?.isEmpty == false) ? location : nil,
            status: intent.status,
            curriculum: intent.curriculum,
            attendeeIds: roster,
            actualAttendeeIds: intent.actualAttendeeIds,
            notes: (intent.notes?.isEmpty == false) ? intent.notes : nil,
            developmentFocus: intent.developmentFocus,
            createdByCoachId: intent.createdByCoachId ?? defaultCoachId)
    }
}
