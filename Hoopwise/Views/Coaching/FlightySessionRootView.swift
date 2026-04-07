import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Cross-platform image type alias
#if os(iOS)
typealias PlatformImage = UIImage
#elseif os(macOS)
typealias PlatformImage = NSImage
#endif

// MARK: - Flighty-Inspired Session Root View
/// A redesigned coaching hub with Flighty's "boringly obvious" aesthetic
struct FlightySessionRootView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedSegment = 1
    @State private var currentTime = Date()
    @State private var showingAddProgram = false
    @State private var selectedCoachId: UUID? = nil  // For admin to filter programs by coach
    @Namespace private var tabNamespace  // For matchedGeometryEffect on tab indicator
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact header with title, count, and picker
                compactHeader

                // Content - Programs OR Calendar, same as iPhone (no dual-pane)
                if selectedSegment == 0 {
                    FlightyProgramsListView(selectedCoachId: $selectedCoachId)
                } else {
                    FlightySessionsCalendarView()
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }
    
    // MARK: - Enhanced Header with Prominent Picker (Liquid Glass Style)
    private var compactHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 0) {
            // Main segment picker - full width, prominent
            HStack(spacing: 16) {
                // Programs tab
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedSegment = 0 }
                    HapticFeedback.impact(.light)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                        Text(isChinese ? "训练计划" : "Programs")
                            .font(.system(size: 15, weight: .regular))
                        
                        // Count badge - pure glass
                        Text("\(dataManager.programs.filter { $0.status != .archived }.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(selectedSegment == 0 ? .blue : Color.gray)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .glassEffect()
                            }
                    }
                    .foregroundColor(selectedSegment == 0 ? .blue : Color.gray)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        if selectedSegment == 0 {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .glassEffect()
                                .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Calendar tab
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedSegment = 1 }
                    HapticFeedback.impact(.light)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                        Text(isChinese ? "日历" : "Calendar")
                            .font(.system(size: 15, weight: .regular))
                        
                        // Today's sessions count - pure glass
                        if todaySessionsCount > 0 {
                            Text("\(todaySessionsCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(selectedSegment == 1 ? .blue : Color.gray)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .glassEffect()
                                }
                        }
                    }
                    .foregroundColor(selectedSegment == 1 ? .blue : Color.gray)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        if selectedSegment == 1 {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .glassEffect()
                                .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground)
            
            // Divider
            Rectangle()
                .fill(AppTheme.surfaceColor)
                .frame(height: 1)
            
            // Action bar (only for Programs)
            if selectedSegment == 0 {
                HStack(spacing: 8) {
                    // Admin coach picker (left side)
                    if dataManager.isAdmin {
                        adminCoachPicker
                    }
                    
                    Spacer()
                    
                    // New Program button (right side)
                    if authManager.canCreatePrograms {
                        Button(action: { showingAddProgram = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14))
                                Text(isChinese ? "新建计划" : "New Program")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(AppTheme.accentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentColor.opacity(0.12))
                            .cornerRadius(20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.cardBackground)
            }
        }
        .sheet(isPresented: $showingAddProgram) {
            StreamlinedAddProgramView()
        }
    }
    
    // Legacy segment button kept for potential reuse
    private func compactSegmentButton(title: String, icon: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSegment = index
            }
            HapticFeedback.impact(.light)
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(selectedSegment == index ? Color(hex: "#0D0D0D") : AppTheme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selectedSegment == index ? AppTheme.accentColor : Color.clear)
            )
        }
    }
    
    private var todaySessionsCount: Int {
        dataManager.sessionEvents.filter { Calendar.current.isDateInToday($0.date) }.count
    }
    
    // MARK: - Admin Coach Picker
    private var adminCoachPicker: some View {
        Menu {
            Button(action: { selectedCoachId = nil }) {
                Label("All Coaches", systemImage: "person.3.fill")
            }
            
            Divider()
            
            ForEach(dataManager.staffCoaches.filter { $0.isActive }, id: \.id) { coach in
                Button(action: { selectedCoachId = coach.id }) {
                    HStack {
                        Label(coach.name, systemImage: "person.fill")
                        if selectedCoachId == coach.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.purple)
                
                Text(selectedCoachName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surfaceColor)
            .cornerRadius(8)
        }
    }
    
    private var selectedCoachName: String {
        if let coachId = selectedCoachId,
           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
            return coach.name
        }
        return "All Coaches"
    }
}

