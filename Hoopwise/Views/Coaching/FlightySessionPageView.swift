import SwiftUI
import Combine
import MapKit
import os
#if os(iOS)
import UIKit
import AudioToolbox
#endif

// MARK: - Flighty-Styled Session Page View
/// A redesigned session detail page with Flighty's dark, confident aesthetic
/// Preserves all functionality from SessionPageView with updated styling
struct FlightySessionPageView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @State var session: SessionEvent
    let accessMode: SessionAccessMode

    var embeddedInSplit: Bool = false
    
    @State private var selectedTab = 1  // Default to Attendance tab

    /// A team practice lands on Plan (the team's focus is there); every
    /// other session on Attendance.
    init(session: SessionEvent, accessMode: SessionAccessMode, embeddedInSplit: Bool = false, initialTab: Int? = nil) {
        _session = State(initialValue: session)
        self.accessMode = accessMode
        self.embeddedInSplit = embeddedInSplit
        _selectedTab = State(initialValue: initialTab ?? (session.sessionType == .teamPractice ? 0 : 1))
    }
    /// Measured roster row heights; sizes the non-scrolling attendance List.
    @State private var rosterRowHeights: [UUID: CGFloat] = [:]
    @Environment(\.horizontalSizeClass) private var pageSizeClass
    @Environment(\.displayScale) private var displayScale
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingSessionVersions = false
    @State private var showingSkipSheet = false
    @State private var skipReason: SkipReason = .holiday
    /// The student whose profile photo the leading swipe is retaking.
    @State private var studentForPhoto: Student?
    /// Marks shown on screen but not written yet: a quick run of taps is
    /// saved as ONE write (`flushAttendanceMarks`), not one full save and
    /// reload per tap.
    @State private var pendingMarks: [UUID: AttendanceMark] = [:]
    @State private var markFlush: Task<Void, Never>?
    @State private var confirmingAllPresent = false
    @Environment(\.scenePhase) private var scenePhase
    /// What the plan generator read and decided on its last run here.
    @State private var planRationale: DrillPlanGenerator.PlanRationale?
    @State private var selectedStudentForPeep: Student?
    @State private var showingDrillPicker = false
    @State private var showingStudentPicker = false
    @State private var isExportingCards = false
    @State private var exportedCardsURL: URL?
    @State private var showingCardShareSheet = false
    @State private var cardExportError: String?
    @State private var drillPickerSection: CurriculumSection = .warmup
    /// Set when the plan dashboard's "Find drills" opens the picker.
    @State private var pickerAttribute: DrillAttribute?
    @State private var selectedDrillForDetail: DrillItem?
    /// Open media viewer keyed to a (drillId, index) pair so the cover
    /// rebuilds correctly when the user taps different tiles.
    @State private var plannerMediaViewer: PlannerMediaViewerTarget?
    /// A drill drawing opened from the plan: a popup with its step player.
    @State private var plannerDrawing: DrillMedia?

    fileprivate struct PlannerMediaViewerTarget: Identifiable, Hashable {
        let drillId: UUID
        let index: Int
        var id: String { "\(drillId.uuidString)#\(index)" }
    }

    @State private var showingSmartDrillPicker = false
    @State private var showingManageStudents = false
    @State private var showingInlineDrillInputFor: CurriculumSection?
    @State private var showingSessionPhotoCapture = false
    /// Which wording the roll-call photo sheet uses: the completion prompt,
    /// or the coach adding a photo by hand.
    @State private var rollCallReason: RollCallPhotoSheet.Reason = .manual
    @State private var showingSessionPhotoFullScreen = false
    @State private var isExportingSessionPhoto = false
    @State private var sessionPhotoExportToast: SessionPhotoExportToast?
    @State private var inlineDrillTextBySection: [CurriculumSection: String] = [:]
    @State private var notesEditorTarget: NotesEditorTarget = .session
    @FocusState private var focusedNotesEditor: NotesEditorTarget?
    /// Notes tab: this session's reminders (the default, on the left) or
    /// the notebook (14 Nov 2026 — Reminders replaced the Reflection tab).
    @State private var notesPane: NotesPane = .reminders
    /// The Notes tab's width: from 1100 pt (a Mac window, a 13" iPad in
    /// landscape) Reminders and Notes sit side by side, no switch.
    @State private var notesTabWidth: CGFloat = 0
    /// DEBUG HOOPWISE_NOTES_WIDE_AT=<pt> moves the threshold (checking the
    /// wide layout on an iPad simulator in portrait).
    private var notesWideAt: CGFloat {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["HOOPWISE_NOTES_WIDE_AT"].flatMap(Double.init) { return CGFloat(v) }
        #endif
        return 1100
    }
    @State private var quickReminderText = ""
    @State private var quickReminderDue: QuickReminderDue = .beforeNextClass
    @State private var editingSessionReminder: Reminder?
    @State private var showDoneReminders = false
    @State private var quickReminderCustomDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var quickReminderPriority: ReminderPriority = .medium
    @State private var quickReminderStudents: Set<UUID> = []
    @State private var quickReminderNote = ""
    @State private var showQuickReminderNote = false
    @FocusState private var quickReminderFocused: Bool
    
    // Plan tab drill management
    @State private var expandedDrillId: UUID?
    @State private var showAddOptionsFor: CurriculumSection?
    @State private var draggingDrillId: UUID?
    @AppStorage("recentlyUsedDrillIds") private var recentlyUsedDrillIdsData: Data = Data()
    
    
    // Computed properties
    var parentProgram: Program? {
        guard let programId = session.programId else { return nil }
        return dataManager.programs.first { $0.id == programId }
    }

    private func addInlineTextDrill(section: CurriculumSection) {
        let text = (inlineDrillTextBySection[section] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        createAndAttachDrill(
            title: text,
            steps: [],
            details: "",
            duration: section == .warmup ? 8 : 12,
            difficulty: .beginner,
            section: section,
            visibility: .privateOnly,
            quickNote: true
        )

        inlineDrillTextBySection[section] = ""
        showingInlineDrillInputFor = nil
    }
    
    var parentPhase: MicroCycle? {
        guard let microCycleId = session.microCycleId else { return nil }
        return dataManager.microCycles.first { $0.id == microCycleId }
    }
    
    /// Who this session is for: `AttendanceMath.expectedIds` (the session's
    /// own roster, else its program's enrolment — the ONE roster definition),
    /// plus anyone already marked on it, so a marked athlete never vanishes
    /// from the page. It read the program's enrolment alone, so a session
    /// whose roster differed (a second private client added to one lesson)
    /// counted 2 expected and listed 1 (November 2026).
    var enrolledStudents: [Student] {
        var ids = Set(AttendanceMath.expectedIds(of: session, programs: dataManager.programs))
        ids.formUnion(session.actualAttendeeIds)
        ids.formUnion(session.excusedAbsences)
        ids.formUnion(session.unexcusedAbsences)
        return dataManager.students.filter { ids.contains($0.id) }
    }
    
    /// The status bar / Dynamic Island inset of a pushed page (0 in a sheet).
    @State private var windowSafeTop: CGFloat = 0
    /// Back and ⋯ sit just under the status bar on a full page, 30 pt into
    /// the card in a sheet.
    private var floatingButtonsTop: CGFloat { windowSafeTop > 0 ? windowSafeTop + 4 : 30 }

    var programColor: Color {
        parentProgram.map { Color(hex: $0.colorHex) } ?? .blue
    }

    private var currentCoachId: UUID {
        dataManager.loggedInCoachId ?? dataManager.coach.id
    }
    
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .top) {
                #if os(iOS)
                Group {
                    if selectedTab == 1 {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                heroCard(safeAreaTop: windowSafeTop)
                                primarySessionCTA
                                tabSelector
                                    .frame(maxWidth: .infinity)
                                attendanceStats
                                attendanceTab
                            }
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                heroCard(safeAreaTop: windowSafeTop)
                                primarySessionCTA
                                tabSelector
                                    .frame(maxWidth: .infinity)
                                tabContent
                            }
                        }
                    }
                }
                #else
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroCard(safeAreaTop: windowSafeTop)
                        primarySessionCTA
                        tabSelector
                            .frame(maxWidth: .infinity)
                        tabContent
                    }
                }
                #endif
                
                // Floating navigation buttons overlay (iOS 26 glass)
                HStack {
                    if !embeddedInSplit {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background {
                                    Circle().fill(.black.opacity(0.35))
                                }
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: embeddedInSplit)
                    }

                    Spacer()

                    Menu {
                        if accessMode.canEdit {
                            Button(action: { showingEditSheet = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "编辑详情" : "Edit Details", systemImage: "pencil")
                            }

                            Button(action: { showingManageStudents = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "管理学员" : "Manage Students", systemImage: "person.2.badge.gearshape")
                            }
                        }

                        allPresentMenuItem

                        Button(action: { exportPlayerCards() }) {
                            Label(
                                LocalizationManager.shared.currentLanguage == .chinese ? "打印球员卡（A3）" : "Print Player Cards (A3)",
                                systemImage: "rectangle.stack.badge.person.crop"
                            )
                        }
                        .disabled(isExportingCards)

                        if session.status == .scheduled {
                            // No "Start Session": sessions start on their own at
                            // the scheduled time (SessionStatusMonitor). A past
                            // session that never ran can be marked completed.
                            if session.endTime < Date() {
                                Button(action: completeSession) {
                                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "标记已完成" : "Mark Completed", systemImage: "checkmark.circle.fill")
                                }
                            }

                            Button(action: { showingSkipSheet = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "跳过课程" : "Skip Session", systemImage: "forward.fill")
                            }
                        }
                        
                        if session.status == .inProgress {
                            Button(action: completeSession) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "完成课程" : "Complete Session", systemImage: "checkmark.circle.fill")
                            }
                        }

                        // Reset to scheduled — escape hatch for sessions that
                        // were marked complete/in-progress/skipped/cancelled by
                        // mistake (or by older auto-status logic). Only shown
                        // when the session isn't already scheduled.
                        if session.status != .scheduled && accessMode.canEdit {
                            Divider()
                            Button(action: resetToScheduled) {
                                Label(
                                    LocalizationManager.shared.currentLanguage == .chinese ? "标记为已安排" : "Mark Scheduled",
                                    systemImage: "calendar.badge.clock"
                                )
                            }
                        }

                        // Recovery: every attendance mark, game change and
                        // overwrite keeps a copy (SessionVersionsSheet).
                        Button(action: { showingSessionVersions = true }) {
                            Label(LocalizationManager.shared.currentLanguage == .chinese ? "恢复早前版本" : "Restore Earlier Version",
                                  systemImage: "clock.arrow.circlepath")
                        }

                        // Cancel session - available for any status except already cancelled
                        if session.status != .cancelled {
                            Divider()
                            Button(role: .destructive, action: { showingCancelConfirmation = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "取消课程" : "Cancel Session", systemImage: "xmark.circle.fill")
                            }
                        }
                        
                        if accessMode.canDelete {
                            Divider()
                            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "删除课程" : "Delete Session", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle().fill(.black.opacity(0.35))
                            }
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .accessibilityIdentifier("session.more")
                }
                .padding(.horizontal, 16)
                .padding(.top, floatingButtonsTop)
            }
        }
        // No iOS 26 scroll-edge bar at the top: it drew a grey band beside
        // the Dynamic Island over the hero's blue on a pushed page.
        .scrollEdgeEffectHidden(true, for: .top)
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .background { allPresentConfirmation(Color.clear) }
        // The REAL top inset (status bar / Dynamic Island): the GeometryReader
        // above sits inside ignoresSafeArea and always reads 0, which put Back
        // and ⋯ in the status bar on a pushed page. A sheet reads 0 here.
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { windowSafeTop = g.safeAreaInsets.top }
                    .onChange(of: g.safeAreaInsets.top) { _, top in windowSafeTop = top }
            }
        }
        // `.navigationBarHidden(true)` (the legacy API) disables the
        // interactive edge-swipe back gesture. The modern equivalent hides
        // the bar visually while keeping the swipe-to-pop gesture alive.
        .toolbar(.hidden, for: .navigationBar)
        // Belt-and-braces: even with `.toolbar(.hidden, for: .navigationBar)`
        // SwiftUI sometimes leaves the pop gesture's delegate in a state
        // that blocks the edge swipe. This UIKit-side helper resets it.
        #if os(iOS)
        .background(EnableSwipeBackGesture().frame(width: 0, height: 0).allowsHitTesting(false))
        #endif
        .sheet(isPresented: $showingEditSheet) {
            EditSessionDetailsView(session: $session, onSave: saveSession)
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除课程？" : "Delete Session?", isPresented: $showingDeleteConfirmation) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) { deleteSession() }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "此操作无法撤销。" : "This action cannot be undone.")
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "取消课程？" : "Cancel Session?", isPresented: $showingCancelConfirmation) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "返回" : "Go Back", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消课程" : "Cancel Session", role: .destructive) { cancelSession() }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "此课程将被标记为已取消。" : "This session will be marked as cancelled.")
        }
        .makeUpOfferAlert()
        .sheet(isPresented: $showingSessionVersions) {
            SessionVersionsSheet(sessionId: session.id, students: dataManager.students)
        }
        .sheet(isPresented: $showingSkipSheet) {
            SkipSessionSheet(reason: $skipReason) {
                skipSession(reason: skipReason)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingDrillPicker) {
            DrillPickerView(selectedDrillIds: drillIdsBinding(for: drillPickerSection)) {
                saveSession()
            }
        }
        .sheet(isPresented: $showingStudentPicker) {
            SessionStudentPickerView(
                students: enrolledStudents,
                selectedStudentId: $session.manOfTheMatchId
            ) {
                saveSession()
            }
        }
        .sheet(isPresented: $showingManageStudents) {
            ManageSessionStudentsSheet(session: $session) {
                saveSession()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingCardShareSheet) {
            if let url = exportedCardsURL {
                ShareSheet(items: [url])
            }
        }
        .alert(
            LocalizationManager.shared.currentLanguage == .chinese ? "导出失败" : "Export Failed",
            isPresented: Binding(get: { cardExportError != nil }, set: { if !$0 { cardExportError = nil } })
        ) {
            Button("OK", role: .cancel) { cardExportError = nil }
        } message: {
            Text(cardExportError ?? "")
        }
        .overlay {
            if isExportingCards {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "正在生成球员卡…" : "Generating cards…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(14)
                }
            }
        }
        .overlay(alignment: .top) {
            if let toast = sessionPhotoExportToast {
                SessionPhotoExportToastView(toast: toast, isChinese: isChinese)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sessionPhotoExportToast)
        #endif
        // Keep `@State session` in sync with the canonical record. Without
        // this, opening the same session a second time from a different
        // entry point (calendar, dashboard tile, …) leaves the local
        // snapshot frozen at view-init time — that's the stale-snapshot
        // path that wiped games + the attendance photo for one coach.
        .task { refreshSessionFromStore() }
        .onChange(of: dataManager.sessionEvents) { _, _ in
            refreshSessionFromStore()
        }
        .onDisappear { flushAttendanceMarks() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flushAttendanceMarks() }
        }
    }

    /// Pulls the latest `SessionEvent` out of the dataManager cache and
    /// merges its fields onto our local `@State session` *non-destructively*:
    ///   - structural fields (games, photo, attendance, curriculum, etc.)
    ///     are always overwritten when the store is newer.
    ///   - text fields (`notes`, `coachNotes`) are skipped while their
    ///     respective editor is focused, so the user's in-progress typing
    ///     isn't clobbered by a CloudKit sync arriving mid-sentence.
    private func refreshSessionFromStore() {
        guard let fresh = dataManager.sessionEvents.first(where: { $0.id == session.id }) else {
            return
        }
        // Marks tapped but not yet written must not be undone by a refresh
        // arriving in the meantime.
        defer { for (id, mark) in pendingMarks { applyMarkLocally(mark, to: id) } }
        // Live fields ALWAYS follow the store: every write to them is
        // immediate and field-level, so the store is never behind this copy.
        // (Gating them on updatedAt let this copy keep showing an empty game
        // list after the store had the games.)
        if session.games != fresh.games { session.games = fresh.games }
        if session.actualAttendeeIds != fresh.actualAttendeeIds { session.actualAttendeeIds = fresh.actualAttendeeIds }
        if session.excusedAbsences != fresh.excusedAbsences { session.excusedAbsences = fresh.excusedAbsences }
        if session.unexcusedAbsences != fresh.unexcusedAbsences { session.unexcusedAbsences = fresh.unexcusedAbsences }
        if session.attendancePhotoPath != fresh.attendancePhotoPath { session.attendancePhotoPath = fresh.attendancePhotoPath }

        // Bail early when nothing else has changed downstream.
        guard fresh.updatedAt > session.updatedAt else { return }

        session.title = fresh.title
        session.date = fresh.date
        session.startTime = fresh.startTime
        session.endTime = fresh.endTime
        session.location = fresh.location
        session.status = fresh.status
        session.microCycleId = fresh.microCycleId
        session.programId = fresh.programId
        session.sessionType = fresh.sessionType
        session.curriculum = fresh.curriculum
        session.attendeeIds = fresh.attendeeIds
        session.actualAttendeeIds = fresh.actualAttendeeIds
        session.excusedAbsences = fresh.excusedAbsences
        session.attendancePhotoPath = fresh.attendancePhotoPath
        session.developmentFocus = fresh.developmentFocus
        session.manOfTheMatchId = fresh.manOfTheMatchId
        session.drillsCompleted = fresh.drillsCompleted
        session.rating = fresh.rating
        session.games = fresh.games
        session.headerImageURL = fresh.headerImageURL

        if focusedNotesEditor != .session {
            session.notes = fresh.notes
        }
        if focusedNotesEditor != .reflections {
            session.coachNotes = fresh.coachNotes
        }
        session.updatedAt = fresh.updatedAt
    }

    /// The A3 print sheet of player cards (AthleteCardRenderer) for the
    /// session's roster — who it expects plus anyone marked; its stored roster
    /// is often empty, so it used to export nobody.
    @MainActor
    private func exportPlayerCards() {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        isExportingCards = true
        Task { @MainActor in
            defer { isExportingCards = false }
            let cards = dataManager.athleteCards(forSession: session)
            guard !cards.isEmpty else {
                cardExportError = isChinese ? "没有可导出的球员" : "No players to export"
                return
            }
            guard let pdfData = AthleteCardRenderer.printSheet(cards) else {
                cardExportError = isChinese ? "生成 PDF 失败" : "Failed to generate PDF"
                return
            }
            let month = AthleteCardMonth.label(Date(), chinese: isChinese)
            let safeName = session.title.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName) - Player cards \(month) - A3.pdf")
            do {
                try pdfData.write(to: url, options: .atomic)
                exportedCardsURL = url
                showingCardShareSheet = true
            } catch {
                cardExportError = error.localizedDescription
            }
        }
    }

    private func drillIdsBinding(for section: CurriculumSection) -> Binding<[UUID]> {
        switch section {
        case .warmup: return $session.curriculum.warmupDrillIds
        case .main: return $session.curriculum.skillDrillIds
        case .cooldown: return $session.curriculum.gameDrillIds
        }
    }
    
    private func scheduleItem(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statusColor: Color {
        switch session.status {
        case .scheduled: return .blue
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .red
        case .skipped: return .gray
        }
    }
    
    // MARK: - Hero Card (Extends under Dynamic Island)
    private func heroCard(safeAreaTop: CGFloat) -> some View {
        // The content starts BELOW the floating back / ⋯ buttons (40 pt at
        // safe area + 30) and the card grows to fit it, so nothing ever sits
        // under them (Luther, 12 Nov 2026: the status tag ran under Back).
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(session.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .opacity(session.status == .cancelled ? 0.6 : 1)
                .strikethrough(session.status == .cancelled)
                .lineLimit(2)

            // Location
            if let location = session.location, !location.isEmpty {
                Label {
                    Text(location)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.9))
            }

            // Phase info
            if let phase = parentPhase {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "阶段 \(phase.phaseNumber): \(phase.title)" : "Phase \(phase.phaseNumber): \(phase.title)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Status, format, date, time — one row that wraps instead of
            // running off the edge on a phone.
            FlowLayout(spacing: 8) {
                heroStatusPill
                FormatBadge(format: dataManager.sessionFormat(session), size: .compact)
                heroMetaPill(
                    icon: "calendar",
                    value: session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                )
                heroMetaPill(
                    icon: "clock",
                    value: "\(session.startTime.formatted(date: .omitted, time: .shortened)) – \(session.endTime.formatted(date: .omitted, time: .shortened))"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, floatingButtonsTop + 52)
        .frame(maxWidth: .infinity, minHeight: 200 + safeAreaTop, alignment: .bottomLeading)
        .background {
            ZStack {
                heroMapBackground
                // Dark gradient overlay for text visibility
                Rectangle()
                    .fill(Color.black.opacity(0.18))
                    .blendMode(.multiply)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.65),
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipped()
    }

    /// The session's status as a pill in the meta row, in its colour.
    private var heroStatusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .symbolEffect(.pulse, options: .repeating, isActive: session.status == .inProgress)
            Text(session.status.displayName)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(statusColor.opacity(0.28))
        }
        .glassEffect(.regular, in: Capsule())
    }
    
    // MARK: - Hero Background
    /// The program's colour with court lines (CardCourtBackground). Session
    /// headers used to be random Unsplash photos — third-party content App
    /// Review rejected (4.1(a), October 2026); stored URLs are ignored.
    private var heroMapBackground: some View {
        CardCourtBackground(color: programColor, style: CourtArtStyle(session.sessionType))
    }
    
    
    // MARK: - Schedule Bar (Scrollable)
    private var scheduleBar: some View {
        HStack(spacing: 0) {
            scheduleItem(icon: "calendar", value: session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 30)
            
            scheduleItem(icon: "clock", value: "\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
    }

    private func heroMetaPill(icon: String, value: String) -> some View {
        Label {
            Text(value)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        // Dark scrim under the glass so white text stays readable on
        // bright header images (sky, light hardwood, etc.). Mirrors the
        // pattern used by the floating nav buttons earlier in this file —
        // without it, `.glassEffect(.regular)` picks up the underlying
        // photo and the pill can render near-white-on-white.
        .background {
            Capsule().fill(.black.opacity(0.35))
        }
        .glassEffect(.regular, in: Capsule())
    }
    
    // MARK: - Tab Content
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            planTab
        case 1:
            attendanceTab
        #if os(iOS)
        case 2:
            gamesTab
        case 3:
            notesTab
        #else
        case 2:
            notesTab
        #endif
        default:
            planTab
        }
    }
    
    // MARK: - Primary Session CTA (Apple Fitness "Start Workout" pattern)
    @ViewBuilder
    private var primarySessionCTA: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        // A scheduled session whose end time is already in the past can't be
        // "started" — the coach was filling in history. Offer Complete /
        // Cancel instead so the SessionEventStatus lands somewhere truthful.
        let isPast = session.endTime < Date()

        switch session.status {
        case .scheduled where isPast:
            if accessMode.canEdit {
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        cancelSession()
                    } label: {
                        Label(isChinese ? "取消" : "Cancel", systemImage: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .controlSize(.large)
                    .tint(.red)

                    Button {
                        completeSession()
                    } label: {
                        Label(isChinese ? "标记已完成" : "Mark Completed", systemImage: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .controlSize(.large)
                    .tint(.green)
                    .sensoryFeedback(.success, trigger: session.status == .completed)
                }
                // One size for both (Luther, November 2026): "Mark Completed"
                // wrapped to two lines and stood taller than Cancel. One line
                // each, shrinking slightly before it would wrap.
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        case .scheduled:
            // Upcoming: nothing to press. It starts by itself at its time.
            EmptyView()
        case .inProgress:
            if accessMode.canEdit {
                Button {
                    completeSession()
                } label: {
                    Label(isChinese ? "完成课程" : "Complete Session", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .tint(.green)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .sensoryFeedback(.success, trigger: session.status == .completed)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Tab Selector (native segmented)
    @ViewBuilder
    private var tabSelector: some View {
        #if targetEnvironment(macCatalyst)
        macTabSelector
        #else
        systemTabSelector
        #endif
    }

    #if targetEnvironment(macCatalyst)
    @Namespace private var macTabPill

    /// The Mac's tab bar (14 Nov 2026, Luther: "increase the height … mac
    /// only"): a segmented control cannot be made taller on Catalyst, so the
    /// same look is drawn — a capsule track, the selected tab a sliding pill —
    /// at 44 pt with larger labels.
    private var macTabSelector: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let tabs = [isChinese ? "计划" : "Plan", isChinese ? "出勤" : "Attend",
                    isChinese ? "比赛" : "Games", isChinese ? "笔记" : "Notes"]
        return HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, title in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selectedTab = i }
                } label: {
                    Text(title)
                        .font(.body.weight(selectedTab == i ? .semibold : .medium))
                        .foregroundStyle(selectedTab == i ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selectedTab == i {
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                                    .overlay(Capsule().fill(.white.opacity(0.06)))
                                    .matchedGeometryEffect(id: "pill", in: macTabPill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == i ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(height: 44)
        .background(Capsule().fill(Color(.secondarySystemFill)))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
    #endif

    private var systemTabSelector: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Picker("Tab", selection: $selectedTab) {
            Text(isChinese ? "计划" : "Plan").tag(0)
            Text(isChinese ? "出勤" : "Attend").tag(1)
            #if os(iOS)
            Text(isChinese ? "比赛" : "Games").tag(2)
            Text(isChinese ? "笔记" : "Notes").tag(3)
            #else
            Text(isChinese ? "笔记" : "Notes").tag(2)
            #endif
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
    
    // MARK: - Plan Tab
    /// A team practice's target: the skills its team's focus plays need.
    private var teamFocusSkills: [String] {
        guard let teamId = session.curriculum.teamId,
              let team = dataManager.teams.first(where: { $0.id == teamId }) else { return [] }
        let book = team.playbook
        return book.skills(in: book.focusPlays)
    }

    private var planTab: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if let teamId = session.curriculum.teamId {
                    // A team practice plans from its TEAM (focus plays, their
                    // roles' drills), not from age · level · phase.
                    SessionTeamPlanCard(
                        teamId: teamId,
                        rosterIds: AttendanceMath.expectedIds(of: session, programs: dataManager.programs) + session.curriculum.coachIds,
                        durationMinutes: session.durationMinutes,
                        canEdit: accessMode.canEdit,
                        curriculum: $session.curriculum,
                        onChange: saveSession)
                } else if accessMode.canEdit {
                    generatePlanButton
                }

                // What the plan trains vs what it should (November 2026).
                SessionPlanDashboard(
                    curriculum: session.curriculum,
                    drills: dataManager.drills,
                    teams: dataManager.teams,
                    phaseFocus: parentPhase?.focus ?? [],
                    skillTargets: parentProgram?.skillTargets,
                    teamSkills: teamFocusSkills,
                    groupRatings: DrillPlanGenerator.groupRatings(
                        students: AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
                            .compactMap { id in dataManager.students.first { $0.id == id } },
                        players: dataManager.players),
                    canEdit: accessMode.canEdit,
                    onFind: { axis in
                        drillPickerSection = .main
                        pickerAttribute = axis
                        showingSmartDrillPicker = true
                    })

                // Warmup
                curriculumSection(
                    title: isChinese ? "热身" : "WARMUP",
                    icon: "flame.fill",
                    color: Color.accentColor,
                    drillIds: session.curriculum.warmupDrillIds,
                    minutes: session.curriculum.warmupMinutes,
                    section: .warmup
                )

                // Skills
                curriculumSection(
                    title: isChinese ? "技能" : "SKILLS",
                    icon: "figure.basketball",
                    color: Color.accentColor,
                    drillIds: session.curriculum.skillDrillIds,
                    minutes: session.curriculum.skillsMinutes,
                    section: .main
                )

                // Plays from the Hub's library this session runs.
                SessionPlanPlaysSection(
                    plays: $session.curriculum.plays,
                    canEdit: accessMode.canEdit,
                    color: Color.accentColor,
                    onChange: saveSession
                )

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .sheet(item: $selectedDrillForDetail) { drill in
            NavigationStack {
                DrillDetailView(drill: drill)
                    .environmentObject(dataManager)
            }
        }
        .fullScreenCover(item: $plannerMediaViewer) { target in
            // Resolve the drill out of the latest dataManager state so the
            // viewer reflects any media edits made elsewhere while planning.
            if let drill = dataManager.drills.first(where: { $0.id == target.drillId }) {
                DrillMediaViewer(media: DrillDrawingMedia.viewerMedia(drill.media), initialIndex: target.index)
            } else {
                EmptyView()
            }
        }
        .sheet(item: $plannerDrawing) { media in
            if let drawing = DrillDrawingMedia.drawing(for: media) {
                DrillDrawingSheet(title: dataManager.drills.first { $0.id == media.drillId }?.localizedName ?? "",
                                  drawing: drawing)
            }
        }
        .sheet(isPresented: $showingSmartDrillPicker) {
            SmartDrillPickerSheet(
                session: $session,
                section: drillPickerSection,
                program: parentProgram,
                phase: parentPhase,
                students: enrolledStudents,
                allDrills: dataManager.drills,
                currentCoachId: currentCoachId,
                onSave: saveSession,
                attribute: pickerAttribute
            )
        }
    }
    
    // MARK: - Generate Plan Button (auto-fill / regenerate via DrillPlanGenerator)

    /// Pinned at the top of the Plan tab. When the curriculum is empty it
    /// reads "Generate Plan"; once populated it shifts to the discreet
    /// "Regenerate" so a fresh mix is one tap away. Runs synchronously — the
    /// generator scores deterministically against the in-memory drill cache,
    /// finishes in milliseconds.
    @ViewBuilder
    private var generatePlanButton: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let isEmpty = session.curriculum.totalDrillCount == 0

        if isEmpty {
            Button {
                generatePlanFromLibrary()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(isChinese ? "自动生成计划" : "Generate Plan")
                    Spacer()
                    Text(isChinese ? "基于年龄/水平/阶段" : "Age · Level · Phase")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: session.curriculum.totalDrillCount)
        } else {
            HStack(alignment: .firstTextBaseline) {
                // What the engine read and decided — shown after it ran.
                if let rationale = planRationale {
                    Label(rationale.summary, systemImage: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan.rationale")
                }
                Spacer()
                Button {
                    generatePlanFromLibrary()
                } label: {
                    Label(isChinese ? "重新生成" : "Regenerate",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.accentColor)
                .sensoryFeedback(.impact(weight: .light), trigger: session.curriculum.totalDrillCount)
            }
            .padding(.horizontal, 4)
        }
    }

    private func generatePlanFromLibrary() {
        // Every earlier session of this program: the engine reads its plans
        // to decide what to review and what to introduce.
        let history: [SessionEvent] = {
            guard let pid = session.programId else { return [] }
            return dataManager.sessionEvents.filter { $0.programId == pid && $0.id != session.id }
        }()
        let players = enrolledStudents.compactMap { dataManager.player(for: $0.id) }

        let ctx = DrillPlanGenerator.Context(
            session: session,
            program: parentProgram,
            phase: parentPhase,
            enrolledStudents: enrolledStudents,
            players: players,
            allDrills: dataManager.drills,
            programHistory: history
        )

        let result = DrillPlanGenerator.generatePlan(in: ctx)
        // Preserve the coach's hand-typed notes and chosen plays.
        var merged = result.curriculum
        if let existingNotes = session.curriculum.notes, !existingNotes.isEmpty {
            merged.notes = existingNotes
        }
        merged.plays = session.curriculum.plays
        session.curriculum = merged
        planRationale = result.rationale
        saveSession()
        HapticFeedback.notification(.success)
    }

    // MARK: - Duration Intelligence Bar
    private var durationIntelligenceBar: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let status = durationStatus
        let progress = min(Double(totalPlannedMinutes) / Double(max(sessionDurationMinutes, 1)), 1.5)
        
        return HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(status.color)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isChinese ? "\(totalPlannedMinutes) / \(sessionDurationMinutes) 分钟" : "\(totalPlannedMinutes) / \(sessionDurationMinutes) min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(status.message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(status.color)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(status.color)
                            .frame(width: geo.size.width * min(progress, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(status.color.opacity(0.08))
        .cornerRadius(10)
    }
    
    // MARK: - Quick Picks Section
    private var quickPicksSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let drillsToShow = recentlyUsedDrills.isEmpty ? popularDrillsForAgeGroup : recentlyUsedDrills
        let title = recentlyUsedDrills.isEmpty 
            ? (isChinese ? "适合此年龄组" : "Popular for age group")
            : (isChinese ? "最近使用" : "Recently used")
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: recentlyUsedDrills.isEmpty ? "star.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.purple)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drillsToShow) { drill in
                        quickPickDrillChip(drill: drill)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(12)
    }
    
    private func quickPickDrillChip(drill: DrillItem) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return Menu {
            Button {
                session.curriculum.warmupDrillIds.append(drill.id)
                trackDrillUsage(drill.id)
                saveSession()
            } label: {
                Label(isChinese ? "添加到热身" : "Add to Warmup", systemImage: "flame.fill")
            }
            Button {
                session.curriculum.skillDrillIds.append(drill.id)
                trackDrillUsage(drill.id)
                saveSession()
            } label: {
                Label(isChinese ? "添加到技能" : "Add to Skills", systemImage: "figure.basketball")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: drill.category.icon)
                    .font(.system(size: 10))
                    .foregroundColor(Color.drillCategoryColor(drill.category))
                
                Text(drill.localizedName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text("\(drill.durationMinutes)m")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.purple.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private func curriculumSection(title: String, icon: String, color: Color, drillIds: [UUID], minutes: Int, section: CurriculumSection) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let actualDuration = sectionDuration(for: section)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Label {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                }

                Spacer()

                // Duration chip
                Text(isChinese ? "\(actualDuration) 分钟" : "\(actualDuration) min")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())
                    .contentTransition(.numericText())

                // + menu
                if accessMode.canEdit {
                    Menu {
                        Button {
                            drillPickerSection = section
                            pickerAttribute = nil
                            showingSmartDrillPicker = true
                        } label: {
                            Label(isChinese ? "从训练库添加" : "From Library", systemImage: "books.vertical")
                        }
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingInlineDrillInputFor = showingInlineDrillInputFor == section ? nil : section
                            }
                        } label: {
                            Label(isChinese ? "快速文本" : "Quick Text", systemImage: "text.cursor")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Inline text input
            if showingInlineDrillInputFor == section && accessMode.canEdit {
                HStack(spacing: 8) {
                    TextField(
                        isChinese ? "输入训练名称..." : "Enter drill name...",
                        text: Binding(
                            get: { inlineDrillTextBySection[section] ?? "" },
                            set: { inlineDrillTextBySection[section] = $0 }
                        )
                    )
                    .font(.footnote)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
                    .onSubmit { addInlineTextDrill(section: section) }

                    Button {
                        addInlineTextDrill(section: section)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(color)

                    Button {
                        withAnimation { showingInlineDrillInputFor = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .tint(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Drills
            if drillIds.isEmpty {
                HStack {
                    Text(isChinese ? "点击 + 添加训练" : "Tap + to add drills")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(drillIds.enumerated()), id: \.element) { index, drillId in
                        if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                            drillRow(drill: drill, color: color, section: section, index: index, totalCount: drillIds.count)
                            if drillId != drillIds.last {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func drillRow(drill: DrillItem, color: Color, section: CurriculumSection, index: Int, totalCount: Int) -> some View {
        let isExpanded = expandedDrillId == drill.id
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return VStack(spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                if accessMode.canEdit {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 16)
                }

                // Lead with the first media thumbnail when present —
                // coaches said visuals make drills easier to recall while
                // planning. Falls back to the category icon tile.
                if let firstMedia = drill.media.min(by: { $0.sortOrder < $1.sortOrder }) {
                    DrillMediaThumb(media: firstMedia, size: 32, cornerRadius: 8)
                } else {
                    Image(systemName: drill.category.icon)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.localizedName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("\(drill.durationMinutes) min")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i < drill.difficulty.level ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                                    .frame(width: 5, height: 5)
                            }
                        }

                        if drill.media.count > 1 {
                            Label("\(drill.media.count)", systemImage: "photo.stack")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                if session.drillsCompleted.contains(drill.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: session.drillsCompleted.contains(drill.id))
                }

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, accessMode.canEdit ? 10 : 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedDrillId = isExpanded ? nil : drill.id
                }
            }
            
            // Expanded inline details
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Visuals — compact 84pt carousel so it reads at a
                    // glance while planning without dominating the row.
                    if !drill.media.isEmpty {
                        DrillMediaCarousel(
                            media: drill.media,
                            tileSize: 84,
                            horizontalPadding: 0,
                            onTap: { item, _ in
                                HapticFeedback.impact(.light)
                                // A drawing plays in a popup; photos and
                                // videos open the full-screen viewer.
                                if DrillDrawingMedia.drawing(for: item) != nil {
                                    plannerDrawing = item
                                } else if let idx = DrillDrawingMedia.viewerMedia(drill.media)
                                            .firstIndex(where: { $0.id == item.id }) {
                                    plannerMediaViewer = PlannerMediaViewerTarget(
                                        drillId: drill.id, index: idx
                                    )
                                }
                            },
                            onAdd: nil
                        )
                    }

                    if !drill.description.isEmpty {
                        Text(drill.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    
                    if !drill.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "步骤" : "Steps")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(drill.instructions.prefix(3).enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(idx + 1).")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    Text(step)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                            if drill.instructions.count > 3 {
                                Text(isChinese ? "+\(drill.instructions.count - 3) 更多" : "+\(drill.instructions.count - 3) more")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Quick actions
                    HStack(spacing: 8) {
                        Button {
                            selectedDrillForDetail = drill
                        } label: {
                            Label(isChinese ? "详情" : "Details", systemImage: "info.circle")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.mini)
                        .tint(Color.accentColor)

                        Spacer()

                        if accessMode.canEdit {
                            if index > 0 {
                                Button {
                                    withAnimation { moveDrill(from: index, to: index - 1, in: section) }
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.circle)
                                .controlSize(.mini)
                                .tint(.secondary)
                            }

                            if index < totalCount - 1 {
                                Button {
                                    withAnimation { moveDrill(from: index, to: index + 1, in: section) }
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.circle)
                                .controlSize(.mini)
                                .tint(.secondary)
                            }

                            Button(role: .destructive) {
                                withAnimation {
                                    expandedDrillId = nil
                                    removeDrill(drill.id, from: section)
                                }
                            } label: {
                                Label(isChinese ? "移除" : "Remove", systemImage: "trash")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.mini)
                        }
                    }
                }
                .padding(.horizontal, accessMode.canEdit ? 58 : 64)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? AnyShapeStyle(Color.accentColor.opacity(0.06)) : AnyShapeStyle(Color.clear))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if accessMode.canEdit {
                Button(role: .destructive) {
                    withAnimation { removeDrill(drill.id, from: section) }
                } label: {
                    Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                }
            }
        }
    }

    private func createAndAttachDrill(
        title: String,
        steps: [String],
        details: String,
        duration: Int,
        difficulty: DifficultyLevel,
        section: CurriculumSection,
        visibility: DrillLibraryVisibility,
        quickNote: Bool
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let visibilityTag = visibility == .shared ? "visibility:shared" : "visibility:private"
        let ownerTag = "owner:\(currentCoachId.uuidString)"
        var tags = [visibilityTag, ownerTag]
        if quickNote { tags.append("quick-note") }

        let newDrill = DrillItem(
            name: cleanTitle,
            category: categoryForSection(section),
            difficulty: difficulty,
            durationMinutes: max(duration, 1),
            description: details,
            instructions: steps,
            tags: tags
        )

        dataManager.addDrill(newDrill)

        switch section {
        case .warmup:
            session.curriculum.warmupDrillIds.append(newDrill.id)
        case .main:
            session.curriculum.skillDrillIds.append(newDrill.id)
        case .cooldown:
            session.curriculum.gameDrillIds.append(newDrill.id)
        }

        saveSession()
    }

    private func categoryForSection(_ section: CurriculumSection) -> DrillCategory {
        switch section {
        case .warmup: return .warmup
        case .main: return .skills
        case .cooldown: return .cooldown
        }
    }
    
    private func removeDrill(_ drillId: UUID, from section: CurriculumSection) {
        switch section {
        case .warmup:
            session.curriculum.warmupDrillIds.removeAll { $0 == drillId }
        case .main:
            session.curriculum.skillDrillIds.removeAll { $0 == drillId }
        case .cooldown:
            session.curriculum.gameDrillIds.removeAll { $0 == drillId }
        }
        saveSession()
    }
    
    // MARK: - Recently Used Drills
    private var recentlyUsedDrillIds: [UUID] {
        (try? JSONDecoder().decode([UUID].self, from: recentlyUsedDrillIdsData)) ?? []
    }
    
    private func trackDrillUsage(_ drillId: UUID) {
        var ids = recentlyUsedDrillIds.filter { $0 != drillId }
        ids.insert(drillId, at: 0)
        let trimmed = Array(ids.prefix(10))
        if let encoded = try? JSONEncoder().encode(trimmed) {
            recentlyUsedDrillIdsData = encoded
        }
    }
    
    private var recentlyUsedDrills: [DrillItem] {
        recentlyUsedDrillIds.compactMap { id in
            dataManager.drills.first { $0.id == id }
        }.prefix(5).map { $0 }
    }
    
    private var popularDrillsForAgeGroup: [DrillItem] {
        guard let program = parentProgram else { return [] }
        let targetLevel: Int
        switch program.ageGroup {
        case .u6, .u8, .u10: targetLevel = 1
        case .u12, .u14: targetLevel = 2
        case .u16, .u18, .adult: targetLevel = 3
        }
        return dataManager.drills
            .filter { $0.difficulty.level == targetLevel || $0.isFavorite }
            .sorted { ($0.isFavorite ? 1 : 0) > ($1.isFavorite ? 1 : 0) }
            .prefix(5).map { $0 }
    }
    
    // MARK: - Duration Intelligence
    private var totalPlannedMinutes: Int {
        let warmupDrills = session.curriculum.warmupDrillIds.compactMap { id in
            dataManager.drills.first { $0.id == id }
        }
        let skillDrills = session.curriculum.skillDrillIds.compactMap { id in
            dataManager.drills.first { $0.id == id }
        }
        return warmupDrills.reduce(0) { $0 + $1.durationMinutes } + skillDrills.reduce(0) { $0 + $1.durationMinutes }
    }
    
    private var sessionDurationMinutes: Int {
        let diff = session.endTime.timeIntervalSince(session.startTime)
        return max(Int(diff / 60), 0)
    }
    
    private var durationStatus: (message: String, color: Color) {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let diff = sessionDurationMinutes - totalPlannedMinutes
        if diff > 15 {
            return (isChinese ? "还有 \(diff) 分钟可用" : "\(diff) min available", .green)
        } else if diff >= 0 {
            return (isChinese ? "计划紧凑" : "Well planned", .blue)
        } else {
            return (isChinese ? "超出 \(-diff) 分钟" : "\(-diff) min over", .orange)
        }
    }
    
    private func sectionDuration(for section: CurriculumSection) -> Int {
        let drillIds: [UUID]
        switch section {
        case .warmup: drillIds = session.curriculum.warmupDrillIds
        case .main: drillIds = session.curriculum.skillDrillIds
        case .cooldown: drillIds = session.curriculum.gameDrillIds
        }
        return drillIds.compactMap { id in
            dataManager.drills.first { $0.id == id }?.durationMinutes
        }.reduce(0, +)
    }
    
    // MARK: - Drill Reordering
    private func moveDrill(from sourceIndex: Int, to destIndex: Int, in section: CurriculumSection) {
        switch section {
        case .warmup:
            guard sourceIndex < session.curriculum.warmupDrillIds.count else { return }
            let id = session.curriculum.warmupDrillIds.remove(at: sourceIndex)
            session.curriculum.warmupDrillIds.insert(id, at: min(destIndex, session.curriculum.warmupDrillIds.count))
        case .main:
            guard sourceIndex < session.curriculum.skillDrillIds.count else { return }
            let id = session.curriculum.skillDrillIds.remove(at: sourceIndex)
            session.curriculum.skillDrillIds.insert(id, at: min(destIndex, session.curriculum.skillDrillIds.count))
        case .cooldown:
            guard sourceIndex < session.curriculum.gameDrillIds.count else { return }
            let id = session.curriculum.gameDrillIds.remove(at: sourceIndex)
            session.curriculum.gameDrillIds.insert(id, at: min(destIndex, session.curriculum.gameDrillIds.count))
        }
        saveSession()
    }
    
    // MARK: - Phase Insights Section
    private var phaseInsightsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                Text(isChinese ? "课程洞察" : "SESSION INSIGHTS")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            // Phase info
            if let phase = parentPhase {
                VStack(alignment: .leading, spacing: 10) {
                    // Phase title
                    HStack(spacing: 8) {
                        Image(systemName: "flag.fill")
                            .foregroundColor(programColor.accessibleText)
                        Text(isChinese ? "阶段 \(phase.phaseNumber): \(phase.title)" : "Phase \(phase.phaseNumber): \(phase.title)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    // Focus areas
                    if !phase.focus.isEmpty {
                        HStack(spacing: 6) {
                            Text(isChinese ? "训练重点:" : "Focus:")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            ForEach(phase.focus.prefix(3), id: \.self) { focus in
                                HStack(spacing: 4) {
                                    Image(systemName: focus.icon)
                                        .font(.system(size: 10))
                                    Text(focus.displayName)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(programColor.accessibleText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(programColor.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                    
                    // Intensity & Volume
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "强度" : "Intensity")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                ForEach(0..<10) { i in
                                    Rectangle()
                                        .fill(i < phase.intensity ? Color.orange : Color.gray.opacity(0.2))
                                        .frame(width: 8, height: 12)
                                        .cornerRadius(2)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "训练量" : "Volume")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                ForEach(0..<10) { i in
                                    Rectangle()
                                        .fill(i < phase.volume ? Color.blue : Color.gray.opacity(0.2))
                                        .frame(width: 8, height: 12)
                                        .cornerRadius(2)
                                }
                            }
                        }
                    }
                    
                    // Phase objectives
                    if !phase.objectives.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isChinese ? "阶段目标:" : "Phase Objectives:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(phase.objectives.prefix(3), id: \.self) { objective in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                    Text(objective)
                                        .font(.system(size: 12))
                                        .foregroundColor(.black.opacity(0.8))
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(programColor.opacity(0.05))
                .cornerRadius(12)
            }
            
            // Program & student level info
            if let program = parentProgram {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: program.mascot.icon)
                            .foregroundColor(Color(hex: program.colorHex))
                        Text(program.name)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    
                    HStack(spacing: 12) {
                        // Age group
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(program.ageGroup.displayName)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        
                        // Student count
                        HStack(spacing: 4) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 10))
                            Text("\(enrolledStudents.count) \(isChinese ? "学员" : "students")")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        
                        // Avg skill level indicator
                        if !enrolledStudents.isEmpty {
                            let avgLevel = calculateAverageSkillLevel()
                            HStack(spacing: 4) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 10))
                                Text(isChinese ? "平均水平: \(avgLevel)" : "Avg Level: \(avgLevel)")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Skill targets recommendation
                    if let targets = program.skillTargets, targets.hasTargets {
                        Text(isChinese ? "建议选择难度与学员水平匹配的训练" : "Recommended: Match drill difficulty to student levels")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
                .padding(14)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
    
    private func calculateAverageSkillLevel() -> String {
        guard !enrolledStudents.isEmpty else { return "N/A" }
        // Calculate based on age groups since Student doesn't have skills directly
        var totalLevel = 0
        for student in enrolledStudents {
            if let ageGroup = student.ageGroup {
                switch ageGroup {
                case .u6, .u8, .u10: totalLevel += 1
                case .u12, .u14: totalLevel += 2
                case .u16, .u18, .adult: totalLevel += 3
                }
            } else {
                totalLevel += 2 // Default to intermediate
            }
        }
        let avg = totalLevel / enrolledStudents.count
        if avg <= 1 { return LocalizationManager.shared.currentLanguage == .chinese ? "初级" : "Beginner" }
        if avg <= 2 { return LocalizationManager.shared.currentLanguage == .chinese ? "中级" : "Intermediate" }
        return LocalizationManager.shared.currentLanguage == .chinese ? "高级" : "Advanced"
    }
    
    // State for adding athletes from attendance
    @State private var showingAddAthleteSheet = false
    
    // MARK: - Attendance Tab

    #if os(iOS)
    /// The roster as a non-scrolling List sized to its rows. A List, because
    /// `.swipeActions` only fire on List rows: in the old LazyVStack the
    /// Excuse / Clear / Refund swipes were inert and the long-press menu was
    /// the only way to reach them. Only the roster is a List — the hero above
    /// stays in the page's ScrollView, where its glass and chips render as
    /// designed. Rows report their height so the List is exactly as tall as
    /// the stack it replaced.
    @ViewBuilder
    private var attendanceRoster: some View {
        if pageSizeClass == .regular {
            attendanceGrid
        } else {
            attendanceList
                .background(Color(.secondarySystemGroupedBackground))
        }
    }

    /// iPad / Mac (14 Nov 2026, Luther: "instead of a list with barely
    /// visible names, a double row list with larger player names and
    /// pictures"): two columns of cards — 56 pt photo, the name large, the
    /// second name and the mark under it, the same three-position control.
    /// No swipes here, so Photo is in the card's menu.
    private var attendanceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(enrolledStudents) { student in
                attendanceCard(student: student)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func attendanceCard(student: Student) -> some View {
        let mark: AttendanceMark = session.effectiveAttendanceMark(for: student.id)
        return HStack(spacing: 14) {
            Button {
                selectedStudentForPeep = student
            } label: {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        StudentAvatarView(student: student, size: 56)
                        Circle()
                            .fill(mark.tint)
                            .frame(width: 18, height: 18)
                            .overlay(Image(systemName: mark.icon).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                            .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(student.primaryDisplayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let second = student.secondaryNameLine {
                            Text(second)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(mark.label(isChinese: isChinese))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mark == .unmarked ? Color.secondary : mark.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            AttendanceMarkControl(mark: mark) { newMark in
                setAttendanceState(for: student.id, state: newMark)
            }
            .disabled(!accessMode.canTakeAttendance)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(mark == .present ? mark.tint.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .contextMenu {
            if accessMode.canTakeAttendance {
                AttendanceMarkMenu(mark: mark) { newMark in
                    setAttendanceState(for: student.id, state: newMark)
                }
            }
            #if os(iOS) && !targetEnvironment(macCatalyst)
            Button {
                studentForPhoto = student
            } label: {
                Label(isChinese ? "拍照" : "Photo", systemImage: "camera.fill")
            }
            #endif
        }
        .accessibilityIdentifier("attendance.card")
    }

    private var attendanceList: some View {
        let students = enrolledStudents
        // Each row rounded UP to whole points, because that is how tall the
        // List makes its cells. Summing the raw fractions left the frame a
        // sliver short: the last divider was clipped, and the List kept a
        // fraction of scroll range that it re-settled every layout pass (the
        // first row visibly jittered).
        let height = students.reduce(CGFloat(0)) { $0 + (rosterRowHeights[$1.id] ?? 66).rounded(.up) }
        return List {
            ForEach(students) { student in
                attendanceRow(student: student)
                    // The Divider used to be its own stacked element under each
                    // row; reserve its hairline so the roster is as tall as before.
                    .padding(.bottom, 1 / displayScale)
                    .background(alignment: .bottom) {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Divider()
                        }
                        .padding(.leading, 66)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                        rosterRowHeights[student.id] = newHeight
                    }
                    .attendancePageRow(background: Color(.secondarySystemGroupedBackground))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 0)
        .frame(height: height)
    }

    /// Below the roster: add athlete, session photo, bottom breathing room.
    private var attendanceFooter: some View {
        VStack(spacing: 8) {
            // A scrimmage / game prep with no program can still take coaches.
            if (parentProgram != nil || session.sessionType.takesCoachesAsPlayers) && accessMode.canEdit {
                addAthleteButton
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            sessionPhotoSection
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Spacer(minLength: 100)
        }
    }
    #endif

    private var attendanceTab: some View {
        Group {
            #if os(iOS)
            VStack(spacing: 8) {
                attendanceRoster
                coachesOnRoster

                attendanceFooter
            }
            #else
            VStack(spacing: 0) {
                attendanceStats
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(enrolledStudents) { student in
                            attendanceRow(student: student)
                        }

                        if parentProgram != nil && accessMode.canEdit {
                            addAthleteButton
                        }

                        sessionPhotoSection

                        Spacer(minLength: 100)
                    }
                    .padding(20)
                }
            }
            #endif
        }
        #if os(iOS)
        // Leading swipe → the masked back camera, straight to the shutter
        // (no library, no edit step). The square photo replaces the
        // student's profile picture on capture; cancel changes nothing.
        .fullScreenCover(item: $studentForPhoto) { student in
            ProfilePhotoCamera { image in
                if let image { saveProfilePhoto(image, for: student.id) }
                studentForPhoto = nil
            }
        }
        #endif
        .sheet(item: $selectedStudentForPeep) { student in
            StudentQuickPeepView(student: student, sessionId: session.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddAthleteSheet) {
            // Available pool = all students not already enrolled in this
            // program. Mirrors the legacy `AddAthleteFromAttendanceView`
            // behavior; we just route it through the shared picker now.
            // A private session offers anyone not already expected at it
            // (they join this session only); a group class, anyone not on
            // the program's roster.
            // Group classes too (18 Nov 2026, Luther: enrolled athletes missing
            // from a class could not be found here — the list left out the
            // whole program): anyone not EXPECTED at this class.
            let takenIds = Set(AttendanceMath.expectedIds(of: session, programs: dataManager.programs))
                .union(session.actualAttendeeIds)
            // Without a program there is no roster to join: coaches only.
            let available = (parentProgram == nil && !isPrivateSession) ? []
                : dataManager.students.filter { !takenIds.contains($0.id) }
            let banner = isPrivateSession
                ? AthletePickerSheet.Banner(
                    title: isChinese ? "仅加入本节课" : "This Session Only",
                    subtitle: isChinese
                        ? "学员会被标记为出席，并从他自己的私教课包扣一节课；不会加入这个项目"
                        : "They're marked present and one session comes off their own private bundle. They don't join this program.",
                    tint: programColor)
                : AthletePickerSheet.Banner(
                    title: isChinese ? "从此课程开始计费" : "Sessions Count From Here",
                    subtitle: isChinese
                        ? "学员加入这个项目以及本节和之后的课；合约课时从本节课开始计算"
                        : "They join this program, this class and the ones after it; their contract sessions count from this one",
                    tint: programColor
                )
            AthletePickerSheet(
                title: isChinese ? "添加学员" : "Add Athlete",
                students: available,
                accentColor: programColor,
                banner: banner,
                confirmLabel: isChinese ? "添加" : "Add",
                showSelectionCounter: false,
                coaches: coachesToOffer
            ) { ids in
                let coachIds = Set(dataManager.staffCoaches.map(\.id))
                addCoachesToSession(ids.filter { coachIds.contains($0) })
                enrollStudentsFromAttendance(studentIds: ids.filter { !coachIds.contains($0) })
            }
        }
        .sheet(isPresented: $showingSessionPhotoCapture, onDismiss: { rollCallReason = .manual }) {
            RollCallPhotoSheet(programColor: programColor, reason: rollCallReason) { image in
                #if os(iOS)
                if let path = PhotoCaptureManager.shared.saveAttendancePhoto(image, for: session.id) {
                    // Optimistic local update + field-level write. Avoids
                    // the whole-record `saveSession()` overwrite that
                    // previously wiped games/attendance when the local
                    // `@State session` had gone stale.
                    session.attendancePhotoPath = path
                    dataManager.setSessionAttendancePhoto(sessionId: session.id, path: path)
                }
                #endif
            }
        }
        .fullScreenCover(isPresented: $showingSessionPhotoFullScreen) {
            if let path = session.attendancePhotoPath,
               let image = PhotoCaptureManager.shared.loadAttendancePhoto(from: path) {
                SessionPhotoViewer(image: image) { showingSessionPhotoFullScreen = false }
            } else {
                EmptyView()
            }
        }
    }
    
    #if os(iOS)
    /// Same writes as Edit Student's photo path: full image + widget/list
    /// thumbnail, through updateStudent. Reads the student fresh from the
    /// store so the swipe never saves a stale copy over newer edits.
    private func saveProfilePhoto(_ image: UIImage, for studentId: UUID) {
        guard let data = image.jpegData(compressionQuality: 0.7),
              var student = dataManager.students.first(where: { $0.id == studentId }) else { return }
        student.profileImageData = data
        student.thumbnailImageData = makeProfileThumbnailData(from: data)
        student.updatedAt = Date()
        dataManager.updateStudent(student)
        HapticFeedback.notification(.success)
    }
    #endif

    private var addAthleteButton: some View {
        Button(action: { showingAddAthleteSheet = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(programColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(programColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "添加学员" : "Add Athlete")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(programColor)
                    Text(isPrivateSession
                         ? (isChinese ? "加入本节课（不加入项目）" : "Add someone to this session only")
                         : (isChinese ? "将新学员加入此项目" : "Enroll a new student in this program"))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(programColor.opacity(0.05))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(programColor.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    /// Private by the program's TYPE (SessionPrivacy, the one answer).
    private var isPrivateSession: Bool {
        SessionPrivacy.isPrivate(session, programs: dataManager.programs, contracts: dataManager.contracts)
    }

    /// Add Athlete on a PRIVATE session (November 2026, Luther): the athlete
    /// joins THIS session's roster and is marked present — never the program.
    /// Enrolling them there (the group-class behaviour) made a second client
    /// "expected" at every later lesson of the first client's private
    /// program, and inferred absent — charged — when not marked.
    private func addToThisSessionOnly(studentIds: [UUID]) {
        dataManager.addStudentsToSessionOnly(sessionId: session.id, studentIds: studentIds)
        refreshSessionFromStore()
        // The roster is not a live field, so a later save from this copy must
        // carry the new one rather than restore the old.
        if let fresh = dataManager.sessionEvents.first(where: { $0.id == session.id }) {
            session.attendeeIds = fresh.attendeeIds
        }
        HapticFeedback.notification(.success)
    }

    // MARK: Coaches on the floor (scrimmage / game prep)

    /// Organization coaches on this session, as display-only players.
    private var guestCoaches: [Student] {
        session.curriculum.coachIds.compactMap { id in
            dataManager.staffCoaches.first { $0.id == id }?.asGuestPlayer(dataManager: dataManager)
        }
    }

    /// Coaches the Add Athlete sheet offers: only on a scrimmage or game
    /// prep session, and only those not already on it.
    private var coachesToOffer: [Student] {
        guard session.sessionType.takesCoachesAsPlayers else { return [] }
        let taken = Set(session.curriculum.coachIds)
        return dataManager.staffCoaches
            .filter { $0.isActive && !taken.contains($0.id) }
            .map { $0.asGuestPlayer(dataManager: dataManager) }
    }

    private func addCoachesToSession(_ ids: [UUID]) {
        let new = ids.filter { !session.curriculum.coachIds.contains($0) }
        guard !new.isEmpty else { return }
        session.curriculum.coachIds.append(contentsOf: new)
        saveSession()
    }

    private func removeCoachFromSession(_ id: UUID) {
        session.curriculum.coachIds.removeAll { $0 == id }
        saveSession()
    }

    /// The coaches on this session, under the athletes: photo, name, a Coach
    /// tag and a menu to take them off. No attendance mark — a coach is
    /// never charged or counted.
    @ViewBuilder
    private var coachesOnRoster: some View {
        let coaches = guestCoaches
        if !coaches.isEmpty {
            VStack(spacing: 0) {
                ForEach(coaches) { coach in
                    HStack(spacing: 12) {
                        StudentAvatarView(student: coach, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coach.primaryDisplayName)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            if let secondary = coach.secondaryNameLine {
                                Text(secondary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Text(isChinese ? "教练" : "Coach")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.indigo, in: .capsule)
                        Spacer(minLength: 6)
                        if accessMode.canEdit {
                            Menu {
                                Button(role: .destructive) { removeCoachFromSession(coach.id) } label: {
                                    Label(isChinese ? "移出本节课" : "Remove from session", systemImage: "minus.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel(isChinese ? "更多" : "More")
                            .accessibilityIdentifier("session.coachRow.more")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("session.coachRow")
                    if coach.id != coaches.last?.id {
                        Divider().padding(.leading, 72)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    private func enrollStudentsFromAttendance(studentIds: [UUID]) {
        guard !studentIds.isEmpty else { return }
        if isPrivateSession {
            addToThisSessionOnly(studentIds: studentIds)
            return
        }
        guard var program = parentProgram else { return }

        var didChangeProgram = false
        var didChangeSession = false

        for studentId in studentIds {
            if !program.enrolledStudentIds.contains(studentId) {
                program.enrolledStudentIds.append(studentId)
                didChangeProgram = true
            }
            if !session.actualAttendeeIds.contains(studentId) {
                session.actualAttendeeIds.append(studentId)
                didChangeSession = true
            }
        }

        if didChangeProgram {
            dataManager.updateProgram(program)
        }
        // Expected from now on: this class and the program's coming ones
        // (an athlete already enrolled may have been missing from them).
        dataManager.addToUpcomingRosters(studentIds: studentIds, programId: program.id, current: session.id)
        if !session.attendeeIds.isEmpty {
            for id in studentIds where !session.attendeeIds.contains(id) { session.attendeeIds.append(id) }
        }
        if didChangeSession {
            // Field-level attendance write — see `setAttendanceState`.
            dataManager.setSessionAttendance(
                sessionId: session.id,
                actualAttendeeIds: session.actualAttendeeIds,
                excusedAbsences: session.excusedAbsences
            )
        }

        HapticFeedback.notification(.success)
    }

    private var attendanceStats: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let rate = enrolledStudents.isEmpty ? 0 : Double(session.actualAttendeeIds.count) / Double(enrolledStudents.count)

        return HStack(spacing: 0) {
            attendanceStat(
                value: "\(session.actualAttendeeIds.count)",
                label: isChinese ? "到场" : "Present",
                tint: AnyShapeStyle(Color.green)
            )

            Divider().frame(height: 40)

            attendanceStat(
                value: "\(enrolledStudents.count)",
                label: isChinese ? "预期" : "Expected",
                tint: AnyShapeStyle(HierarchicalShapeStyle.primary)
            )

            Divider().frame(height: 40)

            attendanceStat(
                value: "\(Int(rate * 100))%",
                label: isChinese ? "比率" : "Rate",
                tint: rate >= 0.8 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.accentColor)
            )
        }
        .padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private func attendanceStat(value: String, label: String, tint: AnyShapeStyle) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Always-visible "Session photo" block. Empty → CTA button; populated →
    /// thumbnail that opens full-screen, with a Replace button.
    @ViewBuilder
    private var sessionPhotoSection: some View {
        if let photoPath = session.attendancePhotoPath {
            VStack(alignment: .leading, spacing: 10) {
                // The thumbnail itself opens the full-screen viewer — that
                // replaces the old "View" action button and gives the row
                // below enough room so "Replace" / "Export" / "Remove"
                // labels stop wrapping with hyphenation on a phone-sized
                // screen.
                //
                // `.contentShape(.rect(cornerRadius: 14))` constrains the
                // hit-test region to the glassed card outline; without it
                // taps just above the card edge (where the "Add Athlete"
                // row sits) were being captured by this Button.
                Button {
                    showingSessionPhotoFullScreen = true
                } label: {
                    attendancePhotoPreview(photoPath: photoPath)
                }
                .buttonStyle(.plain)
                .contentShape(.rect(cornerRadius: 14))

                HStack(spacing: 8) {
                    Button {
                        showingSessionPhotoCapture = true
                    } label: {
                        Label(isChinese ? "替换" : "Replace", systemImage: "arrow.triangle.2.circlepath.camera")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    #if os(iOS)
                    Button {
                        exportSessionPhotoToLibrary()
                    } label: {
                        if isExportingSessionPhoto {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Label(isChinese ? "导出" : "Export", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isExportingSessionPhoto)
                    #endif

                    Spacer()

                    // Icon-only destructive button — saves ~70pt vs. a
                    // labeled button and keeps the row from over-packing
                    // once Export was added alongside Replace.
                    Button(role: .destructive) {
                        removeSessionPhoto()
                    } label: {
                        Image(systemName: "trash")
                            .accessibilityLabel(isChinese ? "删除" : "Remove")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
        } else {
            Button {
                showingSessionPhotoCapture = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isChinese ? "添加课程照片" : "Add session photo")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(isChinese ? "作为出勤证据" : "Proof of who was present")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private func removeSessionPhoto() {
        if let path = session.attendancePhotoPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        // Field-level clear instead of `saveSession()` — same reason as the
        // set path above: don't risk a stale snapshot wiping siblings.
        session.attendancePhotoPath = nil
        dataManager.setSessionAttendancePhoto(sessionId: session.id, path: nil)
    }

    #if os(iOS)
    /// Composes the attendance photo with a watermark of coach name, when
    /// the photo was taken, location, present-count and the names of present
    /// students, then saves the result to the user's Photos library. The band
    /// is always Chinese — these photos go to Chinese-reading WeChat groups.
    private func exportSessionPhotoToLibrary() {
        guard !isExportingSessionPhoto,
              let path = session.attendancePhotoPath,
              let basePhoto = PhotoCaptureManager.shared.loadAttendancePhoto(from: path) else { return }

        isExportingSessionPhoto = true
        HapticFeedback.impact(.light)

        let presentStudents = dataManager.students.filter { session.actualAttendeeIds.contains($0.id) }
        // ALWAYS CHINESE (19 Nov 2026, Luther: "everything should be in
        // Chinese including the name of the coach") — these photos go to
        // WeChat groups. Students by Chinese name (else their pinyin name).
        let names: [String] = presentStudents.compactMap { student in
            let name = student.primaryName(chinese: true).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        let nameList = names.joined(separator: "、")

        // The coach's Chinese name: their profile's, else their own row in
        // the organization's, else (nothing in Chinese anywhere) their name.
        let coachName: String = {
            let coach = dataManager.coach
            func chinese(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return t
            }
            if let zh = chinese(coach.chineseName) { return zh }
            let me = dataManager.staffCoaches.first { $0.id == dataManager.loggedInCoachId }
                ?? dataManager.staffCoaches.first {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                        coach.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                }
            if let zh = chinese(me?.chineseName) { return zh }
            return coach.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // WHEN THE PICTURE WAS TAKEN (19 Nov 2026, Luther: not the session's
        // time) — the photo file is written at the shutter; a photo whose
        // file date cannot be read falls back to now.
        let stamp = PhotoCaptureManager.shared.attendancePhotoTakenDate(from: path) ?? Date()
        let zhLocale = Locale(identifier: "zh_CN")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = zhLocale
        dateFormatter.dateFormat = "yyyy年M月d日 HH:mm"
        let dateText = dateFormatter.string(from: stamp)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = zhLocale
        weekdayFormatter.dateFormat = "EEEE"  // → "星期日"
        let weekdayText = weekdayFormatter.string(from: stamp)

        let composed = renderWatermarkedAttendancePhoto(
            photo: basePhoto,
            coachName: coachName,
            weekdayText: weekdayText,
            dateText: dateText,
            location: session.location,
            presentCount: presentStudents.count,
            nameList: nameList
        ) ?? basePhoto

        PhotoCaptureManager.shared.saveImageToPhotoLibrary(composed) { result in
            isExportingSessionPhoto = false
            switch result {
            case .success:
                HapticFeedback.notification(.success)
                showSessionPhotoExportToast(.success)
            case .failure(let error):
                HapticFeedback.notification(.error)
                showSessionPhotoExportToast(.failure(error.localizedDescription))
            }
        }
    }

    private func showSessionPhotoExportToast(_ toast: SessionPhotoExportToast) {
        sessionPhotoExportToast = toast
        let dismissAfter: TimeInterval = (toast == .success) ? 2.0 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter) {
            if sessionPhotoExportToast == toast {
                sessionPhotoExportToast = nil
            }
        }
    }

    /// Renders the watermarked photo via SwiftUI's `ImageRenderer`. Output is
    /// pinned to the source photo's point size via `proposedSize`, and the
    /// watermark band uses `.overlay(alignment: .bottom)` so its content can
    /// never spill past the photo's bottom edge (the truncation bug we hit
    /// when anchoring with a ZStack).
    @MainActor
    private func renderWatermarkedAttendancePhoto(
        photo: UIImage,
        coachName: String,
        weekdayText: String,
        dateText: String,
        location: String?,
        presentCount: Int,
        nameList: String
    ) -> UIImage? {
        let pointSize = photo.size
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }

        let overlay = AttendanceWatermarkOverlay(
            photo: photo,
            coachName: coachName,
            weekdayText: weekdayText,
            dateText: dateText,
            location: location,
            presentCount: presentCount,
            nameList: nameList
        )

        let renderer = ImageRenderer(content: overlay)
        renderer.scale = max(photo.scale, 1)
        renderer.proposedSize = ProposedViewSize(width: pointSize.width, height: pointSize.height)
        renderer.isOpaque = true
        return renderer.uiImage
    }
    #endif

    private func attendancePhotoPreview(photoPath: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(isChinese ? "考勤照片" : "Attendance Photo")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            
            // Photo thumbnail - handle both URL and local path
            if photoPath.hasPrefix("http") {
                AsyncImage(url: URL(string: photoPath)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    case .failure:
                        photoErrorPlaceholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if let localImage = PhotoCaptureManager.shared.loadAttendancePhoto(from: photoPath) {
                #if os(iOS)
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                #endif
            } else {
                photoErrorPlaceholder
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var photoErrorPlaceholder: some View {
        ContentUnavailableView {
            Label(isChinese ? "无法加载照片" : "Unable to load photo", systemImage: "photo")
                .font(.caption)
        }
        .frame(height: 80)
    }
    
    private func attendanceRow(student: Student) -> some View {
        let isPresent = session.actualAttendeeIds.contains(student.id)
        
        // Four states from three stores. The default is UNMARKED — it used to
        // fall through to .absent, which now consumes a session.
        let attendanceState: AttendanceMark = session.effectiveAttendanceMark(for: student.id)
        return HStack(spacing: 10) {
            // Main tappable area - opens Quick Peep
            Button(action: {
                #if targetEnvironment(macCatalyst)
                macPopupTrace("tap quick peep")
                #endif
                selectedStudentForPeep = student
            }) {
                HStack(spacing: 10) {
                    // Avatar with presence indicator
                    ZStack(alignment: .bottomTrailing) {
                        StudentAvatarView(student: student, size: 40)
                        
                        // Status indicator dot
                        Circle()
                            .fill(attendanceState.tint)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: attendanceState.icon)
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 2, y: 2)
                    }
                    
                    // Name info
                    VStack(alignment: .leading, spacing: 1) {
                        Text(student.primaryDisplayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let chinese = student.secondaryNameLine {
                            Text(chinese)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }

                        // The switch is off for unmarked, excused AND absent,
                        // so the row says which one it is. Present needs no
                        // caption: the switch is on.
                        if attendanceState != .present {
                            Text(attendanceState.label(isChinese: isChinese))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(attendanceState.tint)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()

            // Three-position switch: excused · not marked · present. Left in
            // the middle once roll call starts = absent (AttendanceInference).
            // Same control as the Take Attendance sheet.
            AttendanceMarkControl(mark: attendanceState) { newMark in
                setAttendanceState(for: student.id, state: newMark)
            }
            .disabled(!accessMode.canTakeAttendance)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if accessMode.canTakeAttendance {
                AttendanceMarkMenu(mark: attendanceState) { newMark in
                    setAttendanceState(for: student.id, state: newMark)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                studentForPhoto = student
            } label: {
                Label(isChinese ? "拍照" : "Photo", systemImage: "camera.fill")
            }
            .tint(Color.accentColor)
        }
        // No trailing swipe (October 2026, Luther): Clear duplicated the
        // switch's middle position and the long-press menu, and Refund lives
        // on the contract sheet's "Sessions deducted" list.
        #endif
    }
    
    // MARK: - Attendance State
    
    private func setAttendanceState(for studentId: UUID, state: AttendanceMark) {
        // Shown at once (the local copy), written shortly after with any
        // other marks made in the meantime — see `flushAttendanceMarks`.
        applyMarkLocally(state, to: studentId)
        pendingMarks[studentId] = state
        markFlush?.cancel()
        markFlush = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flushAttendanceMarks()
        }
    }

    private func applyMarkLocally(_ state: AttendanceMark, to studentId: UUID) {
        session.actualAttendeeIds.removeAll { $0 == studentId }
        session.excusedAbsences.removeAll { $0 == studentId }
        session.unexcusedAbsences.removeAll { $0 == studentId }
        switch state {
        case .present:  session.actualAttendeeIds.append(studentId)
        case .excused:  session.excusedAbsences.append(studentId)
        case .absent:   session.unexcusedAbsences.append(studentId)
        case .unmarked: break
        }
    }

    /// Writes every pending mark in ONE field-level write (siblings — games,
    /// photo — survive even if this copy is stale). Redemption happens inside
    /// the writer via the single FIFO authority; do not redeem here — a second
    /// call site is how the two divergent redemption paths arose. Runs after
    /// a pause in tapping, and at once when the page goes away or the app
    /// goes to the background, so no mark is left unsaved.
    private func flushAttendanceMarks() {
        markFlush?.cancel()
        markFlush = nil
        guard !pendingMarks.isEmpty else { return }
        let states = pendingMarks.mapValues(\.triState)
        pendingMarks = [:]
        dataManager.setStudentAttendanceStates(sessionId: session.id, states: states)
    }

    /// Everyone expected who is not marked present or excused (unmarked, or
    /// absent by inference) — what "All present" marks.
    private var studentsToMarkPresent: [Student] {
        enrolledStudents.filter {
            let mark = session.effectiveAttendanceMark(for: $0.id)
            return mark != .present && mark != .excused
        }
    }

    /// "All present": one write for the whole roster. Excused students keep
    /// their excuse.
    private func markAllPresent() {
        for student in studentsToMarkPresent {
            applyMarkLocally(.present, to: student.id)
            pendingMarks[student.id] = .present
        }
        flushAttendanceMarks()
        HapticFeedback.notification(.success)
    }

    /// "All present" lives in the page's ⋯ menu (Luther, 17 Nov 2026 — it
    /// was a button above the roster). Shown when attendance can be taken.
    @ViewBuilder
    private var allPresentMenuItem: some View {
        if accessMode.canTakeAttendance, !enrolledStudents.isEmpty {
            Button {
                confirmingAllPresent = true
            } label: {
                Label(isChinese ? "全部到场" : "Mark All Present", systemImage: "checkmark.circle.fill")
            }
            .disabled(studentsToMarkPresent.isEmpty)
            .accessibilityIdentifier("attendance.allPresent")
        }
    }

    /// Its confirmation states the money consequence; attached to the page
    /// so it opens from any tab.
    private func allPresentConfirmation<V: View>(_ content: V) -> some View {
        let remaining = studentsToMarkPresent.count
        return content.confirmationDialog(
            isChinese ? "将 \(remaining) 名学员标记为到场？" : "Mark \(remaining) present?",
            isPresented: $confirmingAllPresent,
            titleVisibility: .visible
        ) {
            Button(isChinese ? "全部到场" : "Mark all present") { markAllPresent() }
        } message: {
            Text(isChinese
                 ? "每位到场学员扣除 1 课时（如有课时包）。请假的学员不变。"
                 : "Each present student uses 1 session from their balance, if they have one. Excused students stay excused.")
        }
    }

    // MARK: - Games Tab (iOS Only)
    #if os(iOS)
    private var gamesTab: some View {
        SessionGamesTabView(
            session: $session,
            enrolledStudents: enrolledStudents,
            programColor: programColor,
            onSave: saveSession,
            guestPlayers: guestCoaches
        )
    }
    #endif
    
    // MARK: - Notes Tab (iOS Notes Style)
    @State private var showPreviousNotes = false
    @State private var notesViewMode: NotesViewMode = .all
    @State private var notesSearchText = ""
    @State private var quickNoteTitle = ""
    @State private var quickNoteBody = ""
    @State private var showNotesStudio = false
    @State private var pinnedNoteIDs: Set<String> = []
    @State private var showNotesUtilities = false
    @State private var showMentionPanel = false
    @State private var showReminderPanel = false
    
    // iOS Notes style states
    @State private var showFloatingActionBar = false
    @State private var floatingBarAutoHideTask: Task<Void, Never>?
    @State private var showMentionPicker = false
    @State private var showTagPicker = false
    @State private var mentionSearchText = ""
    @State private var tagSearchText = ""
    
    private enum NotesEditorTarget: Hashable {
        case session
        case reflections
    }

    private enum NotesPane: Hashable { case notes, reminders }

    private enum QuickReminderDue: Hashable, CaseIterable {
        case beforeNextClass, tomorrow, nextWeek, custom
    }

    private enum NotesViewMode: Hashable {
        case all
        case sticky
        case templates
    }

    private struct SessionNoteCard: Identifiable, Hashable {
        let id: String
        let title: String
        let body: String
        let source: NotesEditorTarget
        let timeLabel: String?
    }

    private var activeCoachesForTagging: [StaffCoach] {
        Array(dataManager.staffCoaches.filter { $0.isActive }.prefix(8))
    }

    private var notesDelimiter: String { "\n\n---\n\n" }

    private var allNoteCards: [SessionNoteCard] {
        noteCards(from: session.notes ?? "", source: .session) +
        noteCards(from: session.coachNotes ?? "", source: .reflections)
    }

    private var filteredNoteCards: [SessionNoteCard] {
        let query = notesSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = allNoteCards
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.body.lowercased().contains(query)
        }
    }

    private var stickyNoteCards: [SessionNoteCard] {
        let pinned = filteredNoteCards.filter { pinnedNoteIDs.contains($0.id) }
        if !pinned.isEmpty { return pinned }
        return Array(filteredNoteCards.prefix(6))
    }
    
    // THE NOTES TAB (14 November 2026, Luther: "the weakest point of the
    // session … have lines like a notebook. change the reflection tab for
    // reminders. redo this notes section to be more aligned with the app").
    // Notes = a ruled notebook card (the session's notes; an older coach
    // reflection keeps its own card when it has text), the previous class's
    // notes, then the rating and player of the session as cards. Reminders =
    // this session's follow-ups, added in one line ("before next class" by
    // default), due ones surface in Home's attention as before.
    private var notesTab: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                if notesTabWidth >= notesWideAt {
                    // Wide window (15 Nov 2026, Luther: the Mac "not taking
                    // advantage of the window size"): both panes at once,
                    // Reminders on the left as in the switch.
                    HStack(alignment: .top, spacing: 20) {
                        sessionRemindersPane
                            .frame(width: min(560, notesTabWidth * 0.4))
                        VStack(spacing: 14) { notebookColumn }
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 120)
                } else {
                    VStack(spacing: 14) {
                        notesTypeToggle
                        if notesPane == .notes {
                            notebookColumn
                        } else {
                            sessionRemindersPane
                        }
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { notesTabWidth = $0 }
            .background(Color(.systemGroupedBackground))

            if showMentionPicker { notesMentionPickerOverlay }
            if showTagPicker { notesTagPickerOverlay }
            if showFloatingActionBar && (notesPane == .notes || notesTabWidth >= notesWideAt) { notesFloatingActionBar }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.height < -40 { showFloatingBar() } })
        .onChange(of: focusedNotesEditor) { _, target in
            if let target { notesEditorTarget = target }
        }
        .sheet(item: $editingSessionReminder) { reminder in
            AddReminderSheet(sessionId: session.id, programId: session.programId, existingReminder: reminder)
                .environmentObject(dataManager)
        }
        .onDisappear { saveSession() }
    }

    /// The notebook, an older reflection, the previous class's notes, then
    /// the rating and player of the session.
    @ViewBuilder
    private var notebookColumn: some View {
        notebookCard(title: isChinese ? "课程笔记" : "SESSION NOTES",
                     icon: "note.text",
                     text: activeSessionNotesBinding,
                     target: .session,
                     placeholder: isChinese ? "笔记、观察、提示..." : "Notes, observations, cues...")
        if !(session.coachNotes ?? "").isEmpty {
            notebookCard(title: isChinese ? "教练复盘" : "REFLECTION",
                         icon: "text.quote",
                         text: Binding(get: { session.coachNotes ?? "" },
                                       set: { session.coachNotes = $0.isEmpty ? nil : $0 }),
                         target: .reflections,
                         placeholder: "")
        }
        previousNotesIndentSection
        afterClassCards
    }

    private var activeSessionNotesBinding: Binding<String> {
        Binding(get: { session.notes ?? "" }, set: { session.notes = $0.isEmpty ? nil : $0 })
    }

    // MARK: Notebook

    private func notebookCard(title: String, icon: String, text: Binding<String>,
                              target: NotesEditorTarget, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(title).font(.caption2.weight(.bold)).monospaced()
                } icon: {
                    Image(systemName: icon).font(.caption).foregroundStyle(programColor)
                }
                .foregroundStyle(.secondary)
                Spacer()
                Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            RuledNotebookEditor(text: text, placeholder: placeholder, marginColor: programColor)
                .focused($focusedNotesEditor, equals: target)
                .disabled(!accessMode.canAddNotes)
                .onChange(of: text.wrappedValue) { _, newValue in
                    checkForMentionTrigger(in: newValue)
                }
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(target == .session ? "notes.notebook" : "notes.reflection")
    }

    // MARK: Rating + player of the session

    @ViewBuilder
    private var afterClassCards: some View {
        let showRating = session.status == .completed
        let showPlayer = session.status == .completed || session.status == .inProgress
        if showRating || showPlayer {
            if pageSizeClass == .regular {
                HStack(alignment: .top, spacing: 14) {
                    if showRating { ratingSection }
                    if showPlayer { manOfTheMatchSection }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                if showRating { ratingSection }
                if showPlayer { manOfTheMatchSection }
            }
        }
    }

    // MARK: Reminders

    /// The program's next class after this one — and after now, so a
    /// reminder written on an old session is not born overdue.
    private var nextClassAfterSession: SessionEvent? {
        guard let programId = session.programId else { return nil }
        let after = max(session.endTime, Date().addingTimeInterval(3600))
        return dataManager.cachedSessionEvents
            .filter { $0.programId == programId && $0.startTime > after && !SessionLifecycle.didNotHappen($0) }
            .min { $0.startTime < $1.startTime }
    }

    private func dueDate(for choice: QuickReminderDue) -> Date {
        let cal = Calendar.current
        let tomorrowMorning = cal.date(bySettingHour: 9, minute: 0, second: 0,
                                       of: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
        switch choice {
        case .beforeNextClass:
            return nextClassAfterSession.map { $0.startTime.addingTimeInterval(-3600) } ?? tomorrowMorning
        case .tomorrow:
            return tomorrowMorning
        case .nextWeek:
            return cal.date(byAdding: .day, value: 6, to: tomorrowMorning) ?? tomorrowMorning
        case .custom:
            return quickReminderCustomDate
        }
    }

    private func dueLabel(for choice: QuickReminderDue) -> String {
        switch choice {
        case .beforeNextClass:
            if let next = nextClassAfterSession {
                let day = next.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                return isChinese ? "下节课前 · \(day)" : "Before next class · \(day)"
            }
            return isChinese ? "明天" : "Tomorrow"
        case .tomorrow: return isChinese ? "明天" : "Tomorrow"
        case .nextWeek: return isChinese ? "一周后" : "In a week"
        case .custom: return isChinese ? "选择日期…" : "Choose a date…"
        }
    }

    private func addQuickReminder() {
        let title = quickReminderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let note = quickReminderNote.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.addReminder(Reminder(title: title, note: note.isEmpty ? nil : note,
                                         dueDate: dueDate(for: quickReminderDue),
                                         priority: quickReminderPriority,
                                         sessionId: session.id, programId: session.programId,
                                         taggedStudentIds: Array(quickReminderStudents)))
        quickReminderText = ""
        quickReminderNote = ""
        showQuickReminderNote = false
        quickReminderStudents = []
        quickReminderPriority = .medium
        quickReminderFocused = true
    }

    /// The reminder's details as chips under the quick-add field (14 Nov
    /// 2026, Luther: the sliders button opened a separate sheet — the
    /// options belong next to the due date). Due · athletes · priority ·
    /// note. Coach tagging was removed (no other coaches use the app).
    private var quickReminderOptions: some View {
        let athletes = enrolledStudents
        return FlowLayout(spacing: 8) {
            Menu {
                ForEach(QuickReminderDue.allCases, id: \.self) { choice in
                    Button {
                        quickReminderDue = choice
                    } label: {
                        if quickReminderDue == choice { Label(dueLabel(for: choice), systemImage: "checkmark") }
                        else { Text(dueLabel(for: choice)) }
                    }
                }
            } label: {
                reminderChip(icon: "calendar",
                             text: quickReminderDue == .custom
                                ? quickReminderCustomDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                : dueLabel(for: quickReminderDue),
                             active: true, tint: .accentColor)
            }
            if quickReminderDue == .custom {
                DatePicker("", selection: $quickReminderCustomDate, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }

            if !athletes.isEmpty {
                Menu {
                    ForEach(athletes) { student in
                        Button {
                            if quickReminderStudents.contains(student.id) { quickReminderStudents.remove(student.id) }
                            else { quickReminderStudents.insert(student.id) }
                        } label: {
                            if quickReminderStudents.contains(student.id) { Label(student.primaryDisplayName, systemImage: "checkmark") }
                            else { Text(student.primaryDisplayName) }
                        }
                    }
                } label: {
                    reminderChip(icon: "person.fill",
                                 text: taggedLabel(athletes.filter { quickReminderStudents.contains($0.id) }.map(\.primaryDisplayName),
                                                   empty: isChinese ? "学员" : "Athlete"),
                                 active: !quickReminderStudents.isEmpty, tint: .blue)
                }
                .menuActionDismissBehavior(.disabled)
            }

            Menu {
                ForEach(ReminderPriority.allCases, id: \.self) { p in
                    Button {
                        quickReminderPriority = p
                    } label: {
                        Label(p.displayName, systemImage: quickReminderPriority == p ? "checkmark" : p.icon)
                    }
                }
            } label: {
                reminderChip(icon: quickReminderPriority.icon, text: quickReminderPriority.displayName,
                             active: quickReminderPriority != .medium, tint: quickReminderPriority.color)
            }

            Button {
                withAnimation(.snappy(duration: 0.2)) { showQuickReminderNote.toggle() }
            } label: {
                reminderChip(icon: "text.alignleft", text: isChinese ? "备注" : "Note",
                             active: showQuickReminderNote || !quickReminderNote.isEmpty, tint: .orange, menu: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// "@" in the quick-add field: the session's athletes first, then
    /// everyone; a tap writes the name and tags them (the reminder then shows
    /// on their profile).
    @ViewBuilder
    private var mentionSuggestions: some View {
        if let query = ReminderMentions.activeQuery(in: quickReminderText) {
            let found = ReminderMentions.matches(query, in: dataManager.students,
                                                 preferred: enrolledStudents.map(\.id))
            if !found.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(found) { student in
                            Button {
                                quickReminderText = ReminderMentions.inserting(student.primaryDisplayName, into: quickReminderText)
                                quickReminderStudents.insert(student.id)
                            } label: {
                                HStack(spacing: 6) {
                                    StudentAvatarView(student: student, size: 22)
                                    Text(student.primaryDisplayName).font(.subheadline.weight(.medium))
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.14), in: Capsule())
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("reminders.mention")
                        }
                    }
                }
                .padding(.leading, 34)
            }
        }
    }

    private func taggedLabel(_ names: [String], empty: String) -> String {
        switch names.count {
        case 0: return empty
        case 1: return names[0]
        default: return "\(names[0]) +\(names.count - 1)"
        }
    }

    private func reminderChip(icon: String, text: String, active: Bool, tint: Color, menu: Bool = true) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption)
            Text(text).lineLimit(1)
            if menu {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(active ? tint : Color.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(active ? tint.opacity(0.14) : Color.primary.opacity(0.06), in: Capsule())
    }

    private var sessionRemindersPane: some View {
        let all = dataManager.reminders.filter { $0.sessionId == session.id }
        let open = all.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
        let done = all.filter(\.isCompleted).sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label {
                        Text(isChinese ? "这节课的提醒" : "REMINDERS FROM THIS SESSION").font(.caption2.weight(.bold)).monospaced()
                    } icon: {
                        Image(systemName: "bell").font(.caption).foregroundStyle(.orange)
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    if !open.isEmpty {
                        Text("\(open.count)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                if accessMode.canAddNotes {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            TextField(isChinese ? "添加提醒，@ 标记学员，按回车保存" : "Add a reminder — @ tags an athlete, Return saves", text: $quickReminderText)
                                .focused($quickReminderFocused)
                                .submitLabel(.done)
                                .onSubmit(addQuickReminder)
                                .accessibilityIdentifier("reminders.quickAdd")
                        }
                        mentionSuggestions
                        quickReminderOptions
                            .padding(.leading, 34)
                        if showQuickReminderNote {
                            TextField(isChinese ? "备注（可选）" : "Note (optional)", text: $quickReminderNote, axis: .vertical)
                                .font(.subheadline)
                                .lineLimit(1...4)
                                .padding(.leading, 34)
                                .accessibilityIdentifier("reminders.quickNote")
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if open.isEmpty {
                    Text(isChinese ? "课后要跟进的事写在这里。到期时会出现在首页的待办里。"
                                   : "Things to follow up after this class. When one is due it shows in Home's attention.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(open) { reminder in
                            sessionReminderRow(reminder)
                            if reminder.id != open.last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showDoneReminders.toggle() }
                    } label: {
                        HStack {
                            Label {
                                Text(isChinese ? "已完成 · \(done.count)" : "DONE · \(done.count)").font(.caption2.weight(.bold)).monospaced()
                            } icon: {
                                Image(systemName: "checkmark.circle").font(.caption)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .rotationEffect(.degrees(showDoneReminders ? 180 : 0))
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showDoneReminders {
                        ForEach(done) { sessionReminderRow($0) }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .accessibilityIdentifier("notes.reminders")
    }

    private func sessionReminderRow(_ reminder: Reminder) -> some View {
        let tagged = dataManager.students.filter { reminder.taggedStudentIds.contains($0.id) }
        return HStack(alignment: .top, spacing: 12) {
            Button {
                dataManager.toggleReminderCompletion(reminder)
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(reminder.isCompleted ? Color.green : reminder.statusColor)
            }
            .buttonStyle(.plain)
            .disabled(!accessMode.canAddNotes)
            .sensoryFeedback(.success, trigger: reminder.isCompleted)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                if let note = reminder.note, !note.isEmpty {
                    Text(note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label(reminder.relativeTimeString, systemImage: "calendar")
                        .foregroundStyle(reminder.isCompleted ? Color.secondary : reminder.statusColor)
                    if !tagged.isEmpty {
                        HStack(spacing: -6) {
                            ForEach(tagged.prefix(4)) { StudentAvatarView(student: $0, size: 18) }
                        }
                        Text(tagged.prefix(2).map(\.primaryDisplayName).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { if accessMode.canAddNotes { editingSessionReminder = reminder } }
        .contextMenu {
            Button { editingSessionReminder = reminder } label: { Label(isChinese ? "编辑" : "Edit", systemImage: "pencil") }
            Button(role: .destructive) { dataManager.deleteReminder(reminder) } label: {
                Label(isChinese ? "删除" : "Delete", systemImage: "trash")
            }
        }
        .accessibilityIdentifier("reminders.row")
    }

    /// Get the previous session in the same program (for notes carryover)
    private var previousSessionInProgram: SessionEvent? {
        guard let programId = session.programId else { return nil }
        
        // Get all sessions for this program, sorted by date descending
        let programSessions = dataManager.cachedSessionEvents
            .filter { $0.programId == programId && $0.id != session.id }
            .sorted { $0.startTime > $1.startTime }
        
        // Find the most recent session before the current one
        return programSessions.first { $0.startTime < session.startTime }
    }
    
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    
    // MARK: - iOS Notes Style Components
    
    private var notesTypeToggle: some View {
        Picker("Notes", selection: $notesPane) {
            Text(isChinese ? "提醒" : "Reminders").tag(NotesPane.reminders)
            Text(isChinese ? "笔记" : "Notes").tag(NotesPane.notes)
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: notesPane)
        .accessibilityIdentifier("notes.pane")
    }

    private var previousNotesIndentSection: some View {
        Group {
            if let prev = previousSessionInProgram, (prev.notes != nil || prev.coachNotes != nil) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPreviousNotes.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Label {
                                Text(isChinese ? "上次课程笔记" : "PREVIOUS SESSION NOTES")
                                    .font(.caption2.weight(.bold))
                                    .monospaced()
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)

                            Text("· \(prev.startTime.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showPreviousNotes ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .sensoryFeedback(.impact(weight: .light), trigger: showPreviousNotes)

                    if showPreviousNotes {
                        HStack(spacing: 0) {
                            Rectangle().fill(.tertiary).frame(width: 3)
                            VStack(alignment: .leading, spacing: 8) {
                                if let notes = prev.notes, !notes.isEmpty {
                                    Text(notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(6)
                                }
                                if let coachNotes = prev.coachNotes, !coachNotes.isEmpty {
                                    Text(coachNotes).font(.subheadline.italic()).foregroundStyle(.tertiary).lineLimit(4)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 8)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
    
    private var notesMentionPickerOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "提及" : "Mention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(enrolledStudents.prefix(10)) { student in
                            Button {
                                insertMention("@\(student.name)")
                                showMentionPicker = false
                            } label: {
                                Text("@\(student.name.components(separatedBy: " ").first ?? student.name)")
                                    .font(.footnote.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(Color.accentColor)
                        }
                        ForEach(activeCoachesForTagging) { coach in
                            Button {
                                insertMention("@\(coach.name)")
                                showMentionPicker = false
                            } label: {
                                Text("@\(coach.name.components(separatedBy: " ").first ?? coach.name)")
                                    .font(.footnote.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var notesTagPickerOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "标签" : "Tag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["focus", "improve", "highlight", "followup", "urgent"], id: \.self) { tag in
                            Button {
                                insertMention("#\(tag)")
                                showTagPicker = false
                            } label: {
                                Text("#\(tag)")
                                    .font(.footnote.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                            .tint(tag == "urgent" ? .red : .secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var notesFloatingActionBar: some View {
        HStack(spacing: 8) {
            Button {
                showNotesUtilities.toggle()
            } label: {
                Label(isChinese ? "笔记" : "Notes", systemImage: "square.grid.2x2")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.secondary)

            Button {
                withAnimation { showMentionPicker = true; showTagPicker = false }
            } label: {
                Label(isChinese ? "标签" : "Tag", systemImage: "at")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.secondary)

            Button {
                showReminderPanel.toggle()
            } label: {
                Label(isChinese ? "提醒" : "Remind", systemImage: "bell")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.secondary)

            Spacer()

            Button {
                appendQuickNote()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .tint(Color.accentColor)
            .sensoryFeedback(.success, trigger: activeNotesBinding.wrappedValue.count)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private func showFloatingBar() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showFloatingActionBar = true }
        floatingBarAutoHideTask?.cancel()
        floatingBarAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { withAnimation { showFloatingActionBar = false } }
            }
        }
    }
    
    private func checkForMentionTrigger(in text: String) {
        let lastChar = text.last
        if lastChar == "@" { withAnimation { showMentionPicker = true; showTagPicker = false } }
        else if lastChar == "#" { withAnimation { showTagPicker = true; showMentionPicker = false } }
        else if lastChar == " " || lastChar == "\n" { withAnimation { showMentionPicker = false; showTagPicker = false } }
    }

    private var notesWorkspaceHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isChinese ? "课程笔记" : "Session Notes")
                .font(.system(size: 18, weight: .bold))

            Text(isChinese ? "一个干净编辑区，其他功能按需展开。" : "One clean editor block with utilities revealed only when needed.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                notesHintChip(icon: "note.text", label: isChinese ? "条目" : "Entries")
                notesHintChip(icon: "square.grid.2x2", label: isChinese ? "便签" : "Sticky")
                notesHintChip(icon: "bell", label: isChinese ? "提醒" : "Reminders")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        )
    }

    private func notesHintChip(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private var activeNotesTitle: String {
        notesEditorTarget == .session ? (isChinese ? "课程笔记" : "Session Notes") : (isChinese ? "教练复盘" : "Coach Reflections")
    }

    private var activeNotesPlaceholder: String {
        notesEditorTarget == .session
            ? (isChinese ? "记录课程流程、训练重点和观察…" : "Capture structure, coaching cues, and observations...")
            : (isChinese ? "课后复盘、下次改进与球员反馈…" : "Post-session review, adjustments, and feedback...")
    }

    private var activeNotesBinding: Binding<String> {
        if notesEditorTarget == .session {
            return Binding(
                get: { session.notes ?? "" },
                set: { session.notes = $0.isEmpty ? nil : $0 }
            )
        }

        return Binding(
            get: { session.coachNotes ?? "" },
            set: { session.coachNotes = $0.isEmpty ? nil : $0 }
        )
    }

    private var notesUtilityBar: some View {
        HStack(spacing: 8) {
            subtleUtilityButton(
                icon: "square.grid.2x2",
                title: isChinese ? "笔记" : "Notes",
                isActive: showNotesUtilities
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNotesUtilities.toggle()
                }
            }

            subtleUtilityButton(
                icon: "at",
                title: isChinese ? "标签" : "Tag",
                isActive: showMentionPanel
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMentionPanel.toggle()
                }
            }

            subtleUtilityButton(
                icon: "bell",
                title: isChinese ? "提醒" : "Remind",
                isActive: showReminderPanel
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showReminderPanel.toggle()
                }
            }

            Spacer()

            Button {
                appendQuickNote()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(programColor)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!accessMode.canAddNotes)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func subtleUtilityButton(icon: String, title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(isActive ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isActive ? programColor : Color.gray.opacity(0.12))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var notesModeAndSearchBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                notesModeButton(.all, title: isChinese ? "全部" : "All")
                notesModeButton(.sticky, title: isChinese ? "便签" : "Sticky")
                notesModeButton(.templates, title: isChinese ? "模板" : "Templates")
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField(isChinese ? "搜索笔记" : "Search notes", text: $notesSearchText)
                    .font(.system(size: 13))

                if !notesSearchText.isEmpty {
                    Button {
                        notesSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func notesModeButton(_ mode: NotesViewMode, title: String) -> some View {
        Button {
            notesViewMode = mode
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(notesViewMode == mode ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(notesViewMode == mode ? programColor : Color.gray.opacity(0.12))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var quickNoteComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isChinese ? "新建笔记" : "New Note")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    mentionTargetButton(title: isChinese ? "课程" : "Session", target: .session)
                    mentionTargetButton(title: isChinese ? "复盘" : "Reflection", target: .reflections)
                }
            }

            TextField(isChinese ? "标题" : "Title", text: $quickNoteTitle)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)

            TextField(isChinese ? "写下内容…" : "Write your note...", text: $quickNoteBody, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)

            HStack {
                Text(isChinese ? "支持 @球员 / @教练 标签" : "Supports @player / @coach mentions")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    appendQuickNote()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(isChinese ? "添加" : "Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(programColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!accessMode.canAddNotes)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var notesCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if (notesViewMode == .sticky ? stickyNoteCards : filteredNoteCards).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(isChinese ? "还没有笔记，先创建一条。" : "No notes yet. Create your first one.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else if notesViewMode == .sticky {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(stickyNoteCards.indices, id: \.self) { index in
                        noteCardView(stickyNoteCards[index], index: index, compact: true)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredNoteCards.indices, id: \.self) { index in
                        noteCardView(filteredNoteCards[index], index: index, compact: false)
                    }
                }
            }
        }
    }

    private func noteCardView(_ card: SessionNoteCard, index: Int, compact: Bool) -> some View {
        let pastelColors: [Color] = [
            Color.blue.opacity(0.14),
            Color.pink.opacity(0.16),
            Color.green.opacity(0.14),
            Color.yellow.opacity(0.16),
            Color.purple.opacity(0.14)
        ]
        let cardColor = pastelColors[index % pastelColors.count]

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(card.title)
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
                    .lineLimit(compact ? 2 : 1)
                Spacer(minLength: 6)
                if let timeLabel = card.timeLabel {
                    Text(timeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if !card.body.isEmpty {
                Text(card.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : 2)
            }

            HStack {
                Text(card.source == .session ? (isChinese ? "课程" : "Session") : (isChinese ? "复盘" : "Reflection"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.7))
                    .cornerRadius(7)
                Spacer()
                Button {
                    if pinnedNoteIDs.contains(card.id) {
                        pinnedNoteIDs.remove(card.id)
                    } else {
                        pinnedNoteIDs.insert(card.id)
                    }
                } label: {
                    Image(systemName: pinnedNoteIDs.contains(card.id) ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private var noteTemplatesSection: some View {
        let templates: [(String, String, NotesEditorTarget)] = [
            (
                isChinese ? "课程复盘" : "Session Review",
                isChinese ? "今天有效的训练点\n- \n\n下次调整\n- " : "What worked\n- \n\nAdjust next time\n- ",
                .reflections
            ),
            (
                isChinese ? "球员观察" : "Player Observation",
                isChinese ? "球员: @\n亮点:\n改进:\n下一步:" : "Player: @\nStrength:\nNeeds work:\nNext step:",
                .session
            ),
            (
                isChinese ? "训练计划笔记" : "Practice Plan Note",
                isChinese ? "目标\n- \n\n关键口令\n- \n\n结束回顾\n- " : "Objective\n- \n\nKey cues\n- \n\nDebrief\n- ",
                .session
            )
        ]

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(templates.enumerated()), id: \.offset) { _, item in
                Button {
                    quickNoteTitle = item.0
                    quickNoteBody = item.1
                    notesEditorTarget = item.2
                    notesViewMode = .all
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.0)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(item.1.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mentionsComposerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isChinese ? "插入标签" : "Insert Mentions", systemImage: "at")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(spacing: 8) {
                mentionTargetButton(title: isChinese ? "课程笔记" : "Session", target: .session)
                mentionTargetButton(title: isChinese ? "教练复盘" : "Reflections", target: .reflections)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(enrolledStudents.prefix(12)) { student in
                        Button {
                            insertMention("@\(student.name)")
                        } label: {
                            Text("@\(student.name.components(separatedBy: " ").first ?? student.name)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    ForEach(activeCoachesForTagging) { coach in
                        Button {
                            insertMention("@\(coach.name)")
                        } label: {
                            Text("@\(coach.name.components(separatedBy: " ").first ?? coach.name)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.purple.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        )
    }

    private func mentionTargetButton(title: String, target: NotesEditorTarget) -> some View {
        Button {
            notesEditorTarget = target
            focusedNotesEditor = target
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(notesEditorTarget == target ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(notesEditorTarget == target ? programColor : Color.gray.opacity(0.12))
                .cornerRadius(8)
        }
    }

    private func notionEditorCard(
        title: String,
        icon: String,
        target: NotesEditorTarget,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if notesEditorTarget == target {
                    Text(isChinese ? "编辑中" : "Editing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(programColor)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .focused($focusedNotesEditor, equals: target)
                    .font(.system(size: 14))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.07))
                    .cornerRadius(10)
                    .disabled(!accessMode.canAddNotes)
                    .onTapGesture {
                        notesEditorTarget = target
                    }

                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        )
    }

    private func insertMention(_ mention: String) {
        guard accessMode.canAddNotes else { return }

        switch notesEditorTarget {
        case .session:
            let base = (session.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            session.notes = base.isEmpty ? "\(mention) " : "\(base) \(mention) "
            focusedNotesEditor = .session
        case .reflections:
            let base = (session.coachNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            session.coachNotes = base.isEmpty ? "\(mention) " : "\(base) \(mention) "
            focusedNotesEditor = .reflections
        }
    }

    private func appendQuickNote() {
        guard accessMode.canAddNotes else { return }

        let cleanBody = quickNoteBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty else { return }

        let title = quickNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? (isChinese ? "未命名笔记" : "Untitled Note") : title
        let timePrefix = isChinese ? "时间" : "Time"
        let entry = "\(resolvedTitle)\n\(cleanBody)\n\(timePrefix): \(Date().formatted(date: .omitted, time: .shortened))"

        switch notesEditorTarget {
        case .session:
            session.notes = appendEntry(entry, into: session.notes)
        case .reflections:
            session.coachNotes = appendEntry(entry, into: session.coachNotes)
        }

        quickNoteTitle = ""
        quickNoteBody = ""
        notesViewMode = .all
        saveSession()
    }

    private func appendEntry(_ entry: String, into existing: String?) -> String {
        let clean = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return entry }
        return clean + notesDelimiter + entry
    }

    private func noteCards(from text: String, source: NotesEditorTarget) -> [SessionNoteCard] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return trimmed
            .components(separatedBy: notesDelimiter)
            .enumerated()
            .compactMap { index, raw in
                let cleanEntry = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanEntry.isEmpty else { return nil }

                let lines = cleanEntry.components(separatedBy: .newlines)
                let title = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? (isChinese ? "未命名" : "Untitled")
                let timeLine = lines.first(where: {
                    $0.lowercased().hasPrefix("time:") || $0.hasPrefix("时间:") || $0.hasPrefix("时间：")
                })

                let body = lines
                    .dropFirst()
                    .filter {
                        let lowered = $0.lowercased()
                        return !lowered.hasPrefix("time:") && !$0.hasPrefix("时间:") && !$0.hasPrefix("时间：")
                    }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let timeLabel = timeLine?
                    .replacingOccurrences(of: "Time:", with: "")
                    .replacingOccurrences(of: "time:", with: "")
                    .replacingOccurrences(of: "时间:", with: "")
                    .replacingOccurrences(of: "时间：", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return SessionNoteCard(
                    id: "\(source == .session ? "s" : "r")-\(index)-\(title)",
                    title: title,
                    body: body,
                    source: source,
                    timeLabel: timeLabel
                )
            }
    }
    
    private func afterClassCard<Content: View>(_ title: String, icon: String, tint: Color,
                                               @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title).font(.caption2.weight(.bold)).monospaced()
            } icon: {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
            }
            .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var ratingSection: some View {
        afterClassCard(isChinese ? "课程评分" : "HOW DID IT GO", icon: "star.fill", tint: .yellow) {
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        session.rating = session.rating == star ? nil : star
                        saveSession()
                    } label: {
                        Image(systemName: star <= (session.rating ?? 0) ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= (session.rating ?? 0) ? Color.yellow : Color.secondary.opacity(0.5))
                            .symbolEffect(.bounce, value: session.rating)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!accessMode.canAddNotes)
                    .sensoryFeedback(.impact(weight: .light), trigger: session.rating)
                }
                Spacer(minLength: 0)
                if let r = session.rating {
                    Text(ratingWord(r))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("notes.rating")
    }

    private func ratingWord(_ r: Int) -> String {
        let en = ["Rough", "So-so", "Solid", "Good", "Great"], zh = ["较差", "一般", "不错", "很好", "非常好"]
        let i = max(1, min(5, r)) - 1
        return isChinese ? zh[i] : en[i]
    }

    private var manOfTheMatchSection: some View {
        afterClassCard(isChinese ? "本课最佳" : "PLAYER OF THE SESSION", icon: "crown.fill", tint: .orange) {
            if let momId = session.manOfTheMatchId,
               let student = dataManager.students.first(where: { $0.id == momId }) {
                HStack(spacing: 12) {
                    StudentAvatarView(student: student, size: 44)
                        .overlay(Circle().strokeBorder(Color.orange, lineWidth: 2).padding(-3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(student.primaryDisplayName)
                            .font(.headline)
                            .lineLimit(1)
                        if let second = student.secondaryNameLine {
                            Text(second).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if accessMode.canAddNotes {
                        Button(isChinese ? "更换" : "Change") { showingStudentPicker = true }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
            } else {
                Button {
                    showingStudentPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                        Text(isChinese ? "选择本课最佳球员" : "Choose who stood out")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!accessMode.canAddNotes)
                .sensoryFeedback(.selection, trigger: showingStudentPicker)
            }
        }
        .accessibilityIdentifier("notes.player")
    }
    
    // MARK: - Actions
    private func toggleAttendance(for studentId: UUID) {
        let willBePresent: Bool
        if session.actualAttendeeIds.contains(studentId) {
            session.actualAttendeeIds.removeAll { $0 == studentId }
            willBePresent = false
        } else {
            session.actualAttendeeIds.append(studentId)
            session.excusedAbsences.removeAll { $0 == studentId }
            willBePresent = true
        }
        // Field-level write — see `setAttendanceState` for rationale.
        dataManager.setStudentAttendanceState(
            sessionId: session.id,
            studentId: studentId,
            state: willBePresent ? .present : .absent
        )
    }
    
    private func skipSession(reason: SkipReason) {
        SessionLifecycle.apply(.skip(reason), to: &session)
        saveSession()
        HapticFeedback.notification(.warning)
    }

    private func cancelSession() {
        SessionLifecycle.apply(.cancel, to: &session)
        saveSession()
        HapticFeedback.notification(.warning)
    }

    /// Reset a session back to `.scheduled`. Used to undo a status set
    /// by mistake (or by the legacy auto-status monitor). Attendance is
    /// preserved — only the status field flips. If the user wants to also
    /// clear who was marked present, they can toggle each athlete off.
    private func resetToScheduled() {
        // If the session was running on the live engine, stop it; a
        // scheduled session shouldn't have a live activity in flight.
        #if os(iOS)
        if session.status == .inProgress {
            Task { @MainActor in
                SessionLiveActivityManager.shared.endActivity(showAttendanceReminder: false)
            }
            if LiveSessionEngine.shared.session?.id == session.id {
                LiveSessionEngine.shared.end()
            }
        }
        #endif

        SessionLifecycle.apply(.resetToScheduled, to: &session)
        saveSession()
        HapticFeedback.notification(.success)
    }
    
    /// Completes the session and opens the roll-call photo prompt
    /// (October 2026, Luther). A past session that never started (the app
    /// was not open during its window) is started first, so the lifecycle's
    /// scheduled → in progress → completed path is always the one taken —
    /// .complete alone is only legal from in progress, and "Mark Completed"
    /// on such a session used to save without changing anything.
    private func completeSession() {
        if session.status == .scheduled {
            SessionLifecycle.apply(.start, to: &session)
        }
        guard SessionLifecycle.apply(.complete, to: &session) else { return }
        saveSession()

        #if os(iOS)
        if LiveSessionEngine.shared.session?.id == session.id {
            LiveSessionEngine.shared.end()
        }
        Task { @MainActor in
            SessionLiveActivityManager.shared.endActivity(showAttendanceReminder: true)
        }
        // The roll-call photo: who was there, as a picture. Skipped if one
        // was already taken (e.g. from the 5-minute reminder).
        if session.attendancePhotoPath == nil {
            rollCallReason = .completed
            showingSessionPhotoCapture = true
        }
        #endif
    }
    
    private func saveSession() {
        debugLog("🎮 [DEBUG] saveSession called for: \(session.title)")
        debugLog("   - Games count: \(session.games.count)")
        if !session.games.isEmpty {
            for game in session.games {
                debugLog("   - Game \(game.gameNumber): status=\(game.status.rawValue), stats=\(game.playerStats.count)")
            }
        }
        session.updatedAt = Date()
        // Details only: games, marks and the photo are written field by
        // field as they happen and keep the store's values here, so this
        // copy can never erase them however stale it is.
        dataManager.updateSessionEvent(session, keepLiveFields: true)
    }
    
    private func deleteSession() {
        dataManager.deleteSessionEvent(session)
        dismiss()
    }
}

private enum DrillLibraryVisibility: String, CaseIterable {
    case privateOnly
    case shared

    var title: String {
        switch self {
        case .privateOnly: return "Private"
        case .shared: return "Shared"
        }
    }

    var chineseTitle: String {
        switch self {
        case .privateOnly: return "仅自己"
        case .shared: return "共享给教练"
        }
    }
}

private struct QuickCreateDrillInput {
    let title: String
    let steps: [String]
    let details: String
    let durationMinutes: Int
    let difficulty: DifficultyLevel
    let visibility: DrillLibraryVisibility
}

private struct QuickCreateDrillSheet: View {
    @Environment(\.dismiss) private var dismiss

    let section: CurriculumSection
    let onCreate: (QuickCreateDrillInput) -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var stepsText = ""
    @State private var durationMinutes = 10
    @State private var difficulty: DifficultyLevel = .beginner
    @State private var visibility: DrillLibraryVisibility = .privateOnly

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TextField(isChinese ? "训练标题" : "Drill title", text: $title)
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)

                    TextField(isChinese ? "训练描述（可选）" : "Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)

                    TextField(
                        isChinese ? "步骤（每行一个）" : "Steps (one per line)",
                        text: $stepsText,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    HStack(spacing: 10) {
                        Picker(isChinese ? "时长" : "Duration", selection: $durationMinutes) {
                            ForEach([5, 8, 10, 12, 15, 20, 25, 30], id: \.self) { value in
                                Text(isChinese ? "\(value) 分钟" : "\(value) min").tag(value)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker(isChinese ? "难度" : "Difficulty", selection: $difficulty) {
                            ForEach(DifficultyLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)

                    Picker(isChinese ? "可见性" : "Visibility", selection: $visibility) {
                        ForEach(DrillLibraryVisibility.allCases, id: \.self) { option in
                            Text(isChinese ? option.chineseTitle : option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(isChinese ? "快速创建训练" : "Quick Create Drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "添加" : "Add") {
                        let steps = stepsText
                            .split(separator: "\n")
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }

                        onCreate(
                            QuickCreateDrillInput(
                                title: title,
                                steps: steps,
                                details: details,
                                durationMinutes: durationMinutes,
                                difficulty: difficulty,
                                visibility: visibility
                            )
                        )
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                switch section {
                case .warmup: durationMinutes = 8
                case .main: durationMinutes = 12
                case .cooldown: durationMinutes = 10
                }
            }
        }
    }
}

// MARK: - Skip Reason
// SkipReason moved to Models/SessionLifecycle.swift (shared with Mac).

// MARK: - Skip Session Sheet
struct SkipSessionSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var reason: SkipReason
    let onConfirm: () -> Void
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(isChinese ? "跳过课程" : "Skip Session")
                        .font(.title2.bold())
                    Text(isChinese ? "跳过的课程不会计入合同消耗" : "Skipped sessions won't count toward contracts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                // Reason picker
                VStack(alignment: .leading, spacing: 8) {
                    Text(isChinese ? "原因" : "Reason")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(SkipReason.allCases) { r in
                            Button {
                                reason = r
                                HapticFeedback.impact(.light)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: r.icon)
                                        .font(.system(size: 14))
                                    Text(r.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(reason == r ? Color.orange.opacity(0.15) : Color(.systemGray6))
                                .foregroundColor(reason == r ? .orange : .primary)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(reason == r ? Color.orange : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(isChinese ? "确认跳过" : "Confirm Skip")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .tint(Color.accentColor)
                .padding(.horizontal)
                .padding(.bottom)
                .sensoryFeedback(.warning, trigger: false)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        FlightySessionPageView(
            session: SessionEvent(
                microCycleId: nil,
                programId: nil,
                sessionType: .training,
                title: "U12 Training",
                date: Date(),
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                location: "Main Court"
            ),
            accessMode: .execution
        )
        .environmentObject(DataManager.shared)
    }
}

// MARK: - Session Games Tab View (iOS Only)
#if os(iOS)
struct SessionGamesTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Binding var session: SessionEvent
    let enrolledStudents: [Student]
    let programColor: Color
    let onSave: () -> Void
    /// Organization coaches playing in this scrimmage / game prep: on game
    /// teams like anyone, left out of every stat and insight.
    var guestPlayers: [Student] = []

    /// Everyone who can be put on a team or scored.
    private var players: [Student] { enrolledStudents + guestPlayers }
    
    @State private var showingCreateGame = false
    @State private var selectedGame: SessionGame?
    @State private var selectedRecapGame: SessionGame?

    /// Every played game of this session's program so far (just this
    /// session's when it has no program) — GameStatsReport.
    private var statsSessions: [SessionEvent] {
        let all = session.programId.map { pid in
            dataManager.sessionEvents.filter { $0.programId == pid && $0.id != session.id } + [session]
        } ?? [session]
        // Coaches who played are not athletes: their lines leave the stats.
        let coachIds = Set(dataManager.staffCoaches.map(\.id))
        return all.map { GameStatsReport.withoutPlayers(coachIds, in: $0) }
    }

    private var gameStats: GameStatsReport.Report {
        GameStatsReport.make(sessions: statsSessions, roster: enrolledStudents.map(\.id), current: session,
                             excluding: Set(dataManager.staffCoaches.map(\.id)))
    }

    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    @State private var gameToDelete: SessionGame?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            // The record of games and, beside it on iPad / Mac (under it on
            // the phone), the dashboard of how they were played (14 Nov 2026).
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 20) {
                    gamesColumn
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: 480)
                    analysisColumn
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            } else {
                VStack(spacing: 24) {
                    gamesColumn
                    analysisColumn
                        .padding(.horizontal, 16)
                    Spacer(minLength: 76)
                }
                .padding(.top, 8)
            }
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除比赛" : "Delete Game", isPresented: Binding(
            get: { gameToDelete != nil },
            set: { if !$0 { gameToDelete = nil } }
        )) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) {
                gameToDelete = nil
            }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) {
                if let game = gameToDelete {
                    deleteGame(game)
                }
            }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "确定要删除这场比赛吗？" : "Are you sure you want to delete this game?")
        }
        .fullScreenCover(isPresented: $showingCreateGame) {
            CreateGameSheet(session: $session, enrolledStudents: players, programColor: programColor, onSave: onSave)
        }
        .fullScreenCover(item: $selectedGame) { game in
            if let index = session.games.firstIndex(where: { $0.id == game.id }) {
                LiveGameScoringView(
                    // Custom binding: local mutation for UI, then a
                    // field-level write that updates ONLY this one game's
                    // entry — siblings (other games, photo, attendance)
                    // stay intact even if our local snapshot is stale.
                    game: Binding(
                        get: { session.games[index] },
                        set: { updated in
                            session.games[index] = updated
                            dataManager.updateSessionGame(inSessionId: session.id, game: updated)
                        }
                    ),
                    students: players,
                    allGamesInSession: session.games,
                    // The Save button on the scoring screen used to do a
                    // whole-session overwrite. The binding above already
                    // persists per change, so this is a no-op stub —
                    // safer than a stale full-session write.
                    onSave: {},
                    onSaveCompletedRound: { completedRound in
                        session.games.append(completedRound)
                        dataManager.appendSessionGame(toSessionId: session.id, game: completedRound)
                    }
                )
            }
        }
        .fullScreenCover(item: $selectedRecapGame) { game in
            GameRecapView(game: game, students: players, allGamesInSession: session.games)
        }

    }
    
    private var gamesColumn: some View {
        VStack(spacing: 0) {
            gamesHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if session.games.isEmpty {
                emptyGamesState
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(session.games.enumerated()), id: \.element.id) { index, game in
                        if horizontalSizeClass == .regular { wideGameRow(game) } else { gameRow(game) }
                        if index < session.games.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
        }
    }

    /// The dashboard, then at most three things worth acting on from the
    /// program's games so far (October 2026, Luther: limited, smart).
    @ViewBuilder
    private var analysisColumn: some View {
        let report = gameStats
        let insights = GameStatsReport.insights(report: report, sessions: statsSessions,
                                                roster: enrolledStudents.map(\.id))
        let played = statsSessions.contains { $0.games.contains(where: GameStatsReport.played) }
        VStack(alignment: .leading, spacing: 24) {
            if played {
                GameDashboardView(programSessions: statsSessions, session: session,
                                  roster: enrolledStudents.map(\.id), students: dataManager.students,
                                  excluding: Set(dataManager.staffCoaches.map(\.id)))
            }
            if !insights.isEmpty {
                GameInsightsView(insights: insights, games: report.games, sessions: report.sessions,
                                 students: dataManager.students)
            }
        }
    }

    private var gamesHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "比赛" : "SCRIMMAGE GAMES")
                    .font(.caption.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
                Text("^[\(session.games.count) game](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText(value: Double(session.games.count)))
            }
            Spacer()
            Button {
                showingCreateGame = true
            } label: {
                Label(isChinese ? "新比赛" : "New Game", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.accentColor)
            .sensoryFeedback(.selection, trigger: showingCreateGame)
        }
    }
    
    /// "Why play games?" — one coaching tip, unattributed (17 Nov 2026,
    /// before App Store submission: the card used to credit quotes to real
    /// players and coaches that could not be sourced).
    private var emptyGamesState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let tips: [String] = isChinese ? [
            "孩子们通过打比赛学得最快：竞争、应对压力、与队友沟通，这些是技术练习教不会的。",
            "多比赛、少说教。比赛本身就是最好的老师。",
            "让比赛成为老师。在有意义的比赛情境中，孩子们学得更快。",
            "训练中学到的东西，只有放进比赛里才真正有意义。",
            "允许孩子犯错。比赛中的错误是最好的学习机会。",
            "篮球智商是在比赛中打出来的，不是在训练中讲出来的。",
            "孩子们需要感受比赛的节奏，任何练习都无法完全模拟。",
            "让比赛保持有趣——孩子们在玩乐中学得最快。",
            "真正的判断力只能在真实的比赛压力下培养。",
            "让孩子在比赛中自己解决问题，而不是直接告诉他们答案。",
            "比赛给孩子最真实的反馈。",
            "3对3、4对4、5对5，让每个孩子都有更多触球和决策的机会。",
        ] : [
            "Kids learn fastest by playing games: competing, handling pressure and talking to teammates are things drills can't teach.",
            "Coach less, play more. The game itself is the best teacher.",
            "Let the game be the teacher. Kids learn faster in game situations that mean something.",
            "What kids learn in drills only makes sense once they use it in a game.",
            "Let kids make mistakes. Mistakes in games are the best learning moments.",
            "Basketball IQ is built by playing, not explained in practice.",
            "Kids need to feel the rhythm of a game. No drill quite recreates it.",
            "Keep games fun — kids learn fastest when they're enjoying it.",
            "Real decision-making only grows under real game pressure.",
            "Let kids solve problems in games instead of handing them the answers.",
            "Games give kids the most honest feedback there is.",
            "Small-sided games — 3v3, 4v4 — give every child more touches and more decisions.",
        ]
        let tip = tips[Int.random(in: 0..<tips.count)]

        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "为什么要打比赛？" : "Why Play Games?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }

            Text(tip)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func quickStartGameButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func createStarterGame(type: SessionGameType) {
        let availableStudents = enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }
        // Coaches on a scrimmage are always in the pool (they take no roll call).
        let playerPool = (availableStudents.isEmpty ? enrolledStudents : availableStudents) + guestPlayers

        guard playerPool.count >= 2 else {
            showingCreateGame = true
            return
        }

        let gameNumber = (session.games.map { $0.gameNumber }.max() ?? 0) + 1
        let teamCount = max(type.requiredTeams, 2)
        var teams: [GameTeam] = []

        if !type.isIndividual {
            for index in 0..<teamCount {
                let preset = GameTeam.presetColors[index]
                teams.append(GameTeam(name: preset.name, colorHex: preset.hex))
            }

            for (index, student) in playerPool.enumerated() {
                teams[index % teamCount].playerIds.append(student.id)
            }
        }

        var newGame = SessionGame(
            sessionId: session.id,
            gameNumber: gameNumber,
            gameType: type,
            teams: teams,
            durationMinutes: 10,
            basketValue: UserDefaults.standard.object(forKey: SessionGame.basketValueDefaultsKey) as? Int ?? 2,
            status: .ready
        )

        if type.isIndividual {
            newGame.playerStats = playerPool.map {
                SessionPlayerStats(playerId: $0.id, gameId: newGame.id, teamId: newGame.id)
            }
        }

        // Optimistic local update for snappy UI, then a field-level write
        // through SwiftDataManager. The field-level helper reads the current
        // SDSessionEvent from the model context and only mutates `games`, so
        // a stale `@State session` on this view (or any sibling view) can
        // no longer wipe sibling fields like `attendancePhotoPath`.
        session.games.append(newGame)
        dataManager.appendSessionGame(toSessionId: session.id, game: newGame)
        selectedGame = newGame
    }

    private func deleteGame(_ game: SessionGame) {
        session.games.removeAll { $0.id == game.id }
        dataManager.deleteSessionGame(inSessionId: session.id, gameId: game.id)
    }

    
    private func gameRow(_ game: SessionGame) -> some View {
        HStack(spacing: 12) {
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Game \(game.gameNumber)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    statusBadge(game.status)
                }

                HStack(spacing: 6) {
                    Image(systemName: game.gameType.icon)
                        .font(.caption2)
                    Text(game.gameType.displayName)
                        .font(.caption.weight(.medium))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(game.durationMinutes) min")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Compact team scores
            if !game.teams.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(game.activeTeams.enumerated()), id: \.element.id) { index, team in
                        compactTeamScore(team: team, score: game.score(for: team.id))
                        if index < game.activeTeams.count - 1 {
                            Text("–")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Action button
            Button {
                if game.status == .completed {
                    selectedRecapGame = game
                } else {
                    selectedGame = game
                }
            } label: {
                Image(systemName: game.status == .completed ? "chart.bar.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .controlSize(.small)
            .tint(game.status == .completed ? .green : Color.accentColor)
            .sensoryFeedback(.selection, trigger: selectedGame?.id)

            // Delete button
            Button(role: .destructive) {
                gameToDelete = game
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .tint(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if game.status == .completed {
                selectedRecapGame = game
            } else {
                selectedGame = game
            }
        }
    }

    private func openGame(_ game: SessionGame) {
        if game.status == .completed { selectedRecapGame = game } else { selectedGame = game }
    }

    /// iPad / Mac (14 Nov 2026, Luther: "Game 1 and completed, a bit
    /// awkward" — in the narrower games column the old row broke its words
    /// letter by letter). One line each side: the game and how it is played;
    /// the score with the winner bright; a ⋯ menu instead of two buttons.
    private func wideGameRow(_ game: SessionGame) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let teams = game.activeTeams.isEmpty ? game.teams : game.activeTeams
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(isChinese ? "第\(game.gameNumber)场" : "Game \(game.gameNumber)")
                        .font(.headline)
                    if game.status == .completed {
                        Text(isChinese ? "终场" : "FINAL")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    } else {
                        statusBadge(game.status)
                    }
                }
                .lineLimit(1)
                Label {
                    Text("\(game.gameType.displayName) · \(game.durationMinutes) min")
                } icon: {
                    Image(systemName: game.gameType.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)

            Spacer(minLength: 8)

            if teams.count == 2 {
                let a = game.score(for: teams[0].id), b = game.score(for: teams[1].id)
                HStack(spacing: 8) {
                    wideScore(teams[0], a, bright: a >= b || game.status != .completed, dotFirst: true)
                    Text("–").font(.subheadline).foregroundStyle(.tertiary)
                    wideScore(teams[1], b, bright: b >= a || game.status != .completed, dotFirst: false)
                }
                .fixedSize()
            } else if let leader = game.individualLeaderboard.first {
                Text("\(leader.points)")
                    .font(.title3.weight(.bold).monospacedDigit())
            }

            Menu {
                Button {
                    openGame(game)
                } label: {
                    Label(game.status == .completed ? (isChinese ? "比赛回顾" : "Game Recap") : (isChinese ? "继续记分" : "Keep Scoring"),
                          systemImage: game.status == .completed ? "chart.bar.fill" : "play.fill")
                }
                Button(role: .destructive) {
                    gameToDelete = game
                } label: {
                    Label(isChinese ? "删除比赛" : "Delete Game", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("games.row.menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { openGame(game) }
        .accessibilityIdentifier("games.row")
    }

    private func wideScore(_ team: GameTeam, _ score: Int, bright: Bool, dotFirst: Bool) -> some View {
        let dot = Circle()
            .fill(Color(hex: team.colorHex))
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1))
            .frame(width: 12, height: 12)
        let number = Text("\(score)")
            .font(.title3.weight(.bold).monospacedDigit())
            .foregroundStyle(bright ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentTransition(.numericText(value: Double(score)))
        return HStack(spacing: 6) {
            if dotFirst { dot; number } else { number; dot }
        }
    }

    private func compactTeamScore(team: GameTeam, score: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: team.colorHex))
                .frame(width: 14, height: 14)
                .overlay(
                    Text(String(team.name.prefix(1)))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text("\(score)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(team.displayColor(for: colorScheme))
                .contentTransition(.numericText(value: Double(score)))
        }
    }

    private func statusBadge(_ status: SessionGameStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
                .symbolEffect(.pulse, options: .repeating, isActive: status == .inProgress)
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }

    private func statusColor(_ status: SessionGameStatus) -> Color {
        switch status {
        case .setup: return .secondary
        case .ready: return Color.accentColor
        case .inProgress: return .red
        case .paused: return .secondary
        case .completed: return .green
        }
    }
}

// MARK: - Scroll Offset Preference Key
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


struct LiveGameScoringView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var game: SessionGame
    let students: [Student]
    let allGamesInSession: [SessionGame]
    let onSave: () -> Void
    var onSaveCompletedRound: ((SessionGame) -> Void)? = nil  // Callback to save completed round as new game
    @State private var timerSeconds: Int = 0
    @State private var isTimerRunning = false
    @State private var selectedTeamIndex: Int = 0
    @State private var headerCollapsed = false
    @State private var showingRecap = false
    /// Value of the next basket scored by tapping a row; back to the game's
    /// standard value (setup page) after each basket.
    @State private var basketValue = 2
    /// Every stat logged on this screen, newest last — what Undo reverses.
    @State private var actionLog: [GameStatAction] = []
    @State private var undoTick = 0
    /// Set the moment the countdown reaches 0 so we don't fire the alarm
    /// every tick afterward. Reset by `resetTimer()` and on round transitions.
    @State private var hasFiredAlarm = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Countdown helpers

    /// Total seconds the game is configured to run.
    private var totalSeconds: Int { game.durationMinutes * 60 }

    /// Seconds left on the clock. Goes negative once we're in overtime;
    /// the game does not auto-end at zero — the coach decides.
    private var remainingSeconds: Int { totalSeconds - timerSeconds }

    /// Display string. Counts down to 00:00, then keeps going as "OT MM:SS"
    /// so coaches can see how much extra they're letting it run.
    private var formattedClock: String {
        if remainingSeconds >= 0 {
            return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
        }
        let over = -remainingSeconds
        return String(format: "OT %02d:%02d", over / 60, over % 60)
    }

    /// True once we've crossed zero — drives the red-flash colour and the
    /// reset of the alarm guard.
    private var isExpired: Bool { timerSeconds >= totalSeconds }

    /// Has the clock entered the warning window (last 30s)? Used for tint.
    private var isWarningWindow: Bool {
        remainingSeconds > 0 && remainingSeconds <= 30
    }

    private var clockTint: Color {
        if isExpired { return .red }
        if isWarningWindow { return .orange }
        return .primary
    }
    
    private var isBattleRoyal: Bool { game.gameType.isIndividual }
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isBattleRoyal {
                    battleRoyalCompactHeader
                    battleRoyalPlayersList
                } else if isIPad && activeTeamsForScoring.count == 2 {
                    // iPad / Mac: the same entry as the phone, both teams
                    // side by side (November 2026 — the old two-column
                    // screen with per-player +1/+2/+3 buttons is retired).
                    liveScoreboard
                    liveEntryWide
                } else {
                    // iPhone: one team at a time, all its players on screen
                    // (October 2026 field redesign — see LiveTeamPanel).
                    liveScoreboard
                    liveEntry
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isBattleRoyal ? (isChinese ? "大乱斗 \(game.gameNumber)" : "Battle Royal \(game.gameNumber)") : "Game \(game.gameNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { onSave(); dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !isBattleRoyal && game.teams.count > 2 && game.status != .completed {
                        Button(action: endRound) {
                            Label(isChinese ? "下一轮" : "Next Round", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(Color.accentColor)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if game.status != .completed {
                        Button(role: .destructive, action: endGame) {
                            Text(isChinese ? "结束" : "End Game")
                        }
                    }
                }
            }
            .onReceive(timer) { _ in
                guard isTimerRunning && game.status == .inProgress else { return }
                timerSeconds += 1
                // First tick that crosses the duration: ring + vibrate but
                // keep ticking. Coach manually ends the game from the toolbar.
                if !hasFiredAlarm && isExpired {
                    fireExpirationAlarm()
                    hasFiredAlarm = true
                }
            }
            .onAppear {
                if game.status == .inProgress, let startedAt = game.startedAt {
                    timerSeconds = Int(Date().timeIntervalSince(startedAt))
                    // If the app was backgrounded past expiration, don't
                    // ring the alarm now — only ring on a live transition.
                    if isExpired { hasFiredAlarm = true }
                }
            }
            .sheet(isPresented: $showingRecap) {
                GameRecapView(game: game, students: students, allGamesInSession: allGamesInSession)
            }
        }
    }
    
    // MARK: - Battle Royal Header
    private var battleRoyalHeader: some View {
        VStack(spacing: 16) {
            // Timer
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerSeconds >= game.durationMinutes * 60 ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                    .contentTransition(.numericText())
                Text("/ \(game.durationMinutes):00")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Timer controls
            if game.status != .completed {
                HStack(spacing: 12) {
                    Button(action: toggleTimer) {
                        Label(
                            isTimerRunning ? (isChinese ? "暂停" : "Pause")
                                            : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume")),
                            systemImage: isTimerRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .tint(isTimerRunning ? .red : .green)
                    .sensoryFeedback(.impact, trigger: isTimerRunning)

                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(.secondary)
                }
            }

            // Crown + title
            Label {
                Text(isChinese ? "个人排名" : "Leaderboard")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 8)
            
            // Top 3 preview
            let leaderboard = game.individualLeaderboard
            if !leaderboard.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(leaderboard.prefix(3).enumerated()), id: \.element.playerId) { index, entry in
                        if let student = students.first(where: { $0.id == entry.playerId }) {
                            VStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    StudentAvatarView(student: student, size: 50)
                                    if index == 0 {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.yellow)
                                            .offset(y: -10)
                                    }
                                }
                                Text("\(entry.points)")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? .orange : (index == 1 ? .gray : .brown))
                                Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }.padding(24).background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Battle Royal Compact Header
    private var battleRoyalCompactHeader: some View {
        VStack(spacing: 8) {
            // Timer and controls in one row
            HStack(spacing: 12) {
                // Countdown clock
                Text(formattedClock)
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                    .symbolEffect(.pulse, options: .repeating, isActive: isExpired && isTimerRunning)
                Text("/ \(game.durationMinutes):00")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                // Timer controls
                if game.status != .completed {
                    bigPlayPauseButton
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .background(Color.gray.opacity(0.12), in: Circle())
                    }
                }
            }
            
            // Top 3 leaderboard compact
            let leaderboard = game.individualLeaderboard
            if !leaderboard.isEmpty {
                HStack(spacing: 16) {
                    ForEach(Array(leaderboard.prefix(3).enumerated()), id: \.element.playerId) { index, entry in
                        if let student = students.first(where: { $0.id == entry.playerId }) {
                            HStack(spacing: 6) {
                                if index == 0 {
                                    Image(systemName: "crown.fill").font(.system(size: 12)).foregroundColor(.orange)
                                }
                                Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text("\(entry.points)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? .orange : (index == 1 ? .gray : .brown))
                            }
                        }
                    }
                    Spacer()
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Compact Game Header (smaller to show more players)
    private var compactGameHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(formattedClock)
                    .font(.system(size: 36, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                    .symbolEffect(.pulse, options: .repeating, isActive: isExpired && isTimerRunning)
                Text(String(format: "/ %d:00", game.durationMinutes))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                if game.status != .completed {
                    bigPlayPauseButton
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.regular)
                    .tint(.secondary)
                }
            }

            // Team scores
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 24, height: 24)
                            .overlay(
                                Text(String(team.name.prefix(1)))
                                    .font(.caption2.bold())
                                    .foregroundStyle(team.colorHex == "#F5F5F5" ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(Color.white))
                            )
                        Text("\(game.score(for: team.id))")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color(hex: team.colorHex))
                            .contentTransition(.numericText(value: Double(game.score(for: team.id))))
                    }
                    .frame(maxWidth: .infinity)
                    if index < teamsOnCourt.count - 1 {
                        Text("vs")
                            .font(.subheadline.bold())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Waiting teams
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "候场" : "Next")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                            Text(GameTeam.localizedColorName(team.name))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
    
    private var gameHeader: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60)).font(.system(size: 48, weight: .bold, design: .monospaced)).foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if game.status != .completed {
                HStack(spacing: 16) {
                    Button(action: toggleTimer) {
                        HStack(spacing: 6) { Image(systemName: isTimerRunning ? "pause.fill" : "play.fill"); Text(isTimerRunning ? (isChinese ? "暂停" : "Pause") : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume"))) }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary).padding(10).background(Color.gray.opacity(0.1)).cornerRadius(20) }
                }
            }
            // Only show active teams on court
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    VStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 40, height: 40).overlay(Text(String(team.name.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                        Text("\(game.score(for: team.id))").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundColor(Color(hex: team.colorHex))
                        Text(GameTeam.localizedColorName(team.name)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        if game.teams.count > 2 {
                            Text("\(team.wins)W-\(team.losses)L").font(.system(size: 10, weight: .medium)).foregroundColor(.gray.opacity(0.7))
                        }
                    }.frame(maxWidth: .infinity)
                    if index < teamsOnCourt.count - 1 { Text("vs").font(.system(size: 20, weight: .bold)).foregroundColor(.gray.opacity(0.4)) }
                }
            }
            // Show waiting teams if more than 2 teams total
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 8) {
                    Text(isChinese ? "候场" : "NEXT UP").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.gray.opacity(0.6))
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 16, height: 16)
                            Text(team.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Text("\(team.wins)W").font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
                        }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.1)).cornerRadius(12)
                    }
                }.padding(.top, 8)
            }
        }.padding(24).background(Color(.secondarySystemGroupedBackground))
    }
    
    // MARK: - Live entry (iPhone)

    /// Clock + the two scores. The scores ARE the team switcher: tap the
    /// other team and its players slide in.
    private var liveScoreboard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(formattedClock)
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .foregroundStyle(clockTint)
                    .contentTransition(.numericText())
                Spacer()
                if game.status != .completed {
                    Button(action: resetTimer) {
                        Image(systemName: "arrow.counterclockwise").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).tint(.secondary)
                    Button(action: toggleTimer) {
                        Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(isTimerRunning ? Color.orange : Color.green))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isTimerRunning ? "Pause timer" : "Start timer")
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                    teamScoreSwitch(team: team, index: index)
                }
            }
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "候场" : "Next").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
                            Text(GameTeam.localizedColorName(team.name)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .sensoryFeedback(.selection, trigger: selectedTeamIndex)
    }

    /// WHO IS UP (19 Nov 2026, Luther: with more than two teams, tap a team on
    /// the scoreboard and pick which team plays instead). Only before the
    /// clock has run and before anyone has a stat — after that the round is
    /// under way and the rotation decides.
    private var lineupEditable: Bool {
        guard game.status != .completed, !game.waitingTeams.isEmpty,
              timerSeconds == 0, !isTimerRunning else { return false }
        let noStats = game.playerStats.allSatisfy {
            $0.points == 0 && $0.rebounds == 0 && $0.assists == 0 && $0.steals == 0 && $0.blocks == 0
        }
        return noStats && game.baskets.isEmpty && game.teamScores.values.allSatisfy { $0 == 0 }
    }

    /// `waiting` goes on court in `current`'s slot, and `current` takes
    /// `waiting`'s place in the queue.
    private func putOnCourt(_ waiting: GameTeam, replacing current: GameTeam) {
        guard let slot = game.activeTeamIds.firstIndex(of: current.id),
              let a = game.teams.firstIndex(where: { $0.id == current.id }),
              let b = game.teams.firstIndex(where: { $0.id == waiting.id }) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            game.activeTeamIds[slot] = waiting.id
            game.teams.swapAt(a, b)
        }
        HapticFeedback.impact(.light)
        onSave()
    }

    @ViewBuilder
    private func teamScoreSwitch(team: GameTeam, index: Int) -> some View {
        if lineupEditable {
            Menu {
                Section(isChinese ? "换上哪队？" : "Who's up instead?") {
                    ForEach(game.waitingTeams) { waiting in
                        Button {
                            putOnCourt(waiting, replacing: team)
                        } label: {
                            Label(GameTeam.localizedColorName(waiting.name), systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                if !(isIPad && activeTeamsForScoring.count == 2) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selectedTeamIndex = index }
                    } label: {
                        Label(isChinese ? "显示\(GameTeam.localizedColorName(team.name))的球员" : "Show \(GameTeam.localizedColorName(team.name))'s players",
                              systemImage: "person.3")
                    }
                }
            } label: {
                teamScoreLabel(team: team, index: index, choosable: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.team.\(index)")
        } else {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selectedTeamIndex = index }
            } label: {
                teamScoreLabel(team: team, index: index, choosable: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("live.team.\(index)")
        }
    }

    private func teamScoreLabel(team: GameTeam, index: Int, choosable: Bool) -> some View {
        // Side by side (iPad / Mac) both teams are on screen: no selection.
        let selected = (isIPad && activeTeamsForScoring.count == 2) || selectedTeamIndex == index
        let color = team.displayColor(for: colorScheme)
        return Group {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
                Text(GameTeam.localizedColorName(team.name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                if choosable {
                    // Says the team can be swapped for a waiting one.
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("\(game.score(for: team.id))")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(game.score(for: team.id))))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(selected ? 0.18 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? color : .clear, lineWidth: 2))
        }
    }

    /// Basket-value strip, the selected team's players, and the last action.
    @ViewBuilder
    private var liveEntry: some View {
        let teams = activeTeamsForScoring
        if selectedTeamIndex < teams.count {
            let team = teams[selectedTeamIndex]
            VStack(spacing: 10) {
                if game.status != .completed {
                    basketValueStrip
                }
                LiveTeamPanel(game: $game, team: team, students: students,
                              pointValue: basketValue, onAction: log)
                    .id(team.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: selectedTeamIndex == 0 ? .leading : .trailing),
                        removal: .move(edge: selectedTeamIndex == 0 ? .trailing : .leading)))
                    .allowsHitTesting(game.status != .completed)
                lastActionBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .clipped()
        }
    }

    /// Wide windows: the value strip, both teams' panels side by side (no
    /// switching — the scores above only show the score), the last action.
    private var liveEntryWide: some View {
        VStack(spacing: 12) {
            if game.status != .completed {
                basketValueStrip
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(activeTeamsForScoring) { team in
                    LiveTeamPanel(game: $game, team: team, students: students,
                                  pointValue: basketValue, onAction: log)
                        .allowsHitTesting(game.status != .completed)
                }
            }
            lastActionBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// +1 / +2 / +3. The game's standard value (set on the setup page) is
    /// selected by default and marked; any other is for the next basket only.
    private var basketValueStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { value in
                let selected = basketValue == value
                let standard = game.basketValue == value
                Button {
                    basketValue = value
                } label: {
                    VStack(spacing: 0) {
                        Text("+\(value)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        if standard {
                            Text(isChinese ? "标准" : "standard")
                                .font(.system(size: 9, weight: .semibold))
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("live.value.\(value)")
            }
        }
        .sensoryFeedback(.selection, trigger: basketValue)
        .onAppear { basketValue = game.basketValue }
    }

    private var lastActionBar: some View {
        HStack(spacing: 10) {
            Text(lastActionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("live.last")
            Button(action: undoLast) {
                Label(isChinese ? "撤销" : "Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(actionLog.isEmpty)
            .accessibilityIdentifier("live.undo")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        .sensoryFeedback(.warning, trigger: undoTick)
    }

    private func name(_ id: UUID) -> String {
        students.first { $0.id == id }?.primaryDisplayName ?? "—"
    }

    private var lastActionText: String {
        guard let last = actionLog.last else {
            return isChinese ? "点击球员得分 · 按住拖到传球人记助攻" : "Tap a player to score · drag to the passer for an assist"
        }
        let who = name(last.playerId)
        switch last.kind {
        case .points(let n):
            let assist = last.assistId.map { isChinese ? " · 助攻 \(name($0))" : " · assist \(name($0))" } ?? ""
            return "+\(n) \(who)\(assist)"
        case .rebound: return (isChinese ? "篮板 " : "Rebound ") + who
        case .steal: return (isChinese ? "抢断 " : "Steal ") + who
        case .block: return (isChinese ? "盖帽 " : "Block ") + who
        }
    }

    private func log(_ action: GameStatAction) {
        action.apply(to: &game)
        actionLog.append(action)
        if case .points = action.kind { basketValue = game.basketValue }
        onSave()
    }

    private func undoLast() {
        guard let last = actionLog.popLast() else { return }
        last.undo(on: &game)
        undoTick += 1
        onSave()
    }

    // Teams currently on court for scoring
    private var activeTeamsForScoring: [GameTeam] {
        game.activeTeams.isEmpty ? game.teams : game.activeTeams
    }
    
    private var teamTabs: some View {
        HStack(spacing: 8) {
            ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                teamTabButton(team: team, index: index)
            }
        }
        .padding(16)
        .sensoryFeedback(.selection, trigger: selectedTeamIndex)
    }

    @ViewBuilder
    private func teamTabButton(team: GameTeam, index: Int) -> some View {
        let isSelected = selectedTeamIndex == index
        let label = HStack(spacing: 6) {
            Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
            Text(GameTeam.localizedColorName(team.name))
                .font(.footnote.weight(.semibold))
        }
        let action: () -> Void = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTeamIndex = index
            }
        }

        if isSelected {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(hex: team.colorHex))
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Color(hex: team.colorHex))
        }
    }
    
    // MARK: - iPad Side-by-Side Teams View
    private var sideBySideTeamsView: some View {
        HStack(spacing: 12) {
            // Only show active teams for scoring
            ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                teamColumn(team: team, teamIndex: index)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private func teamColumn(team: GameTeam, teamIndex: Int) -> some View {
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let isYellowTeam = team.colorHex == "#FFD700"
        // Use darker color for light teams (yellow, white) for better readability
        let displayColor = (isWhiteTeam || isYellowTeam) ? Color.black : teamColor
        
        return VStack(spacing: 0) {
            // Team header with score
            HStack(spacing: 8) {
                Circle().fill(teamColor).frame(width: 20, height: 20)
                    .overlay(Text(String(team.name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundColor(isWhiteTeam || isYellowTeam ? .black : .white))
                Text(GameTeam.localizedColorName(team.name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(game.score(for: team.id))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(displayColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(teamColor.opacity(0.15))
            .cornerRadius(12, corners: [.topLeft, .topRight])
            
            // Players list
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(team.playerIds, id: \.self) { playerId in
                        if let student = students.first(where: { $0.id == playerId }) {
                            compactPlayerRow(student: student, team: team)
                        }
                    }
                }
                .padding(8)
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
    
    private func compactPlayerRow(student: Student, team: GameTeam) -> some View {
        let stats = game.stats(for: student.id)
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let isYellowTeam = team.colorHex == "#FFD700"
        // Use darker color for light teams for better button/text readability
        let buttonColor = (isWhiteTeam || isYellowTeam) ? Color(hex: "#CC9900") : teamColor
        
        return VStack(spacing: 6) {
            // Player info row
            HStack(spacing: 8) {
                StudentAvatarView(student: student, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(student.primaryDisplayName.components(separatedBy: " ").first ?? student.primaryDisplayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(stats?.points ?? 0)").font(.system(size: 11, weight: .bold)).foregroundColor(buttonColor)
                        Text("PTS").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            
            // Compact scoring buttons
            if game.status != .completed {
                let rebLabel = isChinese ? "篮板" : "REB"
                let astLabel = isChinese ? "助攻" : "AST"
                let stlLabel = isChinese ? "抢断" : "STL"
                let blkLabel = isChinese ? "盖帽" : "BLK"
                
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        compactStatButton("+1", color: buttonColor) { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+2", color: buttonColor) { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+3", color: buttonColor) { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }
                    }
                    HStack(spacing: 4) {
                        compactStatButton(rebLabel, color: .secondary) { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(astLabel, color: .secondary) { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(stlLabel, color: .secondary) { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(blkLabel, color: .secondary) { game.addStat(.block, for: student.id, teamId: team.id); onSave() }
                    }
                }
            }
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
    }

    private func compactStatButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .controlSize(.small)
        .tint(color)
    }
    
    // MARK: - Battle Royal Players List
    private var battleRoyalPlayersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Sort by points descending
                let sortedPlayers = game.playerStats.sorted { $0.points > $1.points }
                ForEach(Array(sortedPlayers.enumerated()), id: \.element.playerId) { index, stats in
                    if let student = students.first(where: { $0.id == stats.playerId }) {
                        battleRoyalPlayerRow(student: student, stats: stats, rank: index + 1)
                    }
                }
            }.padding(16)
        }
    }
    
    private func battleRoyalPlayerRow(student: Student, stats: SessionPlayerStats, rank: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Rank indicator
                ZStack {
                    Circle()
                        .fill(rank == 1 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                        .frame(width: 24, height: 24)
                    if rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    } else {
                        Text("\(rank)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                
                StudentAvatarView(student: student, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Show both English and Chinese names
                    HStack(spacing: 6) {
                        Text(student.primaryDisplayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.secondaryNameLine {
                            Text(chineseName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Show all stats (no assists for Battle Royal)
                    HStack(spacing: 8) {
                        statLabel("PTS", value: stats.points)
                        statLabel("REB", value: stats.rebounds)
                        statLabel("STL", value: stats.steals)
                        statLabel("BLK", value: stats.blocks)
                    }
                }
                
                Spacer()
            }
            
            // Scoring buttons
            if game.status != .completed {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: Color.accentColor, add: { game.addStat(.points(1), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+2", color: Color.accentColor, add: { game.addStat(.points(2), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+3", color: Color.accentColor, add: { game.addStat(.points(3), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: student.id); onSave() })
                    }
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .secondary, add: { game.addStat(.rebound, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("STL", color: .secondary, add: { game.addStat(.steal, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("BLK", color: .secondary, add: { game.addStat(.block, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: student.id); onSave() })
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
    
    private var playersList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Use activeTeamsForScoring to match teamTabs indexing
                if selectedTeamIndex < activeTeamsForScoring.count {
                    let team = activeTeamsForScoring[selectedTeamIndex]
                    ForEach(team.playerIds, id: \.self) { playerId in
                        if let student = students.first(where: { $0.id == playerId }) { playerScoringRow(student: student, team: team) }
                    }
                }
            }.padding(16)
        }
    }
    
    private func playerScoringRow(student: Student, team: GameTeam) -> some View {
        let stats = game.stats(for: student.id)
        let teamColor = Color(hex: team.colorHex)
        let isWhiteTeam = team.colorHex == "#F5F5F5"
        let buttonColor = isWhiteTeam ? Color.gray : teamColor
        
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                StudentAvatarView(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    // Show both English and Chinese names
                    HStack(spacing: 6) {
                        Text(student.primaryDisplayName).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.secondaryNameLine {
                            Text(chineseName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    // Show all stats in a compact row
                    HStack(spacing: 8) {
                        statLabel("PTS", value: stats?.points ?? 0)
                        statLabel("REB", value: stats?.rebounds ?? 0)
                        statLabel("AST", value: stats?.assists ?? 0)
                        statLabel("STL", value: stats?.steals ?? 0)
                        statLabel("BLK", value: stats?.blocks ?? 0)
                    }
                }
                Spacer()
            }
            
            if game.status != .completed {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: buttonColor, add: { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+2", color: buttonColor, add: { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+3", color: buttonColor, add: { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: team.id); onSave() })
                    }
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .secondary, add: { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("AST", color: .secondary, add: { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.assist, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("STL", color: .secondary, add: { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("BLK", color: .secondary, add: { game.addStat(.block, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: team.id); onSave() })
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func statLabel(_ label: String, value: Int) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let localizedLabel: String = {
            switch label {
            case "PTS": return isChinese ? "分" : "PTS"
            case "REB": return isChinese ? "板" : "REB"
            case "AST": return isChinese ? "助" : "AST"
            case "STL": return isChinese ? "断" : "STL"
            case "BLK": return isChinese ? "帽" : "BLK"
            default: return label
            }
        }()
        return HStack(spacing: 2) { Text("\(value)").font(.system(size: 13, weight: .bold)).foregroundStyle(.primary); Text(localizedLabel).font(.system(size: 10)).foregroundStyle(.secondary) }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("stat.\(label)")
            .accessibilityValue("\(value)")
    }
    private func statButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.small)
        .tint(color)
    }

    /// Stat button with long-press to undo/remove
    private func undoableStatButton(_ label: String, color: Color, add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let localizedLabel: String = {
            switch label {
            case "REB": return isChinese ? "篮板" : "REB"
            case "AST": return isChinese ? "助攻" : "AST"
            case "STL": return isChinese ? "抢断" : "STL"
            case "BLK": return isChinese ? "盖帽" : "BLK"
            default: return label
            }
        }()
        // One touch, one action: StatPressButton (tap adds, hold removes).
        // The Button + simultaneous long press here re-added on release.
        return StatPressButton(label: localizedLabel, color: color, add: add, remove: remove)
    }
    private func toggleTimer() {
        isTimerRunning.toggle()
        if isTimerRunning {
            if game.status == .ready {
                game.status = .inProgress
                game.startedAt = Date()
                hasFiredAlarm = false
            } else {
                game.status = .inProgress
            }
        } else {
            game.status = .paused
        }
        onSave()
    }
    private func resetTimer() {
        timerSeconds = 0
        isTimerRunning = false
        game.status = .ready
        game.startedAt = nil
        hasFiredAlarm = false
        onSave()
    }

    /// Hero play/pause control — sized so it's tappable across the gym
    /// from a bench. 56pt circle, large SF symbol, prominent fill.
    @ViewBuilder
    private var bigPlayPauseButton: some View {
        Button(action: toggleTimer) {
            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(isTimerRunning ? Color.orange : Color.green)
                )
                .shadow(color: (isTimerRunning ? Color.orange : Color.green).opacity(0.35),
                        radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isTimerRunning)
        .accessibilityLabel(isTimerRunning ? "Pause timer" : "Start timer")
    }

    /// Time-up alarm. Three short haptics + system sound bursts so the
    /// coach hears it across the gym even with the phone in a bag.
    /// Doesn't end the game — that stays on the coach's End Game tap.
    private func fireExpirationAlarm() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        // Sound 1005 = "Tweet" / short notification chime, audible without
        // disturbing nearby gyms. AudioServicesPlayAlertSound also vibrates
        // by default on devices that support it, but the haptic generator
        // adds a sharper kick on newer iPhones.
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.6) {
                AudioServicesPlayAlertSound(SystemSoundID(1005))
                generator.notificationOccurred(.warning)
            }
        }
        #endif
    }
    
    private func endRound() {
        isTimerRunning = false
        
        // Determine winner of this round (use score(for:) which returns 0 if not set)
        let activeScores = game.activeTeamIds.map { teamId -> (UUID, Int) in
            (teamId, game.score(for: teamId))
        }
        
        // Find winner (highest score, or first team if tied)
        if let winner = activeScores.max(by: { $0.1 < $1.1 }) {
            // Rotate teams for next round (winner stays on)
            if game.gameType == .twoTeam && game.teams.count > 2 {
                // Save completed round as a separate game before resetting
                let completedRound = SessionGame(
                    id: UUID(),
                    sessionId: game.sessionId,
                    gameNumber: allGamesInSession.count + 1,
                    gameType: game.gameType,
                    teams: game.teams,
                    activeTeamIds: game.activeTeamIds,
                    teamScores: game.teamScores,
                    playerStats: game.playerStats,
                    durationMinutes: game.durationMinutes,
                    basketValue: game.basketValue,
                    roundNumber: game.roundNumber,
                    status: .completed,
                    startedAt: game.startedAt,
                    endedAt: Date(),
                    winningTeamId: winner.0
                )
                onSaveCompletedRound?(completedRound)
                
                // Rotate teams
                game.rotateTeamsForWinner(winnerId: winner.0)
                
                // Reset scores and player stats for new round
                for teamId in game.activeTeamIds {
                    game.teamScores[teamId] = 0
                }
                game.playerStats.removeAll()  // Clear all player stats for fresh round
                
                timerSeconds = 0
                game.status = .ready
                game.startedAt = nil
                hasFiredAlarm = false
            } else if game.gameType == .continuousFullCourt {
                game.rotateTeamsForContinuous(scoringTeamId: winner.0)
            }
        }
        onSave()
    }
    
    private func endGame() {
        isTimerRunning = false; game.status = .completed; game.endedAt = Date()
        
        // Determine overall winner based on total scores
        if let maxScore = game.teamScores.values.max(), let winningTeamId = game.teamScores.first(where: { $0.value == maxScore })?.key { 
            game.winningTeamId = winningTeamId 
        }
        
        // Update win/loss for final round
        if let winnerId = game.winningTeamId {
            if let winnerIndex = game.teams.firstIndex(where: { $0.id == winnerId }) {
                game.teams[winnerIndex].wins += 1
            }
            for teamId in game.activeTeamIds where teamId != winnerId {
                if let loserIndex = game.teams.firstIndex(where: { $0.id == teamId }) {
                    game.teams[loserIndex].losses += 1
                }
            }
        }
        
        onSave()
        
        // Show recap if there are stats
        if !game.playerStats.isEmpty {
            showingRecap = true
        }
    }
}
#endif

// MARK: - Game Recap View
/// Post-game stat recap with MVP, awards, and player comparisons
// MARK: - Live Timeline Drill Row
struct LiveTimelineDrillRow: View {
    let item: LiveDrillItem
    let index: Int
    let currentIndex: Int
    let isLast: Bool
    let onTap: () -> Void
    /// Optional: long-press / context-menu action that jumps the live engine
    /// to this drill. Falls back to `onTap` when nil for source compat.
    var onJumpTo: (() -> Void)? = nil

    private var isCompleted: Bool { index < currentIndex }
    private var isCurrent: Bool { index == currentIndex }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(index == 0 ? AnyShapeStyle(Color.clear) : (isCompleted ? AnyShapeStyle(item.sectionColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary)))
                        .frame(width: 2, height: 12)
                    ZStack {
                        Circle()
                            .fill(isCurrent ? AnyShapeStyle(item.sectionColor) : (isCompleted ? AnyShapeStyle(item.sectionColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary)))
                            .frame(width: 12, height: 12)
                        if isCurrent {
                            Circle()
                                .stroke(item.sectionColor.opacity(0.3), lineWidth: 4)
                                .frame(width: 20, height: 20)
                        }
                        if isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    Rectangle()
                        .fill(isLast ? AnyShapeStyle(Color.clear) : (isCompleted ? AnyShapeStyle(item.sectionColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary)))
                        .frame(width: 2, height: 12)
                }
                .frame(width: 24)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.drill.name)
                            .font(.footnote.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(HierarchicalShapeStyle.primary) : (isCompleted ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(HierarchicalShapeStyle.secondary)))
                            .strikethrough(isCompleted)
                        Text("\(item.durationSeconds / 60) min • \(item.section.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isCurrent {
                        Text("NOW")
                            .font(.caption2.bold())
                            .monospaced()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(item.sectionColor, in: .rect(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isCurrent ? AnyShapeStyle(item.sectionColor.opacity(0.1)) : AnyShapeStyle(Color.clear), in: .rect(cornerRadius: 10))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: currentIndex)
        .contextMenu {
            if let onJumpTo {
                Button {
                    onJumpTo()
                } label: {
                    Label("Set as current drill", systemImage: "play.circle")
                }
            }
        }
    }
}

// MARK: - Live Attendance Sheet
struct LiveAttendanceSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var session: SessionEvent
    let students: [Student]
    let programColor: Color
    let onSave: () -> Void

    private func currentMark(for studentId: UUID) -> AttendanceMark {
        session.effectiveAttendanceMark(for: studentId)
    }

    /// Optimistic local update so the control responds immediately, then the
    /// canonical write. Redemption is handled inside
    /// setStudentAttendanceState by the single FIFO authority — never here.
    private func applyMark(_ mark: AttendanceMark, to studentId: UUID) {
        session.actualAttendeeIds.removeAll { $0 == studentId }
        session.excusedAbsences.removeAll { $0 == studentId }
        session.unexcusedAbsences.removeAll { $0 == studentId }
        switch mark {
        case .present:  session.actualAttendeeIds.append(studentId)
        case .excused:  session.excusedAbsences.append(studentId)
        case .absent:   session.unexcusedAbsences.append(studentId)
        case .unmarked: break
        }
        dataManager.setStudentAttendanceState(sessionId: session.id,
                                              studentId: studentId,
                                              state: mark.triState)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("ATTENDANCE")
                            .font(.caption2.weight(.bold))
                            .monospaced()
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(session.actualAttendeeIds.count)/\(students.count) present")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                            .contentTransition(.numericText(value: Double(session.actualAttendeeIds.count)))
                    }

                    HStack(spacing: 12) {
                        Button {
                            // Optimistic local + field-level write so we
                            // don't drag a stale `games` / photo onto the
                            // record. Excused list is preserved.
                            session.actualAttendeeIds = students.map { $0.id }
                            dataManager.setSessionAttendance(
                                sessionId: session.id,
                                actualAttendeeIds: session.actualAttendeeIds,
                                excusedAbsences: session.excusedAbsences
                            )
                        } label: {
                            Label("Mark All Present", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .controlSize(.regular)
                        .tint(.green)
                        .sensoryFeedback(.success, trigger: session.actualAttendeeIds.count == students.count)

                        Button(role: .destructive) {
                            session.actualAttendeeIds = []
                            dataManager.setSessionAttendance(
                                sessionId: session.id,
                                actualAttendeeIds: [],
                                excusedAbsences: session.excusedAbsences
                            )
                        } label: {
                            Label("Clear All", systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .controlSize(.regular)
                        .tint(.secondary)
                    }

                    ForEach(students) { student in
                        // Same control as the session attendance tab: the
                        // three-position switch (excused · not marked ·
                        // present); the middle reads absent once roll call
                        // has started. A notified absence must stay
                        // recordable as excused, or it consumes a session.
                        AttendanceStudentRow(
                            student: student,
                            mark: currentMark(for: student.id),
                            isRedeemed: dataManager.isSessionRedeemed(sessionId: session.id,
                                                                      studentId: student.id),
                            onChange: { newMark in
                                applyMark(newMark, to: student.id)
                            },
                            onRefund: {
                                dataManager.refundSessionToBundle(sessionId: session.id,
                                                                  studentId: student.id)
                            }
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Take Attendance")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Live Attendance Row
/// Shared mapping between the stored arrays and the four-state control.
extension SessionEvent {
    func attendanceMark(for studentId: UUID) -> AttendanceMark {
        if actualAttendeeIds.contains(studentId) { return .present }
        if excusedAbsences.contains(studentId) { return .excused }
        if unexcusedAbsences.contains(studentId) { return .absent }
        return .unmarked
    }

    /// What the coach sees: the recorded mark, except that an unmarked
    /// student reads ABSENT once roll call has started (AttendanceInference).
    /// Display only — the absence is charged an hour after class.
    func effectiveAttendanceMark(for studentId: UUID) -> AttendanceMark {
        let recorded = attendanceMark(for: studentId)
        if recorded == .unmarked, AttendanceInference.isInferredAbsent(studentId, in: self) {
            return .absent
        }
        return recorded
    }
}

extension AttendanceMark {
    var triState: AttendanceTriState {
        switch self {
        case .unmarked: return .unmarked
        case .present:  return .present
        case .excused:  return .excused
        case .absent:   return .absent
        }
    }
}

struct LiveAttendanceRow: View {
    let student: Student
    let isPresent: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.primaryDisplayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let age = student.age {
                    Text("\(age) years old")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()

            Toggle("", isOn: Binding(
                get: { isPresent },
                set: { _ in action() }
            ))
            .labelsHidden()
            .tint(.green)
            .sensoryFeedback(.impact(weight: .light), trigger: isPresent)
        }
        .padding(12)
        .background(
            isPresent ? AnyShapeStyle(Color.green.opacity(0.1)) : AnyShapeStyle(HierarchicalShapeStyle.quinary),
            in: .rect(cornerRadius: 12)
        )
    }
}

// MARK: - Live Notes Sheet
struct LiveNotesSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var notes: String
    let programColor: Color
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("SESSION NOTES")
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $notes)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    .frame(minHeight: 200)

                Text("Add observations, player performance notes, or areas to improve.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Coach Notes")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Smart Drill Picker Sheet
/// Intelligent drill picker that suggests drills based on program, phase, student level, and section context
struct SmartDrillPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: SessionEvent
    let section: CurriculumSection
    let program: Program?
    let phase: MicroCycle?
    let students: [Student]
    let allDrills: [DrillItem]
    let currentCoachId: UUID
    let onSave: () -> Void
    /// From the plan dashboard's "Find drills": the drills strong on it
    /// come first.
    var attribute: DrillAttribute? = nil

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    /// The drills library itself (Luther, November 2026: "reflect the drills
    /// library properly with the same search bar") — age, block, type,
    /// Personal, search across everything, Claude on Return on the Mac — with
    /// an add button per drill. The age starts at the program's; Warm-up
    /// opens on Routine, Skills on Compete.
    var body: some View {
        NavigationStack {
            DrillsLibraryView(pick: DrillsLibraryView.Pick(
                title: section == .warmup ? (isChinese ? "添加到热身" : "Add to Warm-up")
                                          : (isChinese ? "添加到技能" : "Add to Skills"),
                initialAge: program.map { DrillPlanGenerator.libraryAge(for: $0.ageGroup) },
                initialBlock: section == .warmup ? .routine : .compete,
                attribute: attribute,
                isAdded: isDrillInSection,
                add: { drill in
                    addDrillToSection(drill.id)
                    dismiss()
                }))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isChinese ? "取消" : "Cancel") { dismiss() }
                    }
                }
        }
    }

    private func isDrillInSection(_ drillId: UUID) -> Bool {
        switch section {
        case .warmup: return session.curriculum.warmupDrillIds.contains(drillId)
        case .main: return session.curriculum.skillDrillIds.contains(drillId)
        case .cooldown: return session.curriculum.gameDrillIds.contains(drillId)
        }
    }
    
    private func addDrillToSection(_ drillId: UUID) {
        switch section {
        case .warmup: session.curriculum.warmupDrillIds.append(drillId)
        case .main: session.curriculum.skillDrillIds.append(drillId)
        case .cooldown: session.curriculum.gameDrillIds.append(drillId)
        }
        onSave()
    }
}

// MARK: - DrillItem extension for intensity
extension DrillItem {
    var intensity: Int {
        switch difficulty {
        case .beginner: return 3
        case .intermediate: return 6
        case .advanced: return 9
        }
    }
}


// MARK: - Manage Session Students Sheet
struct ManageSessionStudentsSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    @Binding var session: SessionEvent
    let onSave: () -> Void
    
    @State private var searchText = ""
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    private var allStudents: [Student] {
        dataManager.students.sorted { $0.createdAt > $1.createdAt }
    }
    
    private var filteredStudents: [Student] {
        if searchText.isEmpty {
            return allStudents
        }
        let search = searchText.lowercased()
        return allStudents.filter { student in
            student.name.lowercased().contains(search) ||
            (student.chineseName?.lowercased().contains(search) ?? false)
        }
    }
    
    private var enrolledStudents: [Student] {
        allStudents.filter { session.attendeeIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quick actions
                HStack(spacing: 12) {
                    Button {
                        session.attendeeIds = allStudents.map { $0.id }
                    } label: {
                        Text(isChinese ? "全选" : "Select All")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Color.accentColor)

                    Button(role: .destructive) {
                        session.attendeeIds = []
                    } label: {
                        Text(isChinese ? "清除" : "Clear")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(.secondary)

                    Spacer()

                    Text("\(session.attendeeIds.count) \(isChinese ? "已选" : "selected")")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(session.attendeeIds.count)))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // Student list
                List {
                    ForEach(filteredStudents) { student in
                        let isSelected = session.attendeeIds.contains(student.id)

                        Button {
                            if isSelected {
                                session.attendeeIds.removeAll { $0 == student.id }
                            } else {
                                session.attendeeIds.append(student.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                StudentAvatarView(student: student, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.primaryDisplayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let chinese = student.secondaryNameLine {
                                        Text(chinese)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                                    .symbolEffect(.bounce, value: isSelected)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: isSelected)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .searchable(text: $searchText, prompt: isChinese ? "搜索学员" : "Search students")
            .navigationTitle(isChinese ? "管理学员" : "Manage Students")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") {
                        onSave()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Session Photo Viewer
/// Full-screen viewer for the session attendance photo. Pinch-to-zoom plus
/// a Done button. Uses the platform image type so it works on iOS and macOS.
struct SessionPhotoViewer: View {
    let image: PlatformImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = max(1, min(lastScale * value.magnification, 5)) }
                        .onEnded { _ in lastScale = scale }
                )
            #elseif os(macOS)
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
            #endif

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Session Photo Export Toast
enum SessionPhotoExportToast: Equatable {
    case success
    case failure(String)
}

struct SessionPhotoExportToastView: View {
    let toast: SessionPhotoExportToast
    let isChinese: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 24)
    }

    private var iconName: String {
        switch toast {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast {
        case .success: return .green
        case .failure: return .orange
        }
    }

    private var message: String {
        switch toast {
        case .success:
            return isChinese ? "已保存到相册" : "Saved to Photos"
        case .failure(let detail):
            let prefix = isChinese ? "保存失败" : "Save failed"
            return detail.isEmpty ? prefix : "\(prefix) · \(detail)"
        }
    }
}

// MARK: - Attendance Watermark Overlay
#if os(iOS)
/// The roll-call photo's band (October 2026 layout, Luther): one left edge,
/// three levels. The COUNT leads — who is present ("7 到场"; no total since
/// 19 Nov 2026) — then one line of WHEN THE PHOTO WAS TAKEN (weekday · date ·
/// time) and one of WHO/WHERE (coach · venue), always in Chinese, and the names of the
/// players present below a hairline. Attached with `.overlay(alignment:
/// .bottom)` so it can never overflow the photo's bottom edge — anchoring
/// with a ZStack clipped the last line of names on some aspect ratios.
struct AttendanceWatermarkOverlay: View {
    let photo: UIImage
    let coachName: String
    /// Day of week (e.g. "星期日").
    let weekdayText: String
    let dateText: String
    let location: String?
    /// Who is in the picture — the count stands alone (19 Nov 2026,
    /// Luther: no total); the band is always Chinese.
    let presentCount: Int
    let nameList: String

    /// Sizes are tuned for a 1024-wide photo (PhotoCaptureManager's max) and
    /// scale with it, clamped so WeChat thumbnails stay legible.
    private var s: CGFloat {
        max(0.6, photo.size.width / 1024.0)
    }

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .frame(width: photo.size.width, height: photo.size.height)
            .overlay(alignment: .bottom) {
                watermarkBand
            }
    }

    private var whenLine: String {
        [weekdayText, dateText].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var whoWhereLine: String {
        var parts: [String] = []
        if !coachName.isEmpty { parts.append("\(coachName)教练") }
        if let location, !location.isEmpty { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    private var watermarkBand: some View {
        VStack(alignment: .leading, spacing: 18 * s) {
            HStack(alignment: .center, spacing: 28 * s) {
                countBlock
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 2 * s)
                    .frame(maxHeight: 120 * s)
                VStack(alignment: .leading, spacing: 8 * s) {
                    if !whenLine.isEmpty {
                        Text(whenLine)
                            .font(.system(size: 40 * s, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    if !whoWhereLine.isEmpty {
                        Text(whoWhereLine)
                            .font(.system(size: 28 * s, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

            if !nameList.isEmpty {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 1.5 * s)
                Text(nameList)
                    .font(.system(size: 28 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
                    .lineSpacing(6 * s)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 36 * s)
        .padding(.top, 60 * s)
        .padding(.bottom, 30 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0),
                        .init(color: .black.opacity(0.78), location: 0.3),
                        .init(color: .black.opacity(0.92), location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// "7" large, "到场" under it.
    private var countBlock: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 2 * s) {
                Text("\(presentCount)")
                    .font(.system(size: 92 * s, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("到场")
                .font(.system(size: 26 * s, weight: .bold))
                .foregroundStyle(Color(red: 0.62, green: 0.88, blue: 0.80))
        }
        .monospacedDigit()
        .fixedSize()
    }
}
#endif

// MARK: - Swipe-Back Gesture Enabler
/// SwiftUI hides the nav bar but on some screens the system silently disables
/// the interactive pop gesture (especially when `navigationBarBackButtonHidden`
/// is implied or a custom back button covers the chrome). Dropping into UIKit
/// to clear the gesture-recognizer delegate brings it back without affecting
/// any other navigation behavior.
#if os(iOS)
struct EnableSwipeBackGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> EnableSwipeBackController {
        EnableSwipeBackController()
    }

    func updateUIViewController(_ uiViewController: EnableSwipeBackController, context: Context) {}

    final class EnableSwipeBackController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            // Walk up the responder chain to the enclosing UINavigationController.
            guard let nav = navigationControllerInChain else { return }
            nav.interactivePopGestureRecognizer?.isEnabled = true
            // Setting delegate to nil is the canonical workaround that
            // re-enables the edge swipe even when the nav bar is hidden or
            // the back button is custom.
            nav.interactivePopGestureRecognizer?.delegate = nil
        }

        private var navigationControllerInChain: UINavigationController? {
            var current: UIViewController? = self
            while current != nil {
                if let nav = current?.navigationController { return nav }
                current = current?.parent
            }
            return nil
        }
    }
}
#endif

#if os(iOS)
private extension View {
    /// A full-bleed List row that draws exactly what the old stacked layout
    /// drew: no insets, no system separator, no system background.
    func attendancePageRow(background: Color = .clear) -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}
#endif
