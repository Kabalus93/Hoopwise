#if DEBUG
import SwiftUI
import SwiftData

/// Presents ONE real creation sheet, full screen, over a deterministic fixture
/// store — the verification path for "this refactor did not change the UI".
///
/// HOOPWISE_SHOT="privateBooking" | "createSession" | "addSession" | "addProgram"
/// swaps the app's root for this gallery (see SAMApp). It exists because the
/// alternative is clicking four multi-step navigation paths identically twice,
/// which is exactly the thing that makes a before/after comparison untrustworthy:
/// the sheet is constructed directly, so the two runs cannot differ in how they
/// got there. No Accessibility on this Mac, so synthetic navigation is fragile —
/// same constraint that produced DemoScenario on the Mac side.
///
/// SAFETY: the fixture writes only when the store is completely empty (no
/// students, no sessions, no programs). A real store — the 133-athlete device
/// one — can never be seeded by this, and the sheets themselves write nothing
/// until their Save button is pressed, which no automated run presses.
@MainActor
enum SheetGalleryDebug {

    static var requestedShot: String? {
        ProcessInfo.processInfo.environment["HOOPWISE_SHOT"]
    }

    // Fixed ids so the two runs are byte-identical, not merely similar.
    private static let studentId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000001")!
    private static let contractId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000002")!
    private static let programId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000003")!
    private static let phaseId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000004")!
    private static let expiredContractId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000005")!
    /// Own student, so "first active contract" pickers cannot land on the
    /// termless one instead.
    private static let expiredStudentId = UUID(uuidString: "5A1D0000-0000-4000-A000-000000000006")!

    /// Deterministic minimum needed to construct the sheets. Refuses to touch
    /// a store that has anything in it.
    static func seedIfEmpty(dataManager dm: DataManager) {
        guard dm.students.isEmpty, dm.sessionEvents.isEmpty, dm.programs.isEmpty else { return }

        var components = DateComponents()
        components.year = 2015; components.month = 4; components.day = 12
        let birthdate = Calendar.current.date(from: components)

        dm.addStudent(Student(id: studentId,
                              name: "Fixture Athlete",
                              chineseName: "样例",
                              birthdate: birthdate))

        dm.addProgram(Program(id: programId,
                              name: "Fixture Program",
                              programType: .group,
                              ageGroup: .u12,
                              enrolledStudentIds: [studentId],
                              status: .active,
                              recurringDays: [.friday],
                              usesPhases: true))

        dm.addMicroCycle(MicroCycle(id: phaseId,
                                    programId: programId,
                                    phaseNumber: 1,
                                    title: "Fixture Phase",
                                    durationWeeks: 2))

        dm.addContract(Contract(id: contractId,
                                studentId: studentId,
                                contractNumber: 1,
                                kind: .privateBundle,
                                pricePerSession: 300,
                                bundleSize: 10,
                                bundlePurchaseDate: Date(),
                                sessionMinutes: 60))

        // A second contract with a real term, bought long enough ago to be
        // past it — the case the red "Expired" warning exists for and could
        // never reach while isExpired returned false.
        var termStart = DateComponents()
        termStart.year = 2025; termStart.month = 9; termStart.day = 1
        let lastAutumn = Calendar.current.date(from: termStart)
        dm.addStudent(Student(id: expiredStudentId,
                              name: "Lapsed Fixture",
                              birthdate: birthdate))
        dm.addContract(Contract(id: expiredContractId,
                                studentId: expiredStudentId,
                                contractNumber: 2,
                                kind: .privateBundle,
                                enrollmentDate: lastAutumn ?? Date(),
                                pricePerSession: 300,
                                bundleSize: 10,
                                bundlePurchaseDate: lastAutumn,
                                sessionMinutes: 60,
                                validityMonths: 6))
    }