// MARK: - Flighty Programs List View (Minimalist Sidebar Design)
struct FlightyProgramsListView: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selectedCoachId: UUID?
    @State private var showingArchivedPrograms = false
    @State private var selectedDay: Weekday? = nil
    @State private var userTappedDay: Weekday? = nil
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    
    // Filter out archived programs for main display
    private var activePrograms: [Program] {
        let allPrograms = dataManager.programs.filter { $0.status != .archived }
        
        if dataManager.isAdmin, let coachId = selectedCoachId {
            return allPrograms.filter { program in
                program.coachId == coachId || program.createdByCoachId == coachId
            }
        }
        return dataManager.accessiblePrograms.filter { $0.status != .archived }
    }
    
    private var archivedProgramsCount: Int {
        dataManager.programs.filter { $0.status == .archived }.count
    }
    
    // Group programs by their primary recurring day
    private var programsByDay: [(day: Weekday, programs: [Program])] {
        let grouped = Dictionary(grouping: activePrograms) { program -> Weekday in
            program.recurringDays.first ?? .saturday
        }
        return Weekday.allCases.compactMap { day in
            if let programs = grouped[day], !programs.isEmpty {
                return (day: day, programs: programs.sorted(by: { $0.name < $1.name }))
            }
            return nil
        }
    }
    
    // Days that have programs
    private var daysWithPrograms: [Weekday] {
        programsByDay.map { $0.day }
    }
    
    // Check if we're filtering by a coach who has no programs
    private var isFilteringByCoachWithNoPrograms: Bool {
        guard dataManager.isAdmin, let coachId = selectedCoachId else { return false }
        let coachPrograms = dataManager.programs.filter { $0.status != .archived }.filter { program in
            program.coachId == coachId || program.createdByCoachId == coachId
        }
        return coachPrograms.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isFilteringByCoachWithNoPrograms {
                coachNoProgramsState
                Spacer()
            } else if activePrograms.isEmpty && archivedProgramsCount == 0 {
                emptyState
                Spacer()
            } else if activePrograms.isEmpty && archivedProgramsCount > 0 {
                allArchivedState
                Spacer()
            } else {
                // Two-column layout: Day sidebar | Programs list
                programsMainContent
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingArchivedPrograms) {
            ArchivedProgramsView()
        }
        .onAppear {
            if selectedDay == nil, let firstDay = daysWithPrograms.first {
                selectedDay = firstDay
            }
        }
    }
    
    // MARK: - Main Two-Column Content
    private var programsMainContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: Day sidebar
            daySidebar
            
            // Subtle vertical divider
            Rectangle()
                .fill(AppTheme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .frame(width: 1)
            
            // Right: Programs list
            programsScrollList
        }
    }
    
    // MARK: - Day Sidebar (Left Column)
    private var daySidebar: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Archive button at top
                    if archivedProgramsCount > 0 {
                        Button(action: { showingArchivedPrograms = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "archivebox.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text("\(archivedProgramsCount)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .background(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                    }
                    
                    ForEach(programsByDay, id: \.day) { dayGroup in
                        Button(action: {
                            userTappedDay = dayGroup.day
                            selectedDay = dayGroup.day
                            HapticFeedback.impact(.light)
                        }) {
                            Text(dayGroup.day.shortName)
                                .font(.system(size: 13, weight: selectedDay == dayGroup.day ? .semibold : .regular))
                                .foregroundColor(selectedDay == dayGroup.day ? AppTheme.accentColor : AppTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(
                                    selectedDay == dayGroup.day
                                        ? AppTheme.accentColor.opacity(0.1)
                                        : Color.clear
                                )
                        }
                        .buttonStyle(.plain)
                        .id("sidebar_\(dayGroup.day.rawValue)")
                        
                        if dayGroup.day != programsByDay.last?.day {
                            Divider()
                                .background(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        }
                    }
                }
            }
            .frame(width: 56)
            .onChange(of: selectedDay) { _, newDay in
                if let day = newDay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("sidebar_\(day.rawValue)", anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - Programs Scroll List (Right Column)
    private var programsScrollList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(programsByDay, id: \.day) { dayGroup in
                        // Day section header
                        daySectionHeader(day: dayGroup.day, count: dayGroup.programs.count)
                            .id("day_\(dayGroup.day.rawValue)")
                            .onAppear {
                                if userTappedDay == nil {
                                    selectedDay = dayGroup.day
                                }
                            }
                        
                        // Programs for this day
                        ForEach(dayGroup.programs) { program in
                            NavigationLink(destination: FlightyProgramDetailView(program: program)) {
                                minimalProgramRow(program: program)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .padding(.leading, 52)
                                .background(AppTheme.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        }
                    }
                    
                    // Bottom padding for tab bar
                    Spacer().frame(height: 100)
                }
            }
            .onChange(of: userTappedDay) { _, newDay in
                if let day = newDay {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("day_\(day.rawValue)", anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        userTappedDay = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Day Section Header
    private func daySectionHeader(day: Weekday, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(day.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.accentColor)
            
            Text("·")
                .foregroundColor(AppTheme.textTertiary)
            
            Text(isChinese ? "训练班" : "Programs")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textTertiary)
            
            Spacer()
            
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }
    
    // MARK: - Minimal Program Row (Clean, No Card)
    private func minimalProgramRow(program: Program) -> some View {
        let programColor = program.mascotColor
        let nextSession = dataManager.sessionEvents
            .filter { $0.programId == program.id && $0.startTime > Date() }
            .sorted { $0.startTime < $1.startTime }
            .first
        
        // Look up matching category for custom icon
        let matchingCategory = dataManager.ageCategories.first { 
            $0.shortName.uppercased() == program.ageGroup.rawValue.uppercased() 
        }
        #if canImport(UIKit)
        let customIconImage: UIImage? = matchingCategory?.customIconImage
        #elseif canImport(AppKit)
        let customIconImage: NSImage? = matchingCategory?.customIconImage
        #endif
        
        return HStack(spacing: 10) {
            // Color indicator + mascot icon (from age group or custom category)
            ZStack {
                Circle()
                    .fill(programColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                if let customImage = customIconImage {
                    #if canImport(UIKit)
                    Image(uiImage: customImage)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    #elseif canImport(AppKit)
                    Image(nsImage: customImage)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                    #endif
                } else {
                    Image(systemName: program.mascotIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(programColor)
                }
            }
            
            // Name and info
            VStack(alignment: .leading, spacing: 2) {
                Text(program.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if !program.enrolledStudentIds.isEmpty {
                        Text("\(program.enrolledStudentIds.count)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Next session time (compact)
            if let next = nextSession {
                Text(next.startTime, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
    
    // MARK: - All Archived State
    private var allArchivedState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text("All Programs Archived")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("You have \(archivedProgramsCount) archived program\(archivedProgramsCount == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Button(action: { showingArchivedPrograms = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12, weight: .semibold))
                    Text("View Archived")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange)
                .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    // MARK: - Helper Functions
    private func archiveProgram(_ program: Program) {
        var updatedProgram = program
        updatedProgram.status = .archived
        updatedProgram.updatedAt = Date()
        dataManager.updateProgram(updatedProgram)
        HapticFeedback.notification(.success)
    }
    
    private func calculateAttendanceRate(for program: Program) -> Double {
        let sessions = dataManager.sessionEvents.filter { $0.programId == program.id && $0.status == .completed }
        guard !sessions.isEmpty else { return 0 }
        
        let totalExpected = sessions.count * program.enrolledStudentIds.count
        let totalAttended = sessions.reduce(0) { result, session in result + session.attendeeIds.count }
        
        guard totalExpected > 0 else { return 0 }
        return Double(totalAttended) / Double(totalExpected) * 100
    }
    
    private func deleteProgram(_ program: Program) {
        // Delete associated micro cycles
        let programMicroCycles = dataManager.microCycles.filter { $0.programId == program.id }
        for cycle in programMicroCycles {
            dataManager.deleteMicroCycle(cycle)
        }
        
        // Delete associated sessions
        let programSessions = dataManager.sessionEvents.filter { $0.programId == program.id }
        for session in programSessions {
            dataManager.deleteSessionEvent(session)
        }
        
        // Delete the program
        dataManager.deleteProgram(program)
    }
    
    // Empty state when filtering by a coach who has no programs
    private var coachNoProgramsState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.textTertiary.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(spacing: 6) {
                Text(isChinese ? "该教练暂无课程" : "No Programs for This Coach")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(isChinese ? "选择其他教练或创建新课程" : "Select another coach or create a new program")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            
            // Button to clear coach filter
            Button(action: { selectedCoachId = nil }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12))
                    Text(isChinese ? "显示全部" : "Show All")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.accentColor)
                .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentColor.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.accentColor)
            }
            
            VStack(spacing: 6) {
                Text("No Programs Yet")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Tap + in the header to create one")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(AppTheme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
}

// MARK: - Opened Program Card (Displayed when card is expanded)
struct OpenedProgramCard: View {
    let program: Program
    let enrolledCount: Int
    let phaseCount: Int
    let sessionCount: Int
    let attendanceRate: Double
    let expandedHeight: CGFloat
    
    @State private var cachedImage: PlatformImage? = nil
    
    private var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            ZStack {
                if let platformImage = cachedImage {
                    #if os(iOS)
                    Image(uiImage: platformImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: expandedHeight)
                        .clipped()
                    #elseif os(macOS)
                    Image(nsImage: platformImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: expandedHeight)
                        .clipped()
                    #endif
                    
                    // Gradient overlay
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    programColor
                    
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.clear,
                            Color.black.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    GeometryReader { geo in
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 80, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.1))
                            .position(x: geo.size.width * 0.85, y: geo.size.height * 0.5)
                    }
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 12) {
                // Program name
                Text(program.name.uppercased())
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                
                // Stats row
                HStack(spacing: 20) {
                    statItem(value: "\(phaseCount)", label: "Phases")
                    statItem(value: "\(sessionCount)", label: "Sessions")
                    statItem(value: "\(enrolledCount)", label: "Athletes")
                    statItem(value: "\(Int(attendanceRate))%", label: "Attend.")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: expandedHeight)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 15, y: 8)
        .onAppear {
            if cachedImage == nil, let imageData = program.imageData {
                cachedImage = downsampleImage(data: imageData, maxDimension: 400)
            }
        }
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private func downsampleImage(data: Data, maxDimension: CGFloat) -> PlatformImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            #if os(iOS)
            return UIImage(data: data)
            #elseif os(macOS)
            return NSImage(data: data)
            #endif
        }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            #if os(iOS)
            return UIImage(data: data)
            #elseif os(macOS)
            return NSImage(data: data)
            #endif
        }
        
        #if os(iOS)
        return UIImage(cgImage: downsampledImage)
        #elseif os(macOS)
        return NSImage(cgImage: downsampledImage, size: NSSize(width: maxDimension, height: maxDimension))
        #endif
    }
}

// MARK: - Program Detail Content (Shown below expanded card)
struct ProgramDetailContent: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    
    @State private var showingEditStudents = false
    @State private var showingAddPhase = false
    @State private var selectedStudentIds: Set<UUID> = []
    
    var microCycles: [MicroCycle] {
        dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }
    
    var enrolledStudents: [Student] {
        dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Training Phases Section
            phasesSection
            
            // Athletes Section
            athletesSection
            
            // Objectives Section
            if !program.objectives.isEmpty {
                objectivesSection
            }
        }
        .onAppear {
            selectedStudentIds = Set(program.enrolledStudentIds)
        }
        .sheet(isPresented: $showingEditStudents) {
            EditEnrolledStudentsView(program: .constant(program), selectedIds: $selectedStudentIds)
        }
        .sheet(isPresented: $showingAddPhase) {
            AddPhaseView(program: program, nextPhaseNumber: microCycles.count + 1)
        }
    }
    
    // MARK: - Phases Section
    private var phasesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(programColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 16))
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TRAINING PHASES")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("\(microCycles.count) phase\(microCycles.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                
                Spacer()
                
                Button(action: { showingAddPhase = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(programColor)
                    .cornerRadius(20)
                }
            }
            
            if microCycles.isEmpty {
                Button(action: { showingAddPhase = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.badge.plus")
                            .font(.system(size: 28))
                            .foregroundColor(programColor)
                        Text("Create Your First Phase")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(programColor.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(microCycles) { cycle in
                        NavigationLink(destination: FlightyMicroCycleDetailView(microCycle: cycle, program: program)) {
                            PhaseRowCard(microCycle: cycle, accentColor: programColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(programColor.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Athletes Section
    private var athletesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    
                    Text("ATHLETES")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                }
                
                Spacer()
                
                Text("\(enrolledStudents.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(programColor)
                    .cornerRadius(12)
                
                Button(action: { showingEditStudents = true }) {
                    Text("Manage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(programColor)
                }
            }
            
            if enrolledStudents.isEmpty {
                Button(action: { showingEditStudents = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20))
                            .foregroundColor(programColor)
                        Text("Add athletes to this program")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .padding(12)
                    .background(AppTheme.surfaceColor)
                    .cornerRadius(10)
                }
            } else {
                // Stacked avatars
                HStack(spacing: -10) {
                    ForEach(Array(enrolledStudents.prefix(6).enumerated()), id: \.element.id) { index, student in
                        StudentAvatarView(student: student, size: 40)
                            .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                            .zIndex(Double(6 - index))
                    }
                    
                    if enrolledStudents.count > 6 {
                        ZStack {
                            Circle()
                                .fill(programColor)
                                .frame(width: 40, height: 40)
                            Text("+\(enrolledStudents.count - 6)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .overlay(Circle().stroke(AppTheme.cardBackground, lineWidth: 2))
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Objectives Section
    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OBJECTIVES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(program.objectives, id: \.self) { objective in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text(objective)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(20)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Phase Row Card (Compact)
struct PhaseRowCard: View {
    let microCycle: MicroCycle
    let accentColor: Color
    
    var body: some View {
        HStack(spacing: 14) {
            // Phase number
            ZStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 40, height: 40)
                Text("\(microCycle.phaseNumber)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(microCycle.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                HStack(spacing: 8) {
                    Text("\(microCycle.durationWeeks) weeks")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    if !microCycle.focus.isEmpty {
                        Text(microCycle.focus.first?.displayName ?? "")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.12))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
        }
        .padding(12)
        .background(AppTheme.surfaceColor)
        .cornerRadius(12)
    }
}

// MARK: - Program Poster Card (Dribbble-Inspired)
struct ProgramPosterCard: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    let enrolledCount: Int
    let phaseCount: Int
    let sessionCount: Int
    let attendanceRate: Double
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    private var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    var body: some View {
        NavigationLink(destination: FlightyProgramDetailView(program: program)) {
            posterContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete Program", systemImage: "trash")
            }
        }
        .alert("Delete Program?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
        } message: {
            Text("This will permanently delete \"\(program.mascot.displayName)\" and all its phases and sessions.")
        }
    }
    
    private var posterContent: some View {
        ZStack(alignment: .bottomLeading) {
            // Background - either uploaded image or gradient
            ZStack {
                if let imageData = program.imageData {
                    #if os(iOS)
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                    }
                    #endif
                } else {
                    // Gradient background based on program color
                    LinearGradient(
                        colors: [
                            programColor.opacity(0.9),
                            programColor.opacity(0.5),
                            Color(hex: "#1A1A1A")
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    
                    // Decorative mascot watermark
                    GeometryReader { geo in
                        Image(systemName: program.mascot.icon)
                            .font(.system(size: 100, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.1))
                            .position(x: geo.size.width * 0.75, y: geo.size.height * 0.35)
                    }
                }
                
                // Dark gradient overlay at bottom for text readability
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 140)
                }
            }
            
            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                // Top section - Status and age badges
                HStack {
                    if program.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppTheme.accentColor)
                                .frame(width: 6, height: 6)
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.accentColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                    }
                    
                    Spacer()
                    
                    // Age group badge
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                }
                .padding(16)
                
                Spacer()
                
                // Bottom section - Name and stats
                VStack(alignment: .leading, spacing: 10) {
                    // Program name - large text
                    Text(program.mascot.displayName.uppercased())
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    
                    // Stats row
                    HStack(spacing: 20) {
                        statBadge(value: "\(phaseCount)", label: "Phases")
                        statBadge(value: "\(sessionCount)", label: "Sessions")
                        statBadge(value: "\(enrolledCount)", label: "Athletes")
                        statBadge(value: "\(Int(attendanceRate))%", label: "Attend.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(height: 200)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: programColor.opacity(0.4), radius: 10, y: 5)
    }
    
    private func statBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

// MARK: - American Express Card Tier
enum AmexCardTier: CaseIterable {
    case green
    case gold
    case platinum
    case centurion
    
    var name: String {
        switch self {
        case .green: return "GREEN"
        case .gold: return "GOLD"
        case .platinum: return "PLATINUM"
        case .centurion: return "CENTURION"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .green:
            return [
                Color(hex: "#1B5E20"),
                Color(hex: "#2E7D32"),
                Color(hex: "#388E3C"),
                Color(hex: "#1B5E20")
            ]
        case .gold:
            return [
                Color(hex: "#B8860B"),
                Color(hex: "#DAA520"),
                Color(hex: "#FFD700"),
                Color(hex: "#B8860B")
            ]
        case .platinum:
            return [
                Color(hex: "#4A4A4A"),
                Color(hex: "#8E8E8E"),
                Color(hex: "#C0C0C0"),
                Color(hex: "#E8E8E8"),
                Color(hex: "#8E8E8E"),
                Color(hex: "#4A4A4A")
            ]
        case .centurion:
            return [
                Color(hex: "#0D0D0D"),
                Color(hex: "#1A1A1A"),
                Color(hex: "#2D2D2D"),
                Color(hex: "#1A1A1A"),
                Color(hex: "#0D0D0D")
            ]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .green: return Color(hex: "#4CAF50")
        case .gold: return Color(hex: "#FFD700")
        case .platinum: return Color(hex: "#E0E0E0")
        case .centurion: return Color(hex: "#B8860B")
        }
    }
    
    var textColor: Color {
        switch self {
        case .green, .centurion: return .white
        case .gold: return Color(hex: "#1A1A1A")
        case .platinum: return Color(hex: "#2D2D2D")
        }
    }
    
    var secondaryTextColor: Color {
        switch self {
        case .green, .centurion: return .white.opacity(0.7)
        case .gold: return Color(hex: "#1A1A1A").opacity(0.6)
        case .platinum: return Color(hex: "#2D2D2D").opacity(0.6)
        }
    }
    
    var chipColor: Color {
        switch self {
        case .green: return Color(hex: "#FFD700")
        case .gold: return Color(hex: "#B8860B")
        case .platinum: return Color(hex: "#C0C0C0")
        case .centurion: return Color(hex: "#B8860B")
        }
    }
}

// MARK: - Apple Wallet Style Card (American Express Design)
struct WalletStyleCard: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    let enrolledCount: Int
    let phaseCount: Int
    let sessionCount: Int
    let attendanceRate: Double
    let isExpanded: Bool
    let cardIndex: Int
    let currentIndex: Int
    let totalCards: Int
    let expandedHeight: CGFloat
    let collapsedSpacing: CGFloat
    let dragOffset: CGFloat
    let onDelete: () -> Void
    var onTap: (() -> Void)? = nil
    
    @State private var showingDeleteConfirmation = false
    @State private var cachedImage: PlatformImage? = nil
    
    private var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    // MARK: - American Express Card Tier (based on program stars)
    private var cardTier: AmexCardTier {
        switch program.stars {
        case .one: return .green
        case .two: return .gold
        case .three: return .platinum
        case .four: return .centurion
        }
    }
    
    // Number of stars to display (1-4)
    private var starCount: Int {
        program.stars.rawValue
    }
    
    // Calculate the Y offset for this card based on its position relative to current
    private var cardOffset: CGFloat {
        let relativePosition = cardIndex - currentIndex
        
        if relativePosition < 0 {
            // Cards above current - stack them at top with minimal spacing
            return CGFloat(relativePosition) * collapsedSpacing
        } else if relativePosition == 0 {
            // Current card - apply drag offset for interactive feel
            return dragOffset * 0.4
        } else {
            // Cards below current - position below the expanded card
            return expandedHeight + CGFloat(relativePosition - 1) * collapsedSpacing
        }
    }
    
    // Scale effect - cards further from current are slightly smaller (subtle)
    private var cardScale: CGFloat {
        let distance = abs(cardIndex - currentIndex)
        return max(0.95, 1.0 - CGFloat(distance) * 0.015)
    }
    
    // All cards should be fully opaque (no transparency)
    private var cardOpacity: Double {
        return 1.0
    }
    
    var body: some View {
        Group {
            if isExpanded {
                // Expanded card - navigable
                NavigationLink(destination: FlightyProgramDetailView(program: program)) {
                    cardContent
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label("Delete Program", systemImage: "trash")
                    }
                }
                .alert("Delete Program?", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                            onDelete()
                        }
                    }
                } message: {
                    Text("This will permanently delete \"\(program.mascot.displayName)\" and all its phases and sessions.")
                }
            } else {
                // Collapsed card - tappable to expand
                Button(action: { onTap?() }) {
                    cardContent
                }
                .buttonStyle(.plain)
            }
        }
        .offset(y: cardOffset)
        .scaleEffect(cardScale, anchor: .top)
        .opacity(cardOpacity)
        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: currentIndex)
        .animation(.interpolatingSpring(stiffness: 400, damping: 35), value: dragOffset)
        .onAppear {
            // Pre-decode and cache image on appear to avoid decoding during scroll
            if cachedImage == nil, let imageData = program.imageData {
                // Downsample image for better performance
                cachedImage = downsampleImage(data: imageData, maxDimension: 400)
            }
        }
    }
    
    // Downsample image to reduce memory and improve scroll performance
    private func downsampleImage(data: Data, maxDimension: CGFloat) -> PlatformImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            #if os(iOS)
            return UIImage(data: data)
            #elseif os(macOS)
            return NSImage(data: data)
            #endif
        }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            #if os(iOS)
            return UIImage(data: data)
            #elseif os(macOS)
            return NSImage(data: data)
            #endif
        }
        
        #if os(iOS)
        return UIImage(cgImage: downsampledImage)
        #elseif os(macOS)
        return NSImage(cgImage: downsampledImage, size: NSSize(width: maxDimension, height: maxDimension))
        #endif
    }
    
    // MARK: - Card Content (American Express Style)
    private var cardContent: some View {
        ZStack {
            // Metallic gradient background (Amex style)
            LinearGradient(
                colors: cardTier.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Diagonal shine effect for metallic look
            GeometryReader { geo in
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(35))
                .offset(x: -geo.size.width * 0.2)
            }
            
            // Card content
            VStack(alignment: .leading, spacing: 0) {
                // Top row - Tier badge and Golden Stars
                HStack(alignment: .top) {
                    // Tier name and program start date
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cardTier.name)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2.5)
                            .foregroundColor(cardTier.textColor.opacity(0.85))
                        
                        // Program start date instead of "MEMBER SINCE"
                        HStack(spacing: 3) {
                            Circle()
                                .fill(cardTier.accentColor)
                                .frame(width: 4, height: 4)
                            if let startDate = program.startDate {
                                Text("STARTED \(startDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                                    .font(.system(size: 7, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundColor(cardTier.secondaryTextColor)
                            } else {
                                Text("CREATED \(program.createdAt.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.system(size: 7, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundColor(cardTier.secondaryTextColor)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Golden Stars (1-4 based on tier)
                    HStack(spacing: 3) {
                        ForEach(0..<starCount, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "#FFD700"),
                                            Color(hex: "#B8860B"),
                                            Color(hex: "#FFD700")
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: Color(hex: "#B8860B").opacity(0.5), radius: 2, y: 1)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                
                Spacer()
                
                // Center - Program name and mascot
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: program.mascot.icon)
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(cardTier.textColor.opacity(0.5))
                    
                    Text(program.name.uppercased())
                        .font(.system(size: 20, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(cardTier.textColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 18)
                
                Spacer()
                
                // Bottom row - Stats and age group
                if isExpanded {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Stats row
                            HStack(spacing: 16) {
                                amexCardStat(value: "\(enrolledCount)", label: "ATHLETES")
                                amexCardStat(value: "\(phaseCount)", label: "PHASES")
                                amexCardStat(value: "\(sessionCount)", label: "SESSIONS")
                            }
                            
                            // Age group
                            VStack(alignment: .leading, spacing: 1) {
                                Text("AGE GROUP")
                                    .font(.system(size: 6, weight: .medium))
                                    .tracking(0.8)
                                    .foregroundColor(cardTier.secondaryTextColor)
                                Text(program.ageGroup.displayName.uppercased())
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundColor(cardTier.textColor)
                            }
                        }
                        
                        Spacer()
                        
                        // Attendance rate
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(attendanceRate))%")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(cardTier.accentColor)
                            Text("ATTENDANCE")
                                .font(.system(size: 6, weight: .medium))
                                .tracking(0.8)
                                .foregroundColor(cardTier.secondaryTextColor)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    // Collapsed view - just show program name is visible at top
                    Spacer()
                        .frame(height: 14)
                }
            }
        }
        .frame(height: expandedHeight)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardTier.accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, y: 6)
    }
    
    // MARK: - Amex Style Stat
    private func amexCardStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(cardTier.textColor)
            Text(label)
                .font(.system(size: 6, weight: .medium))
                .tracking(0.5)
                .foregroundColor(cardTier.secondaryTextColor)
        }
    }
    
}

// MARK: - Corner Radius Extension
#if os(iOS)
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
#endif

// MARK: - Flighty Sessions Calendar View (Redesigned)
struct FlightySessionsCalendarView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var authManager = AuthManager.shared
    @State private var selectedDate = Date()
    @State private var currentWeekStart = Date()
    @State private var showingCreateSession = false
    @State private var viewMode: SessionViewMode = .list
    @State private var selectedCoachId: UUID? = nil  // For admin to view other coaches' data
    @State private var isCalendarExpanded = false
    @State private var weekDragOffset: CGFloat = 0
    @State private var contentDragOffset: CGFloat = 0
    @State private var isDraggingWeek = false
    @State private var isDraggingContent = false
    @Namespace private var weekNamespace  // For matchedGeometryEffect on week day indicator
    
    enum SessionViewMode: String, CaseIterable {
        case wallet = "Wallet"
        case list = "List"
        var icon: String {
            switch self {
            case .wallet: return "rectangle.stack.fill"
            case .list: return "list.bullet"
            }
        }
    }
    
    private let calendar = Calendar.current
    
    var weekDays: [Date] {
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentWeekStart)) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    
    var sessionsForSelectedDate: [SessionEvent] {
        let allSessions = dataManager.sessionEvents
        let filteredSessions: [SessionEvent]
        
        // If admin has selected a coach, filter by that coach's sessions
        if dataManager.isAdmin, let coachId = selectedCoachId {
            filteredSessions = allSessions.filter { session in
                // Show sessions from programs assigned to or created by the selected coach
                if let programId = session.programId,
                   let program = dataManager.programs.first(where: { $0.id == programId }) {
                    return program.coachId == coachId || program.createdByCoachId == coachId
                }
                // Or sessions created by the coach
                return session.createdByCoachId == coachId
            }
        } else {
            // Normal behavior: show accessible sessions
            filteredSessions = dataManager.accessibleSessions
        }
        
        return filteredSessions.filter { event in
            calendar.isDate(event.date, inSameDayAs: selectedDate)
        }.sorted { $0.startTime < $1.startTime }
    }
    
    func sessionsForDate(_ date: Date) -> [SessionEvent] {
        let allSessions = dataManager.sessionEvents
        let filteredSessions: [SessionEvent]
        
        // If admin has selected a coach, filter by that coach's sessions
        if dataManager.isAdmin, let coachId = selectedCoachId {
            filteredSessions = allSessions.filter { session in
                if let programId = session.programId,
                   let program = dataManager.programs.first(where: { $0.id == programId }) {
                    return program.coachId == coachId || program.createdByCoachId == coachId
                }
                return session.createdByCoachId == coachId
            }
        } else {
            filteredSessions = dataManager.accessibleSessions
        }
        
        return filteredSessions.filter { event in
            calendar.isDate(event.date, inSameDayAs: date)
        }
    }
    
    var body: some View {
        calendarMaster
            .onAppear {
                currentWeekStart = selectedDate
            }
    }

    private var calendarMaster: some View {
        VStack(spacing: 0) {
            // Combined header row: coach picker (left) + month header (right)
            HStack {
                if dataManager.isAdmin {
                    adminCoachPicker
                }
                
                Spacer()
                
                // Month header inline
                let isChinese = LocalizationManager.shared.currentLanguage == .chinese
                let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
                HStack(spacing: 4) {
                    Text(selectedDate.formatted(.dateTime.month(.abbreviated).locale(locale)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(selectedDate.formatted(.dateTime.year().locale(locale)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Week strip
            weekStrip

            // Sessions for selected day (swipe to change days)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Today indicator
                    if calendar.isDateInToday(selectedDate) {
                        todayBanner
                    }

                    // Sessions list
                    if sessionsForSelectedDate.isEmpty {
                        emptyState
                    } else {
                        switch viewMode {
                        case .wallet:
                            sessionsWalletView
                        case .list:
                            sessionsCompactListView
                        }
                    }
                    
                    // Add Session button
                    if authManager.canCreateSessions {
                        Button(action: { showingCreateSession = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text(LocalizationManager.shared.currentLanguage == .chinese ? "添加课程" : "Add Session")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.accentColor)
                            .cornerRadius(12)
                        }
                        .shadow(color: AppTheme.accentColor.opacity(0.2), radius: 8, x: 0, y: 4)
                        .padding(.top, 8)
                    }
                }
                .sheet(isPresented: $showingCreateSession) {
                    QuickSessionCreatorView(initialDate: selectedDate)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -geo.frame(in: .named("scroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
        }
        .background(AppTheme.background.ignoresSafeArea())
    }
    
    // MARK: - Week Strip / Month Grid (Liquid Glass Style)
    private var weekStrip: some View {
        VStack(spacing: 0) {
            if isCalendarExpanded {
                // Monthly calendar grid
                monthlyCalendarGrid
            } else {
                // Fixed week strip (no scroll, swipe changes week)
                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { date in
                        weekDayButton(date: date)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .offset(x: weekDragOffset)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            isDraggingWeek = true
                            // Rubber-band resistance
                            weekDragOffset = value.translation.width * 0.5
                        }
                        .onEnded { value in
                            isDraggingWeek = false
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            
                            #if os(iOS)
                            let screenWidth = UIScreen.main.bounds.width
                            #else
                            let screenWidth = NSScreen.main?.frame.width ?? 1200
                            #endif

                            if value.translation.width < -threshold || velocity < -100 {
                                // Swipe left: next week
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    weekDragOffset = -screenWidth * 0.3
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    navigateWeek(by: 1)
                                    weekDragOffset = screenWidth * 0.3
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        weekDragOffset = 0
                                    }
                                }
                                HapticFeedback.impact(.light)
                            } else if value.translation.width > threshold || velocity > 100 {
                                // Swipe right: previous week
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    weekDragOffset = screenWidth * 0.3
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    navigateWeek(by: -1)
                                    weekDragOffset = -screenWidth * 0.3
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        weekDragOffset = 0
                                    }
                                }
                                HapticFeedback.impact(.light)
                            } else {
                                // Snap back
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    weekDragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .padding(.vertical, 8)
        .background {
            if isCalendarExpanded {
                Color.clear
                    .glassEffect(in: RoundedRectangle(cornerRadius: 16))
            } else {
                Color.clear
                    .glassEffect(in: Capsule())
            }
        }
    }
    
    // MARK: - Week Day Button (Liquid Glass Style)
    private func weekDayButton(date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let sessionCount = sessionsForDate(date).count
        let hasUpcoming = sessionsForDate(date).contains { $0.startTime > Date() }
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        
        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if calendar.isDate(date, inSameDayAs: selectedDate) {
                    isCalendarExpanded = true
                } else {
                    selectedDate = date
                }
            }
            HapticFeedback.impact(.light)
        }) {
            VStack(spacing: 4) {
                // Day name
                Text(date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(isSelected ? .white : Color.gray)
                
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected ? .medium : .regular, design: .rounded))
                    .foregroundColor(isSelected ? .white : (isToday ? .blue : AppTheme.textPrimary))
                
                // Session indicator dots
                HStack(spacing: 2) {
                    if sessionCount > 0 {
                        ForEach(0..<min(sessionCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white : (hasUpcoming ? .blue : AppTheme.textTertiary))
                                .frame(width: 3, height: 3)
                        }
                        if sessionCount > 3 {
                            Text("+")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(isSelected ? .white : AppTheme.textTertiary)
                        }
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.blue.opacity(0.28))
                        .background {
                            Capsule().fill(.ultraThinMaterial)
                        }
                        .glassEffect()
                        .matchedGeometryEffect(id: "weekDayIndicator", in: weekNamespace)
                } else if isToday {
                    Capsule()
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Monthly Calendar Grid
    private var monthlyCalendarGrid: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        let daysInMonth = calendarDaysForMonth()
        let weekdaySymbols = isChinese ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"]
        
        return VStack(spacing: 8) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        MonthDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: selectedDate, toGranularity: .month),
                            sessionCount: sessionsForDate(date).count,
                            hasUpcoming: sessionsForDate(date).contains { $0.startTime > Date() }
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDate = date
                                currentWeekStart = date
                                isCalendarExpanded = false
                            }
                            HapticFeedback.impact(.light)
                        }
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }
    
    // Generate all days for the current month's calendar grid
    private func calendarDaysForMonth() -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: selectedDate) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let leadingEmptyDays = firstWeekday - 1
        
        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)
        
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }
        
        // Fill trailing empty days to complete the grid
        let remainingDays = (7 - (days.count % 7)) % 7
        days.append(contentsOf: Array(repeating: nil, count: remainingDays))
        
        return days
    }
    
    // MARK: - Today Banner
    private var todayBanner: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentColor)
                    .frame(width: 32, height: 32)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.black)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? "今天" : "Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("\(sessionsForSelectedDate.count) \(isChinese ? (sessionsForSelectedDate.count == 1 ? "节课已安排" : "节课已安排") : (sessionsForSelectedDate.count == 1 ? "session scheduled" : "sessions scheduled"))")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Spacer()
            
            // Current time
            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.accentColor)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [AppTheme.accentColor.opacity(0.15), AppTheme.accentColor.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppTheme.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Sessions List
    private var sessionsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                Spacer()
                
                Text("\(sessionsForSelectedDate.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
            }
            
            // Timeline view
            VStack(spacing: 0) {
                ForEach(Array(sessionsForSelectedDate.enumerated()), id: \.element.id) { index, session in
                    sessionRow(for: session) {
                        TimelineSessionCard(
                            session: session,
                            program: dataManager.programs.first { $0.id == session.programId },
                            isFirst: index == 0,
                            isLast: index == sessionsForSelectedDate.count - 1
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Sessions Wallet View (Timeline style)
    private var sessionsWalletView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(sessionsForSelectedDate.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(sessionsForSelectedDate.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
                        TimelineSessionCard(
                            session: session,
                            program: dataManager.programs.first { $0.id == session.programId },
                            isFirst: index == 0,
                            isLast: index == sessionsForSelectedDate.count - 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Sessions Compact List View
    private var sessionsCompactListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Text("\(sessionsForSelectedDate.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentColor)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            
            ForEach(sessionsForSelectedDate) { session in
                sessionRow(for: session) {
                    CompactSessionRow(session: session, program: dataManager.programs.first { $0.id == session.programId })
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(AppTheme.cardBackground)
        .cornerRadius(16)
    }

    private func sessionRow<Content: View>(for session: SessionEvent, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
            content()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.surfaceColor)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 32))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            VStack(spacing: 6) {
                Text(isChinese ? "无课程" : "No Sessions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text(calendar.isDateInToday(selectedDate) ? (isChinese ? "今天没有课程！" : "You're free today!") : (isChinese ? "这一天没有安排" : "Nothing scheduled for this day"))
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .padding(.horizontal, 20)
        .background(AppTheme.cardBackground)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.surfaceColor, lineWidth: 1)
        )
    }
    
    // MARK: - Navigation
    private func navigateWeek(by value: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if let newDate = calendar.date(byAdding: .weekOfYear, value: value, to: currentWeekStart) {
                currentWeekStart = newDate
                // Also move selected date
                if let newSelected = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) {
                    selectedDate = newSelected
                }
            }
        }
        HapticFeedback.impact(.light)
    }
    
    private func goToToday() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedDate = Date()
            currentWeekStart = Date()
        }
        HapticFeedback.impact(.medium)
    }
    
    // MARK: - Admin Coach Picker
    private var adminCoachPicker: some View {
        HStack(spacing: 8) {
            // Compact admin indicator
            Image(systemName: "shield.checkered")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.15))
                .cornerRadius(6)
            
            // Coach picker
            Menu {
                Button(action: { selectedCoachId = nil }) {
                    Label("All Coaches", systemImage: "person.3.fill")
                }
                
                Divider()
                
                ForEach(dataManager.staffCoaches.filter { $0.isActive }, id: \.id) { coach in
                    Button(action: { selectedCoachId = coach.id }) {
                        HStack {
                            Label(coach.name, systemImage: "person.fill")
                            if selectedCoachId == coach.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                    
                    Text(selectedCoachName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textPrimary)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.surfaceColor)
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Session count for selected coach
            if let coachId = selectedCoachId {
                let coachSessionCount = dataManager.sessionEvents.filter { session in
                    if let programId = session.programId,
                       let program = dataManager.programs.first(where: { $0.id == programId }) {
                        return program.coachId == coachId || program.createdByCoachId == coachId
                    }
                    return session.createdByCoachId == coachId
                }.count
                
                Text("\(coachSessionCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.accentColor.opacity(0.15))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.background)
    }
    
    private var selectedCoachName: String {
        if let coachId = selectedCoachId,
           let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
            return coach.name
        }
        return "All Coaches"
    }
}

// MARK: - Week Day Cell
struct WeekDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let sessionCount: Int
    let hasUpcoming: Bool
    let action: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        return Button(action: action) {
            VStack(spacing: 4) {
                // Day name
                Text(date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : AppTheme.textTertiary)
                
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : (isToday ? AppTheme.accentColor : AppTheme.textPrimary))
                
                // Session indicator dots
                HStack(spacing: 2) {
                    if sessionCount > 0 {
                        ForEach(0..<min(sessionCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white : (hasUpcoming ? AppTheme.accentColor : AppTheme.textTertiary))
                                .frame(width: 3, height: 3)
                        }
                        if sessionCount > 3 {
                            Text("+")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(isSelected ? .white : AppTheme.textTertiary)
                        }
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accentColor : (isToday ? AppTheme.accentColor.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday && !isSelected ? AppTheme.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Month Day Cell (for expanded calendar)
struct MonthDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let sessionCount: Int
    let hasUpcoming: Bool
    let action: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                // Day number
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .foregroundColor(dayTextColor)
                
                // Session indicator
                if sessionCount > 0 {
                    Circle()
                        .fill(isSelected ? Color.white : (hasUpcoming ? AppTheme.accentColor : AppTheme.textTertiary))
                        .frame(width: 4, height: 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppTheme.accentColor : (isToday ? AppTheme.accentColor.opacity(0.1) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday && !isSelected ? AppTheme.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var dayTextColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return AppTheme.accentColor
        } else if !isCurrentMonth {
            return AppTheme.textTertiary.opacity(0.5)
        } else {
            return AppTheme.textPrimary
        }
    }
}

// MARK: - Timeline Session Card
struct TimelineSessionCard: View {
    let session: SessionEvent
    let program: Program?
    let isFirst: Bool
    let isLast: Bool
    
    private var isPast: Bool {
        session.endTime < Date()
    }
    
    private var isNow: Bool {
        let now = Date()
        return session.startTime <= now && session.endTime >= now
    }
    
    private var programColor: Color {
        program.map { Color(hex: $0.colorHex) } ?? AppTheme.accentColor
    }
    
    private var isCancelled: Bool {
        session.status == .cancelled
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Timeline
            VStack(spacing: 0) {
                // Top line
                Rectangle()
                    .fill(isFirst ? Color.clear : AppTheme.surfaceColor)
                    .frame(width: 2)
                
                // Dot
                ZStack {
                    Circle()
                        .fill(isCancelled ? Color.red : (isNow ? Color.green : (isPast ? AppTheme.surfaceColor : programColor)))
                        .frame(width: 12, height: 12)
                    
                    if isNow {
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 4)
                            .frame(width: 20, height: 20)
                    }
                    
                    if isPast && session.status == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Bottom line
                Rectangle()
                    .fill(isLast ? Color.clear : AppTheme.surfaceColor)
                    .frame(width: 2)
            }
            .frame(width: 24)
            
            // Content card
            VStack(alignment: .leading, spacing: 10) {
                // Time row
                HStack {
                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(isNow ? .green : (isPast ? AppTheme.textTertiary : AppTheme.textSecondary))
                    
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text(session.endTime.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Spacer()
                    
                    if isCancelled {
                        Text("CANCELLED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .cornerRadius(6)
                    } else if isNow {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(6)
                    }
                }
                
                // Title
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCancelled ? AppTheme.textTertiary : (isPast ? AppTheme.textTertiary : AppTheme.textPrimary))
                    .strikethrough(isCancelled, color: .red.opacity(0.7))
                    .lineLimit(1)
                
                // Program & attendees
                HStack(spacing: 12) {
                    if let program = program {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(programColor)
                                .frame(width: 8, height: 8)
                            Text(program.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(isPast ? AppTheme.textTertiary : programColor)
                        }
                    }
                    
                    if !session.attendeeIds.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10))
                            Text("\(session.attendeeIds.count)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.5))
                }
            }
            .padding(14)
            .background(isCancelled ? Color.red.opacity(0.08) : (isPast ? AppTheme.surfaceColor.opacity(0.5) : AppTheme.surfaceColor))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isCancelled ? Color.red.opacity(0.3) : (isNow ? Color.green.opacity(0.5) : Color.white.opacity(0.05)), lineWidth: isCancelled ? 1.5 : (isNow ? 2 : 1))
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Flighty Session Row (Legacy - kept for compatibility)
struct FlightySessionRow: View {
    let session: SessionEvent
    let program: Program?
    let isFirst: Bool
    let isLast: Bool
    
    private var isPast: Bool {
        session.endTime < Date()
    }
    
    private var isNow: Bool {
        let now = Date()
        return session.startTime <= now && session.endTime >= now
    }
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(session.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(isPast ? AppTheme.textTertiary : (isNow ? .green : AppTheme.textPrimary))
                
                Text(session.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(width: 50, alignment: .trailing)
            
            Circle()
                .fill(isPast ? AppTheme.textTertiary.opacity(0.3) : (isNow ? Color.green : program.map { Color(hex: $0.colorHex) } ?? .blue))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(session.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isPast ? AppTheme.textTertiary : AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 10) {
                    if let program = program {
                        HStack(spacing: 4) {
                            Image(systemName: program.mascot.icon)
                                .font(.system(size: 10))
                            Text(program.mascot.displayName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: program.colorHex).opacity(isPast ? 0.5 : 1))
                    }
                    
                    if !session.attendeeIds.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2")
                                .font(.system(size: 10))
                            Text("\(session.attendeeIds.count)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            if isNow {
                Text("NOW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(6)
            } else if isPast {
                Image(systemName: session.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(session.status == .completed ? .green : AppTheme.textTertiary.opacity(0.3))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.4))
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Compact Session Row (for List View)
struct CompactSessionRow: View {
    let session: SessionEvent
    let program: Program?
    
    private var isPast: Bool { session.endTime < Date() }
    private var isNow: Bool { session.startTime <= Date() && session.endTime >= Date() }
    private var programColor: Color { program.map { Color(hex: $0.colorHex) } ?? AppTheme.accentColor }
    private var isCancelled: Bool { session.status == .cancelled }
    
    var body: some View {
        HStack(spacing: 10) {
            // Time
            VStack(alignment: .trailing, spacing: 1) {
                Text(session.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(isCancelled ? AppTheme.textTertiary : (isNow ? .green : (isPast ? AppTheme.textTertiary : AppTheme.textSecondary)))
                Text(session.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.6))
            }
            .frame(width: 48, alignment: .trailing)
            
            // Status indicator
            Circle()
                .fill(isCancelled ? Color.red : (isNow ? Color.green : (isPast ? AppTheme.textTertiary.opacity(0.3) : programColor)))
                .frame(width: 6, height: 6)
            
            // Title & info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isCancelled ? AppTheme.textTertiary : (isPast ? AppTheme.textTertiary : AppTheme.textPrimary))
                    .strikethrough(isCancelled, color: .red.opacity(0.7))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let program = program {
                        Text(program.name)
                            .font(.system(size: 10))
                            .foregroundColor(programColor.opacity(isPast ? 0.5 : 0.8))
                            .lineLimit(1)
                    }
                    if !session.attendeeIds.isEmpty {
                        Text("·")
                            .foregroundColor(AppTheme.textTertiary)
                        Text("\(session.attendeeIds.count)")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Status badge or chevron
            if isCancelled {
                Text("CANCELLED")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(4)
            } else if isNow {
                Text("NOW")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .cornerRadius(4)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - Compact Program Row (Simplified, Clean Design)
struct CompactProgramRow: View {
    let program: Program
    let dataManager: DataManager
    
    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese
    private var programColor: Color { Color(hex: program.colorHex) }
    private var sessionCount: Int { dataManager.sessionEvents.filter { $0.programId == program.id }.count }
    
    // Next session for this program
    private var nextSession: SessionEvent? {
        let now = Date()
        return dataManager.sessionEvents
            .filter { $0.programId == program.id && $0.startTime > now }
            .sorted { $0.startTime < $1.startTime }
            .first
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(programColor)
                .frame(width: 4, height: 52)
            
            // Mascot icon
            ZStack {
                Circle()
                    .fill(programColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: program.mascot.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(programColor)
            }
            
            // Main info
            VStack(alignment: .leading, spacing: 4) {
                // Program name - clean, readable
                Text(program.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                // Subtitle: Age group + athlete count
                HStack(spacing: 6) {
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(programColor)
                    
                    Text("•")
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text("\(program.enrolledStudentIds.count) \(isChinese ? "学员" : "athletes")")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            
            Spacer()
            
            // Right side: Next session or status
            VStack(alignment: .trailing, spacing: 2) {
                if let next = nextSession {
                    Text(next.startTime, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(isChinese ? "下节课" : "next")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                } else if sessionCount > 0 {
                    Text("\(sessionCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(isChinese ? "节课" : "sessions")
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }
}

// MARK: - Swipeable Program Row (with Archive and Delete actions)
struct SwipeableProgramRow: View {
    let program: Program
    let dataManager: DataManager
    let onArchive: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    private var programColor: Color { Color(hex: program.colorHex) }
    private var sessionCount: Int { dataManager.sessionEvents.filter { $0.programId == program.id }.count }
    private var phaseCount: Int { dataManager.microCycles.filter { $0.programId == program.id }.count }
    
    var body: some View {
        NavigationLink(destination: FlightyProgramDetailView(program: program)) {
            rowContent
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                withAnimation {
                    onArchive()
                }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
        .alert("Delete Program?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
        } message: {
            Text("This will permanently delete \"\(program.name)\" and all its phases and sessions.")
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 12) {
            // Program icon/mascot
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(programColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: program.mascot.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(programColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(program.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(program.enrolledStudentIds.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppTheme.textTertiary)
                    
                    if sessionCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text("\(sessionCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(AppTheme.textTertiary)
                    }
                    
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(programColor.opacity(0.8))
                }
            }
            
            Spacer()
            
            // Status indicator
            VStack(alignment: .trailing, spacing: 2) {
                Circle()
                    .fill(program.status == .active ? Color.green : AppTheme.textTertiary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text(program.status.rawValue.capitalized)
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.textTertiary)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(programColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Archived Programs View
struct ArchivedProgramsView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    private var archivedPrograms: [Program] {
        dataManager.programs.filter { $0.status == .archived }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if archivedPrograms.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(archivedPrograms) { program in
                                ArchivedProgramRow(
                                    program: program,
                                    onRestore: { restoreProgram(program) },
                                    onDelete: { permanentlyDeleteProgram(program) }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Archived Programs")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "archivebox")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text("No Archived Programs")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                Text("Programs you archive will appear here")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func restoreProgram(_ program: Program) {
        var updatedProgram = program
        updatedProgram.status = .draft  // Restore to draft status
        updatedProgram.updatedAt = Date()
        dataManager.updateProgram(updatedProgram)
        HapticFeedback.notification(.success)
    }
    
    private func permanentlyDeleteProgram(_ program: Program) {
        // Delete associated micro cycles
        let programMicroCycles = dataManager.microCycles.filter { $0.programId == program.id }
        for cycle in programMicroCycles {
            dataManager.deleteMicroCycle(cycle)
        }
        
        // Delete associated sessions
        let programSessions = dataManager.sessionEvents.filter { $0.programId == program.id }
        for session in programSessions {
            dataManager.deleteSessionEvent(session)
        }
        
        // Delete the program
        dataManager.deleteProgram(program)
    }
}

// MARK: - Archived Program Row
struct ArchivedProgramRow: View {
    let program: Program
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    private var programColor: Color { Color(hex: program.colorHex) }
    
    var body: some View {
        HStack(spacing: 12) {
            // Program icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(programColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: program.mascot.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(programColor)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(program.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(programColor.opacity(0.8))
                    
                    Text("•")
                        .foregroundColor(AppTheme.textTertiary)
                    
                    Text("\(program.enrolledStudentIds.count) athletes")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Restore button
                Button(action: {
                    withAnimation {
                        onRestore()
                    }
                }) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
                
                // Delete button
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .alert("Permanently Delete?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Forever", role: .destructive) {
                withAnimation {
                    onDelete()
                }
            }
        } message: {
            Text("This will permanently delete \"\(program.name)\" and all its phases and sessions. This cannot be undone.")
        }
    }
}

// MARK: - Preview
#Preview {
    FlightySessionRootView()
        .environmentObject(DataManager.shared)
}
