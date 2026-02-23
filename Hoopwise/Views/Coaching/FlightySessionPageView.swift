import SwiftUI
import Combine
import MapKit
#if os(iOS)
import UIKit
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
    @State private var drillPickerSection: CurriculumSection = .warmup
    @State private var showingLiveSession = false
    @State private var selectedDrillForDetail: DrillItem?
    @State private var showingSmartDrillPicker = false
    @State private var showingManageStudents = false
    @State private var showingInlineDrillInputFor: CurriculumSection?
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
                        tabSelector
                            .frame(maxWidth: .infinity)
                        tabContent
                    }
                }
                #endif
                
                // Floating navigation buttons overlay
                HStack {
                    if !embeddedInSplit {
                        // Back button
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                    
                    // Menu button
                    Menu {
                        if accessMode.canEdit {
                            Button(action: { showingEditSheet = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "编辑详情" : "Edit Details", systemImage: "pencil")
                            }
                            
                            Button(action: { showingManageStudents = true }) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "管理学员" : "Manage Students", systemImage: "person.2.badge.gearshape")
                            }
                        }
                        
                        if session.status == .scheduled {
                            Button(action: startSession) {
                                Label(LocalizationManager.shared.currentLanguage == .chinese ? "开始课程" : "Start Session", systemImage: "play.fill")
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
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, geometry.safeAreaInsets.top + 30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(hex: "#f5f5f7").ignoresSafeArea())
        .navigationBarHidden(true)
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
            LiveSessionView(session: $session) {
                showingLiveSession = false
            }
        }
        #else
        .sheet(isPresented: $showingLiveSession) {
            LiveSessionView(session: $session) {
                showingLiveSession = false
            }
        }
        #endif
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
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.black)
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
                VStack(alignment: .leading, spacing: 6) {
                    // Status badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(session.status.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(session.status == .cancelled ? Color.red.opacity(0.6) : Color.black.opacity(0.25))
                    .background(.ultraThinMaterial.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(session.status == .cancelled ? Color.red.opacity(0.5) : Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    
                    // Title
                    Text(session.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(session.status == .cancelled ? .white.opacity(0.6) : .white)
                        .strikethrough(session.status == .cancelled, color: .red)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Location
                    if let location = session.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11))
                            Text(location)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // Phase info
                    if let phase = parentPhase {
                        Text(LocalizationManager.shared.currentLanguage == .chinese ? "阶段 \(phase.phaseNumber): \(phase.title)" : "Phase \(phase.phaseNumber): \(phase.title)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    HStack(spacing: 8) {
                        heroMetaPill(
                            icon: "calendar",
                            value: session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        )

                        heroMetaPill(
                            icon: "clock",
                            value: "\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))"
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, safeAreaTop + 50) // Content starts below Dynamic Island
        }
        .frame(height: 200 + safeAreaTop) // Extend height to include safe area
        .clipped()
        .onAppear {
            // Assign image to sessions without one, or replace broken Unsplash Source URLs
            if session.headerImageURL == nil || session.headerImageURL?.contains("source.unsplash.com") == true {
                session.headerImageURL = SessionEvent.randomUnsplashURL()
                saveSession()
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
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(0.95))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.26))
        .background(.ultraThinMaterial.opacity(0.28))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .cornerRadius(10)
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
    
    // MARK: - Tab Selector Namespace for matchedGeometryEffect
    @Namespace private var tabNamespace
    
    // MARK: - Tab Selector (Liquid Glass Style)
    private var tabSelector: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 4) {
            tabButton(title: isChinese ? "计划" : "Plan", index: 0)
            tabButton(title: isChinese ? "出勤" : "Attend", index: 1)
            #if os(iOS)
            tabButton(title: isChinese ? "比赛" : "Games", index: 2)
            tabButton(title: isChinese ? "笔记" : "Notes", index: 3)
            #else
            tabButton(title: isChinese ? "笔记" : "Notes", index: 2)
            #endif
        }
        .padding(6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .glassEffect()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
    
    private func tabButton(title: String, index: Int) -> some View {
        let isActive = selectedTab == index
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? programColor : Color.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule()
                            .fill(programColor.opacity(0.3))
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            }
                            .glassEffect()
                            .matchedGeometryEffect(id: "activeTab", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Plan Tab
    private var planTab: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // Duration Intelligence Bar
                durationIntelligenceBar
                
                // Quick Picks (Recently Used / Popular)
                if accessMode.canEdit && (!recentlyUsedDrills.isEmpty || !popularDrillsForAgeGroup.isEmpty) {
                    quickPicksSection
                }
                
                // Warmup
                curriculumSection(
                    title: isChinese ? "热身" : "WARMUP",
                    icon: "flame.fill",
                    color: .orange,
                    drillIds: session.curriculum.warmupDrillIds,
                    minutes: session.curriculum.warmupMinutes,
                    section: .warmup
                )
                
                // Skills
                curriculumSection(
                    title: isChinese ? "技能" : "SKILLS",
                    icon: "figure.basketball",
                    color: .blue,
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
                        .foregroundColor(.black)
                    
                    Text("•")
                        .foregroundColor(.gray)
                    
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
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text("\(drill.durationMinutes)m")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.purple.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white)
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
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(color)
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // Duration chip with actual time
                Text(isChinese ? "\(actualDuration) 分钟" : "\(actualDuration) min")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.12))
                    .cornerRadius(6)
                
                // Compact + menu for add options
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(color)
                            .frame(width: 28, height: 28)
                            .background(color.opacity(0.12))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Inline text input (appears when triggered from menu)
            if showingInlineDrillInputFor == section && accessMode.canEdit {
                HStack(spacing: 8) {
                    TextField(
                        isChinese ? "输入训练名称..." : "Enter drill name...",
                        text: Binding(
                            get: { inlineDrillTextBySection[section] ?? "" },
                            set: { inlineDrillTextBySection[section] = $0 }
                        )
                    )
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(10)
                    .onSubmit { addInlineTextDrill(section: section) }
                    
                    Button {
                        addInlineTextDrill(section: section)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(color)
                    }
                    
                    Button {
                        withAnimation { showingInlineDrillInputFor = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Drills with drag-to-reorder
            if drillIds.isEmpty {
                HStack {
                    Text(isChinese ? "点击 + 添加训练" : "Tap + to add drills")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
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
        .background(Color.white)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.14), lineWidth: 1)
        )
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.16))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func drillRow(drill: DrillItem, color: Color, section: CurriculumSection, index: Int, totalCount: Int) -> some View {
        let isExpanded = expandedDrillId == drill.id
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return VStack(spacing: 0) {
            // Main row - tap to expand
            HStack(spacing: 12) {
                // Drag handle (only when editing)
                if accessMode.canEdit {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.4))
                        .frame(width: 16)
                }
                
                Image(systemName: drill.category.icon)
                    .font(.system(size: 14))
                    .foregroundColor(Color.drillCategoryColor(drill.category))
                    .frame(width: 32, height: 32)
                    .background(Color.drillCategoryColor(drill.category).opacity(0.12))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(drill.localizedName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text("\(drill.durationMinutes) min")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(i < drill.difficulty.level ? color : Color.gray.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                }
                
                Spacer()
                
                if session.drillsCompleted.contains(drill.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
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
                    if !drill.description.isEmpty {
                        Text(drill.description)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .lineLimit(3)
                    }
                    
                    if !drill.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isChinese ? "步骤" : "Steps")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(color)
                            ForEach(Array(drill.instructions.prefix(3).enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(idx + 1).")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(color)
                                    Text(step)
                                        .font(.system(size: 11))
                                        .foregroundColor(.black.opacity(0.8))
                                }
                            }
                            if drill.instructions.count > 3 {
                                Text(isChinese ? "+\(drill.instructions.count - 3) 更多" : "+\(drill.instructions.count - 3) more")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // Quick actions
                    HStack(spacing: 12) {
                        Button {
                            selectedDrillForDetail = drill
                        } label: {
                            Label(isChinese ? "详情" : "Details", systemImage: "info.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(color)
                        }
                        
                        Spacer()
                        
                        if accessMode.canEdit {
                            // Move up
                            if index > 0 {
                                Button {
                                    withAnimation { moveDrill(from: index, to: index - 1, in: section) }
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // Move down
                            if index < totalCount - 1 {
                                Button {
                                    withAnimation { moveDrill(from: index, to: index + 1, in: section) }
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Button {
                                withAnimation {
                                    expandedDrillId = nil
                                    removeDrill(drill.id, from: section)
                                }
                            } label: {
                                Label(isChinese ? "移除" : "Remove", systemImage: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(.horizontal, accessMode.canEdit ? 58 : 64)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isExpanded ? color.opacity(0.04) : Color.clear)
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
                    .foregroundColor(.black)
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
                                .foregroundColor(.gray)
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
                                .foregroundColor(.gray)
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
                                .foregroundColor(.gray)
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
                                .foregroundColor(.gray)
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
                        .foregroundColor(.gray)
                        
                        // Student count
                        HStack(spacing: 4) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 10))
                            Text("\(enrolledStudents.count) \(isChinese ? "学员" : "students")")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.gray)
                        
                        // Avg skill level indicator
                        if !enrolledStudents.isEmpty {
                            let avgLevel = calculateAverageSkillLevel()
                            HStack(spacing: 4) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 10))
                                Text(isChinese ? "平均水平: \(avgLevel)" : "Avg Level: \(avgLevel)")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.gray)
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
        .background(Color.white)
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
                .background(Color.white)

                if parentProgram != nil && accessMode.canEdit {
                    addAthleteButton
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                if let photoPath = session.attendancePhotoPath {
                    attendancePhotoPreview(photoPath: photoPath)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

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
                        
                        if let photoPath = session.attendancePhotoPath {
                            attendancePhotoPreview(photoPath: photoPath)
                        }
                        
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
            AddAthleteFromAttendanceView(
                session: session,
                program: parentProgram,
                onEnroll: { studentId in
                    enrollStudentFromAttendance(studentId: studentId)
                }
            )
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
                        .foregroundColor(AppTheme.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
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
    
    private func enrollStudentFromAttendance(studentId: UUID) {
        guard var program = parentProgram else { return }
        
        // Add to program enrollment
        if !program.enrolledStudentIds.contains(studentId) {
            program.enrolledStudentIds.append(studentId)
            dataManager.updateProgram(program)
        }
        
        // Mark as present in this session
        if !session.actualAttendeeIds.contains(studentId) {
            session.actualAttendeeIds.append(studentId)
            saveSession()
        }
        
        HapticFeedback.notification(.success)
    }
    
    private var attendanceStats: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 0) {
            attendanceStat(
                value: "\(session.actualAttendeeIds.count)",
                label: isChinese ? "到场" : "Present",
                color: .green
            )
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            attendanceStat(
                value: "\(enrolledStudents.count)",
                label: isChinese ? "预期" : "Expected",
                color: .black
            )
            
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: 1, height: 40)
            
            let rate = enrolledStudents.isEmpty ? 0 : Double(session.actualAttendeeIds.count) / Double(enrolledStudents.count)
            attendanceStat(
                value: "\(Int(rate * 100))%",
                label: isChinese ? "比率" : "Rate",
                color: rate >= 0.8 ? .green : .orange
            )
        }
        .padding(.vertical, 14)
        .background(Color.white)
    }
    
    private func attendanceStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func attendancePhotoPreview(photoPath: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 12))
                    .foregroundColor(programColor)
                Text(isChinese ? "考勤照片" : "Attendance Photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
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
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
    
    private var photoErrorPlaceholder: some View {
        HStack {
            Image(systemName: "photo")
                .foregroundColor(AppTheme.textTertiary)
            Text(isChinese ? "无法加载照片" : "Unable to load photo")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surfaceColor)
        .cornerRadius(10)
    }
    
    private func attendanceRow(student: Student) -> some View {
        let isPresent = session.actualAttendeeIds.contains(student.id)
        let isExcused = session.excusedAbsences.contains(student.id)
        let isExpected = session.attendeeIds.contains(student.id)
        
        // Determine attendance state
        let attendanceState: AttendanceState = {
            if isPresent { return .present }
            if isExcused { return .excused }
            return .absent  // Forfeited if expected
        }()
        
        return HStack(spacing: 10) {
            // Main tappable area - opens Quick Peep
            Button(action: { selectedStudentForPeep = student }) {
                HStack(spacing: 10) {
                    // Avatar with presence indicator
                    ZStack(alignment: .bottomTrailing) {
                        StudentAvatarView(student: student, size: 40)
                        
                        // Status indicator dot
                        Circle()
                            .fill(attendanceState.color)
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
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                        
                        if let chinese = student.chineseName {
                            Text(chinese)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()

            Button(action: {
                setAttendanceState(for: student.id, state: isPresent ? .absent : .present)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isPresent ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isChinese ? "到场" : "Present")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(isPresent ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(isPresent ? Color.green : AppTheme.surfaceColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(AppTheme.isDark ? 0.25 : 0.08), lineWidth: isPresent ? 0 : 1)
                )
            }
            .disabled(!accessMode.canTakeAttendance)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                selectedStudentForMeasurement = student
            } label: {
                Label(isChinese ? "数据" : "Metrics", systemImage: "chart.bar.fill")
            }
            .tint(Color(hex: "#667eea"))

            if isExpected {
                Button {
                    setAttendanceState(for: student.id, state: isExcused ? .absent : .excused)
                } label: {
                    Label(isChinese ? "请假" : "Excuse", systemImage: "calendar.badge.clock")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isPresent || isExcused {
                Button(role: .destructive) {
                    setAttendanceState(for: student.id, state: .absent)
                } label: {
                    Label(isChinese ? "清除" : "Clear", systemImage: "xmark.circle.fill")
                }
            }
        }
        #endif
    }
    
    // MARK: - Attendance State
    private enum AttendanceState {
        case present   // Attended - session consumed
        case absent    // Forfeited - session consumed (expected but no-show)
        case excused   // Excused absence - session preserved
        
        var color: Color {
            switch self {
            case .present: return .green
            case .absent: return Color.gray.opacity(0.4)
            case .excused: return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .present: return "checkmark"
            case .absent: return "xmark"
            case .excused: return "clock"
            }
        }
    }
    
    private func setAttendanceState(for studentId: UUID, state: AttendanceState) {
        // Remove from all lists first
        session.actualAttendeeIds.removeAll { $0 == studentId }
        session.excusedAbsences.removeAll { $0 == studentId }
        
        // Add to appropriate list based on state
        switch state {
        case .present:
            session.actualAttendeeIds.append(studentId)
        case .excused:
            session.excusedAbsences.append(studentId)
        case .absent:
            // Not in any list = forfeited (if expected)
            break
        }
        
        saveSession()
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
    @Namespace private var notesToggleNamespace
    
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
                notesTypeToggle.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
                
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
            .background(Color(red: 1.0, green: 0.99, blue: 0.96))
            
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
        HStack(spacing: 0) {
            notesToggleButton(title: isChinese ? "课程" : "Session", target: .session)
            notesToggleButton(title: isChinese ? "复盘" : "Reflection", target: .reflections)
        }
        .padding(4)
        .background { Capsule().fill(.ultraThinMaterial).glassEffect() }
    }
    
    private func notesToggleButton(title: String, target: NotesEditorTarget) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                notesEditorTarget = target
                focusedNotesEditor = target
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: notesEditorTarget == target ? .medium : .regular))
                .foregroundColor(notesEditorTarget == target ? .blue : .gray)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if notesEditorTarget == target {
                        Capsule().fill(.ultraThinMaterial).glassEffect()
                            .matchedGeometryEffect(id: "notesToggle", in: notesToggleNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
    
    private var notesFullBleedEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: activeNotesBinding)
                .focused($focusedNotesEditor, equals: notesEditorTarget)
                .font(.system(size: 17, weight: .regular))
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
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Color.gray.opacity(0.5))
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
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showPreviousNotes.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Text(isChinese ? "上次课程笔记" : "PREVIOUS SESSION NOTES")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text("· \(prev.startTime.formatted(date: .abbreviated, time: .omitted))")
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.textTertiary)
                            Spacer()
                            Image(systemName: showPreviousNotes ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    if showPreviousNotes {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 8) {
                                if let notes = prev.notes, !notes.isEmpty {
                                    Text(notes).font(.system(size: 14)).foregroundColor(AppTheme.textSecondary).lineLimit(6)
                                }
                                if let coachNotes = prev.coachNotes, !coachNotes.isEmpty {
                                    Text(coachNotes).font(.system(size: 14, weight: .regular).italic()).foregroundColor(AppTheme.textTertiary).lineLimit(4)
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
                Text(isChinese ? "提及" : "Mention").font(.system(size: 12, weight: .semibold)).foregroundColor(.gray).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(enrolledStudents.prefix(10)) { student in
                            Button { insertMention("@\(student.name)"); showMentionPicker = false } label: {
                                Text("@\(student.name.components(separatedBy: " ").first ?? student.name)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                            }
                        }
                        ForEach(activeCoachesForTagging) { coach in
                            Button { insertMention("@\(coach.name)"); showMentionPicker = false } label: {
                                Text("@\(coach.name.components(separatedBy: " ").first ?? coach.name)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                            }
                        }
                    }.padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .background { RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).glassEffect() }
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var notesTagPickerOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "标签" : "Tag").font(.system(size: 12, weight: .semibold)).foregroundColor(.gray).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["focus", "improve", "highlight", "followup", "urgent"], id: \.self) { tag in
                            Button { insertMention("#\(tag)"); showTagPicker = false } label: {
                                Text("#\(tag)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                        }
                    }.padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
            .background { RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial).glassEffect() }
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var notesFloatingActionBar: some View {
        HStack(spacing: 16) {
            Button { showNotesUtilities.toggle() } label: {
                Label(isChinese ? "笔记" : "Notes", systemImage: "square.grid.2x2").font(.system(size: 12, weight: .medium))
            }
            Button { withAnimation { showMentionPicker = true; showTagPicker = false } } label: {
                Label(isChinese ? "标签" : "Tag", systemImage: "at").font(.system(size: 12, weight: .medium))
            }
            Button { showReminderPanel.toggle() } label: {
                Label(isChinese ? "提醒" : "Remind", systemImage: "bell").font(.system(size: 12, weight: .medium))
            }
            Button { appendQuickNote() } label: {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    .frame(width: 28, height: 28).background(programColor).clipShape(Circle())
            }
        }
        .foregroundColor(AppTheme.textSecondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background { Capsule().fill(.ultraThinMaterial).glassEffect() }
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
                .foregroundColor(AppTheme.textSecondary)

            HStack(spacing: 8) {
                notesHintChip(icon: "note.text", label: isChinese ? "条目" : "Entries")
                notesHintChip(icon: "square.grid.2x2", label: isChinese ? "便签" : "Sticky")
                notesHintChip(icon: "bell", label: isChinese ? "提醒" : "Reminders")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
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
        .background(Color.white)
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
                    .foregroundColor(AppTheme.textTertiary)
                TextField(isChinese ? "搜索笔记" : "Search notes", text: $notesSearchText)
                    .font(.system(size: 13))

                if !notesSearchText.isEmpty {
                    Button {
                        notesSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
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
        .background(Color.white)
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
                    .foregroundColor(AppTheme.textTertiary)
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
        .background(Color.white)
        .cornerRadius(12)
    }

    private var notesCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if (notesViewMode == .sticky ? stickyNoteCards : filteredNoteCards).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(isChinese ? "还没有笔记，先创建一条。" : "No notes yet. Create your first one.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.white)
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
                        .foregroundColor(AppTheme.textSecondary)
                }
            }

            if !card.body.isEmpty {
                Text(card.body)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(compact ? 3 : 2)
            }

            HStack {
                Text(card.source == .session ? (isChinese ? "课程" : "Session") : (isChinese ? "复盘" : "Reflection"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
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
                        .foregroundColor(AppTheme.textSecondary)
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
                                .foregroundColor(AppTheme.textPrimary)
                            Text(item.1.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .padding(12)
                    .background(Color.white)
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
                    .foregroundColor(AppTheme.textPrimary)
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
        .background(Color.white)
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
                    .foregroundColor(AppTheme.textPrimary)
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
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
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
            HStack(spacing: 8) {
                Image(systemName: "star")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Text("SESSION RATING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: {
                        session.rating = star
                        saveSession()
                    }) {
                        Image(systemName: star <= (session.rating ?? 0) ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundColor(.yellow)
                    }
                    .disabled(!accessMode.canAddNotes)
                }
                Spacer()
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
    
    private var manOfTheMatchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "trophy")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow)
                Text("MAN OF THE MATCH")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
            
            if let momId = session.manOfTheMatchId,
               let student = dataManager.students.first(where: { $0.id == momId }) {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.yellow)
                    
                    StudentAvatarView(student: student, size: 40)
                    
                    Text(student.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    if accessMode.canAddNotes {
                        Button("Change") {
                            showingStudentPicker = true
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue)
                    }
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            } else {
                Button(action: { showingStudentPicker = true }) {
                    HStack {
                        Image(systemName: "star")
                            .foregroundColor(.yellow.opacity(0.6))
                        Text("Select Man of the Match")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                }
                .disabled(!accessMode.canAddNotes)
            }
        }
    }
    
    // MARK: - Actions
    private func toggleAttendance(for studentId: UUID) {
        if session.actualAttendeeIds.contains(studentId) {
            session.actualAttendeeIds.removeAll { $0 == studentId }
        } else {
            session.actualAttendeeIds.append(studentId)
            // Also remove from excused if present
            session.excusedAbsences.removeAll { $0 == studentId }
        }
        saveSession()
    }
    
    private func startSession() {
        session.status = .inProgress
        saveSession()
        showingLiveSession = true
        
        // Start Live Activity
        #if os(iOS)
        let programName = parentProgram?.name ?? "Training Session"
        let accentColor = parentProgram?.colorHex ?? "#FF6B35"
        
        // Build drill names dictionary
        var drillNames: [UUID: String] = [:]
        for drillId in session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds + session.curriculum.gameDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                drillNames[drillId] = drill.name
            }
        }
        
        Task { @MainActor in
            SessionLiveActivityManager.shared.startActivity(
                for: session,
                programName: programName,
                accentColorHex: accentColor,
                drillNames: drillNames
            )
        }
        #endif
    }
    
    private func skipSession(reason: SkipReason) {
        session.status = .skipped
        session.notes = (session.notes ?? "") + (session.notes?.isEmpty == false ? "\n" : "") + "Skipped: \(reason.displayName)"
        saveSession()
        HapticFeedback.notification(.warning)
    }
    
    private func cancelSession() {
        session.status = .cancelled
        saveSession()
        HapticFeedback.notification(.warning)
    }
    
    private func completeSession() {
        session.status = .completed
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
                        .background(Color.white)
                        .cornerRadius(10)

                    TextField(isChinese ? "训练描述（可选）" : "Description (optional)", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white)
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
                    .background(Color.white)
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
                    .background(Color.white)
                    .cornerRadius(10)

                    Picker(isChinese ? "可见性" : "Visibility", selection: $visibility) {
                        ForEach(DrillLibraryVisibility.allCases, id: \.self) { option in
                            Text(isChinese ? option.chineseTitle : option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(10)
                }
                .padding(16)
            }
            .background(Color(hex: "#f5f5f7").ignoresSafeArea())
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
enum SkipReason: String, CaseIterable, Identifiable {
    case holiday = "holiday"
    case internalReason = "internal"
    case weather = "weather"
    case venueUnavailable = "venue"
    case coachUnavailable = "coach"
    case other = "other"
    
    var id: String { rawValue }
    
    var displayName: String {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch self {
        case .holiday: return isChinese ? "假期" : "Holiday"
        case .internalReason: return isChinese ? "内部原因" : "Internal Reason"
        case .weather: return isChinese ? "天气原因" : "Weather"
        case .venueUnavailable: return isChinese ? "场地不可用" : "Venue Unavailable"
        case .coachUnavailable: return isChinese ? "教练不可用" : "Coach Unavailable"
        case .other: return isChinese ? "其他" : "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .holiday: return "gift.fill"
        case .internalReason: return "building.2.fill"
        case .weather: return "cloud.rain.fill"
        case .venueUnavailable: return "mappin.slash"
        case .coachUnavailable: return "person.fill.xmark"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

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
                
                // Confirm button
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(isChinese ? "确认跳过" : "Confirm Skip")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom)
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
                
                if session.games.isEmpty {
                    emptyGamesState
                        .padding(.horizontal, 16)
                } else {
                    // Compact game list with dividers
                    VStack(spacing: 0) {
                        ForEach(Array(session.games.enumerated()), id: \.element.id) { index, game in
                            gameRow(game)
                            if index < session.games.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(12)
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
                    game: Binding(get: { session.games[index] }, set: { session.games[index] = $0 }),
                    students: enrolledStudents,
                    allGamesInSession: session.games,
                    onSave: onSave,
                    onSaveCompletedRound: { completedRound in
                        session.games.append(completedRound)
                        onSave()
                    }
                )
            }
        }
        .fullScreenCover(item: $selectedRecapGame) { game in
            GameRecapView(game: game, students: enrolledStudents, allGamesInSession: session.games)
        }
    }
    
    private var gamesHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SCRIMMAGE GAMES").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.gray)
                Text("\(session.games.count) game\(session.games.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundColor(.gray.opacity(0.7))
            }
            Spacer()
            Button(action: { showingCreateGame = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("New Game").font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 8).background(programColor).cornerRadius(20)
            }
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
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(isChinese ? "为什么要打比赛？" : "Why Play Games?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "quote.opening")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.5))
            }
            
            Text("\"\(randomQuote.quote)\"")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.85))
                .italic()
                .lineSpacing(3)
            
            HStack(spacing: 6) {
                Text("— \(randomQuote.author)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                Text("·")
                    .foregroundColor(.gray.opacity(0.5))
                Text(randomQuote.role)
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
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
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
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

        session.games.append(newGame)
        onSave()
        selectedGame = newGame
    }
    
    private func deleteGame(_ game: SessionGame) {
        session.games.removeAll { $0.id == game.id }
        onSave()
    }
    
    private func gameRow(_ game: SessionGame) -> some View {
        HStack(spacing: 12) {
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Game \(game.gameNumber)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    statusBadge(game.status)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: game.gameType.icon)
                        .font(.system(size: 10))
                    Text(game.gameType.displayName)
                        .font(.system(size: 11, weight: .medium))
                    Text("•")
                        .foregroundColor(.gray.opacity(0.5))
                    Text("\(game.durationMinutes) min")
                        .font(.system(size: 11))
                }
                .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Compact team scores
            if !game.teams.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(game.activeTeams.enumerated()), id: \.element.id) { index, team in
                        compactTeamScore(team: team, score: game.score(for: team.id))
                        if index < game.activeTeams.count - 1 {
                            Text("-")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            // Action button
            Button(action: {
                if game.status == .completed {
                    selectedRecapGame = game
                } else {
                    selectedGame = game
                }
            }) {
                Image(systemName: game.status == .completed ? "chart.bar.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(game.status == .completed ? .green : programColor)
                    .cornerRadius(8)
            }
            
            // Delete button
            Button(action: {
                gameToDelete = game
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
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
                        .foregroundColor(.white)
                )
            Text("\(score)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: team.colorHex))
        }
    }
    
    private func statusBadge(_ status: SessionGameStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor(status)).frame(width: 6, height: 6)
            Text(status.displayName).font(.system(size: 10, weight: .semibold))
        }.foregroundColor(statusColor(status)).padding(.horizontal, 8).padding(.vertical, 4).background(statusColor(status).opacity(0.1)).cornerRadius(8)
    }
    
    private func statusColor(_ status: SessionGameStatus) -> Color {
        switch status { case .setup: return .gray; case .ready: return .blue; case .inProgress: return .orange; case .paused: return .yellow; case .completed: return .green }
    }
}

// MARK: - Scroll Offset Preference Key
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct CreateGameSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    @Binding var session: SessionEvent
    let enrolledStudents: [Student]
    let programColor: Color
    let onSave: () -> Void
    
    @State private var selectedGameType: SessionGameType = .twoTeam
    @State private var teams: [GameTeam] = []
    @State private var gameDuration: Int = 10
    @State private var unassignedPlayerIds: Set<UUID> = []
    @State private var usePreviousConfig: Bool = false
    @State private var hasPreviousConfig: Bool = false
    @State private var showOnlyPresent: Bool = true  // Default to showing only present students
    @State private var battleRoyalPlayerIds: Set<UUID> = []  // Players for Battle Royal mode
    @State private var selectedUnassignedIds: Set<UUID> = []  // Selected players to assign to a team
    
    // Filtered students based on toggle
    private var availableStudents: [Student] {
        if showOnlyPresent {
            return enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }
        } else {
            return enrolledStudents
        }
    }
    
    private var minTeams: Int { selectedGameType.requiredTeams }
    private var maxTeams: Int { selectedGameType == .twoTeam ? 6 : 4 }
    private var isBattleRoyal: Bool { selectedGameType.isIndividual }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    gameTypeSection
                    playerFilterSection
                    if !isBattleRoyal && hasPreviousConfig { previousConfigSection }
                    durationSection
                    
                    // Show teams section for team games, players section for Battle Royal
                    if isBattleRoyal {
                        battleRoyalPlayersSection
                    } else {
                        teamsSection
                        if !unassignedPlayerIds.isEmpty { unassignedPlayersSection }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color(hex: "#f5f5f7")).navigationTitle(LocalizationManager.shared.currentLanguage == .chinese ? "创建比赛" : "Create Game").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { 
                    Button(LocalizationManager.shared.currentLanguage == .chinese ? "创建" : "Create") { createGame() }
                        .disabled(isBattleRoyal ? battleRoyalPlayerIds.count < 2 : (teams.count < minTeams || teams.contains { $0.playerIds.isEmpty }))
                        .fontWeight(.semibold) 
                }
            }
        }
        .onAppear { loadInitialState() }
        .onChange(of: selectedGameType) { _, newType in adjustTeamsForGameType(newType) }
    }
    
    private func loadInitialState() {
        // For Battle Royal, add all available players by default
        if isBattleRoyal {
            battleRoyalPlayerIds = Set(availableStudents.map { $0.id })
            return
        }
        
        // Check for previous game configuration
        if let lastGame = session.games.last, !lastGame.gameType.isIndividual {
            hasPreviousConfig = true
            // Default to use previous config if available
            usePreviousConfig = true
            loadPreviousConfiguration(from: lastGame)
        } else {
            // Use available students based on filter
            refreshUnassignedPlayers()
            setupDefaultTeams()
        }
    }
    
    private func refreshUnassignedPlayers() {
        let studentIds = availableStudents.map { $0.id }
        // Keep only players that are in the available list and not assigned to teams
        let assignedIds = Set(teams.flatMap { $0.playerIds })
        unassignedPlayerIds = Set(studentIds).subtracting(assignedIds)
    }
    
    private func loadPreviousConfiguration(from game: SessionGame) {
        selectedGameType = game.gameType
        gameDuration = game.durationMinutes
        // Copy teams but reset wins/losses for new game, filter to available students only
        let availableIds = Set(availableStudents.map { $0.id })
        teams = game.teams.map { team in
            var newTeam = GameTeam(id: team.id, name: team.name, colorHex: team.colorHex, playerIds: [])
            newTeam.playerIds = team.playerIds.filter { availableIds.contains($0) }
            return newTeam
        }
        
        // Find any available students not in teams
        let assignedIds = Set(teams.flatMap { $0.playerIds })
        unassignedPlayerIds = availableIds.subtracting(assignedIds)
    }
    
    private func setupDefaultTeams() {
        let defaultTeamCount = selectedGameType.requiredTeams
        teams = []
        for i in 0..<defaultTeamCount {
            let preset = GameTeam.presetColors[i]
            teams.append(GameTeam(name: preset.name, colorHex: preset.hex))
        }
    }
    
    private func adjustTeamsForGameType(_ type: SessionGameType) {
        if type.isIndividual {
            // For Battle Royal, add all available players
            battleRoyalPlayerIds = Set(availableStudents.map { $0.id })
            return
        }
        let required = type.requiredTeams
        while teams.count < required {
            addTeam()
        }
    }
    
    // MARK: - Game Type Section (Native Segmented Picker)
    private var gameTypeSection: some View {
        Picker("Game Type", selection: $selectedGameType) {
            ForEach(SessionGameType.allCases, id: \.self) { type in
                Label(type.localizedName, systemImage: type.icon)
                    .tag(type)
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - Previous Config Section
    private var previousConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(programColor)
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "使用上次分队" : "Use Previous Team Setup")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $usePreviousConfig)
                    .labelsHidden()
                    .onChange(of: usePreviousConfig) { _, useIt in
                        if useIt, let lastGame = session.games.last {
                            loadPreviousConfiguration(from: lastGame)
                        } else {
                            // Reset to empty teams
                            let allStudentIds = Set(enrolledStudents.map { $0.id })
                            unassignedPlayerIds = allStudentIds
                            setupDefaultTeams()
                        }
                    }
            }
            if usePreviousConfig {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "球员将分配到与上场比赛相同的队伍" : "Players will be assigned to the same teams as the last game")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private var durationSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        
        return HStack {
            Text(isChinese ? "时长" : "Duration")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            
            Spacer()
            
            Stepper(value: $gameDuration, in: 1...120, step: 5) {
                Text("\(gameDuration)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(minWidth: 36)
            }
            
            Text(isChinese ? "分钟" : "min")
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .cornerRadius(10)
    }
    
    private var teamsSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isChinese ? "队伍" : "Teams")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                if teams.count < maxTeams {
                    Button(action: addTeam) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(programColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                teamRow(team: team, index: index)
                if index < teams.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func teamRow(team: GameTeam, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Color picker
                Menu {
                    ForEach(GameTeam.presetColors, id: \.hex) { preset in
                        Button(action: { teams[index].colorHex = preset.hex; teams[index].name = preset.name }) {
                            HStack { Circle().fill(Color(hex: preset.hex)).frame(width: 14, height: 14); Text(GameTeam.localizedColorName(preset.name)) }
                        }
                    }
                } label: {
                    Circle()
                        .fill(Color(hex: team.colorHex))
                        .frame(width: 20, height: 20)
                        .overlay(Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundColor(.white))
                }
                
                Text(GameTeam.localizedColorName(team.name))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                
                Text("(\(team.playerIds.count))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if teams.count > 2 {
                    Button(action: { removeTeam(at: index) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Players - horizontal scroll
            if team.playerIds.isEmpty {
                Text(LocalizationManager.shared.currentLanguage == .chinese ? "从下方添加球员" : "Add from below")
                    .font(.system(size: 11))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.leading, 30)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(team.playerIds, id: \.self) { playerId in
                            if let student = availableStudents.first(where: { $0.id == playerId }) ?? enrolledStudents.first(where: { $0.id == playerId }) {
                                playerChip(student: student, teamIndex: index, teamColor: team.colorHex)
                            }
                        }
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func playerChip(student: Student, teamIndex: Int, teamColor: String) -> some View {
        Button(action: { teams[teamIndex].playerIds.removeAll { $0 == student.id }; unassignedPlayerIds.insert(student.id) }) {
            HStack(spacing: 4) {
                StudentAvatarView(student: student, size: 22)
                Text(student.name.components(separatedBy: " ").first ?? student.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: teamColor).opacity(0.12))
            .cornerRadius(14)
        }
    }
    
    // MARK: - Player Filter Section (Compact Toggle)
    private var playerFilterSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let presentCount = enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }.count
        let totalCount = enrolledStudents.count
        
        return HStack(spacing: 12) {
            Text(isChinese ? "球员" : "Players")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.gray)
            
            // Compact segmented toggle
            HStack(spacing: 0) {
                Button(action: { showOnlyPresent = true; refreshUnassignedPlayers() }) {
                    Text(isChinese ? "已到 (\(presentCount))" : "Present (\(presentCount))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(showOnlyPresent ? .white : .black.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(showOnlyPresent ? Color.green : Color.clear)
                }
                
                Button(action: { showOnlyPresent = false; refreshUnassignedPlayers() }) {
                    Text(isChinese ? "全部 (\(totalCount))" : "All (\(totalCount))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(!showOnlyPresent ? .white : .black.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(!showOnlyPresent ? programColor : Color.clear)
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            if showOnlyPresent && presentCount == 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(10)
    }
    
    private var unassignedPlayersSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 10) {
            // Header with team color buttons (tap to assign selected players)
            HStack(spacing: 8) {
                Text(isChinese ? "待分配" : "Unassigned")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                Text("(\(unassignedPlayerIds.count))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                
                Spacer()
                
                // Team color buttons - tap to assign selected players
                ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                    Button(action: {
                        guard !selectedUnassignedIds.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            for playerId in selectedUnassignedIds {
                                unassignedPlayerIds.remove(playerId)
                                teams[index].playerIds.append(playerId)
                            }
                            selectedUnassignedIds.removeAll()
                        }
                    }) {
                        Circle()
                            .fill(Color(hex: team.colorHex))
                            .frame(width: 28, height: 28)
                            .opacity(selectedUnassignedIds.isEmpty ? 0.4 : 1.0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            
            // Selection hint
            if !selectedUnassignedIds.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "已选 \(selectedUnassignedIds.count) 人，点击颜色分配队伍" : "\(selectedUnassignedIds.count) selected — tap a color to assign")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: { selectedUnassignedIds.removeAll() }) {
                        Text(isChinese ? "取消" : "Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(programColor)
                    }
                }
                .padding(.horizontal, 12)
            }
            
            // Player grid - tap to select
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                ForEach(Array(unassignedPlayerIds).sorted { id1, id2 in
                    let name1 = availableStudents.first { $0.id == id1 }?.name ?? ""
                    let name2 = availableStudents.first { $0.id == id2 }?.name ?? ""
                    return name1 < name2
                }, id: \.self) { playerId in
                    if let student = availableStudents.first(where: { $0.id == playerId }) {
                        unassignedPlayerButton(student: student)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(Color.white)
        .cornerRadius(12)
    }
    
    private func unassignedPlayerButton(student: Student) -> some View {
        let isSelected = selectedUnassignedIds.contains(student.id)
        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    selectedUnassignedIds.remove(student.id)
                } else {
                    selectedUnassignedIds.insert(student.id)
                }
            }
        }) {
            VStack(spacing: 4) {
                StudentAvatarView(student: student, size: 36)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? programColor : Color.clear, lineWidth: 2)
                    )
                    .overlay(
                        isSelected ? Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(programColor)
                            .background(Circle().fill(Color.white).frame(width: 12, height: 12))
                            .offset(x: 12, y: -12) : nil
                    )
                Text(student.name.components(separatedBy: " ").first ?? student.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)
            }
            .frame(width: 70)
            .padding(.vertical, 6)
            .background(isSelected ? programColor.opacity(0.1) : Color.gray.opacity(0.05))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
    
    private func addTeam() {
        let usedColors = Set(teams.map { $0.colorHex })
        if let nextColor = GameTeam.presetColors.first(where: { !usedColors.contains($0.hex) }) { teams.append(GameTeam(name: nextColor.name, colorHex: nextColor.hex)) }
    }
    private func removeTeam(at index: Int) { unassignedPlayerIds.formUnion(teams[index].playerIds); teams.remove(at: index) }
    
    private func createGame() {
        var newGame: SessionGame
        
        if isBattleRoyal {
            // For Battle Royal: no teams, create player stats for each participant
            newGame = SessionGame(
                sessionId: session.id,
                gameNumber: session.games.count + 1,
                gameType: selectedGameType,
                teams: [],  // No teams
                durationMinutes: gameDuration,
                status: .ready
            )
            // Pre-create player stats entries for all participants
            for playerId in battleRoyalPlayerIds {
                newGame.playerStats.append(
                    SessionPlayerStats(playerId: playerId, gameId: newGame.id, teamId: playerId)  // Use playerId as pseudo-teamId
                )
            }
        } else {
            newGame = SessionGame(
                sessionId: session.id,
                gameNumber: session.games.count + 1,
                gameType: selectedGameType,
                teams: teams,
                durationMinutes: gameDuration,
                status: .ready
            )
        }
        
        session.games.append(newGame)
        onSave(); dismiss()
    }
    
    // MARK: - Battle Royal Players Section
    private var battleRoyalPlayersSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text(isChinese ? "参赛球员" : "PARTICIPANTS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    Text(isChinese ? "每个人为自己得分" : "Every player scores for themselves")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
                Spacer()
                Text("\(battleRoyalPlayerIds.count) \(isChinese ? "人" : "players")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(programColor)
            }
            
            // Info banner
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "大乱斗模式" : "Battle Royal Mode")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isChinese ? "持球者进攻，其他人防守。不记助攻。" : "Ball holder attacks, others defend. No assists tracked.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.blue.opacity(0.08))
            .cornerRadius(10)
            
            // Player grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                ForEach(availableStudents) { student in
                    Button(action: {
                        if battleRoyalPlayerIds.contains(student.id) {
                            battleRoyalPlayerIds.remove(student.id)
                        } else {
                            battleRoyalPlayerIds.insert(student.id)
                        }
                    }) {
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                StudentAvatarView(student: student, size: 48)
                                if battleRoyalPlayerIds.contains(student.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.green)
                                        .background(Circle().fill(.white).frame(width: 14, height: 14))
                                        .offset(x: 4, y: 4)
                                }
                            }
                            Text(student.name.components(separatedBy: " ").first ?? student.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(battleRoyalPlayerIds.contains(student.id) ? .black : .gray)
                                .lineLimit(1)
                        }
                        .padding(8)
                        .background(battleRoyalPlayerIds.contains(student.id) ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(battleRoyalPlayerIds.contains(student.id) ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
            
            // Select all / deselect all buttons
            HStack(spacing: 12) {
                Button(action: { battleRoyalPlayerIds = Set(availableStudents.map { $0.id }) }) {
                    Text(isChinese ? "全选" : "Select All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(programColor)
                }
                Button(action: { battleRoyalPlayerIds.removeAll() }) {
                    Text(isChinese ? "取消全选" : "Deselect All")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }.padding(12).background(Color.white).cornerRadius(12)
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
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
            .background(Color(hex: "#f5f5f7"))
            .navigationTitle(isBattleRoyal ? (isChinese ? "大乱斗 \(game.gameNumber)" : "Battle Royal \(game.gameNumber)") : "Game \(game.gameNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "完成" : "Done") { onSave(); dismiss() } }
                ToolbarItem(placement: .principal) {
                    if !isBattleRoyal && game.teams.count > 2 && game.status != .completed {
                        Button(action: endRound) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(isChinese ? "下一轮" : "Next Round")
                            }.font(.system(size: 12, weight: .semibold)).foregroundColor(.blue)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { 
                    if game.status != .completed { 
                        Button(action: endGame) { Text(isChinese ? "结束" : "End Game").foregroundColor(.red) } 
                    } 
                }
            }
            .onReceive(timer) { _ in if isTimerRunning && game.status == .inProgress { timerSeconds += 1; if timerSeconds >= game.durationMinutes * 60 { endGame() } } }
            .onAppear { if game.status == .inProgress, let startedAt = game.startedAt { timerSeconds = Int(Date().timeIntervalSince(startedAt)) } }
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
                    .foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 14)).foregroundColor(.gray)
            }
            
            // Timer controls
            if game.status != .completed {
                HStack(spacing: 16) {
                    Button(action: toggleTimer) {
                        HStack(spacing: 6) { 
                            Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            Text(isTimerRunning ? (isChinese ? "暂停" : "Pause") : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume"))) 
                        }
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { 
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.gray)
                            .padding(10).background(Color.gray.opacity(0.1)).cornerRadius(20) 
                    }
                }
            }
            
            // Crown icon and title
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                Text(isChinese ? "个人排名" : "Leaderboard")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
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
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }.padding(24).background(Color.white)
    }
    
    // MARK: - Battle Royal Compact Header
    private var battleRoyalCompactHeader: some View {
        VStack(spacing: 8) {
            // Timer and controls in one row
            HStack(spacing: 12) {
                // Timer
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 12)).foregroundColor(.gray)
                
                Spacer()
                
                // Timer controls
                if game.status != .completed {
                    Button(action: toggleTimer) {
                        Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .padding(10).background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { 
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.gray)
                            .padding(8).background(Color.gray.opacity(0.1)).cornerRadius(16) 
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
                                    .foregroundColor(.gray)
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
        }.padding(.horizontal, 16).padding(.vertical, 12).background(Color.white)
    }
    
    // MARK: - Compact Game Header (smaller to show more players)
    private var compactGameHeader: some View {
        VStack(spacing: 8) {
            // Timer and controls in one row
            HStack(spacing: 12) {
                // Timer
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60))
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 12)).foregroundColor(.gray)
                
                Spacer()
                
                // Timer controls
                if game.status != .completed {
                    Button(action: toggleTimer) {
                        Image(systemName: isTimerRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                            .padding(10).background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { 
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(.gray)
                            .padding(8).background(Color.gray.opacity(0.1)).cornerRadius(16) 
                    }
                }
            }
            
            // Team scores in compact row (only active teams on court)
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 24, height: 24)
                            .overlay(Text(String(team.name.prefix(1))).font(.system(size: 10, weight: .bold)).foregroundColor(team.colorHex == "#F5F5F5" ? .black : .white))
                        Text("\(game.score(for: team.id))").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Color(hex: team.colorHex))
                    }.frame(maxWidth: .infinity)
                    if index < teamsOnCourt.count - 1 { Text("vs").font(.system(size: 14, weight: .bold)).foregroundColor(.gray.opacity(0.5)) }
                }
            }
            
            // Waiting teams queue
            if !game.waitingTeams.isEmpty {
                HStack(spacing: 6) {
                    Text(isChinese ? "候场" : "Next").font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
                    ForEach(game.waitingTeams) { team in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                            Text(GameTeam.localizedColorName(team.name)).font(.system(size: 11, weight: .medium)).foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: team.colorHex).opacity(0.1)).cornerRadius(10)
                    }
                    Spacer()
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 12).background(Color.white)
    }
    
    private var gameHeader: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60)).font(.system(size: 48, weight: .bold, design: .monospaced)).foregroundColor(timerSeconds >= game.durationMinutes * 60 ? .red : .black)
                Text("/ \(game.durationMinutes):00").font(.system(size: 14)).foregroundColor(.gray)
            }
            if game.status != .completed {
                HStack(spacing: 16) {
                    Button(action: toggleTimer) {
                        HStack(spacing: 6) { Image(systemName: isTimerRunning ? "pause.fill" : "play.fill"); Text(isTimerRunning ? (isChinese ? "暂停" : "Pause") : (game.status == .ready ? (isChinese ? "开始" : "Start") : (isChinese ? "继续" : "Resume"))) }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 10).background(isTimerRunning ? .orange : .green).cornerRadius(20)
                    }
                    Button(action: resetTimer) { Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)).foregroundColor(.gray).padding(10).background(Color.gray.opacity(0.1)).cornerRadius(20) }
                }
            }
            // Only show active teams on court
            let teamsOnCourt = game.activeTeams.isEmpty ? game.teams : game.activeTeams
            HStack(spacing: 0) {
                ForEach(Array(teamsOnCourt.enumerated()), id: \.element.id) { index, team in
                    VStack(spacing: 8) {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 40, height: 40).overlay(Text(String(team.name.prefix(1))).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                        Text("\(game.score(for: team.id))").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundColor(Color(hex: team.colorHex))
                        Text(GameTeam.localizedColorName(team.name)).font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
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
                            Text(team.name).font(.system(size: 12, weight: .medium)).foregroundColor(.gray)
                            Text("\(team.wins)W").font(.system(size: 10)).foregroundColor(.gray.opacity(0.7))
                        }.padding(.horizontal, 8).padding(.vertical, 4).background(Color.gray.opacity(0.1)).cornerRadius(12)
                    }
                }.padding(.top, 8)
            }
        }.padding(24).background(Color.white)
    }
    
    // Teams currently on court for scoring
    private var activeTeamsForScoring: [GameTeam] {
        game.activeTeams.isEmpty ? game.teams : game.activeTeams
    }
    
    private var teamTabs: some View {
        HStack(spacing: 8) {
            // Only show active teams in tabs for scoring
            ForEach(Array(activeTeamsForScoring.enumerated()), id: \.element.id) { index, team in
                Button(action: { selectedTeamIndex = index }) {
                    HStack(spacing: 6) { Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12); Text(GameTeam.localizedColorName(team.name)).font(.system(size: 13, weight: .semibold)) }
                        .foregroundColor(selectedTeamIndex == index ? .white : .black).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(selectedTeamIndex == index ? Color(hex: team.colorHex) : Color.gray.opacity(0.1)).cornerRadius(20)
                }
            }
        }.padding(16)
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
                    .foregroundColor(.black)
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
            .background(Color.white)
            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
        }
        .background(Color.white)
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
                        .foregroundColor(.black)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(stats?.points ?? 0)").font(.system(size: 11, weight: .bold)).foregroundColor(buttonColor)
                        Text("PTS").font(.system(size: 9)).foregroundColor(.gray)
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
                    // Points row - compact
                    HStack(spacing: 4) {
                        compactStatButton("+1", color: buttonColor) { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+2", color: buttonColor) { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }
                        compactStatButton("+3", color: buttonColor) { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }
                    }
                    // Other stats row - compact
                    HStack(spacing: 4) {
                        compactStatButton(rebLabel, color: .blue) { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(astLabel, color: .green) { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(stlLabel, color: .red) { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }
                        compactStatButton(blkLabel, color: .purple) { game.addStat(.block, for: student.id, teamId: team.id); onSave() }
                    }
                }
            }
        }
        .padding(8)
        .background(Color(hex: "#f8f8f8"))
        .cornerRadius(8)
    }
    
    private func compactStatButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(color.opacity(0.1))
                .cornerRadius(6)
        }
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
                        .fill(rank == 1 ? Color.orange : (rank == 2 ? Color.gray : (rank == 3 ? Color.brown : Color.gray.opacity(0.2))))
                        .frame(width: 24, height: 24)
                    if rank <= 3 {
                        Image(systemName: rank == 1 ? "crown.fill" : "\(rank).circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(rank)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }
                
                StudentAvatarView(student: student, size: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    // Show both English and Chinese names
                    HStack(spacing: 6) {
                        Text(student.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                        if let chineseName = student.chineseName, !chineseName.isEmpty {
                            Text(chineseName).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
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
            
            // Scoring buttons - Points on first row, other stats on second row
            if game.status != .completed {
                VStack(spacing: 6) {
                    // Points row
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: .orange, add: { game.addStat(.points(1), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+2", color: .orange, add: { game.addStat(.points(2), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("+3", color: .orange, add: { game.addStat(.points(3), for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: student.id); onSave() })
                    }
                    // Other stats row (no assists for Battle Royal)
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .blue, add: { game.addStat(.rebound, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("STL", color: .red, add: { game.addStat(.steal, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: student.id); onSave() })
                        undoableStatButton("BLK", color: .purple, add: { game.addStat(.block, for: student.id, teamId: student.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: student.id); onSave() })
                    }
                }
            }
        }.padding(12).background(Color.white).cornerRadius(12)
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
                        Text(student.name).font(.system(size: 13, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                        if let chineseName = student.chineseName, !chineseName.isEmpty {
                            Text(chineseName).font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
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
                    // Points row
                    HStack(spacing: 6) {
                        undoableStatButton("+1", color: buttonColor, add: { game.addStat(.points(1), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(1), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+2", color: buttonColor, add: { game.addStat(.points(2), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(2), for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("+3", color: buttonColor, add: { game.addStat(.points(3), for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.points(3), for: student.id, teamId: team.id); onSave() })
                    }
                    // Other stats row
                    HStack(spacing: 6) {
                        undoableStatButton("REB", color: .blue, add: { game.addStat(.rebound, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.rebound, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("AST", color: .green, add: { game.addStat(.assist, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.assist, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("STL", color: .red, add: { game.addStat(.steal, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.steal, for: student.id, teamId: team.id); onSave() })
                        undoableStatButton("BLK", color: .purple, add: { game.addStat(.block, for: student.id, teamId: team.id); onSave() }, remove: { game.removeStat(.block, for: student.id, teamId: team.id); onSave() })
                    }
                }
            }
        }.padding(12).background(Color.white).cornerRadius(12)
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
        return HStack(spacing: 2) { Text("\(value)").font(.system(size: 13, weight: .bold)).foregroundColor(.black); Text(localizedLabel).font(.system(size: 10)).foregroundColor(.gray) }
    }
    private func statButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(.system(size: 12, weight: .bold)).foregroundColor(color).padding(.horizontal, 12).padding(.vertical, 8).background(color.opacity(0.1)).cornerRadius(8) }
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
            default: return label  // +1, +2, +3 stay the same
            }
        }()
        return Text(localizedLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1))
            .cornerRadius(8)
            .onTapGesture { add() }
            .onLongPressGesture(minimumDuration: 0.5) {
                HapticFeedback.impact(.medium)
                remove()
            }
    }
    private func toggleTimer() {
        isTimerRunning.toggle()
        if isTimerRunning { if game.status == .ready { game.status = .inProgress; game.startedAt = Date() } else { game.status = .inProgress } } else { game.status = .paused }
        onSave()
    }
    private func resetTimer() { timerSeconds = 0; isTimerRunning = false; game.status = .ready; game.startedAt = nil; onSave() }
    
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
            case .mvp: return .yellow
            case .sharpshooter: return .orange
            case .playmaker: return .green
            case .wall: return .purple
            case .pickpocket: return .red
            case .boardBoss: return .blue
            case .allAround: return .pink
            case .mostImproved: return .cyan
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
            .background(Color(hex: "#f5f5f7"))
            .navigationTitle(isChinese ? "比赛回顾" : "Game Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
    }
    
    // MARK: - Game Result Header
    private var gameResultHeader: some View {
        VStack(spacing: 12) {
            Text(isChinese ? "比赛结束!" : "Game Over!")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.primary)
            
            if game.gameType.isIndividual {
                // Battle Royal - show top 3
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
                                            .font(.system(size: 14))
                                            .foregroundColor(.yellow)
                                            .offset(y: -10)
                                    }
                                }
                                Text("\(entry.points)")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(index == 0 ? .orange : .gray)
                                Text(student.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // Team game - show scores
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
                                        .font(.system(size: 14))
                                        .foregroundColor(.yellow)
                                        .offset(y: -12)
                                }
                            }
                            Text("\(game.score(for: team.id))")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: team.colorHex))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(GameTeam.localizedColorName(team.name))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
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
        .background(Color.white)
        .cornerRadius(16)
    }
    
    // MARK: - MVP Section
    private func mvpSection(student: Student, stats: SessionPlayerStats) -> some View {
        VStack(spacing: 12) {
            // Trophy icon
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            
            Text("MVP")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.orange)
            
            // Player info
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(student.displayName)
                        .font(.system(size: 18, weight: .bold))
                    if let chinese = student.chineseName, !chinese.isEmpty, student.displayName != chinese {
                        Text(chinese)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Stats breakdown
            ViewThatFits {
                HStack(spacing: 16) {
                    mvpStatBubble(isChinese ? "分" : "PTS", value: stats.points, color: .orange)
                    mvpStatBubble(isChinese ? "板" : "REB", value: stats.rebounds, color: .blue)
                    mvpStatBubble(isChinese ? "助" : "AST", value: stats.assists, color: .green)
                    mvpStatBubble(isChinese ? "断" : "STL", value: stats.steals, color: .red)
                    mvpStatBubble(isChinese ? "帽" : "BLK", value: stats.blocks, color: .purple)
                }
                HStack(spacing: 10) {
                    mvpStatBubble(isChinese ? "分" : "PTS", value: stats.points, color: .orange)
                        .frame(width: 38)
                    mvpStatBubble(isChinese ? "板" : "REB", value: stats.rebounds, color: .blue)
                        .frame(width: 38)
                    mvpStatBubble(isChinese ? "助" : "AST", value: stats.assists, color: .green)
                        .frame(width: 38)
                    mvpStatBubble(isChinese ? "断" : "STL", value: stats.steals, color: .red)
                        .frame(width: 38)
                    mvpStatBubble(isChinese ? "帽" : "BLK", value: stats.blocks, color: .purple)
                        .frame(width: 38)
                }
            }
            
            // Contribution score explanation
            Text(isChinese ? "贡献值: \(Int(contributionScore(for: stats)))" : "Contribution: \(Int(contributionScore(for: stats)))")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            // Previous game comparison
            if let prevStats = previousGameStats(for: student.id) {
                comparisonRow(current: stats, previous: prevStats)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.yellow.opacity(0.1), Color.orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
    
    private func mvpStatBubble(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 44)
    }
    
    // MARK: - Comparison Row
    private func comparisonRow(current: SessionPlayerStats, previous: SessionPlayerStats) -> some View {
        VStack(spacing: 8) {
            Text(isChinese ? "与上场比较" : "vs Last Game")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.gray)
            
            HStack(spacing: 12) {
                comparisonItem(isChinese ? "分" : "PTS", current: current.points, previous: previous.points)
                comparisonItem(isChinese ? "板" : "REB", current: current.rebounds, previous: previous.rebounds)
                comparisonItem(isChinese ? "助" : "AST", current: current.assists, previous: previous.assists)
                comparisonItem(isChinese ? "断" : "STL", current: current.steals, previous: previous.steals)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.5))
        .cornerRadius(10)
    }
    
    private func comparisonItem(_ label: String, current: Int, previous: Int) -> some View {
        let diff = current - previous
        let arrow = diff > 0 ? "↑" : (diff < 0 ? "↓" : "→")
        let color: Color = diff > 0 ? .green : (diff < 0 ? .red : .gray)
        
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(arrow)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                Text("\(abs(diff))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.gray)
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
        .background(Color.white)
        .cornerRadius(16)
    }
    
    private func awardCard(award: GameAward, student: Student, value: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(award.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: award.icon)
                    .font(.system(size: 18))
                    .foregroundColor(award.color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(award.name(chinese: isChinese))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(award.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(student.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer()
            
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(award.color)
                .frame(minWidth: 28, alignment: .trailing)
        }
        .padding(10)
        .background(award.color.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - All Players Section
    private var allPlayersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isChinese ? "全员数据" : "All Players")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            
            ForEach(game.playerStats.sorted(by: { contributionScore(for: $0) > contributionScore(for: $1) }), id: \.playerId) { stats in
                if let student = students.first(where: { $0.id == stats.playerId }) {
                    playerStatRow(student: student, stats: stats)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if isMVP {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    // Stats bar
                    ViewThatFits {
                        HStack(spacing: 8) {
                            miniStat("PTS", value: stats.points, prev: prevStats?.points, color: .orange)
                            miniStat("REB", value: stats.rebounds, prev: prevStats?.rebounds, color: .blue)
                            miniStat("AST", value: stats.assists, prev: prevStats?.assists, color: .green)
                            miniStat("STL", value: stats.steals, prev: prevStats?.steals, color: .red)
                            miniStat("BLK", value: stats.blocks, prev: prevStats?.blocks, color: .purple)
                        }
                        HStack(spacing: 6) {
                            miniStat("PTS", value: stats.points, prev: prevStats?.points, color: .orange)
                            miniStat("REB", value: stats.rebounds, prev: prevStats?.rebounds, color: .blue)
                            miniStat("AST", value: stats.assists, prev: prevStats?.assists, color: .green)
                            miniStat("STL", value: stats.steals, prev: prevStats?.steals, color: .red)
                        }
                    }
                }
                
                Spacer()
                
                // Contribution score
                VStack(spacing: 2) {
                    Text("\(Int(contributionScore(for: stats)))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(isChinese ? "贡献" : "CTR")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }
            
            // Improvement tip (if has previous game)
            if let prev = prevStats {
                improvementTip(current: stats, previous: prev)
            }
        }
        .padding(10)
        .background(isMVP ? Color.orange.opacity(0.05) : Color.gray.opacity(0.03))
        .cornerRadius(10)
    }
    
    private func miniStat(_ label: String, value: Int, prev: Int?, color: Color) -> some View {
        let diff = prev.map { value - $0 }
        let arrow: String? = diff.map { $0 > 0 ? "↑" : ($0 < 0 ? "↓" : nil) } ?? nil
        
        return HStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            if let arrow = arrow {
                Text(arrow)
                    .font(.system(size: 8))
                    .foregroundColor((diff ?? 0) > 0 ? .green : .red)
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
                .foregroundColor(.gray)
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
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.blue)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
    }
}

// MARK: - Live Session View
/// A real-time session execution view that displays drills chronologically with timers
struct LiveSessionView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @Binding var session: SessionEvent
    let onEnd: () -> Void
    
    @State private var sessionElapsedSeconds: Int = 0
    @State private var currentDrillIndex: Int = 0
    @State private var drillElapsedSeconds: Int = 0
    @State private var isPaused: Bool = false
    @State private var sessionStartTime: Date = Date()
    @State private var showingEndConfirmation = false
    @State private var showingAttendance = false
    @State private var showingNotes = false
    @State private var sessionNotes: String = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var allDrills: [LiveDrillItem] {
        var items: [LiveDrillItem] = []
        let curriculum = session.curriculum
        
        let warmupDrillDuration = curriculum.warmupDrillIds.isEmpty ? 0 : (curriculum.warmupMinutes * 60) / max(curriculum.warmupDrillIds.count, 1)
        for drillId in curriculum.warmupDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                items.append(LiveDrillItem(drill: drill, section: .warmup, durationSeconds: warmupDrillDuration))
            }
        }
        
        let skillDrillDuration = curriculum.skillDrillIds.isEmpty ? 0 : (curriculum.skillsMinutes * 60) / max(curriculum.skillDrillIds.count, 1)
        for drillId in curriculum.skillDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                items.append(LiveDrillItem(drill: drill, section: .main, durationSeconds: skillDrillDuration))
            }
        }
        
        let gameDrillDuration = curriculum.gameDrillIds.isEmpty ? 0 : (curriculum.gameMinutes * 60) / max(curriculum.gameDrillIds.count, 1)
        for drillId in curriculum.gameDrillIds {
            if let drill = dataManager.drills.first(where: { $0.id == drillId }) {
                items.append(LiveDrillItem(drill: drill, section: .cooldown, durationSeconds: gameDrillDuration))
            }
        }
        return items
    }
    
    private var currentDrill: LiveDrillItem? {
        guard currentDrillIndex < allDrills.count else { return nil }
        return allDrills[currentDrillIndex]
    }
    
    private var totalSessionSeconds: Int { session.curriculum.totalMinutes * 60 }
    private var sessionProgress: Double {
        guard totalSessionSeconds > 0 else { return 0 }
        return min(Double(sessionElapsedSeconds) / Double(totalSessionSeconds), 1.0)
    }
    private var currentDrillProgress: Double {
        guard let drill = currentDrill, drill.durationSeconds > 0 else { return 0 }
        return min(Double(drillElapsedSeconds) / Double(drill.durationSeconds), 1.0)
    }
    private var currentDrillRemainingSeconds: Int {
        guard let drill = currentDrill else { return 0 }
        return max(drill.durationSeconds - drillElapsedSeconds, 0)
    }
    
    private var programColor: Color {
        if let programId = session.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            return Color(hex: program.colorHex)
        }
        return AppTheme.accentColor
    }
    
    private var enrolledStudents: [Student] {
        if let programId = session.programId,
           let program = dataManager.programs.first(where: { $0.id == programId }) {
            return dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
        }
        return dataManager.students.filter { session.attendeeIds.contains($0.id) }
    }
    
    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                liveHeader
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if let drill = currentDrill {
                            currentDrillCard(drill)
                        } else {
                            sessionCompleteCard
                        }
                        drillTimeline
                        quickActions
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }
                
                bottomControls
            }
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .onReceive(timer) { _ in
            guard !isPaused else { return }
            tickTimer()
        }
        .onAppear {
            sessionStartTime = Date()
            sessionNotes = session.coachNotes ?? ""
        }
        .sheet(isPresented: $showingAttendance) {
            LiveAttendanceSheet(session: $session, students: enrolledStudents, programColor: programColor) { saveSession() }
        }
        .sheet(isPresented: $showingNotes) {
            LiveNotesSheet(notes: $sessionNotes, programColor: programColor) {
                session.coachNotes = sessionNotes.isEmpty ? nil : sessionNotes
                saveSession()
            }
        }
        .alert("End Session?", isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Session") { endSession() }
        } message: {
            Text("This will complete the session. Make sure to take attendance before ending.")
        }
    }
    
    private var liveHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: { showingEndConfirmation = true }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppTheme.surfaceColor)
                        .cornerRadius(10)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(isPaused ? "PAUSED" : "LIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isPaused ? .orange : .red)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isPaused ? Color.orange.opacity(0.15) : Color.red.opacity(0.15))
                .cornerRadius(12)
                Spacer()
                Button(action: { isPaused.toggle() }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(programColor)
                        .frame(width: 36, height: 36)
                        .background(programColor.opacity(0.15))
                        .cornerRadius(10)
                }
            }
            VStack(spacing: 4) {
                Text(session.title).font(.system(size: 18, weight: .bold)).foregroundColor(AppTheme.textPrimary)
                Text(formatTime(sessionElapsedSeconds))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(programColor)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(AppTheme.surfaceColor).frame(height: 6)
                        RoundedRectangle(cornerRadius: 4).fill(programColor).frame(width: geo.size.width * sessionProgress, height: 6)
                    }
                }.frame(height: 6)
                Text("\(formatTime(max(totalSessionSeconds - sessionElapsedSeconds, 0))) remaining")
                    .font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
            }
        }
        .padding(16).background(AppTheme.cardBackground)
    }
    
    private func currentDrillCard(_ item: LiveDrillItem) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(item.section.displayName.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(item.sectionColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(item.sectionColor.opacity(0.15)).cornerRadius(8)
                Spacer()
                Text("Drill \(currentDrillIndex + 1) of \(allDrills.count)")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(AppTheme.textTertiary)
            }
            Text(item.drill.name).font(.system(size: 24, weight: .bold)).foregroundColor(AppTheme.textPrimary).multilineTextAlignment(.center)
            ZStack {
                Circle().stroke(AppTheme.surfaceColor, lineWidth: 12).frame(width: 160, height: 160)
                Circle().trim(from: 0, to: currentDrillProgress)
                    .stroke(item.sectionColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 160, height: 160).rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(formatTime(currentDrillRemainingSeconds))
                        .font(.system(size: 36, weight: .bold, design: .monospaced)).foregroundColor(AppTheme.textPrimary)
                    Text("remaining").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary)
                }
            }
            if !item.drill.description.isEmpty {
                Text(item.drill.description).font(.system(size: 13)).foregroundColor(AppTheme.textSecondary).multilineTextAlignment(.center).lineLimit(3)
            }
            HStack(spacing: 12) {
                Button(action: previousDrill) {
                    HStack(spacing: 4) {
                        Image(systemName: "backward.fill").font(.system(size: 12))
                        Text("Previous").font(.system(size: 13, weight: .medium))
                    }.foregroundColor(AppTheme.textSecondary).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(AppTheme.surfaceColor).cornerRadius(20)
                }.disabled(currentDrillIndex == 0).opacity(currentDrillIndex == 0 ? 0.5 : 1)
                Button(action: nextDrill) {
                    HStack(spacing: 4) {
                        Text("Next").font(.system(size: 13, weight: .medium))
                        Image(systemName: "forward.fill").font(.system(size: 12))
                    }.foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(item.sectionColor).cornerRadius(20)
                }
            }
        }
        .padding(20).background(AppTheme.cardBackground).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(item.sectionColor.opacity(0.3), lineWidth: 2))
    }
    
    private var sessionCompleteCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundColor(.green)
            }
            Text("All Drills Complete!").font(.system(size: 20, weight: .bold)).foregroundColor(AppTheme.textPrimary)
            Text("Take attendance and add notes before ending the session.")
                .font(.system(size: 13)).foregroundColor(AppTheme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity).background(AppTheme.cardBackground).cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.green.opacity(0.3), lineWidth: 2))
    }
    
    private var drillTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DRILL TIMELINE").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(AppTheme.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(allDrills.enumerated()), id: \.element.id) { index, item in
                    LiveTimelineDrillRow(item: item, index: index, currentIndex: currentDrillIndex, isLast: index == allDrills.count - 1) {
                        currentDrillIndex = index
                        drillElapsedSeconds = 0
                        HapticFeedback.impact(.medium)
                    }
                }
            }
        }.padding(16).background(AppTheme.cardBackground).cornerRadius(16)
    }
    
    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: { showingAttendance = true }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.blue.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: "person.2.fill").font(.system(size: 18)).foregroundColor(.blue)
                    }
                    Text("Attendance").font(.system(size: 11, weight: .medium)).foregroundColor(AppTheme.textSecondary)
                    Text("\(session.actualAttendeeIds.count)/\(enrolledStudents.count)")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(session.actualAttendeeIds.count > 0 ? Color.green : Color.gray).cornerRadius(8)
                }.frame(maxWidth: .infinity).padding(.vertical, 16).background(AppTheme.cardBackground).cornerRadius(14)
            }.buttonStyle(.plain)
            Button(action: { showingNotes = true }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.orange.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: "note.text").font(.system(size: 18)).foregroundColor(.orange)
                    }
                    Text("Notes").font(.system(size: 11, weight: .medium)).foregroundColor(AppTheme.textSecondary)
                    Text(sessionNotes.isEmpty ? "Add" : "Edit")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(sessionNotes.isEmpty ? Color.gray : Color.orange).cornerRadius(8)
                }.frame(maxWidth: .infinity).padding(.vertical, 16).background(AppTheme.cardBackground).cornerRadius(14)
            }.buttonStyle(.plain)
        }
    }
    
    private var bottomControls: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 16) {
                Button(action: { showingEndConfirmation = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill").font(.system(size: 14))
                        Text("End Session").font(.system(size: 15, weight: .semibold))
                    }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.red).cornerRadius(14)
                }
            }.padding(16).background(AppTheme.cardBackground)
        }
    }
    
    private func tickTimer() {
        sessionElapsedSeconds += 1
        drillElapsedSeconds += 1
        if let drill = currentDrill, drillElapsedSeconds >= drill.durationSeconds {
            if currentDrillIndex < allDrills.count - 1 { nextDrill() }
        }
    }
    
    private func nextDrill() {
        guard currentDrillIndex < allDrills.count - 1 else { return }
        if let drill = currentDrill, !session.drillsCompleted.contains(drill.drill.id) {
            session.drillsCompleted.append(drill.drill.id)
        }
        currentDrillIndex += 1
        drillElapsedSeconds = 0
        HapticFeedback.impact(.medium)
    }
    
    private func previousDrill() {
        guard currentDrillIndex > 0 else { return }
        currentDrillIndex -= 1
        drillElapsedSeconds = 0
        HapticFeedback.impact(.light)
    }
    
    private func endSession() {
        for item in allDrills {
            if !session.drillsCompleted.contains(item.drill.id) {
                session.drillsCompleted.append(item.drill.id)
            }
        }
        session.status = .completed
        session.coachNotes = sessionNotes.isEmpty ? nil : sessionNotes
        saveSession()
        // Session consumption is now derived from SessionEvent records
        // No need to call updateAttendedSessions - it's calculated automatically via sessionsConsumed(for:)
        onEnd()
        dismiss()
    }
    
    private func saveSession() {
        session.updatedAt = Date()
        dataManager.updateSessionEvent(session)
    }
    
    private func formatTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Live Drill Item
