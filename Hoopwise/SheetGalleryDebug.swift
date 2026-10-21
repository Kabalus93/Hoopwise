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
            .sheet(isPresented: .constant(true)) {
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

        case "drillsLibrary":
            // The activity-library drills page, as the Hub pushes it.
            NavigationStack { DrillsLibraryView() }

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
            if let program = dm.programs.first,
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
        let home = GameTeam(name: "Blue", colorHex: "#007AFF", playerIds: Array(ids.prefix(5)))
        let away = GameTeam(name: "White", colorHex: "#F5F5F5", playerIds: Array(ids.dropFirst(5).prefix(5)))
        _game = State(initialValue: SessionGame(sessionId: UUID(), teams: [home, away],
                                                status: .inProgress, startedAt: Date()))
    }

    var body: some View {
        LiveGameScoringView(game: $game, students: students, allGamesInSession: [game], onSave: {})
    }
}
#endif
