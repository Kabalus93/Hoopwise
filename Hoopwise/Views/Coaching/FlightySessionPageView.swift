import SwiftUI
import Combine
import MapKit
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
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingSkipSheet = false
    @State private var skipReason: SkipReason = .holiday
    @State private var selectedStudentForMeasurement: Student?
    @State private var selectedStudentForPeep: Student?
    @State private var showingDrillPicker = false
    @State private var showingStudentPicker = false
    @State private var isExportingCards = false
    @State private var exportedCardsURL: URL?
    @State private var showingCardShareSheet = false
    @State private var cardExportError: String?
    @State private var drillPickerSection: CurriculumSection = .warmup
    @State private var showingLiveSession = false
    @State private var selectedDrillForDetail: DrillItem?
    /// Open media viewer keyed to a (drillId, index) pair so the cover
    /// rebuilds correctly when the user taps different tiles.
    @State private var plannerMediaViewer: PlannerMediaViewerTarget?

    fileprivate struct PlannerMediaViewerTarget: Identifiable, Hashable {
        let drillId: UUID
        let index: Int
        var id: String { "\(drillId.uuidString)#\(index)" }
    }

    @State private var showingSmartDrillPicker = false
    @State private var showingManageStudents = false
    @State private var showingInlineDrillInputFor: CurriculumSection?
    @State private var showingSessionPhotoCapture = false
    @State private var showingSessionPhotoFullScreen = false
    @State private var isExportingSessionPhoto = false
    @State private var sessionPhotoExportToast: SessionPhotoExportToast?
    @State private var inlineDrillTextBySection: [CurriculumSection: String] = [:]
    @State private var notesEditorTarget: NotesEditorTarget = .session
    @FocusState private var focusedNotesEditor: NotesEditorTarget?
    
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
    
    var enrolledStudents: [Student] {
        guard let program = parentProgram else {
            return dataManager.students.filter { session.attendeeIds.contains($0.id) }
        }
        return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    var programColor: Color {
        parentProgram.map { Color(hex: $0.colorHex) } ?? .blue
    }

    private var currentCoachId: UUID {
        dataManager.loggedInCoachId ?? dataManager.coach.id
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                #if os(iOS)
                Group {
                    if selectedTab == 1 {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                heroCard(safeAreaTop: geometry.safeAreaInsets.top)
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
                                heroCard(safeAreaTop: geometry.safeAreaInsets.top)
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
                        heroCard(safeAreaTop: geometry.safeAreaInsets.top)
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

                        Button(action: { exportPlayerCards() }) {
                            Label(
                                LocalizationManager.shared.currentLanguage == .chinese ? "导出球员卡（A3打印）" : "Export Player Cards (A3)",
                                systemImage: "rectangle.stack.badge.person.crop"
                            )
                        }
                        .disabled(isExportingCards || session.attendeeIds.isEmpty)

                        if session.status == .scheduled {
                            if session.endTime < Date() {
                                // Past sessions can't be "started" — offer the
                                // truthful end states instead.
                                Button(action: completeSession) {
                                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "标记已完成" : "Mark Completed", systemImage: "checkmark.circle.fill")
                                }
                            } else {
                                Button(action: startSession) {
                                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "开始课程" : "Start Session", systemImage: "play.fill")
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
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
        .fullScreenCover(isPresented: $showingLiveSession) {
            LiveSessionView {
                showingLiveSession = false
                // Pull final state out of the engine and into the local binding
                if let finished = LiveSessionEngine.shared.session {
                    session = finished
                }
            }
        }
        #else
        .sheet(isPresented: $showingLiveSession) {
            LiveSessionView {
                showingLiveSession = false
                if let finished = LiveSessionEngine.shared.session {
                    session = finished
                }
            }
        }
        #endif
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
        // Bail early when nothing has changed downstream.
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

    @MainActor
    private func exportPlayerCards() {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let studentIds = session.attendeeIds
        guard !studentIds.isEmpty else { return }

        isExportingCards = true
        Task { @MainActor in
            defer { isExportingCards = false }

            let initialCards = PlayerCardPDFExporter.buildCards(
                for: studentIds,
                students: dataManager.students,
                players: dataManager.players,
                contracts: dataManager.contracts,
                sessions: dataManager.sessionEvents
            )

            guard !initialCards.isEmpty else {
                cardExportError = isChinese ? "没有可导出的球员" : "No players to export"
                return
            }

            // Pre-fetch the header backgrounds so the snapshot writer
            // doesn't race the network. Cache hits make repeat exports fast.
            let cards = await PlayerCardPDFExporter.prefetchHeaderImages(for: initialCards)

            let monthLbl = PlayerCardPDFExporter.monthLabel(chinese: isChinese)
            guard let pdfData = PlayerCardPDFExporter.generateSheetPDF(
                cards: cards,
                dataManager: dataManager
            ) else {
                cardExportError = isChinese ? "生成 PDF 失败" : "Failed to generate PDF"
                return
            }

            let safeName = session.title.replacingOccurrences(of: "/", with: "-")
            let filename = "\(safeName) - Cards \(monthLbl).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
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
        ZStack(alignment: .bottomLeading) {
            // Map background (darkened)
            heroMapBackground
            
            // Dark gradient overlay for text visibility
            ZStack {
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
            
            // Content
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    // Status badge — native glass capsule
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .symbolEffect(.pulse, options: .repeating, isActive: session.status == .inProgress)
                        Text(session.status.displayName)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: Capsule())

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

                    HStack(spacing: 8) {
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

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, safeAreaTop + 50)
        }
        .frame(height: 200 + safeAreaTop) // Extend height to include safe area
        .clipped()
        .onAppear {
            // Assign a header image to sessions without one (or replace
            // broken legacy Unsplash Source URLs). Field-level write so we
            // don't drag a stale `@State session` over the canonical
            // record — a previous version of this onAppear could wipe
            // sibling fields when the @State was initialized from a stale
            // cached snapshot.
            if session.headerImageURL == nil || session.headerImageURL?.contains("source.unsplash.com") == true {
                let newURL = SessionEvent.randomUnsplashURL()
                session.headerImageURL = newURL
                dataManager.setSessionHeaderImageURL(sessionId: session.id, url: newURL)
            }
        }
    }
    
    // MARK: - Hero Image Background (Cached)
    @ViewBuilder
    private var heroMapBackground: some View {
        if let imageURL = session.headerImageURL {
            CachedImageView(
                id: ImageCacheManager.sessionImageId(session.id),
                urlString: imageURL,
                placeholder: programGradientFallback
            )
        } else {
            programGradientFallback
        }
    }
    
    private var programGradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [programColor.opacity(0.7), programColor.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "basketball.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.15))
        }
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .controlSize(.large)
                    .tint(.green)
                    .sensoryFeedback(.success, trigger: session.status == .completed)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        case .scheduled:
            if accessMode.canEdit {
                Button {
                    startSession()
                } label: {
                    Label(isChinese ? "开始课程" : "Start Session", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .controlSize(.large)
                .tint(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .sensoryFeedback(.success, trigger: session.status == .inProgress)
            }
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
    private var tabSelector: some View {
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
    private var planTab: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                if accessMode.canEdit {
                    generatePlanButton
                }

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
                DrillMediaViewer(media: drill.media, initialIndex: target.index)
            } else {
                EmptyView()
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
                onSave: saveSession
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
            HStack {
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
        // Pull the recent N sessions on this same program so the generator
        // can avoid drills the cohort just did.
        let recent: [SessionEvent] = {
            guard let pid = session.programId else { return [] }
            return dataManager.sessionEvents
                .filter { $0.programId == pid && $0.id != session.id && $0.date < session.date }
                .sorted { $0.date > $1.date }
                .prefix(3)
                .map { $0 }
        }()

        let players = enrolledStudents.compactMap { dataManager.player(for: $0.id) }

        let ctx = DrillPlanGenerator.Context(
            session: session,
            program: parentProgram,
            phase: parentPhase,
            enrolledStudents: enrolledStudents,
            players: players,
            allDrills: dataManager.drills,
            recentSessions: recent
        )

        let newCurriculum = DrillPlanGenerator.generate(in: ctx)
        // Preserve the coach's hand-typed notes if any.
        var merged = newCurriculum
        if let existingNotes = session.curriculum.notes, !existingNotes.isEmpty {
            merged.notes = existingNotes
        }
        session.curriculum = merged
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
                            onTap: { _, idx in
                                HapticFeedback.impact(.light)
                                plannerMediaViewer = PlannerMediaViewerTarget(
                                    drillId: drill.id, index: idx
                                )
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
                    if let targets = program.skillTargets {
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
    private var attendanceTab: some View {
        Group {
            #if os(iOS)
            VStack(spacing: 8) {
                LazyVStack(spacing: 0) {
                    ForEach(enrolledStudents) { student in
                        attendanceRow(student: student)
                        Divider().padding(.leading, 66)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))

                if parentProgram != nil && accessMode.canEdit {
                    addAthleteButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                sessionPhotoSection
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer(minLength: 100)
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
        .sheet(item: $selectedStudentForMeasurement) { student in
            QuickMeasurementView(student: student, sessionId: session.id)
        }
        .sheet(item: $selectedStudentForPeep) { student in
            StudentQuickPeepView(student: student, sessionId: session.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddAthleteSheet) {
            // Available pool = all students not already enrolled in this
            // program. Mirrors the legacy `AddAthleteFromAttendanceView`
            // behavior; we just route it through the shared picker now.
            let enrolledIds = Set(parentProgram?.enrolledStudentIds ?? [])
            let available = dataManager.students.filter { !enrolledIds.contains($0.id) }
            let banner = AthletePickerSheet.Banner(
                title: isChinese ? "从此课程开始计费" : "Sessions Count From Here",
                subtitle: isChinese
                    ? "学员的合约课时将从本节课开始计算"
                    : "The student's contract sessions will count starting from this session",
                tint: programColor
            )
            AthletePickerSheet(
                title: isChinese ? "添加学员" : "Add Athlete",
                students: available,
                accentColor: programColor,
                banner: banner,
                confirmLabel: isChinese ? "添加" : "Add",
                showSelectionCounter: false
            ) { studentIds in
                enrollStudentsFromAttendance(studentIds: studentIds)
            }
        }
        .sheet(isPresented: $showingSessionPhotoCapture) {
            RollCallPhotoSheet(programColor: programColor) { image in
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
                    Text(isChinese ? "将新学员加入此项目" : "Enroll a new student in this program")
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
    
    private func enrollStudentsFromAttendance(studentIds: [UUID]) {
        guard !studentIds.isEmpty, var program = parentProgram else { return }

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
    /// Composes the attendance photo with a Chinese watermark of coach name,
    /// timestamp, location, present-count and the Chinese names of present
    /// students, then saves the result to the user's Photos library. Watermark
    /// text is always Chinese — these photos are shared with Chinese-reading
    /// managers in WeChat groups regardless of the coach's app language.
    private func exportSessionPhotoToLibrary() {
        guard !isExportingSessionPhoto,
              let path = session.attendancePhotoPath,
              let basePhoto = PhotoCaptureManager.shared.loadAttendancePhoto(from: path) else { return }

        isExportingSessionPhoto = true
        HapticFeedback.impact(.light)

        let presentStudents = dataManager.students.filter { session.actualAttendeeIds.contains($0.id) }
        let names: [String] = presentStudents.compactMap { student in
            if let chinese = student.chineseName?.trimmingCharacters(in: .whitespacesAndNewlines), !chinese.isEmpty {
                return chinese
            }
            let english = student.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? nil : english
        }
        let nameList = names.joined(separator: "、")

        // Prefer the coach's Chinese name on the watermark — these photos
        // go to WeChat groups where Chinese-reading managers see them.
        // Falls back to the English name when no Chinese name is set.
        let coachName: String = {
            let coach = dataManager.coach
            if let zh = coach.chineseName?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty {
                return zh
            }
            return coach.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        // `session.date` is the day bucket with the time component zeroed —
        // the actual start-of-session clock time lives on `session.startTime`.
        // Compose by lifting H:m from startTime onto session.date so the
        // watermark always reads e.g. "2026年5月18日 15:30" rather than 00:00.
        let cal = Calendar.current
        let day = cal.startOfDay(for: session.date)
        let timeComponents = cal.dateComponents([.hour, .minute], from: session.startTime)
        let stamp = cal.date(bySettingHour: timeComponents.hour ?? 0,
                             minute: timeComponents.minute ?? 0,
                             second: 0,
                             of: day) ?? session.startTime

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy年M月d日 HH:mm"
        let dateText = dateFormatter.string(from: stamp)

        // Day-of-week chunk, rendered as its own emphasized line in the
        // watermark so a quick glance shows e.g. "星期日 / 2026年5月18日".
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"  // → "星期日" etc.
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
        let isExcused = session.excusedAbsences.contains(student.id)
        let isExpected = session.attendeeIds.contains(student.id)
        
        // Four states from three stores. The default is UNMARKED — it used to
        // fall through to .absent, which now consumes a session.
        let attendanceState: AttendanceMark = session.attendanceMark(for: student.id)
        let isRedeemed = dataManager.isSessionRedeemed(sessionId: session.id, studentId: student.id)
        
        return HStack(spacing: 10) {
            // Main tappable area - opens Quick Peep
            Button(action: { selectedStudentForPeep = student }) {
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
                        Text(student.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let chinese = student.chineseName {
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

            // Native iOS switch: on = present, flipping a present student off
            // = absent. Untouched students stay unmarked. Excused and Clear
            // are in the swipe actions and the long-press menu below.
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
                selectedStudentForMeasurement = student
            } label: {
                Label(isChinese ? "数据" : "Metrics", systemImage: "chart.bar.fill")
            }
            .tint(Color.accentColor)

            if isExpected {
                Button {
                    setAttendanceState(for: student.id, state: isExcused ? .unmarked : .excused)
                } label: {
                    Label(isChinese ? "请假" : "Excuse", systemImage: "calendar.badge.clock")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // "Clear" means UNMARKED. It used to map to .absent, which now
            // consumes a session — clearing must never charge the client.
            if attendanceState != .unmarked {
                Button(role: .destructive) {
                    setAttendanceState(for: student.id, state: .unmarked)
                } label: {
                    Label(isChinese ? "清除" : "Clear", systemImage: "xmark.circle.fill")
                }
            }
            if isRedeemed {
                Button {
                    dataManager.refundSessionToBundle(sessionId: session.id, studentId: student.id)
                } label: {
                    Label(isChinese ? "退回课时" : "Refund session",
                          systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
        #endif
    }
    
    // MARK: - Attendance State
    
    private func setAttendanceState(for studentId: UUID, state: AttendanceMark) {
        // Optimistic local update so the toggle animates immediately. The
        // canonical write goes through the field-level helper below so
        // siblings (games, photo) survive even if our @State is stale.
        session.actualAttendeeIds.removeAll { $0 == studentId }
        session.excusedAbsences.removeAll { $0 == studentId }
        session.unexcusedAbsences.removeAll { $0 == studentId }

        switch state {
        case .present:  session.actualAttendeeIds.append(studentId)
        case .excused:  session.excusedAbsences.append(studentId)
        case .absent:   session.unexcusedAbsences.append(studentId)
        case .unmarked: break
        }
        let mappedState = state.triState

        // Redemption is handled inside setStudentAttendanceState via the single
        // FIFO authority. Do not redeem here — a second call site is exactly
        // how the two divergent redemption paths arose. Nothing un-charges a
        // session automatically either; that is refundSessionToBundle, an
        // explicit correction.
        dataManager.setStudentAttendanceState(
            sessionId: session.id,
            studentId: studentId,
            state: mappedState
        )
    }
    
    // MARK: - Games Tab (iOS Only)
    #if os(iOS)
    private var gamesTab: some View {
        SessionGamesTabView(
            session: $session,
            enrolledStudents: enrolledStudents,
            programColor: programColor,
            onSave: saveSession
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
    
    private var notesTab: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                notesTypeToggle
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        notesFullBleedEditor
                        previousNotesIndentSection
                        if session.status == .completed { ratingSection.padding(.horizontal, 20).padding(.top, 20) }
                        if session.status == .completed || session.status == .inProgress { manOfTheMatchSection.padding(.horizontal, 20).padding(.top, 16) }
                        Spacer(minLength: 120)
                    }
                }
            }
            .background(Color(.systemBackground))

            if showMentionPicker { notesMentionPickerOverlay }
            if showTagPicker { notesTagPickerOverlay }
            if showFloatingActionBar { notesFloatingActionBar }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in if v.translation.height < -40 { showFloatingBar() } })
        .onDisappear { saveSession() }
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
        Picker("Notes Target", selection: $notesEditorTarget) {
            Text(isChinese ? "课程" : "Session").tag(NotesEditorTarget.session)
            Text(isChinese ? "复盘" : "Reflection").tag(NotesEditorTarget.reflections)
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: notesEditorTarget)
        .onChange(of: notesEditorTarget) { _, newValue in
            focusedNotesEditor = newValue
        }
    }
    
    private var notesFullBleedEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: activeNotesBinding)
                .focused($focusedNotesEditor, equals: notesEditorTarget)
                .font(.body)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .disabled(!accessMode.canAddNotes)
                .onChange(of: activeNotesBinding.wrappedValue) { _, newValue in
                    checkForMentionTrigger(in: newValue)
                }

            if activeNotesBinding.wrappedValue.isEmpty {
                Text(isChinese ? "笔记、观察、提示..." : "Notes, observations, cues...")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 25)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
        }
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                }
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
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "课程评分" : "SESSION RATING")
                    .font(.caption2.weight(.bold))
                    .monospaced()
            } icon: {
                Image(systemName: "star")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        session.rating = star
                        saveSession()
                    } label: {
                        Image(systemName: star <= (session.rating ?? 0) ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.bounce, value: session.rating)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!accessMode.canAddNotes)
                    .sensoryFeedback(.impact(weight: .light), trigger: session.rating)
                }
                Spacer()
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    private var manOfTheMatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(isChinese ? "最佳球员" : "MAN OF THE MATCH")
                    .font(.caption2.weight(.bold))
                    .monospaced()
            } icon: {
                Image(systemName: "trophy")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if let momId = session.manOfTheMatchId,
               let student = dataManager.students.first(where: { $0.id == momId }) {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, value: momId)

                    StudentAvatarView(student: student, size: 40)

                    Text(student.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if accessMode.canAddNotes {
                        Button(isChinese ? "更换" : "Change") {
                            showingStudentPicker = true
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .tint(Color.accentColor)
                    }
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                Button {
                    showingStudentPicker = true
                } label: {
                    HStack {
                        Image(systemName: "star")
                            .foregroundStyle(.tertiary)
                        Text(isChinese ? "选择最佳球员" : "Select Man of the Match")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .disabled(!accessMode.canAddNotes)
                .sensoryFeedback(.selection, trigger: showingStudentPicker)
            }
        }
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
    
    private func startSession() {
        SessionLifecycle.apply(.start, to: &session)
        saveSession()

        let programName = parentProgram?.name ?? "Training Session"
        let accentColor = parentProgram?.colorHex ?? "#007AFF"
        let drills = buildLiveDrills(from: session)

        var drillNames: [UUID: String] = [:]
        for drillId in session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds + session.curriculum.gameDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drillNames[drillId] = drill.name
            }
        }

        // Owns the timer + Live Activity. The cover is just the presenter
        // and can be dismissed without ending the run.
        LiveSessionEngine.shared.start(
            session: session,
            drills: drills,
            programName: programName,
            programColorHex: accentColor,
            drillNames: drillNames
        )

        showingLiveSession = true
    }

    private func buildLiveDrills(from session: SessionEvent) -> [LiveDrillItem] {
        let curriculum = session.curriculum
        var items: [LiveDrillItem] = []
        let warmupCount = max(curriculum.warmupDrillIds.count, 1)
        let skillCount  = max(curriculum.skillDrillIds.count, 1)
        let gameCount   = max(curriculum.gameDrillIds.count, 1)
        let warmupSec = curriculum.warmupDrillIds.isEmpty ? 0 : (curriculum.warmupMinutes * 60) / warmupCount
        let skillSec  = curriculum.skillDrillIds.isEmpty  ? 0 : (curriculum.skillsMinutes * 60) / skillCount
        let gameSec   = curriculum.gameDrillIds.isEmpty   ? 0 : (curriculum.gameMinutes * 60) / gameCount
        for id in curriculum.warmupDrillIds {
            if let d = dataManager.drills.first(where: { $0.id == id }) {
                items.append(LiveDrillItem(drill: d, section: .warmup, durationSeconds: warmupSec))
            }
        }
        for id in curriculum.skillDrillIds {
            if let d = dataManager.drills.first(where: { $0.id == id }) {
                items.append(LiveDrillItem(drill: d, section: .main, durationSeconds: skillSec))
            }
        }
        for id in curriculum.gameDrillIds {
            if let d = dataManager.drills.first(where: { $0.id == id }) {
                items.append(LiveDrillItem(drill: d, section: .cooldown, durationSeconds: gameSec))
            }
        }
        return items
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
    
    private func completeSession() {
        SessionLifecycle.apply(.complete, to: &session)
        saveSession()
        
        // Session consumption is now derived from SessionEvent records
        // No need to call updateAttendedSessions - it's calculated automatically via sessionsConsumed(for:)
        
        // End Live Activity with attendance reminder
        #if os(iOS)
        Task { @MainActor in
            SessionLiveActivityManager.shared.endActivity(showAttendanceReminder: true)
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
        dataManager.updateSessionEvent(session)
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
    @Binding var session: SessionEvent
    let enrolledStudents: [Student]
    let programColor: Color
    let onSave: () -> Void
    
    @State private var showingCreateGame = false
    @State private var selectedGame: SessionGame?
    @State private var selectedRecapGame: SessionGame?
    
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    
    @State private var gameToDelete: SessionGame?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                gamesHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                if !sessionHighlights.isEmpty {
                    highlightsStrip
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                if session.games.isEmpty {
                    emptyGamesState
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(session.games.enumerated()), id: \.element.id) { index, game in
                            gameRow(game)
                            if index < session.games.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 100)
            }
            .padding(.top, 8)
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
            CreateGameSheet(session: $session, enrolledStudents: enrolledStudents, programColor: programColor, onSave: onSave)
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
                    students: enrolledStudents,
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
            GameRecapView(game: game, students: enrolledStudents, allGamesInSession: session.games)
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
    
    private var emptyGamesState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let quotes: [(quote: String, author: String, role: String)] = isChinese ? [
            ("孩子们通过打比赛学得最快。比赛教会他们技术练习无法教会的东西——如何竞争、如何应对压力、如何与队友沟通。", "格雷格·波波维奇", "NBA主教练"),
            ("最好的球员是在街头和球场上成长的，在那里每次触球都是一次学习机会。让孩子们去比赛吧。", "埃托雷·梅西纳", "欧洲联赛主教练"),
            ("我们过度执教、训练过度，却让他们比赛不足。比赛才是最好的老师。", "鲍勃·比格罗", "青少年篮球倡导者"),
            ("我学习篮球的方式就是打球。没有人教我挡拆——我是在比赛中学会的。", "史蒂夫·纳什", "名人堂球员"),
            ("让比赛成为老师。孩子们在有意义的比赛环境中学习得更快。", "唐·肖瓦尔特", "青少年篮球教练"),
            ("你不能在黑板上学会游泳。篮球也是一样的。", "菲尔·杰克逊", "NBA传奇教练"),
            ("比赛是最好的练习。训练中学到的东西只有在比赛中才能真正理解。", "帕特·莱利", "NBA名人堂教练"),
            ("让孩子们犯错。比赛中的错误是最好的学习机会。", "杰伊·比拉斯", "ESPN篮球分析师"),
            ("年轻球员需要比赛时间，而不是更多的训练时间。", "杰里·韦斯特", "NBA传奇人物"),
            ("真正的篮球智商是在比赛中培养的，不是在训练中。", "拉里·伯德", "名人堂球员"),
            ("我看过太多孩子练习完美的技术，但在比赛中却不知所措。", "查尔斯·巴克利", "名人堂球员"),
            ("比赛教会孩子如何思考，训练只教会他们如何行动。", "休·霍林斯", "青少年篮球教练"),
            ("5对5比赛是最好的篮球课堂。", "泽利科·奥布拉多维奇", "欧洲联赛传奇教练"),
            ("孩子们需要感受比赛的节奏，这是任何训练都无法模拟的。", "里克·卡莱尔", "NBA主教练"),
            ("在我执教生涯中，最好的球员都是在比赛中成长的。", "迈克·沙舍夫斯基", "大学篮球名帅"),
            ("不要剥夺孩子犯错的权利。比赛中的错误是成长的催化剂。", "约翰·伍登", "UCLA传奇教练"),
            ("每一次比赛都是一堂课。输赢都是学习。", "德安东尼", "NBA主教练"),
            ("孩子们在玩乐中学习最快。让比赛保持有趣。", "史蒂夫·科尔", "NBA主教练"),
            ("真正的决策能力只能在真实的比赛压力下培养。", "布拉德·史蒂文斯", "NBA主教练"),
            ("我宁愿让孩子在比赛中学习，也不愿看他们在训练中完美。", "汤姆·伊佐", "大学篮球名帅"),
            ("比赛是检验真理的唯一标准。篮球也是如此。", "姚明", "名人堂球员"),
            ("孩子需要理解为什么，而不只是怎么做。比赛给他们这个答案。", "蒂姆·邓肯", "名人堂球员"),
            ("最好的学习发生在孩子们忘记他们在学习的时候——那就是比赛。", "科比·布莱恩特", "名人堂球员"),
            ("比赛是青少年篮球训练中最被低估的工具。", "大卫·布拉特", "欧洲联赛冠军教练"),
            ("让孩子在比赛中找到自己的风格。", "马努·吉诺比利", "名人堂球员"),
            ("训练教技术，比赛教智慧。两者都需要，但比赛更重要。", "托尼·帕克", "名人堂球员"),
            ("孩子们不需要更多的训练，他们需要更多真正的比赛经验。", "迪肯贝·穆托姆博", "名人堂球员"),
            ("比赛中的一分钟胜过训练中的十分钟。", "保罗·皮尔斯", "名人堂球员"),
            ("让孩子们在比赛中解决问题，而不是告诉他们答案。", "雷吉·米勒", "名人堂球员"),
            ("篮球智商不是教出来的，是打出来的。", "阿伦·艾弗森", "名人堂球员"),
            ("我见过最聪明的年轻球员都是在街头比赛中成长的。", "凯文·杜兰特", "NBA球星"),
            ("比赛给孩子们他们真正需要的东西：真实的反馈。", "勒布朗·詹姆斯", "NBA传奇球员")
        ] : [
            ("Kids learn fastest by playing games. Games teach what drills can't — how to compete, handle pressure, and communicate with teammates.", "Gregg Popovich", "NBA Head Coach"),
            ("The best players grew up on the streets and playgrounds, where every touch was a learning moment. Let kids play.", "Ettore Messina", "EuroLeague Head Coach"),
            ("We over-coach, over-drill, and under-play. The game itself is the best teacher.", "Bob Bigelow", "Youth Basketball Advocate"),
            ("The way I learned basketball was playing. Nobody taught me the pick-and-roll — I learned it in games.", "Steve Nash", "Hall of Fame Player"),
            ("Let the game be the teacher. Kids learn faster in meaningful game situations.", "Don Showalter", "USA Basketball Youth Coach"),
            ("You can't learn to swim on a blackboard. Basketball is the same.", "Phil Jackson", "Legendary NBA Coach"),
            ("The game is the best practice. What you learn in drills only makes sense in games.", "Pat Riley", "Hall of Fame Coach"),
            ("Let kids make mistakes. Mistakes in games are the best learning opportunities.", "Jay Bilas", "ESPN Basketball Analyst"),
            ("Young players need game time, not more practice time.", "Jerry West", "NBA Legend"),
            ("True basketball IQ is developed in games, not in practice.", "Larry Bird", "Hall of Fame Player"),
            ("I've seen too many kids practice perfect technique but freeze up in games.", "Charles Barkley", "Hall of Fame Player"),
            ("Games teach kids how to think. Drills only teach them how to act.", "Hugh Hollins", "Youth Basketball Coach"),
            ("Five-on-five is the best basketball classroom.", "Željko Obradović", "EuroLeague Legend"),
            ("Kids need to feel the rhythm of a game. No drill can simulate that.", "Rick Carlisle", "NBA Head Coach"),
            ("In my coaching career, the best players grew up playing games.", "Mike Krzyzewski", "Duke Legend"),
            ("Don't take away a child's right to make mistakes. Errors in games are catalysts for growth.", "John Wooden", "UCLA Legend"),
            ("Every game is a lesson. Win or lose, you learn.", "Mike D'Antoni", "NBA Head Coach"),
            ("Kids learn fastest when they're having fun. Keep games enjoyable.", "Steve Kerr", "NBA Head Coach"),
            ("Real decision-making can only develop under real game pressure.", "Brad Stevens", "NBA Executive"),
            ("I'd rather have kids learn in games than look perfect in practice.", "Tom Izzo", "College Basketball Coach"),
            ("The game is the ultimate test. Let them play it.", "Yao Ming", "Hall of Fame Player"),
            ("Kids need to understand why, not just how. Games give them the answer.", "Tim Duncan", "Hall of Fame Player"),
            ("The best learning happens when kids forget they're learning — that's games.", "Kobe Bryant", "Hall of Fame Player"),
            ("Games are the most underrated tool in youth basketball development.", "David Blatt", "EuroLeague Champion Coach"),
            ("Let kids find their own style through games.", "Manu Ginóbili", "Hall of Fame Player"),
            ("Drills teach technique, games teach wisdom. Both matter, but games matter more.", "Tony Parker", "Hall of Fame Player"),
            ("Kids don't need more drills. They need more real game experience.", "Dikembe Mutombo", "Hall of Fame Player"),
            ("One minute in a game is worth ten minutes in practice.", "Paul Pierce", "Hall of Fame Player"),
            ("Let kids solve problems in games instead of giving them the answers.", "Reggie Miller", "Hall of Fame Player"),
            ("Basketball IQ isn't taught — it's developed through playing.", "Allen Iverson", "Hall of Fame Player"),
            ("The smartest young players I've seen grew up playing pickup games.", "Kevin Durant", "NBA Star"),
            ("Games give kids what they really need: real feedback.", "LeBron James", "NBA Legend"),
            ("Stop the whistle. Let them play. Let them learn.", "Doc Rivers", "NBA Head Coach"),
            ("The playground taught me more than any coach ever could.", "Magic Johnson", "Hall of Fame Player"),
            ("In Serbia, we let kids play 3v3, 4v4, 5v5 from age 6. That's why we produce great players.", "Saša Đorđević", "EuroLeague Coach"),
            ("Youth basketball should be 80% games, 20% instruction. We have it backwards.", "Brian McCormick", "Youth Basketball Author")
        ]
        let randomQuote = quotes[Int.random(in: 0..<quotes.count)]
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label {
                    Text(isChinese ? "为什么要打比赛？" : "Why Play Games?")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Image(systemName: "quote.opening")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("\u{201C}\(randomQuote.quote)\u{201D}")
                .font(.footnote)
                .foregroundStyle(.primary)
                .italic()
                .lineSpacing(3)

            HStack(spacing: 6) {
                Text("— \(randomQuote.author)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(randomQuote.role)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
        let playerPool = availableStudents.isEmpty ? enrolledStudents : availableStudents

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

    // MARK: - Stat Highlights

    /// Tiny chips above the games list summarising the most interesting
    /// shape of the day so far. Kids and coaches scan them in 2 seconds.
    /// Only shows what's actually meaningful — empty session = empty strip.
    private struct GameHighlight: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let label: String
        let value: String
        let detail: String?
    }

    private var sessionHighlights: [GameHighlight] {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        let completedGames = session.games.filter { $0.status == .completed }
        guard !completedGames.isEmpty else { return [] }

        var out: [GameHighlight] = []

        // Top scorer across all completed games today.
        let allStats = completedGames.flatMap(\.playerStats)
        let scoreByPlayer: [UUID: Int] = Dictionary(allStats.map { ($0.playerId, $0.points) },
                                                     uniquingKeysWith: +)
        if let (pid, pts) = scoreByPlayer.max(by: { $0.value < $1.value }), pts > 0,
           let s = enrolledStudents.first(where: { $0.id == pid }) {
            out.append(.init(
                icon: "scope",
                tint: .orange,
                label: isCN ? "本场得分王" : "Top scorer",
                value: "\(pts)",
                detail: firstName(of: s)
            ))
        }

        // Most assists today — secondary "playmaker of the day" call-out.
        let assistsByPlayer: [UUID: Int] = Dictionary(allStats.map { ($0.playerId, $0.assists) },
                                                       uniquingKeysWith: +)
        if let (pid, ast) = assistsByPlayer.max(by: { $0.value < $1.value }), ast > 0,
           let s = enrolledStudents.first(where: { $0.id == pid }) {
            out.append(.init(
                icon: "hand.raised.fill",
                tint: .blue,
                label: isCN ? "助攻王" : "Most assists",
                value: "\(ast)",
                detail: firstName(of: s)
            ))
        }

        // Closest game — smallest non-zero margin among today's completed games.
        // For team games only; battle royal margins don't read the same way.
        let teamGames = completedGames.filter { !$0.gameType.isIndividual }
        let margins = teamGames.compactMap { game -> (margin: Int, gameNumber: Int)? in
            let scores = game.teamScores.values.sorted(by: >)
            guard scores.count >= 2 else { return nil }
            return (scores[0] - scores[1], game.gameNumber)
        }
        if let closest = margins.min(by: { $0.margin < $1.margin }) {
            out.append(.init(
                icon: "scalemass",
                tint: .purple,
                label: isCN ? "最焦灼" : "Closest game",
                value: closest.margin == 0
                    ? (isCN ? "平局" : "tie")
                    : "\(closest.margin) \(isCN ? "分" : "pt\(closest.margin == 1 ? "" : "s")")",
                detail: isCN ? "第\(closest.gameNumber)场" : "Game \(closest.gameNumber)"
            ))
        }

        return out
    }

    private var highlightsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(sessionHighlights) { highlight in
                    highlightChip(highlight)
                }
            }
        }
    }

    private func highlightChip(_ h: GameHighlight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: h.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(h.tint)
                Text(h.label)
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(h.value)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                if let detail = h.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 130, alignment: .leading)
        .background(h.tint.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(h.tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func firstName(of student: Student) -> String {
        student.name.components(separatedBy: " ").first ?? student.name
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
                .foregroundStyle(Color(hex: team.colorHex))
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
                } else if isIPad {
                    // iPad: Show both teams side by side
                    compactGameHeader
                    sideBySideTeamsView
                } else {
                    // iPhone: Tab-based team switching
                    compactGameHeader
                    teamTabs
                    playersList
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
                                Text(student.name.components(separatedBy: " ").first ?? student.name)
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
                                Text(student.name.components(separatedBy: " ").first ?? student.name)
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
                    Text(student.name.components(separatedBy: " ").first ?? student.name)
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
                        Text(student.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.chineseName, !chineseName.isEmpty {
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
                        Text(student.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                        if let chineseName = student.chineseName, !chineseName.isEmpty {
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
        return Button(action: add) {
            Text(localizedLabel)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 8))
        .controlSize(.regular)
        .tint(color)
        .sensoryFeedback(.impact(weight: .light), trigger: false)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in remove() }
        )
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
struct GameRecapView: View {
    let game: SessionGame
    let students: [Student]
    let allGamesInSession: [SessionGame]
    @Environment(\.dismiss) var dismiss
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    // MARK: - Award Types
    enum GameAward: CaseIterable {
        case mvp, sharpshooter, playmaker, wall, pickpocket, boardBoss, allAround, mostImproved
        
        var icon: String {
            switch self {
            case .mvp: return "crown.fill"
            case .sharpshooter: return "scope"
            case .playmaker: return "arrow.triangle.branch"
            case .wall: return "shield.lefthalf.filled"
            case .pickpocket: return "hand.point.up.left.fill"
            case .boardBoss: return "arrow.up.arrow.down.circle.fill"
            case .allAround: return "seal.fill"
            case .mostImproved: return "chart.line.uptrend.xyaxis"
            }
        }
        
        var color: Color {
            switch self {
            case .mvp: return Color.accentColor
            case .sharpshooter: return Color.accentColor
            case .playmaker: return .green
            case .wall: return .secondary
            case .pickpocket: return .red
            case .boardBoss: return Color.accentColor
            case .allAround: return Color.accentColor
            case .mostImproved: return .green
            }
        }
        
        func name(chinese: Bool) -> String {
            switch self {
            case .mvp: return chinese ? "MVP" : "MVP"
            case .sharpshooter: return chinese ? "神射手" : "Sharpshooter"
            case .playmaker: return chinese ? "助攻王" : "Playmaker"
            case .wall: return chinese ? "盖帽王" : "The Wall"
            case .pickpocket: return chinese ? "抢断王" : "Pickpocket"
            case .boardBoss: return chinese ? "篮板王" : "Board Boss"
            case .allAround: return chinese ? "全能之星" : "All-Around"
            case .mostImproved: return chinese ? "进步之星" : "Most Improved"
            }
        }
        
        func description(chinese: Bool) -> String {
            switch self {
            case .mvp: return chinese ? "本场最有价值球员" : "Most Valuable Player"
            case .sharpshooter: return chinese ? "得分最多" : "Most Points Scored"
            case .playmaker: return chinese ? "助攻次数最多" : "Most Assists"
            case .wall: return chinese ? "盖帽次数最多" : "Most Blocks"
            case .pickpocket: return chinese ? "抢断次数最多" : "Most Steals"
            case .boardBoss: return chinese ? "篮板最多" : "Most Rebounds"
            case .allAround: return chinese ? "多项数据均衡出色" : "Great in Multiple Stats"
            case .mostImproved: return chinese ? "比上场进步最大" : "Biggest Improvement"
            }
        }
    }
    
    // MARK: - Stat Calculations
    
    /// Calculate contribution score (MVP formula that values all stats)
    private func contributionScore(for stats: SessionPlayerStats) -> Double {
        Double(stats.points) * 1.0 +
        Double(stats.rebounds) * 1.2 +
        Double(stats.assists) * 1.5 +
        Double(stats.steals) * 1.5 +
        Double(stats.blocks) * 1.5
    }
    
    /// Get MVP (highest contribution score)
    private var mvpStats: SessionPlayerStats? {
        game.playerStats.max(by: { contributionScore(for: $0) < contributionScore(for: $1) })
    }
    
    /// Get all awards earned
    private var earnedAwards: [(award: GameAward, playerId: UUID, value: Int)] {
        var awards: [(GameAward, UUID, Int)] = []
        let stats = game.playerStats.filter { $0.hasStats }
        guard !stats.isEmpty else { return [] }
        
        // MVP
        if let mvp = mvpStats {
            awards.append((.mvp, mvp.playerId, Int(contributionScore(for: mvp))))
        }
        
        // Sharpshooter - most points (min 2)
        if let top = stats.max(by: { $0.points < $1.points }), top.points >= 2 {
            if top.playerId != mvpStats?.playerId {
                awards.append((.sharpshooter, top.playerId, top.points))
            }
        }
        
        // Playmaker - most assists (min 1)
        if let top = stats.max(by: { $0.assists < $1.assists }), top.assists >= 1 {
            awards.append((.playmaker, top.playerId, top.assists))
        }
        
        // The Wall - most blocks (min 1)
        if let top = stats.max(by: { $0.blocks < $1.blocks }), top.blocks >= 1 {
            awards.append((.wall, top.playerId, top.blocks))
        }
        
        // Pickpocket - most steals (min 1)
        if let top = stats.max(by: { $0.steals < $1.steals }), top.steals >= 1 {
            awards.append((.pickpocket, top.playerId, top.steals))
        }
        
        // Board Boss - most rebounds (min 2)
        if let top = stats.max(by: { $0.rebounds < $1.rebounds }), top.rebounds >= 2 {
            awards.append((.boardBoss, top.playerId, top.rebounds))
        }
        
        // All-Around - good in 3+ categories
        for stat in stats {
            var categories = 0
            if stat.points >= 2 { categories += 1 }
            if stat.rebounds >= 1 { categories += 1 }
            if stat.assists >= 1 { categories += 1 }
            if stat.steals >= 1 { categories += 1 }
            if stat.blocks >= 1 { categories += 1 }
            if categories >= 3 && stat.playerId != mvpStats?.playerId {
                awards.append((.allAround, stat.playerId, categories))
                break
            }
        }
        
        return awards
    }
    
    /// Get previous game stats for a player in this session
    private func previousGameStats(for playerId: UUID) -> SessionPlayerStats? {
        // Look for the same player in earlier games in this session
        let previousGames = allGamesInSession.filter { $0.id != game.id && $0.status == .completed }
        for prevGame in previousGames.reversed() {
            if let stats = prevGame.playerStats.first(where: { $0.playerId == playerId && $0.hasStats }) {
                return stats
            }
        }
        return nil
    }
    
    /// Calculate improvement percentage
    private func improvement(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return current > 0 ? 100 : nil }
        return Double(current - previous) / Double(previous) * 100
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Game result header
                    gameResultHeader
                    
                    // MVP Section
                    if let mvp = mvpStats, let student = students.first(where: { $0.id == mvp.playerId }) {
                        mvpSection(student: student, stats: mvp)
                    }
                    
                    // Awards Section
                    if !earnedAwards.isEmpty {
                        awardsSection
                    }
                    
                    // All Players Stats
                    allPlayersSection
                    
                    // Educational tip
                    educationalTip
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isChinese ? "比赛回顾" : "Game Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Game Result Header
    private var gameResultHeader: some View {
        VStack(spacing: 12) {
            Text(isChinese ? "比赛结束!" : "Game Over!")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            if game.gameType.isIndividual {
                let leaderboard = game.individualLeaderboard
                let top3 = Array(leaderboard.prefix(3))
                let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: max(1, top3.count))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(top3.enumerated()), id: \.element.playerId) { index, entry in
                        if let student = students.first(where: { $0.id == entry.playerId }) {
                            VStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    StudentAvatarView(student: student, size: index == 0 ? 60 : 48)
                                    if index == 0 {
                                        Image(systemName: "crown.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.accentColor)
                                            .offset(y: -10)
                                            .symbolEffect(.bounce, value: entry.playerId)
                                    }
                                }
                                Text("\(entry.points)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(index == 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                    .contentTransition(.numericText(value: Double(entry.points)))
                                Text(student.displayName)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                let teamsToShow = game.activeTeams.isEmpty ? game.teams : game.activeTeams
                let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: max(1, teamsToShow.count))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(teamsToShow, id: \.id) { team in
                        VStack(spacing: 6) {
                            ZStack(alignment: .top) {
                                Circle()
                                    .fill(Color(hex: team.colorHex))
                                    .frame(width: 44, height: 44)
                                if team.id == game.winningTeamId {
                                    Image(systemName: "crown.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.accentColor)
                                        .offset(y: -12)
                                        .symbolEffect(.bounce, value: team.id)
                                }
                            }
                            Text("\(game.score(for: team.id))")
                                .font(.title.bold().monospacedDigit())
                                .foregroundStyle(Color(hex: team.colorHex))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.numericText(value: Double(game.score(for: team.id))))
                            Text(GameTeam.localizedColorName(team.name))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    
    // MARK: - MVP Section
    private func mvpSection(student: Student, stats: SessionPlayerStats) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 80, height: 80)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: student.id)
            }

            Text("MVP")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.displayName)
                        .font(.title3.bold())
                    if let chinese = student.chineseName, !chinese.isEmpty, student.displayName != chinese {
                        Text(chinese)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ViewThatFits {
                HStack(spacing: 16) {
                    mvpStatBubble(isChinese ? "分" : "PTS", value: stats.points)
                    mvpStatBubble(isChinese ? "板" : "REB", value: stats.rebounds)
                    mvpStatBubble(isChinese ? "助" : "AST", value: stats.assists)
                    mvpStatBubble(isChinese ? "断" : "STL", value: stats.steals)
                    mvpStatBubble(isChinese ? "帽" : "BLK", value: stats.blocks)
                }
                HStack(spacing: 10) {
                    mvpStatBubble(isChinese ? "分" : "PTS", value: stats.points).frame(width: 38)
                    mvpStatBubble(isChinese ? "板" : "REB", value: stats.rebounds).frame(width: 38)
                    mvpStatBubble(isChinese ? "助" : "AST", value: stats.assists).frame(width: 38)
                    mvpStatBubble(isChinese ? "断" : "STL", value: stats.steals).frame(width: 38)
                    mvpStatBubble(isChinese ? "帽" : "BLK", value: stats.blocks).frame(width: 38)
                }
            }

            Text(isChinese ? "贡献值: \(Int(contributionScore(for: stats)))" : "Contribution: \(Int(contributionScore(for: stats)))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if let prevStats = previousGameStats(for: student.id) {
                comparisonRow(current: stats, previous: prevStats)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    private func mvpStatBubble(_ label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 44)
    }
    
    // MARK: - Comparison Row
    private func comparisonRow(current: SessionPlayerStats, previous: SessionPlayerStats) -> some View {
        VStack(spacing: 8) {
            Text(isChinese ? "与上场比较" : "vs Last Game")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                comparisonItem(isChinese ? "分" : "PTS", current: current.points, previous: previous.points)
                comparisonItem(isChinese ? "板" : "REB", current: current.rebounds, previous: previous.rebounds)
                comparisonItem(isChinese ? "助" : "AST", current: current.assists, previous: previous.assists)
                comparisonItem(isChinese ? "断" : "STL", current: current.steals, previous: previous.steals)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    private func comparisonItem(_ label: String, current: Int, previous: Int) -> some View {
        let diff = current - previous
        let arrow = diff > 0 ? "↑" : (diff < 0 ? "↓" : "→")
        let tint: AnyShapeStyle = diff > 0 ? AnyShapeStyle(Color.green) : (diff < 0 ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))

        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(arrow)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Text("\(abs(diff))")
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Awards Section
    private var awardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "荣誉榜" : "Awards")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(earnedAwards.filter { $0.award != .mvp }, id: \.award) { item in
                    if let student = students.first(where: { $0.id == item.playerId }) {
                        awardCard(award: item.award, student: student, value: item.value)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    private func awardCard(award: GameAward, student: Student, value: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(award.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: award.icon)
                    .font(.headline)
                    .foregroundStyle(award.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(award.name(chinese: isChinese))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(student.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            Text("\(value)")
                .font(.headline.bold().monospacedDigit())
                .foregroundStyle(award.color)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }

    // MARK: - All Players Section
    private var allPlayersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "全员数据" : "All Players")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(game.playerStats.sorted(by: { contributionScore(for: $0) > contributionScore(for: $1) }), id: \.playerId) { stats in
                if let student = students.first(where: { $0.id == stats.playerId }) {
                    playerStatRow(student: student, stats: stats)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func playerStatRow(student: Student, stats: SessionPlayerStats) -> some View {
        let prevStats = previousGameStats(for: student.id)
        let isMVP = stats.playerId == mvpStats?.playerId

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                StudentAvatarView(student: student, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(student.displayName)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if isMVP {
                            Image(systemName: "trophy.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    ViewThatFits {
                        HStack(spacing: 8) {
                            miniStat("PTS", value: stats.points, prev: prevStats?.points)
                            miniStat("REB", value: stats.rebounds, prev: prevStats?.rebounds)
                            miniStat("AST", value: stats.assists, prev: prevStats?.assists)
                            miniStat("STL", value: stats.steals, prev: prevStats?.steals)
                            miniStat("BLK", value: stats.blocks, prev: prevStats?.blocks)
                        }
                        HStack(spacing: 6) {
                            miniStat("PTS", value: stats.points, prev: prevStats?.points)
                            miniStat("REB", value: stats.rebounds, prev: prevStats?.rebounds)
                            miniStat("AST", value: stats.assists, prev: prevStats?.assists)
                            miniStat("STL", value: stats.steals, prev: prevStats?.steals)
                        }
                    }
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(Int(contributionScore(for: stats)))")
                        .font(.headline.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(isChinese ? "贡献" : "CTR")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }

            if let prev = prevStats {
                improvementTip(current: stats, previous: prev)
            }
        }
        .padding(10)
        .background(
            isMVP ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(HierarchicalShapeStyle.quinary),
            in: .rect(cornerRadius: 10)
        )
    }

    private func miniStat(_ label: String, value: Int, prev: Int?) -> some View {
        let diff = prev.map { value - $0 }
        let arrow: String? = diff.map { $0 > 0 ? "↑" : ($0 < 0 ? "↓" : nil) } ?? nil

        return HStack(spacing: 1) {
            Text("\(value)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.primary)
            if let arrow = arrow {
                Text(arrow)
                    .font(.system(size: 8))
                    .foregroundStyle((diff ?? 0) > 0 ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.red))
            }
        }
    }
    
    private func improvementTip(current: SessionPlayerStats, previous: SessionPlayerStats) -> some View {
        // Find the biggest improvement or suggestion
        var message = ""
        
        let pointsDiff = current.points - previous.points
        let rebDiff = current.rebounds - previous.rebounds
        let astDiff = current.assists - previous.assists
        let stlDiff = current.steals - previous.steals
        
        if pointsDiff > 2 {
            message = isChinese ? "得分大涨 +\(pointsDiff)!" : "Scoring up +\(pointsDiff)!"
        } else if astDiff > 0 {
            message = isChinese ? "助攻增加了！" : "More assists!"
        } else if rebDiff > 0 {
            message = isChinese ? "篮板进步了！" : "Rebounding improved!"
        } else if stlDiff > 0 {
            message = isChinese ? "防守更积极！" : "Better defense!"
        } else if current.rebounds == 0 && previous.rebounds == 0 {
            message = isChinese ? "试试抢篮板！" : "Try getting rebounds!"
        } else if current.assists == 0 && previous.assists == 0 {
            message = isChinese ? "多传球给队友！" : "Pass more to teammates!"
        }
        
        if message.isEmpty { return AnyView(EmptyView()) }
        
        return AnyView(
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 46)
        )
    }
    
    // MARK: - Educational Tip
    private var educationalTip: some View {
        let tips = isChinese ? [
            "助攻让队友更容易得分，是最重要的团队数据！",
            "篮板给球队更多进攻机会，抢篮板很重要！",
            "抢断和盖帽能阻止对手得分，防守也是进攻！",
            "好球员不只是得分，还要帮助队友！",
            "每次努力都有价值，数据会记录你的成长！"
        ] : [
            "Assists help teammates score - it's the best team stat!",
            "Rebounds give your team extra chances to score!",
            "Steals and blocks stop the other team - defense wins games!",
            "Great players don't just score, they help teammates too!",
            "Every effort counts - stats track your growth!"
        ]
        
        return Text(tips.randomElement() ?? tips[0])
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(Color.accentColor.opacity(0.08)), in: .rect(cornerRadius: 12))
    }
}


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
        session.attendanceMark(for: studentId)
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
                        // Same control as the session attendance tab: a
                        // present/absent switch, with Excused and Clear in the
                        // row's long-press menu. A notified absence must stay
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
                Text(student.name)
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
    
    @State private var searchText = ""
    @State private var selectedCategory: DrillCategory?
    @State private var selectedDifficulty: DifficultyLevel?
    @State private var showOnlySuggested = true
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var coachVisibleDrills: [DrillItem] {
        allDrills.filter { drill in
            let visibilityTag = drill.tags.first(where: { $0.hasPrefix("visibility:") })
            let ownerTag = drill.tags.first(where: { $0.hasPrefix("owner:") })

            if visibilityTag == "visibility:private" {
                guard let ownerTag else { return false }
                return ownerTag == "owner:\(currentCoachId.uuidString)"
            }

            return true
        }
    }
    
    // MARK: - Smart Suggestion Engine
    private var suggestedDrills: [DrillItem] {
        var scored: [(drill: DrillItem, score: Int)] = []
        
        for drill in coachVisibleDrills {
            var score = 0
            
            // 1. Match section type (high priority)
            switch section {
            case .warmup:
                if drill.category == .warmup || drill.category == .conditioning { score += 30 }
                if drill.durationMinutes <= 10 { score += 10 }
            case .main:
                if drill.category == .shooting || drill.category == .skills || drill.category == .offense || drill.category == .defense { score += 30 }
            case .cooldown:
                if drill.category == .cooldown { score += 20 }
                // Game section - any drill can work, but prefer team-focused
                if drill.tags.contains(where: { $0.lowercased().contains("game") || $0.lowercased().contains("scrimmage") }) { score += 25 }
            }
            
            // 2. Match phase focus areas (medium-high priority)
            if let phase = phase {
                for focus in phase.focus {
                    switch focus {
                    case .shooting:
                        if drill.category == .shooting { score += 20 }
                    case .ballHandling:
                        if drill.category == .skills || drill.tags.contains(where: { $0.lowercased().contains("dribbl") || $0.lowercased().contains("handle") }) { score += 20 }
                    case .passing:
                        if drill.tags.contains(where: { $0.lowercased().contains("pass") }) { score += 20 }
                    case .defense:
                        if drill.category == .defense { score += 20 }
                    case .conditioning:
                        if drill.category == .conditioning { score += 20 }
                    case .teamPlay:
                        if drill.category == .offense || drill.minPlayers > 2 { score += 15 }
                    case .gamePrep:
                        if drill.tags.contains(where: { $0.lowercased().contains("game") || $0.lowercased().contains("scrimmage") }) { score += 20 }
                    case .recovery:
                        if drill.category == .cooldown || drill.intensity < 3 { score += 15 }
                    }
                }
                
                // Match phase intensity
                let drillIntensity = drill.difficulty.level
                if abs(drillIntensity * 3 - phase.intensity) <= 2 { score += 10 }
            }
            
            // 3. Match student skill level (medium priority)
            if !students.isEmpty {
                let avgLevel = calculateStudentAverageLevel()
                let drillLevel = drill.difficulty.level
                
                // Perfect match
                if avgLevel == drillLevel { score += 15 }
                // Close match (within 1 level)
                else if abs(avgLevel - drillLevel) == 1 { score += 8 }
                // Too easy or too hard
                else { score -= 5 }
            }
            
            // 4. Match program age group (low-medium priority)
            if let program = program {
                let ageGroupLevel = ageGroupToLevel(program.ageGroup)
                let drillLevel = drill.difficulty.level
                if abs(ageGroupLevel - drillLevel) <= 1 { score += 10 }
            }
            
            // 5. Favorite drills get a boost
            if drill.isFavorite { score += 8 }
            
            // 6. Appropriate player count
            if let maxPlayers = drill.maxPlayers, !students.isEmpty {
                if students.count <= maxPlayers && students.count >= drill.minPlayers { score += 5 }
            }
            
            // Only include drills with positive scores for suggestions
            if score > 0 {
                scored.append((drill, score))
            }
        }
        
        return scored.sorted { $0.score > $1.score }.map { $0.drill }
    }
    
    private func calculateStudentAverageLevel() -> Int {
        guard !students.isEmpty else { return 2 }
        // Calculate based on age groups since Student doesn't have skills directly
        var totalLevel = 0
        for student in students {
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
        return totalLevel / students.count
    }
    
    private func ageGroupToLevel(_ ageGroup: AgeGroup) -> Int {
        switch ageGroup {
        case .u6, .u8, .u10: return 1
        case .u12, .u14: return 2
        case .u16, .u18, .adult: return 3
        }
    }
    
    private var filteredDrills: [DrillItem] {
        var drills = showOnlySuggested ? suggestedDrills : coachVisibleDrills
        
        if !searchText.isEmpty {
            drills = drills.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.localizedName.localizedCaseInsensitiveContains(searchText) }
        }
        
        if let category = selectedCategory {
            drills = drills.filter { $0.category == category }
        }
        
        if let difficulty = selectedDifficulty {
            drills = drills.filter { $0.difficulty == difficulty }
        }
        
        return drills
    }
    
    private var sectionColor: Color { section.color }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Smart suggestion banner
                if showOnlySuggested {
                    smartSuggestionBanner
                }
                
                // Search and filters
                searchAndFilters
                
                // Drill list
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredDrills) { drill in
                            drillSelectionRow(drill: drill)
                        }
                        
                        if filteredDrills.isEmpty {
                            emptyState
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isChinese ? "添加训练" : "Add Drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
        }
    }
    
    private var smartSuggestionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label {
                    Text(isChinese ? "智能推荐" : "Smart Suggestions")
                        .font(.footnote.weight(.semibold))
                } icon: {
                    Image(systemName: "wand.and.stars")
                        .font(.footnote)
                }
                .foregroundStyle(Color.accentColor)
                Spacer()
                Button {
                    showOnlySuggested.toggle()
                } label: {
                    Text(showOnlySuggested ? (isChinese ? "显示全部" : "Show All") : (isChinese ? "仅推荐" : "Suggested Only"))
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .tint(Color.accentColor)
                .sensoryFeedback(.selection, trigger: showOnlySuggested)
            }

            // Context info
            VStack(alignment: .leading, spacing: 4) {
                if let phase = phase {
                    Label {
                        Text(isChinese ? "阶段重点: \(phase.focus.map { $0.displayName }.joined(separator: ", "))" : "Phase focus: \(phase.focus.map { $0.displayName }.joined(separator: ", "))")
                            .font(.caption2)
                    } icon: {
                        Image(systemName: "flag.fill").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }

                Label {
                    let level = calculateStudentAverageLevel()
                    let levelText = level == 1 ? (isChinese ? "初级" : "Beginner") : (level == 2 ? (isChinese ? "中级" : "Intermediate") : (isChinese ? "高级" : "Advanced"))
                    Text(isChinese ? "学员水平: \(levelText)" : "Student level: \(levelText)")
                        .font(.caption2)
                } icon: {
                    Image(systemName: "person.3.fill").font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    }

    private var searchAndFilters: some View {
        VStack(spacing: 10) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "搜索训练..." : "Search drills...", text: $searchText)
                    .font(.subheadline)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SmartDrillFilterChip(title: isChinese ? "全部" : "All", isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(DrillCategory.allCases, id: \.self) { category in
                        SmartDrillFilterChip(title: category.displayName, isSelected: selectedCategory == category) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }

            // Difficulty filter
            HStack(spacing: 8) {
                Text(isChinese ? "难度:" : "Level:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(DifficultyLevel.allCases, id: \.self) { level in
                    difficultyChip(level: level)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func difficultyChip(level: DifficultyLevel) -> some View {
        let isSelected = selectedDifficulty == level
        let dotRow = HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i < level.level ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .frame(width: 6, height: 6)
            }
        }
        let action: () -> Void = { selectedDifficulty = selectedDifficulty == level ? nil : level }

        if isSelected {
            Button(action: action) { dotRow }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Color.accentColor)
        } else {
            Button(action: action) { dotRow }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.secondary)
        }
    }
    
    private func drillSelectionRow(drill: DrillItem) -> some View {
        let isAlreadyAdded = isDrillInSection(drill.id)
        let isSuggested = suggestedDrills.prefix(10).contains(where: { $0.id == drill.id })

        return Button {
            if !isAlreadyAdded {
                addDrillToSection(drill.id)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                // Thumbnail when the drill has visuals — coaches scan the
                // picker by image more than by name once a few drills exist.
                if let firstMedia = drill.media.min(by: { $0.sortOrder < $1.sortOrder }) {
                    DrillMediaThumb(media: firstMedia, size: 44, cornerRadius: 10)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: drill.category.icon)
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drill.localizedName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isAlreadyAdded ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                            .lineLimit(1)

                        if isSuggested && showOnlySuggested {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }

                        if drill.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }

                        if drill.media.count > 1 {
                            Label("\(drill.media.count)", systemImage: "photo.stack")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 8) {
                        Label {
                            Text("\(drill.durationMinutes)min")
                                .font(.caption)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "clock").font(.caption2)
                        }
                        .foregroundStyle(.secondary)

                        HStack(spacing: 2) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(i < drill.difficulty.level ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.quaternary))
                                    .frame(width: 5, height: 5)
                            }
                        }

                        Label {
                            Text(drill.maxPlayers != nil ? "\(drill.minPlayers)-\(drill.maxPlayers!)" : "\(drill.minPlayers)+")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "person.fill").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isAlreadyAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isAlreadyAdded ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.accentColor))
                    .symbolEffect(.bounce, value: isAlreadyAdded)
            }
            .padding(12)
            .contentShape(Rectangle())
            .opacity(isAlreadyAdded ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .disabled(isAlreadyAdded)
        .sensoryFeedback(.success, trigger: isAlreadyAdded)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(isChinese ? "没有找到训练" : "No drills found", systemImage: "tray")
        } actions: {
            if showOnlySuggested {
                Button(isChinese ? "查看所有训练" : "View all drills") {
                    showOnlySuggested = false
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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

// MARK: - Smart Drill Filter Chip (local to avoid conflicts)
private struct SmartDrillFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(action: action) {
                Text(title).font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.accentColor)
        } else {
            Button(action: action) {
                Text(title).font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(.secondary)
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
                                    Text(student.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let chinese = student.chineseName {
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
/// Renders the attendance photo with a clean dark-gradient watermark band at
/// the bottom showing coach name, date/time, location, a "X 人到场" badge and
/// the Chinese names of attending students. The band is attached via
/// `.overlay(alignment: .bottom)` so it can never overflow past the photo's
/// bottom edge — anchoring with `ZStack(alignment: .bottomLeading)` was
/// letting the last line of names get clipped on certain photo aspect ratios.
struct AttendanceWatermarkOverlay: View {
    let photo: UIImage
    let coachName: String
    /// Day of week (localized — e.g. "星期日"). Rendered as its own heavy
    /// emphasized line between the coach name and the date so a quick
    /// glance at a WeChat thumbnail can place which day the session was on.
    let weekdayText: String
    let dateText: String
    let location: String?
    let presentCount: Int
    let nameList: String

    /// Font/padding sizes are tuned for a 1024-wide photo (PhotoCaptureManager's
    /// max). Scale proportionally so the watermark stays legible on smaller
    /// source images and on WeChat thumbnails (which downscale aggressively).
    /// Clamped above 0.6 so very small photos still show readable text.
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

    private var watermarkBand: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            HStack(alignment: .firstTextBaseline, spacing: 18 * s) {
                VStack(alignment: .leading, spacing: 6 * s) {
                    if !coachName.isEmpty {
                        Text(coachName)
                            .font(.system(size: 54 * s, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if !weekdayText.isEmpty {
                        Text(weekdayText)
                            .font(.system(size: 38 * s, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    HStack(spacing: 10 * s) {
                        Text(dateText)
                        if let location, !location.isEmpty {
                            Text("·")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(.system(size: 28 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 12 * s)
                HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                    Text("\(presentCount)")
                        .font(.system(size: 38 * s, weight: .heavy))
                    Text("人到场")
                        .font(.system(size: 22 * s, weight: .heavy))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20 * s)
                .padding(.vertical, 10 * s)
                .background(Capsule().fill(Color.green))
            }

            if !nameList.isEmpty {
                Text(nameList)
                    .font(.system(size: 28 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(3)
                    .lineSpacing(4 * s)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32 * s)
        .padding(.vertical, 28 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.7), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