struct LiveDrillItem: Identifiable {
    let id = UUID()
    let drill: DrillItem
    let section: CurriculumSection
    let durationSeconds: Int
    
    var sectionColor: Color {
        switch section {
        case .warmup: return .orange
        case .main: return .blue
        case .cooldown: return .green
        }
    }
}

// MARK: - Live Timeline Drill Row
struct LiveTimelineDrillRow: View {
    let item: LiveDrillItem
    let index: Int
    let currentIndex: Int
    let isLast: Bool
    let onTap: () -> Void
    
    private var isCompleted: Bool { index < currentIndex }
    private var isCurrent: Bool { index == currentIndex }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Rectangle().fill(index == 0 ? Color.clear : (isCompleted ? item.sectionColor : AppTheme.surfaceColor)).frame(width: 2, height: 12)
                    ZStack {
                        Circle().fill(isCurrent ? item.sectionColor : (isCompleted ? item.sectionColor : AppTheme.surfaceColor)).frame(width: 12, height: 12)
                        if isCurrent { Circle().stroke(item.sectionColor.opacity(0.3), lineWidth: 4).frame(width: 20, height: 20) }
                        if isCompleted { Image(systemName: "checkmark").font(.system(size: 6, weight: .bold)).foregroundColor(.white) }
                    }
                    Rectangle().fill(isLast ? Color.clear : (isCompleted ? item.sectionColor : AppTheme.surfaceColor)).frame(width: 2, height: 12)
                }.frame(width: 24)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.drill.name).font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            .foregroundColor(isCurrent ? AppTheme.textPrimary : (isCompleted ? AppTheme.textTertiary : AppTheme.textSecondary))
                            .strikethrough(isCompleted)
                        Text("\(item.durationSeconds / 60) min • \(item.section.displayName)")
                            .font(.system(size: 10)).foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                    if isCurrent {
                        Text("NOW").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(item.sectionColor).cornerRadius(6)
                    }
                }.padding(.vertical, 8).padding(.horizontal, 12)
                .background(isCurrent ? item.sectionColor.opacity(0.1) : Color.clear).cornerRadius(10)
            }
        }.buttonStyle(.plain)
    }
}