    /// The sheet in a real sheet presentation, so what is captured is what a
    /// coach sees — detent, corner radius and navigation bar included — rather
    /// than the view body rendered bare as a root.
    static func root(shot: String, dataManager dm: DataManager) -> some View {
        Color.black
            .ignoresSafeArea()
            // The live game is a full-screen cover in the app (an iPad shows
            // its wide layout there); everything else is a sheet.
            .sheet(isPresented: .constant(shot != "liveGame")) {
                sheetContent(shot: shot, dataManager: dm)
                    .environmentObject(dm)
                    .modelContainer(dm.modelContainer)
            }
            .fullScreenCover(isPresented: .constant(shot == "liveGame")) {
                sheetContent(shot: shot, dataManager: dm)
                    .environmentObject(dm)
                    .modelContainer(dm.modelContainer)
            }
    }

    @ViewBuilder
    private static func sheetContent(shot: String, dataManager dm: DataManager) -> some View {
        switch shot {
        case "privateBooking":
            if let student = dm.students.first(where: { $0.id == studentId }),
               let contract = dm.contracts.first(where: { $0.id == contractId }) {
                SchedulePrivateSessionSheet(student: student, contract: contract)
            } else {
                missing("privateBooking: fixture student/contract not found")
            }

        case "createSession":
            if let phase = dm.microCycles.first(where: { $0.id == phaseId }) {
                FlightyCreateSessionView(
                    microCycle: phase,
                    program: dm.programs.first(where: { $0.id == programId }),
                    sessionNumber: 1)
            } else {
                missing("createSession: fixture phase not found")
            }

        case "addSession":
            AddSessionOnboardingView(initialDate: fixedDate)

        case "addProgram":
            AddProgramOnboardingView { _ in }

        case "profileCamera":
            ProfilePhotoCamera { _ in }

        case "editStudent":
            // The edit page of the first program's first enrolled student.
            if let program = dm.programs.first,
               let student = dm.students.first(where: { program.enrolledStudentIds.contains($0.id) }) {
                EditStudentView(student: student, player: nil)
            } else {
                missing("editStudent: no enrolled student")
            }

        case "gameStats":
            // The Games tab's insights over a made-up season of the first
            // program's roster (its last player never plays) —
            // built in memory, never saved.
            if let program = dm.programs.first {
                let roster = program.enrolledStudentIds
                let sessions = demoSessions(roster: roster.count > 1 ? Array(roster.dropLast()) : roster)
                let report = GameStatsReport.make(sessions: sessions, roster: roster, current: sessions.last)
                ScrollView {
                    GameInsightsView(insights: GameStatsReport.insights(report: report, sessions: sessions, roster: roster),
                                     games: report.games, sessions: report.sessions, students: dm.students)
                        .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                missing("gameStats: no program")
            }

        case "studentProfile":
            // The athlete profile of the first program's first student.
            if let program = dm.programs.first,
               let student = dm.students.first(where: { program.enrolledStudentIds.contains($0.id) }) {
                NavigationStack { StudentDetailView(student: student) }
            } else {
                missing("studentProfile: no enrolled student")
            }

        case "trainingStats":
            // The profile's Training Stats over a made-up season.
            if let program = dm.programs.first,
               let student = dm.students.first(where: { program.enrolledStudentIds.contains($0.id) }) {
                ScrollView {
                    CollapsibleTrainingStatsSection(
                        studentId: student.id,
                        sessions: demoSessions(roster: program.enrolledStudentIds))
                        .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                missing("trainingStats: no enrolled student")
            }

        case "makeUpOffer":
            // The question a cancelled class with a plan asks (SessionPlanShift).
            Color(.systemGroupedBackground)
                .makeUpOfferAlert()
                .onAppear {
                    dm.makeUpOffer = MakeUpOffer(
                        cancelledSessionId: UUID(), programId: programId, phaseId: phaseId,
                        start: fixedDate.addingTimeInterval(21 * 86_400), durationMinutes: 60,
                        curriculum: SessionCurriculum(), note: "Make-up for demo",
                        className: "U8 Elite")
                }

        case "addStudent":
            // Adding an athlete: the edit page over a fresh, unsaved record.
            EditStudentView()

        case "groupContract":
            // An imported-shape group balance (shared, 12 left), NOT saved:
            // the sheet only renders it.
            if let program = dm.programs.first,
               let studentId = program.enrolledStudentIds.first {
                AddEditContractSheet(studentId: studentId, existing: Contract(
                    studentId: studentId, contractNumber: 99, kind: .group,
                    bundleSize: 12, bundlePurchaseDate: fixedDate,
                    notes: "Imported from 上课名单 on 2026-10-15: 12 sessions left."))
            } else {
                missing("groupContract: no enrolled student")
            }

        case "classListImport":
            // The import preview over HOOPWISE_CLASSLIST_PREVIEW's file.
            ClassListImportView(preloadURL: ProcessInfo.processInfo
                .environment["HOOPWISE_CLASSLIST_PREVIEW"].map { URL(fileURLWithPath: $0) })

        case "sessionPage":
            // The first program's earliest session, on its default Attendance
            // tab — the roster rows and their swipe actions.
            if let program = dm.programs.first,
               let session = dm.sessionEvents
                .filter({ $0.programId == program.id })
                .min(by: { $0.startTime < $1.startTime }) {
                NavigationStack {
                    FlightySessionPageView(session: session, accessMode: .execution)
                }
            } else {
                missing("sessionPage: no program session in the store")
            }

        case "scrimmageSession":
            // A program session shown as a scrimmage: Add Athlete also offers
            // the organization's coaches.
            if let program = dm.programs.first,
               var session = dm.sessionEvents
                .filter({ $0.programId == program.id })
                .min(by: { $0.startTime < $1.startTime }) {
                if ProcessInfo.processInfo.environment["HOOPWISE_SCRIMMAGE_RESET"] == "1" {
                    // UI tests put the demo session back as it was.
                    let _ = {
                        session.sessionType = .training
                        session.curriculum.coachIds = []
                        dm.updateSessionEvent(session, keepLiveFields: true)
                    }()
                    missing("scrimmageSession: reset to training")
                } else {
                    let _ = { session.sessionType = .scrimmage }()
                    NavigationStack {
                        FlightySessionPageView(session: session, accessMode: .execution)
                    }
                }
            } else {
                missing("scrimmageSession: no program session in the store")
            }

        case "privateSession":
            // A private client's session: Add Athlete adds to THIS session
            // only (never the program).
            if let program = dm.programs.first(where: { $0.programType == .privateSessions }),
               let session = dm.sessionEvents
                .filter({ $0.programId == program.id })
                .min(by: { $0.startTime < $1.startTime }) {
                NavigationStack {
                    FlightySessionPageView(session: session, accessMode: .execution)
                }
            } else {
                missing("privateSession: no private program session in the store")
            }

        case "pastSession":
            // A class whose time has passed but is still scheduled: the
            // Cancel / Mark Completed pair.
            if let session = dm.sessionEvents
                .filter({ $0.status == .scheduled && $0.endTime < Date() })
                .max(by: { $0.startTime < $1.startTime }) {
                NavigationStack {
                    FlightySessionPageView(session: session, accessMode: .architect)
                }
            } else {
                missing("pastSession: no past scheduled session")
            }

        case "programDetail":
            // The first program's page: hero header, mascot/category tile.
            if let program = dm.programs.first {
                NavigationStack { FlightyProgramDetailView(program: program) }
            } else {
                missing("programDetail: no program in the store")
            }

        case "upcomingSession":
            // The next scheduled session: no Start button — it starts itself.
            if let next = dm.sessionEvents
                .filter({ $0.status == .scheduled && $0.startTime > Date() })
                .min(by: { $0.startTime < $1.startTime }) {
                NavigationStack {
                    FlightySessionPageView(session: next, accessMode: .execution)
                }
            } else {
                missing("upcomingSession: no scheduled session ahead")
            }

        case "rollCallCompleted":
            // What Complete Session opens.
            RollCallPhotoSheet(programColor: .accentColor, reason: .completed) { _ in }

        case "rollCallOverlay":
            // The roll-call photo's watermark over a stand-in photo
            // (a gym-toned gradient, 1024×768 like PhotoCaptureManager's).
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 768)).image { ctx in
                let colors = [UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1).cgColor,
                              UIColor(red: 0.25, green: 0.22, blue: 0.20, alpha: 1).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 768), options: [])
            }
            ScrollView {
                AttendanceWatermarkOverlay(photo: photo, coachName: "王聪", weekdayText: "星期六",
                                           dateText: "2026年10月17日 13:30", location: "酷迅篮球馆",
                                           presentCount: 7, expectedCount: 10,
                                           nameList: "王诗玲、小辣椒、张梓晨、虞鑫晨、沈思梵、汪文轩、任逸冕")
                    .scaleEffect(0.38, anchor: .topLeading)
                    .frame(width: 1024 * 0.38, height: 768 * 0.38, alignment: .topLeading)
                    .padding()
            }

