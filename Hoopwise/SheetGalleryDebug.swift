import Photos
import AVFoundation
#if DEBUG
import SwiftUI
import SwiftData
import OSLog

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
        // HOOPWISE_GALLERY_FULL=1 shows any shot full screen — an iPad page at
        // the window's real (regular) width instead of a form-sheet's compact one.
        let full = shot == "liveGame" || ProcessInfo.processInfo.environment["HOOPWISE_GALLERY_FULL"] == "1"
        return Color.black
            .ignoresSafeArea()
            // The live game is a full-screen cover in the app (an iPad shows
            // its wide layout there); everything else is a sheet.
            .sheet(isPresented: .constant(!full)) {
                sheetContent(shot: shot, dataManager: dm)
                    .environmentObject(dm)
                    .modelContainer(dm.modelContainer)
            }
            .fullScreenCover(isPresented: .constant(full)) {
                ObservedShot(dm: dm) { sheetContent(shot: shot, dataManager: dm) }
                    .environmentObject(dm)
                    .modelContainer(dm.modelContainer)
            }
    }

    /// Redraws a shot when the store finishes loading (a cover presented at
    /// launch is built before the data arrives).
    private struct ObservedShot<Content: View>: View {
        @ObservedObject var dm: DataManager
        @ViewBuilder let content: () -> Content
        var body: some View { content() }
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

        case "backgroundRemoval":
            // The background picker over a drawn scene; results logged.
            ProfileBackgroundDebugShot()

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

        case "gameDashboard":
            // The Games tab's dashboard over the same made-up season — in
            // memory, never saved.
            if let program = dm.programs.first {
                let roster = program.enrolledStudentIds
                let sessions = demoSessions(roster: roster.count > 1 ? Array(roster.dropLast()) : roster)
                ScrollView {
                    GameDashboardView(programSessions: sessions, session: sessions.last!, roster: roster,
                                      students: dm.students, excluding: [])
                        .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                missing("gameDashboard: no program")
            }

        case "studentProfile":
            // The athlete profile of the first program's first student.
            if let program = dm.programs.first,
               let student = dm.students.first(where: { program.enrolledStudentIds.contains($0.id) }) {
                NavigationStack { StudentDetailView(student: student) }
                    .task {
                        // HOOPWISE_DEMO_VAULT=1: the newest photos in this
                        // simulator's library go in the athlete's vault (demo store).
                        guard ScreenshotStore.isActive, ProcessInfo.processInfo.environment["HOOPWISE_DEMO_VAULT"] == "1",
                              await PhotoVault.requestAccess() else { return }
                        let options = PHFetchOptions()
                        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                        options.fetchLimit = 6
                        var ids: [String] = []
                        PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
                        dm.addToVaults(PhotoVault.entries(localIds: ids), studentIds: [student.id])
                    }
            } else {
                missing("studentProfile: no enrolled student")
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

        case "planDashboard":
            // A planned program session in a phase, on its Plan tab: the plan
            // balance octagon over the phase focus + program goals target.
            if var session = dm.sessionEvents.first(where: { s in
                s.microCycleId != nil && !(dm.microCycles.first { $0.id == s.microCycleId }?.focus.isEmpty ?? true)
            }) ?? dm.sessionEvents.first(where: { $0.programId != nil }) {
                // A fresh plan from the generator, in memory only.
                let _ = {
                    let program = dm.programs.first { $0.id == session.programId }
                    let phase = dm.microCycles.first { $0.id == session.microCycleId }
                    let ctx = DrillPlanGenerator.Context(session: session, program: program, phase: phase,
                                                         enrolledStudents: [], players: [], allDrills: dm.drills,
                                                         programHistory: [])
                    session.curriculum = DrillPlanGenerator.generatePlan(in: ctx).curriculum
                }()
                if ProcessInfo.processInfo.environment["HOOPWISE_PLAN_TARGET"] == "1" {
                    // The dashboard alone against a Defense + Passing phase focus.
                    ScrollView {
                        SessionPlanDashboard(curriculum: session.curriculum, drills: dm.drills, teams: dm.teams,
                                             phaseFocus: [.defense, .passing], skillTargets: nil, onFind: { _ in })
                            .padding()
                    }
                } else {
                    NavigationStack {
                        FlightySessionPageView(session: session, accessMode: .execution, initialTab: 0)
                    }
                }
            } else {
                missing("planDashboard: no planned session")
            }

        case "sessionPage":
            // The first program's earliest session, on its default Attendance
            // tab — the roster rows and their swipe actions.
            // HOOPWISE_SESSION_TAB=<0…3> opens another tab; HOOPWISE_SESSION_TODAY=1
            // opens today's session that has games instead.
            if let program = dm.programs.first,
               let session = (ProcessInfo.processInfo.environment["HOOPWISE_SESSION_TODAY"] == "1"
                    ? dm.sessionEvents.first(where: { Calendar.current.isDateInToday($0.startTime) && !$0.games.isEmpty })
                    : nil)
                ?? dm.sessionEvents
                .filter({ $0.programId == program.id })
                .min(by: { $0.startTime < $1.startTime }) {
                let env = ProcessInfo.processInfo.environment
                // HOOPWISE_DEMO_READY_GAMES=1 | clear (demo store only): three
                // unstarted games on this session, or none — the iPad games
                // list's status word check (19 Nov 2026).
                let _ = {
                    // Once per launch: the write redraws this page.
                    guard ScreenshotStore.isActive, !DemoGamesOnce.done,
                          let mode = env["HOOPWISE_DEMO_READY_GAMES"] else { return }
                    DemoGamesOnce.done = true
                    let games: [SessionGame] = mode == "clear" ? [] : (1...3).map { n in
                        var g = SessionGame(sessionId: session.id, gameNumber: n,
                                            teams: [GameTeam(name: "Black", colorHex: "#1C1C1E", playerIds: []),
                                                    GameTeam(name: "White", colorHex: "#F5F5F5", playerIds: [])])
                        g.status = .ready
                        return g
                    }
                    dm.replaceSessionGames(inSessionId: session.id, games: games)
                }()
                // HOOPWISE_DEMO_NOTES=<text> (demo store only): this session's
                // notes are set to the text ("" clears them) before the page
                // opens — how SessionNotesAutosaveUITests puts them back.
                let _ = {
                    guard ScreenshotStore.isActive, !DemoNotesOnce.done, let text = env["HOOPWISE_DEMO_NOTES"] else { return }
                    DemoNotesOnce.done = true
                    dm.setSessionNotes(sessionId: session.id, notes: text.isEmpty ? nil : text, coachNotes: session.coachNotes)
                }()
                // HOOPWISE_DEMO_SHOOTING=1 | clear (demo store only): Free
                // Throws and 5-Spot Twos in this session's Skills with no
                // results yet, or out again (20 Nov 2026).
                let _ = {
                    guard ScreenshotStore.isActive, !DemoShootingOnce.done,
                          let mode = env["HOOPWISE_DEMO_SHOOTING"] else { return }
                    DemoShootingOnce.done = true
                    // Every run starts on the drills' default setups (a
                    // remembered setup from an earlier run would change the pad).
                    for drill in ShootingDrill.allCases {
                        UserDefaults.standard.removeObject(forKey: "shooting.setup.\(drill.rawValue)")
                    }
                    var copy = session
                    // =chart: the Shot Chart instead.
                    let all = ShootingDrill.allCases.map(\.drillId)
                    let ids = mode == "chart" ? [ShootingDrill.shotChart.drillId]
                        : [ShootingDrill.freeThrows.drillId, ShootingDrill.twos.drillId]
                    copy.curriculum.skillDrillIds.removeAll { all.contains($0) }
                    copy.curriculum.warmupDrillIds.removeAll { all.contains($0) }
                    copy.curriculum.shooting = []
                    if mode != "clear" { copy.curriculum.skillDrillIds += ids }
                    dm.updateSessionEvent(copy, keepLiveFields: true)
                    // Results are live data (kept by whole-session saves):
                    // clear them through their own writer.
                    dm.setSessionShooting(sessionId: session.id, runs: [])
                }()
                // HOOPWISE_DEMO_TRACKED=1 | clear (demo store only): the
                // coach's own tracked drill "Wall Passes" (count, passes,
                // Passing) in this session's Skills with no results, or out
                // again (23 Nov 2026).
                let _ = {
                    guard ScreenshotStore.isActive, !DemoTrackedOnce.done,
                          let mode = env["HOOPWISE_DEMO_TRACKED"] else { return }
                    DemoTrackedOnce.done = true
                    let id = DemoTrackedOnce.drillId
                    if dm.drills.first(where: { $0.id == id }) == nil {
                        var drill = DrillItem(id: id, name: "Wall Passes", category: .skills,
                                              description: "Chest passes against the wall for 30 seconds.")
                        drill.tags = DrillItem.tags(["visibility:private"], tracking: TrackDefinition(
                            measure: .inTime, amount: 30, unit: "passes", skills: ["passing"]))
                        dm.addDrill(drill)
                    }
                    // =zones: a shooting drill on the shot map — both corners
                    // and the top, 10 shots each (24 Nov 2026).
                    let zonesId = DemoTrackedOnce.zonesDrillId
                    if dm.drills.first(where: { $0.id == zonesId }) == nil {
                        var def = TrackKind.shooting.preset(chinese: false)
                        def.zones = [5, 7, 9]
                        var drill = DrillItem(id: zonesId, name: "Corner and Top Threes", category: .shooting,
                                              description: "Ten threes from each corner and the top.")
                        drill.tags = DrillItem.tags(["visibility:private"], tracking: def)
                        dm.addDrill(drill)
                    }
                    var copy = dm.sessionEvents.first { $0.id == session.id } ?? session
                    copy.curriculum.skillDrillIds.removeAll { $0 == id || $0 == zonesId }
                    if mode == "zones" { copy.curriculum.skillDrillIds.append(zonesId) }
                    else if mode != "clear" { copy.curriculum.skillDrillIds.append(id) }
                    dm.updateSessionEvent(copy, keepLiveFields: true)
                    dm.setSessionTracking(sessionId: session.id, runs: [])
                    // clear also takes the demo drills out of the library
                    // (they push its rows down for other tests).
                    if mode == "clear" {
                        for demo in dm.drills where demo.id == id || demo.id == zonesId { dm.deleteDrill(demo) }
                    }
                }()
                NavigationStack {
                    // Re-read: a demo hook above may just have written it.
                    FlightySessionPageView(session: dm.sessionEvents.first { $0.id == session.id } ?? session,
                                           accessMode: .execution,
                                           initialTab: env["HOOPWISE_SESSION_TAB"].flatMap(Int.init))
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
                    FlightySessionPageView(session: session, accessMode: .architect,
                                           initialTab: ProcessInfo.processInfo.environment["HOOPWISE_SESSION_TAB"].flatMap(Int.init))
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
                                           presentCount: 7,
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

        case "rateLibrary":
            // One-time: Claude rates every plannable library activity on the
            // eight attribute axes; each rating is logged to hoopwise.mac /
            // rater as "rate <key>|<eight scores>" (Mac demo copy, the
            // Keychain key). tools/attributes/merge.py turns the log into
            // ActivityLibraryAttributes.swift.
            LibraryRatingRun()

        case "newDrill":
            // New Drill; with HOOPWISE_NEWDRILL_DESCRIPTION it asks Claude.
            // HOOPWISE_EDIT_DRILL=<name> opens that drill's Edit Drill (the
            // same form).
            if let name = ProcessInfo.processInfo.environment["HOOPWISE_EDIT_DRILL"],
               let drill = dm.drills.first(where: { $0.name == name }) {
                AddDrillView(editing: drill)
            } else {
                AddDrillView()
            }

        case "courtArt":
            // Every session type's header court, one card each.
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        ZStack(alignment: .bottomLeading) {
                            CardCourtBackground(color: Color(red: 0.08, green: 0.3, blue: 0.75), style: CourtArtStyle(type))
                            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.25), .black.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                            Text(type.displayName).font(.headline).foregroundStyle(.white).padding(12)
                        }
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: 14))
                    }
                }
                .padding(12)
            }
        case "drillDrawingEditor":
            // A drill's drawing in the Coach board's editor (scratch, unsaved).
            DrillDrawingEditor(drawing: .new()) { _ in }
        case "coachBoard":
            // Hub → Coach board (the editor, full screen), as it was left.
            CoachBoardScreen()
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

        case "teamPlay", "playSheet":
            // The demo team's focus play (demo store): =teamPlay its breakdown
            // page (HOOPWISE_TEAMPLAY_PEOPLE=1 faces on, HOOPWISE_TEAMPLAY_FOLLOW=<n>
            // follows role n); =playSheet the share sheet, and with
            // HOOPWISE_PLAYSHEET_EXPORT=team|player|everyone it writes
            // playsheet.pdf + playsheet.jpg to the App Group Library/Caches.
            if ScreenshotStore.isActive, TeamPracticeDemo.seed(dm) != nil,
               let team = dm.teams.first(where: { $0.name == TeamPracticeDemo.teamName }),
               let key = team.playbook.focus.first,
               let play = ((try? dm.modelContext.fetch(FetchDescriptor<JournalPlay>())) ?? []).first(where: { $0.planRef.key == key }) {
                let env = ProcessInfo.processInfo.environment
                let _ = {
                    if let on = env["HOOPWISE_TEAMPLAY_PEOPLE"] { TeamPlayCast.setShowsPeople(on == "1", team: team.id) }
                }()
                if shot == "teamPlay" {
                    NavigationStack { PlayBreakdownView(teamId: team.id, ref: play.planRef, debugFollow: env["HOOPWISE_TEAMPLAY_FOLLOW"].flatMap(Int.init)) }
                } else {
                    PlaySheetShareSheet(play: play, teamId: team.id, initialFocus: nil)
                }
            } else {
                missing("teamPlay: needs HOOPWISE_SCREENSHOT_STORE=1")
            }

        case "homeCards":
            // Home with the demo team pinned and its play marked as being
            // worked on (demo store only).
            if ScreenshotStore.isActive, TeamPracticeDemo.seed(dm) != nil,
               let team = dm.teams.first(where: { $0.name == TeamPracticeDemo.teamName }) {
                let _ = {
                    if !HomePins.isPinned(team.id) { HomePins.toggle(team.id) }
                    let plays = (try? dm.modelContext.fetch(FetchDescriptor<JournalPlay>())) ?? []
                    if let key = team.playbook.focus.first, let play = plays.first(where: { $0.planRef.key == key }) {
                        PlayActivity.edited(play)
                        // HOOPWISE_HOME_PIN_STEP=<n>: that play's step n (0-based) pinned.
                        if let n = ProcessInfo.processInfo.environment["HOOPWISE_HOME_PIN_STEP"].flatMap(Int.init) {
                            PlayActivity.pin(play, step: n)
                        } else {
                            PlayActivity.unpin()
                        }
                    }
                }()
                FlightyActionableDashboard()
            } else {
                missing("homeCards: needs HOOPWISE_SCREENSHOT_STORE=1")
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

        case "gameRecap":
            // A finished 2-team game over the demo roster, with a basket log
            // (scratch, never saved) — the Game Recap sheet.
            let players = Array(dm.students.prefix(6))
            if players.count >= 2 {
                GameRecapView(game: demoRecapGame(players.map(\.id)), students: players, allGamesInSession: [])
            } else {
                missing("gameRecap: no students")
            }

        case "liveGame":
            // A live 5-on-5 game over the demo roster (scratch, never saved).
            // The demo roster has five; the second team is scratch players
            // (never saved) so both teams and Chinese names can be seen.
            let scratch = [("Wáng Shī Líng", "王诗玲"), ("Zhāng Zǐ Chén", "张梓晨"), ("Shěn Sī Fàn", "沈思梵"),
                           ("Wāng Wén Xuān", "汪文轩"), ("Rèn Yì Miǎn", "任逸冕")]
                .map { Student(name: $0.0, chineseName: $0.1) }
            // Built once the roster has loaded — its @State game would keep
            // a half-empty first build.
            if dm.students.count >= 5 {
                LiveGameGalleryHost(students: Array(dm.students.prefix(5)) + scratch)
            } else {
                ProgressView()
            }

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

        case "athletePost":
            // The media vault's post composer on a demo athlete (26 Nov 2026):
            // the athlete's profile photo over a stand-in court as "the photo".
            // HOOPWISE_POST_EXPORT=1 writes post-<template>-<source>.jpg for
            // every template to the App Group Library/Caches.
            if let student = dm.students.max(by: { ($0.profileImageData?.count ?? 0) < ($1.profileImageData?.count ?? 0) }),
               let data = student.profileImageData, let face = UIImage(data: data) {
                let photo = AthletePostDebug.standIn(face)
                AthletePostComposer(student: student, photo: photo)
                    .task {
                        guard ProcessInfo.processInfo.environment["HOOPWISE_POST_EXPORT"] == "1" else { return }
                        AthletePostDebug.export(student: student, photo: photo, dm: dm)
                    }
            } else {
                missing("athletePost: needs a demo athlete with a photo")
            }

        case "videoPost":
            // The video composer over a clip made here (26 Nov 2026): the demo
            // athlete's photo panning on a stand-in court, a ball bouncing, 8 s
            // landscape — so the crop is exercised too. HOOPWISE_POST_SAMPLE=1
            // gives sample numbers. HOOPWISE_VIDEOPOST_EXPORT=1 exports every
            // overlay (9:16, or HOOPWISE_POST_ASPECT=portrait|square) to
            // video-<template>.mp4 and frames video-<template>-<t>.jpg in the
            // App Group Library/Caches, logging "videoPost …" to hoopwise.mac.
            if let student = dm.students.max(by: { ($0.profileImageData?.count ?? 0) < ($1.profileImageData?.count ?? 0) }) {
                // A drawn stand-in when the athlete has no photo (the Mac demo store).
                let face = student.profileImageData.flatMap(UIImage.init(data:))
                    ?? UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800)).image { ctx in
                        UIColor(red: 0.85, green: 0.62, blue: 0.48, alpha: 1).setFill()
                        ctx.cgContext.fillEllipse(in: CGRect(x: 200, y: 120, width: 400, height: 480))
                        UIColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1).setFill()
                        ctx.cgContext.fill(CGRect(x: 120, y: 600, width: 560, height: 200))
                    }
                VideoPostDebugHost(student: student, face: face)
            } else {
                missing("videoPost: needs a demo athlete")
            }

        case "athleteCard", "athleteCardExport":
            // The player card share sheet for an enrolled demo athlete with a
            // photo. =athleteCardExport also writes, 2 s later, the share image
            // (athlete-card.png) and the A3 sheet over that program's roster
            // (athlete-cards-a3.pdf) to the App Group Library/Caches.
            if let program = dm.programs.first(where: { !$0.enrolledStudentIds.isEmpty }),
               let student = dm.students.filter({ program.enrolledStudentIds.contains($0.id) })
                .max(by: { ($0.profileImageData?.count ?? 0) < ($1.profileImageData?.count ?? 0) }) {
                AthleteCardShareSheet(student: student)
                    .task {
                        guard shot == "athleteCardExport",
                              let caches = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.OKTO.SAMp")?
                                .appendingPathComponent("Library/Caches") else { return }
                        try? await Task.sleep(for: .seconds(2))
                        let card = dm.athleteCard(for: student, coachLine: "Big step forward with passing this month!")
                        try? AthleteCardRenderer.shareImage(card)?.pngData()?.write(to: caches.appendingPathComponent("athlete-card.png"))
                        try? AthleteCardRenderer.printSheet(dm.athleteCards(forProgram: program))?
                            .write(to: caches.appendingPathComponent("athlete-cards-a3.pdf"))
                        print("athleteCardExport: wrote \(caches.path)")
                    }
            } else {
                missing("athleteCard: no enrolled student")
            }

        case "quickPeep":
            // The quick peep as a session opens it, with its Edit button.
            // HOOPWISE_PEEP=photo: a student with a profile photo, from any
            // program (the Mac timing check).
            if ProcessInfo.processInfo.environment["HOOPWISE_PEEP"] == "photo",
               let student = dm.students.max(by: { ($0.profileImageData?.count ?? 0) < ($1.profileImageData?.count ?? 0) }) {
                StudentQuickPeepView(student: student, sessionId: nil)
            } else if ProcessInfo.processInfo.environment["HOOPWISE_PEEP"] == "games",
                      let student = dm.students.max(by: {
                          GameStatsReport.player($0.id, sessions: dm.sessionEvents).games
                              < GameStatsReport.player($1.id, sessions: dm.sessionEvents).games }) {
                // The athlete with the most games: the evaluation's evidence.
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
/// HOOPWISE_DEMO_READY_GAMES writes once per launch.
private enum DemoGamesOnce { static var done = false }
private enum DemoShootingOnce { static var done = false }
private enum DemoNotesOnce { static var done = false }
private enum DemoTrackedOnce {
    static var done = false
    static let drillId = UUID(uuidString: "7AC4ED00-0000-4000-8000-00000000BA55")!
    static let zonesDrillId = UUID(uuidString: "7AC4ED00-0000-4000-8000-0000000020E5")!
}

private struct LiveGameGalleryHost: View {
    /// Kept with the game: the scratch players are rebuilt (new ids) on
    /// every redraw of the shot.
    @State private var students: [Student]
    @State private var game: SessionGame

    init(students: [Student]) {
        _students = State(initialValue: students)
        let ids = students.map(\.id)
        // HOOPWISE_LIVE_BLACK=1: the home team plays in black (dark-mode check).
        let black = ProcessInfo.processInfo.environment["HOOPWISE_LIVE_BLACK"] == "1"
        var home = GameTeam(name: black ? "Black" : "Blue", colorHex: black ? "#1C1C1E" : "#007AFF",
                            playerIds: Array(ids.prefix(5)))
        var away = GameTeam(name: "White", colorHex: "#F5F5F5", playerIds: Array(ids.dropFirst(5).prefix(5)))
        // HOOPWISE_LIVE_BENCH=1: 3v3 — three on the floor, two on each bench.
        let benched = ProcessInfo.processInfo.environment["HOOPWISE_LIVE_BENCH"] == "1"
        if benched { home.starters = 3; away.starters = 3 }
        // HOOPWISE_LIVE_TEAMS=3: a third team waits and the round has not
        // started — the scoreboard offers "Who's up instead?".
        if ProcessInfo.processInfo.environment["HOOPWISE_LIVE_TEAMS"] == "3" {
            var yellow = GameTeam(name: "Yellow", colorHex: "#FFCC00", playerIds: Array(ids.dropFirst(10).prefix(5)))
            if benched { yellow.starters = 3 }
            var g = SessionGame(sessionId: UUID(), teams: [home, away, yellow], status: .ready)
            if benched { g.playersPerSide = 3 }
            g.activeTeamIds = [home.id, away.id]
            _game = State(initialValue: g)
            return
        }
        var g = SessionGame(sessionId: UUID(), teams: [home, away], status: .inProgress, startedAt: Date())
        if benched { g.playersPerSide = 3 }
        _game = State(initialValue: g)
    }

    @State private var played: [SessionGame] = []

    var body: some View {
        LiveGameScoringView(game: $game, students: students, allGamesInSession: played + [game], onSave: {},
                            onNextGame: { next in
                                played.append(game)
                                game = next
                            })
            .id(game.id)
    }

}

extension SheetGalleryDebug {
    /// One finished Black v White game: the first half of the players on
    /// Black, the rest on White, baskets logged with their passers.
    static func demoRecapGame(_ ids: [UUID]) -> SessionGame {
        let black = GameTeam(name: "Black", colorHex: "#1C1C1E", playerIds: Array(ids.prefix((ids.count + 1) / 2)))
        let white = GameTeam(name: "White", colorHex: "#F2F2F7", playerIds: Array(ids.dropFirst((ids.count + 1) / 2)))
        var game = SessionGame(sessionId: UUID(), gameNumber: 2, teams: [black, white])
        game.activeTeamIds = [black.id, white.id]
        // (scorer index, passer index or nil, points)
        let script: [(Int, Int?, Int)] = [(0, 1, 2), (1, 0, 2), (0, 1, 2), (2, nil, 2), (0, nil, 2), (1, 2, 2),
                                          (0, 1, 2), (2, 0, 2), (3, nil, 2), (4, 3, 2), (3, nil, 2)]
        for (s, p, n) in script where s < ids.count {
            let team = black.playerIds.contains(ids[s]) ? black.id : white.id
            GameStatAction(playerId: ids[s], teamId: team, kind: .points(n),
                           assistId: p.flatMap { $0 < ids.count ? ids[$0] : nil }).apply(to: &game)
        }
        for (i, kind) in [(1, GameStatAction.Kind.rebound), (1, .rebound), (2, .steal), (4, .rebound),
                          (4, .rebound), (5, .block), (0, .steal)] where i < ids.count {
            let team = black.playerIds.contains(ids[i]) ? black.id : white.id
            GameStatAction(playerId: ids[i], teamId: team, kind: kind).apply(to: &game)
        }
        game.status = .completed
        game.startedAt = fixedDate
        game.endedAt = fixedDate.addingTimeInterval(8 * 60)
        game.winningTeamId = game.score(for: black.id) >= game.score(for: white.id) ? black.id : white.id
        return game
    }

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
                var game = SessionGame(sessionId: s.id, gameNumber: g + 1, playerStats: lines,
                                       status: .completed)
                // A basket log behind the lines (the dashboard's chemistry):
                // the third player makes their own; the others are mostly set
                // up by the next one or two in the list.
                for line in lines {
                    let i = players.firstIndex(of: line.playerId) ?? 0
                    for j in 0..<(line.points / 2) {
                        var passer: UUID? = j % 3 == 2 || i == 2 ? nil : players[(i + 1 + j % 2) % players.count]
                        if passer == line.playerId { passer = nil }
                        game.baskets.append(GameBasket(scorerId: line.playerId, assisterId: passer,
                                                       points: 2, teamId: gid))
                    }
                }
                s.games.append(game)
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
        if var existing = dm.teams.first(where: { $0.name == teamName }) {
            if existing.playbook.focus.isEmpty, !existing.playbook.allPlays.isEmpty {
                existing.playbook.focus = existing.playbook.allPlays.map(\.ref.key)
                dm.updateTeam(existing)
            }
            team = existing
        } else {
            var made = Team(name: teamName, shortName: "HWK", colorHex: "#5856D6",
                            coachId: dm.staffCoaches.first?.id, coachName: dm.staffCoaches.first?.name,
                            homeVenue: dm.locations.first?.name, createdByCoachId: dm.loggedInCoachId)
            made.playerIds = athletes.map(\.id) + (dm.staffCoaches.first.map { [$0.id] } ?? [])
            var book = made.playbook
            let plays = (try? dm.modelContext.fetch(FetchDescriptor<JournalPlay>())) ?? []
            if let play = plays.first(where: { $0.starterKey != nil }) ?? plays.first {
                let ref = play.planRef
                book[.baseOffense].plays = [ref]
                book.focus = [ref.key]
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

/// Rates the library in batches of 30 and logs each rating as it lands.
struct LibraryRatingRun: View {
    @State private var done = 0
    @State private var status = "starting"
    private let activities = ActivityLibrary.shared.plannable

    var body: some View {
        VStack(spacing: 12) {
            Text("Rating the library").font(.title2.bold())
            Text("\(done) / \(activities.count)").font(.largeTitle.monospacedDigit())
            Text(status).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(40)
        .task { await run() }
    }

    private func run() async {
        let log = Logger(subsystem: "hoopwise.mac", category: "rater")
        guard let key = AnthropicKeyStore.key else { status = "no key"; log.notice("rate no key"); return }
        let env = ProcessInfo.processInfo.environment
        let only = env["HOOPWISE_RATE_ONLY"].flatMap(Int.init)
        var list = only.map { Array(activities.prefix($0)) } ?? activities
        // HOOPWISE_RATE_MISSING=1: only what the generated file lacks.
        if env["HOOPWISE_RATE_MISSING"] == "1" { list = list.filter { ActivityLibraryAttributes.ratings[$0.key] == nil } }
        let size = env["HOOPWISE_RATE_BATCH"].flatMap(Int.init) ?? 30
        let batches = stride(from: 0, to: list.count, by: size).map { Array(list[$0..<min($0 + size, list.count)]) }
        for batch in batches {
            let items = batch.enumerated().map { DrillRater.Item(ref: "r\($0.offset + 1)", line: DrillRater.line(ref: "r\($0.offset + 1)", $0.element)) }
            var attempt = 0
            while attempt < 3 {
                attempt += 1
                do {
                    let result = try await DrillRater.rate(items: items, key: key)
                    for (i, activity) in batch.enumerated() {
                        if let scores = result["r\(i + 1)"] {
                            log.notice("rate \(activity.key, privacy: .public)|\(scores.map(String.init).joined(separator: ","), privacy: .public)")
                        } else {
                            log.notice("rate missing \(activity.key, privacy: .public)")
                        }
                    }
                    done += batch.count
                    break
                } catch {
                    status = "retry: \(error.localizedDescription)"
                    log.notice("rate error \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        status = "finished"
        log.notice("rate finished \(done) of \(list.count)")
    }
}


/// DEBUG: a stand-in "action photo" and the export of every template.
/// (Inside the DEBUG block: it sat after it, so a release build — the
/// archive — did not compile.)
@MainActor
enum AthletePostDebug {
    static func standIn(_ face: UIImage) -> UIImage {
        let size = CGSize(width: 1600, height: 2000)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1).cgColor,
                          UIColor(red: 0.18, green: 0.14, blue: 0.12, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            let side: CGFloat = 1300
            face.draw(in: CGRect(x: (size.width - side) / 2, y: 260, width: side, height: side))
        }
    }

    /// The demo store has few games: sample numbers to judge a layout.
    static func sample(_ f: AthletePostFacts) -> AthletePostFacts {
        var facts = f
        let source = f.source
        facts.games = source == .lastGame ? 1 : 9
        let decimals = source != .lastGame
        let values: [(String, String, String, Double)] = [("pts", "PTS", "Points", 18.4), ("reb", "REB", "Rebounds", 7.2),
                                                          ("ast", "AST", "Assists", 5.1), ("stl", "STL", "Steals", 2.3), ("blk", "BLK", "Blocks", 0.8)]
        facts.stats = values.map { .init(key: $0.0, label: $0.1, word: $0.2, value: decimals ? $0.3 : $0.3.rounded(),
                                          text: decimals ? String(format: "%.1f", $0.3) : String(Int($0.3.rounded()))) }
        if decimals { facts.stats.append(.init(key: "gp", label: "GAMES", word: "Games", value: 9, text: "9")) }
        facts.subtitle = source == .lastGame ? "vs Riverside Eagles" : "9 games · per game"
        facts.eyebrow = source == .lastGame ? "GAME · 21 NOV" : (source == .month ? "NOVEMBER" : "ALL GAMES")
        return facts
    }

    static func export(student: Student, photo: UIImage, dm: DataManager) {
        guard let caches = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.OKTO.SAMp")?
            .appendingPathComponent("Library/Caches") else { return }
        let program = dm.programs.first { $0.id == student.programId }
        for source in AthletePostFacts.Source.allCases {
            var facts = AthletePostFacts.make(student: student, jersey: dm.player(for: student.id)?.jerseyNumber,
                                              colorHex: program?.colorHex ?? "#2A78D6", academy: ProgramGuideStore.academyName,
                                              sessions: dm.sessionEvents, source: source, chinese: false)
            if !facts.hasStats { facts = sample(facts) }
            for template in AthletePostTemplate.allCases {
                let aspect: AthletePostAspect = ProcessInfo.processInfo.environment["HOOPWISE_POST_ASPECT"] == "square" ? .square : .portrait
                let renderer = ImageRenderer(content: AthletePostCanvas(template: template, facts: facts, photo: photo,
                                                                        cutout: nil, aspect: aspect))
                renderer.scale = 1
                try? renderer.uiImage?.jpegData(compressionQuality: 0.85)?
                    .write(to: caches.appendingPathComponent("post-\(template.rawValue)-\(source.rawValue).jpg"))
            }
        }
    }
}

/// Makes the stand-in clip, then shows the composer over it (and exports).
struct VideoPostDebugHost: View {
    let student: Student
    let face: UIImage
    @EnvironmentObject var dataManager: DataManager
    @State private var clip: AVAsset?
    @State private var sheet: [(String, UIImage)] = []

    var body: some View {
        Group {
            if !sheet.isEmpty {
                // HOOPWISE_VIDEOPOST_SHEET=1: the exported frames laid out, to be
                // captured (the Mac's App Group cannot be read from outside).
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                        ForEach(sheet.indices, id: \.self) { i in
                            Image(uiImage: sheet[i].1).resizable().scaledToFit()
                        }
                    }
                }
                .background(.black)
            } else if let clip {
                VideoPostComposer(student: student, clip: .asset(clip))
            } else {
                ProgressView("Making a clip…")
            }
        }
        .task {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("videopost-source.mov")
            if !FileManager.default.fileExists(atPath: url.path) {
                await VideoPostDebug.makeClip(face: AthletePostDebug.standIn(face), to: url)
            }
            let asset = AVURLAsset(url: url)
            clip = asset
            if ProcessInfo.processInfo.environment["HOOPWISE_VIDEOPOST_EXPORT"] == "1" {
                let frames = await VideoPostDebug.exportAll(asset: asset, student: student, dm: dataManager)
                if ProcessInfo.processInfo.environment["HOOPWISE_VIDEOPOST_SHEET"] == "1" { sheet = frames }
            }
        }
    }
}

@MainActor
enum VideoPostDebug {
    static let log = Logger(subsystem: "hoopwise.mac", category: "videoPost")

    /// 8 s, 1920×1080, 30 fps: the photo slowly zooming, a ball bouncing.
    static func makeClip(face: UIImage, to url: URL) async {
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let size = CGSize(width: 1920, height: 1080)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = 240
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try? await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { break }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { break }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                let t = Double(i) / Double(frames)
                ctx.setFillColor(UIColor(red: 0.16, green: 0.12, blue: 0.1, alpha: 1).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                if let cg = face.cgImage {
                    let zoom = 1.0 + 0.12 * t
                    let h = size.height * 1.05 * zoom, w = h * 0.8
                    ctx.draw(cg, in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
                }
                // A ball crossing and bouncing.
                let bx = 200 + (size.width - 400) * t
                let by = 160 + abs(sin(t * .pi * 4)) * 600
                ctx.setFillColor(UIColor.orange.cgColor)
                ctx.fillEllipse(in: CGRect(x: bx - 50, y: by - 50, width: 100, height: 100))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        log.log("videoPost clip \(writer.status == .completed ? "made" : "failed", privacy: .public)")
    }

    @discardableResult
    static func exportAll(asset: AVAsset, student: Student, dm: DataManager) async -> [(String, UIImage)] {
        var frames: [(String, UIImage)] = []
        guard let caches = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.OKTO.SAMp")?
            .appendingPathComponent("Library/Caches") else { return frames }
        let env = ProcessInfo.processInfo.environment
        let aspect: VideoPostAspect = env["HOOPWISE_POST_ASPECT"] == "square" ? .square : (env["HOOPWISE_POST_ASPECT"] == "portrait" ? .portrait : .story)
        let program = dm.programs.first { $0.id == student.programId }
        var facts = AthletePostFacts.make(student: student, jersey: dm.player(for: student.id)?.jerseyNumber,
                                          colorHex: program?.colorHex ?? "#2A78D6", academy: ProgramGuideStore.academyName,
                                          sessions: dm.sessionEvents, source: .month, chinese: false)
        if !facts.hasStats { facts = AthletePostDebug.sample(facts) }
        if facts.jersey == nil { facts.jersey = 8 }
        guard let cut = try? await VideoPost.cut(asset, start: 0, length: 8, aspect: aspect) else {
            log.log("videoPost cut failed"); return frames
        }
        let only = env["HOOPWISE_VIDEOPOST_ONLY"]?.split(separator: ",").map(String.init)
        for template in VideoOverlayTemplate.allCases where only?.contains(template.rawValue) ?? true {
            let started = Date()
            let layer = VideoOverlay.layer(template, facts: facts, size: cut.renderSize, duration: cut.duration)
            do {
                let url = try await VideoPost.export(cut, overlay: layer, name: "video-\(template.rawValue)")
                let out = caches.appendingPathComponent("video-\(template.rawValue).mp4")
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.copyItem(at: url, to: out)
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                for t in [0.3, 1.0, 1.6, 2.6, 4.5, 7.6] {
                    if let (img, _) = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)) {
                        frames.append(("\(template.rawValue) \(t)", UIImage(cgImage: img)))
                        try? UIImage(cgImage: img).jpegData(compressionQuality: 0.8)?
                            .write(to: caches.appendingPathComponent("video-\(template.rawValue)-\(t).jpg"))
                    }
                }
                log.log("videoPost \(template.rawValue, privacy: .public) exported in \(Date().timeIntervalSince(started), privacy: .public) s")
            } catch {
                log.log("videoPost \(template.rawValue, privacy: .public) failed \(error.localizedDescription, privacy: .public)")
            }
        }
        log.log("videoPost done")
        return frames
    }
}
#endif