// MARK: - Live Attendance Sheet
struct LiveAttendanceSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: SessionEvent
    let students: [Student]
    let programColor: Color
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("ATTENDANCE").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        Text("\(session.actualAttendeeIds.count)/\(students.count) present").font(.system(size: 12, weight: .medium)).foregroundColor(programColor)
                    }
                    HStack(spacing: 12) {
                        Button(action: { session.actualAttendeeIds = students.map { $0.id }; HapticFeedback.impact(.medium) }) {
                            Text("Mark All Present").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 10).background(Color.green).cornerRadius(10)
                        }
                        Button(action: { session.actualAttendeeIds = []; HapticFeedback.impact(.light) }) {
                            Text("Clear All").font(.system(size: 12, weight: .semibold)).foregroundColor(AppTheme.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 10).background(AppTheme.surfaceColor).cornerRadius(10)
                        }
                    }
                    ForEach(students) { student in
                        LiveAttendanceRow(student: student, isPresent: session.actualAttendeeIds.contains(student.id)) {
                            if session.actualAttendeeIds.contains(student.id) {
                                session.actualAttendeeIds.removeAll { $0 == student.id }
                            } else {
                                session.actualAttendeeIds.append(student.id)
                            }
                            HapticFeedback.impact(.light)
                        }
                    }
                }.padding(16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Take Attendance")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(); dismiss() }.foregroundColor(programColor)
                }
            }
        }
    }
}