        case "createGame":
            // The game setup page over the first program session (Create is
            // never tapped by the shot, so nothing is written).
            if let session = dm.sessionEvents.first(where: { $0.programId != nil }) {
                CreateGameSheet(session: .constant(session),
                                enrolledStudents: Array(dm.students.prefix(10)),
                                programColor: .blue, onSave: {})
            } else {
                missing("createGame: no program session")
            }

        case "cyclePlanner":
            // The cycle planner over the first program (Create is not tapped).
            if let program = dm.programs.first {
                CyclePlannerSheet(program: program, defaultStart: Date())
            } else {
                missing("cyclePlanner: no program")
            }

        case "drillDetail":
            // A drill's page as the session plan's Details opens it (a popup
            // with no Done of its own); prefers a drill with visuals.
            if let drill = dm.drills.first(where: { !$0.media.isEmpty }) ?? dm.drills.first {
                NavigationStack { DrillDetailView(drill: drill) }
            } else {
                missing("drillDetail: no drills")
            }

        case "drillDrawing":
            // A drill drawing as the session plan opens it (scratch, unsaved).
            DrillDrawingSheet(title: "Drive and Kick", drawing: {
                var drawing = DrillDrawing.new()
                drawing.steps[0].caption = "Set"
                drawing.steps[0].diagram.cones = [JournalCourtPoint(4, 8), JournalCourtPoint(11, 8)]
                drawing.steps[0].diagram.actions = [.init(kind: .dribble, player: 1,
                    path: [JournalCourtPoint(7.5, 9.6), JournalCourtPoint(10.5, 5)], shape: .straight)]
                drawing.steps[0].text = "1 drives the gap between the cones."
                for caption in ["Kick", "Shot"] {
                    var next = DrillDrawing.Step(diagram: JournalPlayMath.startOfNextStep(after: drawing.steps.last!.diagram))
                    next.caption = caption
                    drawing.steps.append(next)
                }
                return drawing
            }())

