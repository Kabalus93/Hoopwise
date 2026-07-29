import SwiftUI
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Flighty-Inspired Session Root View
/// A redesigned coaching hub with Flighty's "boringly obvious" aesthetic
struct FlightySessionRootView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedSegment = 1
    @State private var currentTime = Date()
    @State private var showingAddProgram = false
    @Namespace private var tabNamespace  // For matchedGeometryEffect on tab indicator
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact header with title, count, and picker
                compactHeader

                // Content - Programs OR Calendar, same as iPhone (no dual-pane)
                if selectedSegment == 0 {
                    FlightyProgramsListView()
                } else {
                    FlightySessionsCalendarView()
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
            // Centered segment picker with a trailing "+" button overlay so the
            // primary action lives in the header rather than its own band.
            ZStack {
            HStack(spacing: 16) {
                // Programs tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedSegment = 0 }
                } label: {
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
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedSegment = 1 }
                } label: {
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

            // Trailing "+" pill — only meaningful while viewing Programs.
            if selectedSegment == 0 {
                HStack {
                    Spacer()
                    Button {
                        showingAddProgram = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(AppTheme.accentColor)
                            )
                            .accessibilityLabel(isChinese ? "新建计划" : "New Program")
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: showingAddProgram)
                    .padding(.trailing, 12)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            }
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .sensoryFeedback(.selection, trigger: selectedSegment)

            Divider()
        }
        .sheet(isPresented: $showingAddProgram) {
            AddProgramOnboardingView { _ in
                // Land on the Programs tab so the coach immediately sees what they made.
                selectedSegment = 0
            }
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
            .foregroundColor(selectedSegment == index ? AppTheme.neutral900 : AppTheme.textTertiary)
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
    
}

// MARK: - Flighty Programs List View (Minimalist Sidebar Design)
struct FlightyProgramsListView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingArchivedPrograms = false

    private let isChinese = LocalizationManager.shared.currentLanguage == .chinese

    private var activePrograms: [Program] {
        dataManager.programs.filter { $0.status != .archived }
    }

    private var archivedProgramsCount: Int {
        dataManager.programs.filter { $0.status == .archived }.count
    }

    /// Number of unique students with at least one active private contract
    /// (bundle or pay-per-session). Drives the "Private clients" pseudo-tile.
    private var privateClientsCount: Int {
        let ids = dataManager.contracts
            .filter { ($0.kind == .privateBundle || $0.kind == .privatePayPerSession)
                       && $0.status == .active }
            .map(\.studentId)
        return Set(ids).count
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
    
    @State private var searchText: String = ""

    private var filteredProgramsByDay: [(day: Weekday, programs: [Program])] {
        guard !searchText.isEmpty else { return programsByDay }
        let query = searchText.lowercased()
        let roster = dataManager.programs
        return programsByDay.compactMap { group in
            // Match against both the resolved display name and the raw
            // location/name fields so coaches can find programs by
            // location even when their resolved title is a team-style name.
            let filtered = group.programs.filter { program in
                program.resolvedDisplayName(in: roster).lowercased().contains(query)
                    || program.name.lowercased().contains(query)
                    || (program.locationName ?? "").lowercased().contains(query)
            }
            return filtered.isEmpty ? nil : (day: group.day, programs: filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if activePrograms.isEmpty && archivedProgramsCount == 0 {
                emptyState
                Spacer()
            } else if activePrograms.isEmpty && archivedProgramsCount > 0 {
                allArchivedState
                Spacer()
            } else {
                programsList
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingArchivedPrograms) {
            ArchivedProgramsView()
        }
    }

    // MARK: - Programs List (native inset-grouped)
    private var programsList: some View {
        List {
            // Pinned at the top so it stays one tap away even with many programs.
            if privateClientsCount > 0 {
                Section {
                    NavigationLink(destination: PrivateClientsListView()) {
                        Label {
                            Text("Private clients · \(privateClientsCount)")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }

            ForEach(filteredProgramsByDay, id: \.day) { dayGroup in
                Section {
                    ForEach(dayGroup.programs) { program in
                        NavigationLink(destination: FlightyProgramDetailView(program: program)) {
                            minimalProgramRow(program: program, sectionDay: dayGroup.day)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text(dayGroup.day.displayName)
                            .textCase(nil)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("^[\(dayGroup.programs.count) program](inflect: true)")
                            .textCase(nil)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if archivedProgramsCount > 0 {
                Section {
                    Button {
                        showingArchivedPrograms = true
                    } label: {
                        Label {
                            Text("Archived · \(archivedProgramsCount)")
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: isChinese ? "搜索训练班" : "Search programs")
    }

    // MARK: - Day Section Header (unused; kept for compat)
    private func daySectionHeader(day: Weekday, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(day.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(isChinese ? "训练班" : "Programs")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
    
    // MARK: - Minimal Program Row (Two-line)
    private func minimalProgramRow(program: Program, sectionDay: Weekday) -> some View {
        let nextSession = dataManager.sessionEvents
            .filter { $0.programId == program.id && $0.startTime > Date() }
            .sorted { $0.startTime < $1.startTime }
            .first

        let categoryTint = dataManager.ageCategories
            .first(where: { $0.shortName.uppercased() == program.ageGroup.rawValue.uppercased() })?.color
            ?? .accentColor

        // Resolved name disambiguates against the coach's full roster, so two
        // U12s in the same location won't collapse to identical labels.
        let title = program.resolvedDisplayName(in: dataManager.programs)
        let subtitle = program.subtitleLine(localeIsChinese: isChinese)

        // Other recurring days (besides the section's day) — surfaced as a
        // chip so a program that runs Thu+Wed reads honestly even though
        // it's filed under whichever day comes first in `recurringDays`.
        let otherDays = program.recurringDays
            .filter { $0 != sectionDay }
            .sorted { $0.rawValue < $1.rawValue }

        return HStack(spacing: 10) {
            AgeBadge(shortName: program.ageGroup.rawValue, tint: categoryTint, size: .small, filled: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !otherDays.isEmpty {
                        multiDayChip(otherDays: otherDays)
                    }
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let next = nextSession {
                Text(compactRelative(to: next.startTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// "+ Wed" / "+ Wed, Fri" — short-form chip surfaced next to the program
    /// title when the program runs on more than one weekday.
    private func multiDayChip(otherDays: [Weekday]) -> some View {
        let label = otherDays.map { shortWeekday($0) }.joined(separator: ", ")
        return Text("+ \(label)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: .capsule)
            .accessibilityLabel("Also on \(label)")
    }

    private func shortWeekday(_ day: Weekday) -> String {
        if isChinese {
            // 一二三四五六日
            switch day {
            case .sunday:    return "日"
            case .monday:    return "一"
            case .tuesday:   return "二"
            case .wednesday: return "三"
            case .thursday:  return "四"
            case .friday:    return "五"
            case .saturday:  return "六"
            }
        }
        // 3-letter form: Mon, Tue, Wed, …
        return String(day.displayName.prefix(3))
    }

    /// Compact relative label: "Today", "Tomorrow", "in 3d", "in 2w", "in 1mo"
    private func compactRelative(to date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return isChinese ? "今天" : "Today" }
        if calendar.isDateInTomorrow(date) { return isChinese ? "明天" : "Tomorrow" }

        let days = calendar.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 7 { return "\(days)d" }
        if days < 30 { return "\(days / 7)w" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
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
                    .foregroundStyle(.primary)
                
                Text("You have \(archivedProgramsCount) archived program\(archivedProgramsCount == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.primary)
                
                Text("Tap + in the header to create one")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
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
                HStack(alignment: .firstTextBaseline) {
                    // Program name
                    Text(program.name.uppercased())
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    Spacer(minLength: 8)
                    FormatBadge(format: program.format, size: .compact)
                }

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
            // Unified picker shared with session attendance + create-program.
            AthletePickerSheet(
                title: LocalizationManager.shared.currentLanguage == .chinese
                    ? "管理学员" : "Enrolled Students",
                students: dataManager.students,
                initialSelection: selectedStudentIds,
                accentColor: Color(hex: program.colorHex)
            ) { ids in
                let unique = Array(NSOrderedSet(array: ids)) as? [UUID] ?? ids
                selectedStudentIds = Set(unique)
                var updated = program
                updated.enrolledStudentIds = unique
                dataManager.updateProgram(updated)
            }
        }
        .sheet(isPresented: $showingAddPhase) {
            AddPhaseOnboardingView(program: program, nextPhaseNumber: microCycles.count + 1)
                .environmentObject(dataManager)
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
                            .foregroundStyle(.primary)
                        Text("\(microCycles.count) phase\(microCycles.count == 1 ? "" : "s")")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
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
                            .foregroundStyle(.primary)
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
                        .foregroundStyle(.primary)
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
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
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
                .foregroundStyle(.tertiary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(program.objectives, id: \.self) { objective in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text(objective)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
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
                    .foregroundStyle(.primary)
                
                HStack(spacing: 8) {
                    Text("\(microCycle.durationWeeks) weeks")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    
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
                            AppTheme.neutral850
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
                AppTheme.goldDark,
                Color(hex: "#DAA520"),
                AppTheme.gold,
                AppTheme.goldDark
            ]
        case .platinum:
            return [
                AppTheme.charcoal,
                Color(hex: "#8E8E8E"),
                Color(hex: "#C0C0C0"),
                Color(hex: "#E8E8E8"),
                Color(hex: "#8E8E8E"),
                AppTheme.charcoal
            ]
        case .centurion:
            return [
                AppTheme.neutral900,
                AppTheme.neutral850,
                AppTheme.charcoalDark,
                AppTheme.neutral850,
                AppTheme.neutral900
            ]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .green: return Color(hex: "#4CAF50")
        case .gold: return AppTheme.gold
        case .platinum: return Color(hex: "#E0E0E0")
        case .centurion: return AppTheme.goldDark
        }
    }
    
    var textColor: Color {
        switch self {
        case .green, .centurion: return .white
        case .gold: return AppTheme.neutral850
        case .platinum: return AppTheme.charcoalDark
        }
    }
    
    var secondaryTextColor: Color {
        switch self {
        case .green, .centurion: return .white.opacity(0.7)
        case .gold: return AppTheme.neutral850.opacity(0.6)
        case .platinum: return AppTheme.charcoalDark.opacity(0.6)
        }
    }
    
    var chipColor: Color {
        switch self {
        case .green: return AppTheme.gold
        case .gold: return AppTheme.goldDark
        case .platinum: return Color(hex: "#C0C0C0")
        case .centurion: return AppTheme.goldDark
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
                                            AppTheme.gold,
                                            AppTheme.goldDark,
                                            AppTheme.gold
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .shadow(color: AppTheme.goldDark.opacity(0.5), radius: 2, y: 1)
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
    @State private var selectedDate = Date()
    @State private var currentWeekStart = Date()
    @State private var showingCreateSession = false
    @State private var isCalendarExpanded = false
    @State private var weekDragOffset: CGFloat = 0
    @State private var contentDragOffset: CGFloat = 0
    @State private var isDraggingWeek = false
    @State private var isDraggingContent = false
    @Namespace private var weekNamespace  // For matchedGeometryEffect on week day indicator

    private let calendar = Calendar.current
    
    var weekDays: [Date] {
        guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentWeekStart)) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    
    var sessionsForSelectedDate: [SessionEvent] {
        dataManager.sessionEvents
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    func sessionsForDate(_ date: Date) -> [SessionEvent] {
        dataManager.sessionEvents.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    var body: some View {
        calendarMaster
            .onAppear {
                currentWeekStart = selectedDate
            }
    }

    private var calendarMaster: some View {
        VStack(spacing: 0) {
            calendarHeader
            weekStrip
            Divider()
                .padding(.top, 4)
            sessionsListView
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $showingCreateSession) {
            AddSessionOnboardingView(initialDate: selectedDate)
        }
    }

    // MARK: - Header (Apple Calendar style: bold month title + nav + Today)

    private var calendarHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        let monthLabel = selectedDate.formatted(.dateTime.month(.wide).year().locale(locale))
        let isCurrentMonth = calendar.isDate(selectedDate, equalTo: Date(), toGranularity: .month)

        return HStack(alignment: .firstTextBaseline) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCalendarExpanded.toggle()
                }
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: 6) {
                    Text(monthLabel)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Image(systemName: isCalendarExpanded ? "chevron.down" : "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .rotationEffect(.degrees(isCalendarExpanded ? 0 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isCalendarExpanded)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if !isCurrentMonth {
                Button {
                    goToToday()
                } label: {
                    Text(isChinese ? "今天" : "Today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 18) {
                Button { navigateWeek(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Button { navigateWeek(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Sessions list (native List so .swipeActions actually work)

    @ViewBuilder
    private var sessionsListView: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let locale = isChinese ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US")
        let dayLabel = selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(locale))

        List {
            Section {
                if sessionsForSelectedDate.isEmpty {
                    // iOS 26's `.borderedProminent` Button inside a List row
                    // stretched to fill the row vertically (giant blue pill),
                    // even with `.fixedSize()`. Solution: keep the empty state
                    // visual-only (no inline CTA), and rely on the always-
                    // visible "+ Add Session" row below.
                    ContentUnavailableView {
                        Label(isChinese ? "无课程" : "No Sessions", systemImage: "calendar.badge.clock")
                    } description: {
                        Text(calendar.isDateInToday(selectedDate)
                             ? (isChinese ? "今天没有课程" : "Nothing scheduled today")
                             : (isChinese ? "这一天没有安排" : "Nothing scheduled for this day"))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(sessionsForSelectedDate) { session in
                        sessionListRow(for: session)
                    }
                }
            } header: {
                HStack {
                    Text(dayLabel)
                        .textCase(nil)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    if calendar.isDateInToday(selectedDate) {
                        Text(isChinese ? "· 今天" : "· Today")
                            .textCase(nil)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !sessionsForSelectedDate.isEmpty {
                        Text("^[\(sessionsForSelectedDate.count) session](inflect: true)")
                            .textCase(nil)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // "+ Add Session" — always visible, both for empty days and days
            // with existing sessions. Keeps the affordance discoverable while
            // dodging the iOS 26 stretched-button bug seen with
            // `.borderedProminent` inside an `actions:` slot.
            Section {
                Button {
                    showingCreateSession = true
                } label: {
                    Label(isChinese ? "添加课程" : "Add Session",
                          systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .sensoryFeedback(.selection, trigger: showingCreateSession)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func sessionListRow(for session: SessionEvent) -> some View {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        let siblings = dataManager.recurringSiblings(of: session)
        let isOrphanSeries = siblings.count > 1

        return NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
            CompactSessionRow(session: session, program: dataManager.programs.first { $0.id == session.programId })
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                dataManager.deleteSessionEvent(session)
            } label: {
                Label(isCN ? "删除" : "Delete", systemImage: "trash")
            }
            if isOrphanSeries {
                Button {
                    dataManager.deleteRecurringSeries(of: session)
                } label: {
                    Label(isCN ? "删除整组" : "Delete Series", systemImage: "trash.slash")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                dataManager.deleteSessionEvent(session)
            } label: {
                Label(isCN ? "删除课程" : "Delete Session", systemImage: "trash")
            }
            if isOrphanSeries {
                Button(role: .destructive) {
                    dataManager.deleteRecurringSeries(of: session)
                } label: {
                    Label(
                        isCN ? "删除整组（\(siblings.count)）" : "Delete Series (\(siblings.count))",
                        systemImage: "trash.slash"
                    )
                }
            }
        }
    }

    // MARK: - Week Strip / Month Grid (Apple Calendar style)
    private var weekStrip: some View {
        VStack(spacing: 6) {
            // Weekday header letters — always visible, gray, narrow.
            weekdayHeaderRow

            if isCalendarExpanded {
                monthlyCalendarGrid
            } else {
                HStack(spacing: 0) {
                    ForEach(weekDays, id: \.self) { date in
                        appleDayCell(date: date, dimWhenOutOfMonth: false)
                            .frame(maxWidth: .infinity)
                    }
                }
                .offset(x: weekDragOffset)
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            isDraggingWeek = true
                            weekDragOffset = value.translation.width * 0.5
                        }
                        .onEnded { value in
                            isDraggingWeek = false
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.width - value.translation.width
                            if value.translation.width < -threshold || velocity < -100 {
                                navigateWeek(by: 1)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    weekDragOffset = 0
                                }
                            } else if value.translation.width > threshold || velocity > 100 {
                                navigateWeek(by: -1)
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    weekDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    weekDragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var weekdayHeaderRow: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let sundayFirst = isChinese ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"]
        // Rotate the labels so column 0 matches calendar.firstWeekday.
        // calendar.firstWeekday is 1-based with Sunday=1, so subtracting 1
        // yields the index of the first column in the Sunday-first array.
        let offset = (calendar.firstWeekday - 1 + 7) % 7
        let symbols = Array(sundayFirst[offset...]) + Array(sundayFirst[..<offset])
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Apple-style day cell: plain number, today is filled accent circle,
    /// selection (when not today) is an accent ring. Below the number sits a
    /// row of small format-tinted dots to indicate session activity.
    private func appleDayCell(date: Date, dimWhenOutOfMonth: Bool) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isInSelectedMonth = calendar.isDate(date, equalTo: selectedDate, toGranularity: .month)
        let sessions = sessionsForDate(date).sorted { $0.startTime < $1.startTime }
        let formats = sessions.map { dataManager.sessionFormat($0) }

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selectedDate = date
                currentWeekStart = date
                if isCalendarExpanded { isCalendarExpanded = false }
            }
            HapticFeedback.impact(.light)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 32, height: 32)
                    } else if isSelected {
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 17, weight: isToday || isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dayNumberStyle(isToday: isToday,
                                                        isSelected: isSelected,
                                                        isOutOfMonth: dimWhenOutOfMonth && !isInSelectedMonth))
                }

                HStack(spacing: 3) {
                    if formats.isEmpty {
                        Color.clear.frame(width: 4, height: 4)
                    } else {
                        ForEach(0..<min(formats.count, 3), id: \.self) { i in
                            Circle()
                                .fill(formats[i].tint)
                                .frame(width: 4, height: 4)
                        }
                        if formats.count > 3 {
                            Text("+")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayNumberStyle(isToday: Bool, isSelected: Bool, isOutOfMonth: Bool) -> AnyShapeStyle {
        if isToday { return AnyShapeStyle(Color.white) }
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        if isOutOfMonth { return AnyShapeStyle(HierarchicalShapeStyle.quaternary) }
        return AnyShapeStyle(HierarchicalShapeStyle.primary)
    }
    
    // MARK: - Monthly Calendar Grid (Apple-style)
    private var monthlyCalendarGrid: some View {
        let daysInMonth = calendarDaysForFullGrid()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                if let date = date {
                    appleDayCell(date: date, dimWhenOutOfMonth: true)
                } else {
                    Color.clear.frame(height: 50)
                }
            }
        }
    }

    /// Generate days for a full 6-week (42-cell) grid so the layout doesn't
    /// jump as months change. Out-of-month dates are returned and dimmed in
    /// the cell — matches Apple's Calendar behavior.
    private func calendarDaysForFullGrid() -> [Date?] {
        let comps = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let firstOfMonth = calendar.date(from: comps) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingOffset = firstWeekday - calendar.firstWeekday
        let normalizedLeading = (leadingOffset % 7 + 7) % 7

        var days: [Date?] = []
        for i in 0..<42 {
            let dayOffset = i - normalizedLeading
            days.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }
        return days
    }
    
    // Generate all days for the current month's calendar grid
    private func calendarDaysForMonth() -> [Date?] {
        let components = calendar.dateComponents([.year, .month], from: selectedDate)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: selectedDate) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        // Honour calendar.firstWeekday (Monday-first in zh_CN/most non-US locales).
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7

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
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                Image(systemName: "sun.max.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(isChinese ? "今天" : "Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(sessionsForSelectedDate.count) \(isChinese ? (sessionsForSelectedDate.count == 1 ? "节课已安排" : "节课已安排") : (sessionsForSelectedDate.count == 1 ? "session scheduled" : "sessions scheduled"))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()

            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(.caption.bold())
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .glassEffect(.regular.tint(Color.accentColor.opacity(0.1)), in: .rect(cornerRadius: 14))
    }
    
    // MARK: - Sessions Compact List View
    private var sessionsCompactListView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSIONS")
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(sessionsForSelectedDate.count)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: .rect(cornerRadius: 8))
                    .contentTransition(.numericText(value: Double(sessionsForSelectedDate.count)))
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
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func sessionRow<Content: View>(for session: SessionEvent, @ViewBuilder content: () -> Content) -> some View {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        let siblings = dataManager.recurringSiblings(of: session)
        let isOrphanSeries = siblings.count > 1

        return NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
            content()
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                dataManager.deleteSessionEvent(session)
            } label: {
                Label(isCN ? "删除" : "Delete", systemImage: "trash")
            }
            if isOrphanSeries {
                Button {
                    dataManager.deleteRecurringSeries(of: session)
                } label: {
                    Label(isCN ? "删除整组" : "Delete Series", systemImage: "trash.slash")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                dataManager.deleteSessionEvent(session)
            } label: {
                Label(isCN ? "删除课程" : "Delete Session", systemImage: "trash")
            }
            if isOrphanSeries {
                Button(role: .destructive) {
                    dataManager.deleteRecurringSeries(of: session)
                } label: {
                    Label(
                        isCN ? "删除整组（\(siblings.count)）" : "Delete Series (\(siblings.count))",
                        systemImage: "trash.slash"
                    )
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ContentUnavailableView {
            Label(isChinese ? "无课程" : "No Sessions", systemImage: "calendar.badge.clock")
        } description: {
            Text(calendar.isDateInToday(selectedDate)
                 ? (isChinese ? "今天没有课程！" : "You're free today!")
                 : (isChinese ? "这一天没有安排" : "Nothing scheduled for this day"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
                Text(date.formatted(.dateTime.weekday(.narrow).locale(locale)))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))

                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.weight(isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : (isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.primary)))

                HStack(spacing: 2) {
                    if sessionCount > 0 {
                        ForEach(0..<min(sessionCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? AnyShapeStyle(Color.white) : (hasUpcoming ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary)))
                                .frame(width: 3, height: 3)
                        }
                        if sessionCount > 3 {
                            Text("+")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                        }
                    } else {
                        Circle().fill(Color.clear).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 5)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
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
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(dayTextStyle)

                if sessionCount > 0 {
                    Circle()
                        .fill(isSelected ? AnyShapeStyle(Color.white) : (hasUpcoming ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.tertiary)))
                        .frame(width: 4, height: 4)
                } else {
                    Circle().fill(Color.clear).frame(width: 4, height: 4)
                }
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var dayTextStyle: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.white)
        } else if isToday {
            return AnyShapeStyle(Color.accentColor)
        } else if !isCurrentMonth {
            return AnyShapeStyle(HierarchicalShapeStyle.quaternary)
        } else {
            return AnyShapeStyle(HierarchicalShapeStyle.primary)
        }
    }
}


// MARK: - Compact Session Row (for List View)
struct CompactSessionRow: View {
    @EnvironmentObject var dataManager: DataManager
    let session: SessionEvent
    let program: Program?

    // Visual treatment is driven by `session.status` — the same field the
    // session detail screen mutates via Start / Complete. Wall-clock comparisons
    // (`endTime < Date()`) used to determine "past" here, which silently
    // disagreed with the field once a future session's status was set
    // explicitly. Now both views speak the same language.
    private var programColor: Color { program.map { Color(hex: $0.colorHex) } ?? AppTheme.accentColor }
    private var isCancelled: Bool { session.status == .cancelled }
    private var isCompleted: Bool { session.status == .completed }
    private var isSkipped: Bool { session.status == .skipped }
    private var isInProgress: Bool { session.status == .inProgress }
    private var isNow: Bool {
        // "NOW" badge fires on explicit in-progress status only — the coach
        // taps Start, this lights up. Time alone does not.
        isInProgress
    }
    private var format: SessionFormat {
        program?.format ?? dataManager.sessionFormat(session)
    }

    var body: some View {
        // Apple Calendar day-list row: a colored leading bar (the program /
        // format color), the title + secondary line, and times stacked on the
        // trailing edge. No nested bubble — relies on the enclosing List
        // section to provide the card chrome.
        HStack(spacing: 12) {
            // Leading color bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(barColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: format.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(barColor)
                        .symbolEffect(.pulse, options: .repeating, isActive: isNow)
                    Text(session.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isCancelled || isCompleted || isSkipped ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                        .strikethrough(isCancelled)
                        .lineLimit(1)
                    if isNow {
                        Text("NOW")
                            .font(.system(size: 9, weight: .bold))
                            .monospaced()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green, in: .rect(cornerRadius: 4))
                    } else if isCompleted {
                        // Mirrors the green dot in the phase view — "you marked
                        // this done."
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                    } else if isSkipped {
                        Text("SKIPPED")
                            .font(.system(size: 9, weight: .bold))
                            .monospaced()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.gray, in: .rect(cornerRadius: 4))
                    } else if isCancelled {
                        Text("CANCELLED")
                            .font(.system(size: 9, weight: .bold))
                            .monospaced()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red, in: .rect(cornerRadius: 4))
                    }
                }

                HStack(spacing: 6) {
                    Text(format.shortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(format.tint)
                    if let program = program {
                        Text("·").foregroundStyle(.tertiary)
                        Text(program.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !session.attendeeIds.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("\(session.attendeeIds.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(session.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isCancelled || isCompleted || isSkipped ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : (isNow ? AnyShapeStyle(Color.green) : AnyShapeStyle(HierarchicalShapeStyle.primary)))
                Text(session.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
    }

    /// Bar color mirrors `FlightyPhaseSessionRow.statusColor` so calendar
    /// and phase views never disagree:
    ///   • cancelled → red
    ///   • in progress → green (matches the "NOW" badge)
    ///   • completed → green
    ///   • skipped → gray
    ///   • scheduled → program color (or accent for program-less sessions)
    /// No wall-clock fallback — `session.status` is the only source of truth.
    private var barColor: Color {
        switch session.status {
        case .cancelled: return .red
        case .inProgress: return .green
        case .completed: return .green
        case .skipped: return Color.gray.opacity(0.4)
        case .scheduled: return programColor
        }
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                // Subtitle: Age group + athlete count
                HStack(spacing: 6) {
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(programColor)
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(program.enrolledStudentIds.count) \(isChinese ? "学员" : "athletes")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Right side: Next session or status
            VStack(alignment: .trailing, spacing: 2) {
                if let next = nextSession {
                    Text(next.startTime, style: .relative)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isChinese ? "下节课" : "next")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if sessionCount > 0 {
                    Text("\(sessionCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(isChinese ? "节课" : "sessions")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(program.enrolledStudentIds.count)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    
                    if sessionCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text("\(sessionCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.primary)
                
                Text("Programs you archive will appear here")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(program.ageGroup.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(programColor.opacity(0.8))
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text("\(program.enrolledStudentIds.count) athletes")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
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