// MARK: - Live Attendance Row
struct LiveAttendanceRow: View {
    let student: Student
    let isPresent: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                StudentAvatarView(student: student, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.name).font(.system(size: 14, weight: .medium)).foregroundColor(AppTheme.textPrimary)
                    if let age = student.age { Text("\(age) years old").font(.system(size: 11)).foregroundColor(AppTheme.textTertiary) }
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(isPresent ? Color.green : AppTheme.surfaceColor).frame(width: 50, height: 30)
                    Circle().fill(Color.white).frame(width: 24, height: 24).offset(x: isPresent ? 10 : -10).animation(.spring(response: 0.3), value: isPresent)
                }
            }
            .padding(12).background(isPresent ? Color.green.opacity(0.1) : AppTheme.cardBackground).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isPresent ? Color.green.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1))
        }.buttonStyle(.plain)
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
                Text("SESSION NOTES").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(AppTheme.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: $notes).font(.system(size: 15)).foregroundColor(AppTheme.textPrimary).scrollContentBackground(.hidden)
                    .padding(12).background(AppTheme.surfaceColor).cornerRadius(12).frame(minHeight: 200)
                Text("Add observations, player performance notes, or areas to improve.").font(.system(size: 12)).foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
            .padding(16).background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Coach Notes").navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundColor(AppTheme.textSecondary) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(); dismiss() }.foregroundColor(programColor) }
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
            .background(Color(hex: "#f5f5f7"))
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
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundColor(.purple)
                Text(isChinese ? "智能推荐" : "Smart Suggestions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.purple)
                Spacer()
                Button(action: { showOnlySuggested.toggle() }) {
                    Text(showOnlySuggested ? (isChinese ? "显示全部" : "Show All") : (isChinese ? "仅推荐" : "Suggested Only"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.purple)
                }
            }
            
            // Context info
            VStack(alignment: .leading, spacing: 4) {
                if let phase = phase {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10))
                        Text(isChinese ? "阶段重点: \(phase.focus.map { $0.displayName }.joined(separator: ", "))" : "Phase focus: \(phase.focus.map { $0.displayName }.joined(separator: ", "))")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.gray)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 10))
                    let level = calculateStudentAverageLevel()
                    let levelText = level == 1 ? (isChinese ? "初级" : "Beginner") : (level == 2 ? (isChinese ? "中级" : "Intermediate") : (isChinese ? "高级" : "Advanced"))
                    Text(isChinese ? "学员水平: \(levelText)" : "Student level: \(levelText)")
                        .font(.system(size: 11))
                }
                .foregroundColor(.gray)
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.08))
    }
    
    private var searchAndFilters: some View {
        VStack(spacing: 10) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField(isChinese ? "搜索训练..." : "Search drills...", text: $searchText)
                    .font(.system(size: 14))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(10)
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SmartDrillFilterChip(title: isChinese ? "全部" : "All", isSelected: selectedCategory == nil, color: sectionColor) {
                        selectedCategory = nil
                    }
                    ForEach(DrillCategory.allCases, id: \.self) { category in
                        SmartDrillFilterChip(title: category.displayName, isSelected: selectedCategory == category, color: sectionColor) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }
            
            // Difficulty filter
            HStack(spacing: 8) {
                Text(isChinese ? "难度:" : "Level:")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                ForEach(DifficultyLevel.allCases, id: \.self) { level in
                    Button(action: { selectedDifficulty = selectedDifficulty == level ? nil : level }) {
                        HStack(spacing: 4) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(i < level.level ? (selectedDifficulty == level ? Color.white : sectionColor) : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedDifficulty == level ? sectionColor : Color.white)
                        .cornerRadius(8)
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white)
    }
    
    private func drillSelectionRow(drill: DrillItem) -> some View {
        let isAlreadyAdded = isDrillInSection(drill.id)
        let isSuggested = suggestedDrills.prefix(10).contains(where: { $0.id == drill.id })
        
        return Button(action: {
            if !isAlreadyAdded {
                addDrillToSection(drill.id)
                dismiss()
            }
        }) {
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    Circle()
                        .fill(Color.drillCategoryColor(drill.category).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: drill.category.icon)
                        .font(.system(size: 18))
                        .foregroundColor(Color.drillCategoryColor(drill.category))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(drill.localizedName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isAlreadyAdded ? .gray : .black)
                            .lineLimit(1)
                        
                        if isSuggested && showOnlySuggested {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10))
                                .foregroundColor(.purple)
                        }
                        
                        if drill.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        // Duration
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text("\(drill.durationMinutes)min")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.gray)
                        
                        // Difficulty
                        HStack(spacing: 2) {
                            ForEach(0..<3) { i in
                                Circle()
                                    .fill(i < drill.difficulty.level ? sectionColor : Color.gray.opacity(0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        
                        // Players
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                            Text(drill.maxPlayers != nil ? "\(drill.minPlayers)-\(drill.maxPlayers!)" : "\(drill.minPlayers)+")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if isAlreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(sectionColor)
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .opacity(isAlreadyAdded ? 0.6 : 1)
        }
        .disabled(isAlreadyAdded)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            Text(isChinese ? "没有找到训练" : "No drills found")
                .font(.system(size: 14))
                .foregroundColor(.gray)
            if showOnlySuggested {
                Button(action: { showOnlySuggested = false }) {
                    Text(isChinese ? "查看所有训练" : "View all drills")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(sectionColor)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
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
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color.white)
                .cornerRadius(16)
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
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    TextField(isChinese ? "搜索学员..." : "Search students...", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.cardBackground)
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Quick actions
                HStack(spacing: 12) {
                    Button(action: {
                        session.attendeeIds = allStudents.map { $0.id }
                    }) {
                        Text(isChinese ? "全选" : "Select All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentColor.opacity(0.15))
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        session.attendeeIds = []
                    }) {
                        Text(isChinese ? "清除" : "Clear")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.surfaceColor)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Text("\(session.attendeeIds.count) \(isChinese ? "已选" : "selected")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Student list
                List {
                    ForEach(filteredStudents) { student in
                        let isSelected = session.attendeeIds.contains(student.id)
                        
                        Button(action: {
                            if isSelected {
                                session.attendeeIds.removeAll { $0 == student.id }
                            } else {
                                session.attendeeIds.append(student.id)
                            }
                        }) {
                            HStack(spacing: 12) {
                                StudentAvatarView(student: student, size: 40)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(student.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                    if let chinese = student.chineseName {
                                        Text(chinese)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(isChinese ? "管理学员" : "Manage Students")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.textSecondary)
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