        case "drillPicker":
            // The session plan's Add Drill picker (Skills). DEBUG
            // HOOPWISE_DRILLPICKER_SEARCH=<text> types into its search field;
            // on the Mac, HOOPWISE_DRILLPICKER_ASK=1 then presses Return.
            if let session = dm.sessionEvents.first(where: { $0.programId != nil }) ?? dm.sessionEvents.first {
                SmartDrillPickerSheet(session: .constant(session), section: .main,
                                      program: dm.programs.first { $0.id == session.programId }, phase: nil,
                                      students: [], allDrills: dm.drills,
                                      currentCoachId: dm.loggedInCoachId ?? dm.coach.id, onSave: {})
            } else {
                missing("drillPicker: no session in the store")
            }

        case "drillDrawings":
            // Two drawings on a drill page: side by side when wide, a toggle
            // of their names when not (scratch, unsaved).
            ScrollView {
                DrillDrawingsView(drawings: [
                    (media: DrillMedia(drillId: UUID(), kind: .courtDiagram, caption: "Corner shot"),
                     drawing: DrillDrawing.new()),
                    (media: DrillMedia(drillId: UUID(), kind: .courtDiagram, caption: "Option: 1v2"),
                     drawing: { var d = DrillDrawing.new(court: .half); d.steps[0].diagram.cones = [JournalCourtPoint(4, 8)]; return d }())
                ], onEdit: { _ in }, onDelete: { _ in }, onRename: { _, _ in })
                .padding(16)
                // HOOPWISE_DRAWINGS_WIDE=1: laid out as in a wide Mac window.
                .frame(width: ProcessInfo.processInfo.environment["HOOPWISE_DRAWINGS_WIDE"] == "1" ? 1000 : nil)
                .scaleEffect(ProcessInfo.processInfo.environment["HOOPWISE_DRAWINGS_WIDE"] == "1" ? 0.6 : 1)
            }

        case "coachProfile", "coachEdit":
            // The first coach's profile (or the edit form), as Organization opens them.
            if let coach = dm.staffCoaches.first {
                if shot == "coachEdit" { AddEditCoachView(coach: coach) } else { CoachProfileDetailView(coach: coach) }
            } else {
                missing("coachProfile: no coach")
            }

        case "teams":
            // Hub → Teams.
            NavigationStack { TeamsScreen() }

        case "lexicon":
            // Hub → Lexicon; HOOPWISE_LEXICON_TERM=<term> opens that entry.
            NavigationStack {
                if let term = ProcessInfo.processInfo.environment["HOOPWISE_LEXICON_TERM"],
                   let item = Lexicon.shared.search(term).first {
                    LexiconEntryView(item: item)
                } else {
                    LexiconScreen()
                }
            }

        case "teamPractice":
            // A team practice today on the DEMO store: a seeded team (roster,
            // identity, objectives, a broken-down play) and its session page,
            // which opens on Plan.
            if ScreenshotStore.isActive, let session = TeamPracticeDemo.seed(dm) {
                NavigationStack {
                    FlightySessionPageView(session: session, accessMode: .execution)
                }
            } else {
                missing("teamPractice: needs HOOPWISE_SCREENSHOT_STORE=1 and demo athletes")
            }

        case "organization":
            // Hub → Organization: coaches, venues, schools, age categories,
            // share & import.
            NavigationStack { OrganizationView() }

        case "drillsLibrary":
            // The activity-library drills page, as the Hub pushes it.
            NavigationStack { DrillsLibraryView() }

        case "plays":
            // Hub → Plays (the Journal's Plays tab), as the Hub pushes it.
            // HOOPWISE_PLAYS_OPEN etc. open a play, a step or a sheet.
            NavigationStack { JournalPlaysScreen() }

        case "hub":
            FlightyHubView()

        case "liveGame":
            // A live 5-on-5 game over the demo roster (scratch, never saved).
            // The demo roster has five; the second team is scratch players
            // (never saved) so both teams and Chinese names can be seen.
            let scratch = [("Wáng Shī Líng", "王诗玲"), ("Zhāng Zǐ Chén", "张梓晨"), ("Shěn Sī Fàn", "沈思梵"),
                           ("Wāng Wén Xuān", "汪文轩"), ("Rèn Yì Miǎn", "任逸冕")]
                .map { Student(name: $0.0, chineseName: $0.1) }
            LiveGameGalleryHost(students: Array(dm.students.prefix(5)) + scratch)

        case "athletePicker":
            // Add Athlete as a session opens it (banner, sort chips, list).
            AthletePickerSheet(
                title: "Add Athlete",
                students: dm.students,
                accentColor: .blue,
                banner: .init(title: "Sessions Count From Here",
                              subtitle: "The student's contract sessions will count starting from this session",
                              tint: .blue),
                confirmLabel: "Add",
                showSelectionCounter: false
            ) { _ in }

        case "quickPeep":
            // The quick peep as a session opens it, with its Edit button.
            // HOOPWISE_PEEP=photo: a student with a profile photo, from any
            // program (the Mac timing check).
            if ProcessInfo.processInfo.environment["HOOPWISE_PEEP"] == "photo",
               let student = dm.students.max(by: { ($0.profileImageData?.count ?? 0) < ($1.profileImageData?.count ?? 0) }) {
                StudentQuickPeepView(student: student, sessionId: nil)
            } else if let program = dm.programs.first,
               let student = dm.students.first(where: { program.enrolledStudentIds.contains($0.id) }) {
                StudentQuickPeepView(student: student,
                                     sessionId: dm.sessionEvents.first { $0.programId == program.id }?.id)
            } else {
                missing("quickPeep: no enrolled student")
            }

        case "expiredWarning":
            // The red "Expired" warning, on the client whose six-month term
            // lapsed in March. StudentQuickPeepView.contractInfoSection is the
            // only LIVE one: StudentDetailView.contractSection and both of
            // UnifiedStudentCard's contract sections render the same warning
            // and are never referenced, so they could not show it whatever
            // isExpired returned.
            if let student = dm.students.first(where: { $0.id == expiredStudentId }) {
                StudentQuickPeepView(student: student, sessionId: nil)
                    .defaultScrollAnchor(.bottom)
            } else {
                missing("expiredWarning: fixture student not found")
            }

        case "contractRow":
            // The Sales list row. Its "signed" seal was FILLED for every
            // contract in the store, because isSigned returned true for all of
            // them; it is now filled only for a contract that was signed.
            if let student = dm.students.first(where: { $0.id == studentId }),
               let contract = dm.contracts.first(where: { $0.id == contractId }) {
                VStack(spacing: 12) {
                    ContractCard(student: student, contract: contract)
                    Spacer()
                }
                .padding()
            } else {
                missing("contractRow: fixture not found")
            }

        case "contractExpired":
            if let student = dm.students.first(where: { $0.id == expiredStudentId }),
               let contract = dm.contracts.first(where: { $0.id == expiredContractId }) {
                ContractDetailView(student: student, contract: contract)
            } else {
                missing("contractExpired: fixture contract not found")
            }

        case "contractStatus":
            // The three toggles whose setters used to discard the write while
            // the row said it saved (Phase 2.9).
            if let student = dm.students.first(where: { $0.id == studentId }),
               let contract = dm.contracts.first(where: { $0.id == contractId }) {
                // Anchored to the bottom: the Status and Equipment toggles sit
                // below the fold, and a scripted scroll is far less repeatable
                // than asking the scroll view where to start.
                ContractDetailView(student: student, contract: contract)
                    .defaultScrollAnchor(.bottom)
            } else {
                missing("contractStatus: fixture student/contract not found")
            }

        default:
            missing("unknown shot “\(shot)” — expected privateBooking, createSession, addSession or addProgram")
        }
    }

    /// A pinned date, so a sheet that defaults to "today" cannot make two runs
    /// on either side of midnight look like a regression.
    private static var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 25
        components.hour = 18; components.minute = 30
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func missing(_ reason: String) -> some View {
        Text(reason)
            .font(.system(size: 15, design: .monospaced))
            .foregroundStyle(.red)
            .padding()
    }
}

/// Holds a scratch game for the "liveGame" shot: two teams of up to five,
/// already in progress. Nothing is written to the store.
private struct LiveGameGalleryHost: View {
    let students: [Student]
    @State private var game: SessionGame

    init(students: [Student]) {
        self.students = students
        let ids = students.map(\.id)
        // HOOPWISE_LIVE_BLACK=1: the home team plays in black (dark-mode check).
        let black = ProcessInfo.processInfo.environment["HOOPWISE_LIVE_BLACK"] == "1"
        let home = GameTeam(name: black ? "Black" : "Blue", colorHex: black ? "#1C1C1E" : "#007AFF",
                            playerIds: Array(ids.prefix(5)))
        let away = GameTeam(name: "White", colorHex: "#F5F5F5", playerIds: Array(ids.dropFirst(5).prefix(5)))
        _game = State(initialValue: SessionGame(sessionId: UUID(), teams: [home, away],
                                                status: .inProgress, startedAt: Date()))
    }

    var body: some View {
        LiveGameScoringView(game: $game, students: students, allGamesInSession: [game], onSave: {})
    }

}

extension SheetGalleryDebug {
    /// Eight sessions of two games each, scoring rising over time.
    static func demoSessions(roster: [UUID]) -> [SessionEvent] {
        var sessions: [SessionEvent] = []
        let players = Array(roster.prefix(8))
        guard !players.isEmpty else { return [] }
        for week in 0..<8 {
            let start = fixedDate.addingTimeInterval(Double(week - 8) * 7 * 86_400)
            var s = SessionEvent(programId: nil, title: "Demo", date: start, startTime: start,
                                 endTime: start.addingTimeInterval(3600), status: .completed, attendeeIds: roster)
            for g in 0..<2 {
                let gid = UUID()
                let lines = players.enumerated().compactMap { i, p -> SessionPlayerStats? in
                    guard (i + week + g) % 5 != 0 else { return nil }
                    return SessionPlayerStats(playerId: p, gameId: gid, teamId: gid,
                                              points: 2 * ((i * 3 + week + g) % 4) + (week > 4 ? 2 : 0),
                                              rebounds: (i + week) % 3, assists: (i + g + week / 2) % 3,
                                              steals: (i + week) % 2, blocks: i % 4 == 0 ? 1 : 0)
                }
                s.games.append(SessionGame(sessionId: s.id, gameNumber: g + 1, playerStats: lines,
                                           status: .completed))
            }
            sessions.append(s)
        }
        return sessions
    }
}

/// Seeds the demo store with a team and a team practice today (idempotent:
/// both are found by name / team on later runs).
@MainActor
enum TeamPracticeDemo {
    static let teamName = "Hoopwise Hawks"

    static func seed(_ dm: DataManager) -> SessionEvent? {
        let athletes = Array(dm.students.prefix(6))
        guard !athletes.isEmpty else { return nil }
        let team: Team
        if let existing = dm.teams.first(where: { $0.name == teamName }) {
            team = existing
        } else {
            var made = Team(name: teamName, shortName: "HWK", colorHex: "#5856D6",
                            coachId: dm.staffCoaches.first?.id, coachName: dm.staffCoaches.first?.name,
                            homeVenue: dm.locations.first?.name, createdByCoachId: dm.loggedInCoachId)
            made.playerIds = athletes.map(\.id) + (dm.staffCoaches.first.map { [$0.id] } ?? [])
            var book = made.playbook
            book.identity = "Pace and space — share the ball, switch 1–4."
            book.objectives = ["Spacing on every possession", "Two passes before a shot", "Talk on defense"]
            let plays = (try? dm.modelContext.fetch(FetchDescriptor<JournalPlay>())) ?? []
            if let play = plays.first(where: { $0.starterKey != nil }) ?? plays.first {
                let ref = play.planRef
                book[.baseOffense].plays = [ref]
                let numbers = play.conceptPart?.sortedSteps.first?.diagram.offense.map(\.number).sorted() ?? [1, 2, 3, 4, 5]
                func drills(_ skill: String) -> [UUID] {
                    Array(dm.drills.filter { $0.tags.contains("type:\(skill)") }.prefix(2).map(\.id))
                }
                let skillsByRole = [["passing", "dribbling"], ["shooting"], ["shooting", "oneOnOne"], ["post", "rebounding"], ["post", "defence"]]
                book.breakdowns[ref.key] = PlayBreakdown(playName: play.name, roles: numbers.enumerated().map { i, n in
                    let skills = skillsByRole[i % skillsByRole.count]
                    return PlayBreakdown.Role(number: n,
                                              standard: ["Read the first pass", "Fill the corner, catch ready", "Cut hard off the screen", "Seal and call for it", "Rebound, outlet fast"][i % 5],
                                              skills: skills,
                                              drillIds: skills.flatMap(drills),
                                              playerIds: athletes.indices.contains(i) ? [athletes[i].id] : [])
                })
            }
            made.playbook = book
            dm.addTeam(made)
            team = made
        }
        let today = Calendar.current.startOfDay(for: Date())
        if let session = dm.sessionEvents.first(where: {
            $0.curriculum.teamId == team.id && Calendar.current.isDate($0.startTime, inSameDayAs: today)
        }) { return session }
        let start = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        var curriculum = SessionCurriculum()
        curriculum.teamId = team.id
        curriculum.coachIds = team.playerIds.filter { id in dm.staffCoaches.contains { $0.id == id } }
        dm.createSession(SessionCreation.Intent(
            group: .unassigned, sessionType: .teamPractice, start: start, durationMinutes: 90,
            title: "\(team.name) Practice", location: team.homeVenue,
            roster: team.playerIds.filter { id in dm.students.contains { $0.id == id } },
            curriculum: curriculum, createdByCoachId: dm.loggedInCoachId))
        return dm.sessionEvents.first { $0.curriculum.teamId == team.id && Calendar.current.isDate($0.startTime, inSameDayAs: today) }
    }
}
#endif
