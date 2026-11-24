import SwiftUI
import MapKit

// MARK: - Flighty-Styled Program Detail View
/// A redesigned program detail page with Flighty's dark, confident aesthetic
struct FlightyProgramDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State var program: Program
    
    @State private var showingEditStudents = false
    @State private var showingAddPhase = false
    @State private var showingEditProgram = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSkillTargets = false
    @State private var showingParentSummary = false
    @State private var showingManagePhases = false
    @State private var showingSessionsList = false
    @State private var selectedStudentIds: Set<UUID> = []
    @State private var isExportingCards = false
    /// Before printing: keep each athlete's level colour or pick one.
    @State private var choosingCardBackdrop = false
    @State private var exportedCardsURL: URL?
    @State private var showingCardShareSheet = false
    @State private var cardExportError: String?
    @State private var showingDedupeConfirmation = false
    @State private var dedupeResultMessage: String?
    @State var showingCyclePlanner = false
    @State var cycleResultMessage: String?

    var microCycles: [MicroCycle] {
        dataManager.microCycles
            .filter { $0.programId == program.id }
            .sorted { $0.phaseNumber < $1.phaseNumber }
    }
    
    var enrolledStudents: [Student] {
        dataManager.students.filter { program.enrolledStudentIds.contains($0.id) }
    }
    
    var sessionCount: Int {
        dataManager.sessionEvents.filter { $0.programId == program.id }.count
    }

    /// Count of sessions for this program that collide with another session
    /// on the same calendar day. Drives the "Clean up duplicates" menu item —
    /// hidden when zero so the menu doesn't carry dead options.
    /// Counted by THE duplicate rule — program + day + START TIME — so the
    /// number on the button is the number the clean-up would remove. Counting
    /// by calendar day alone reported a program's afternoon session as a
    /// duplicate of its morning one.
    var duplicateSessionCount: Int {
        dataManager.duplicateSessionGroups(forProgramId: program.id)
            .reduce(0) { $0 + max(0, $1.count - 1) }
    }

    /// True when at least one phase on this program has zero session events
    /// — gates the "Generate sessions" backfill button.
    var hasEmptyPhases: Bool {
        microCycles.contains { phase in
            !dataManager.sessionEvents.contains { $0.microCycleId == phase.id }
        }
    }
    
    var programColor: Color {
        Color(hex: program.colorHex)
    }
    
    // MARK: - Category Color (from Organization settings)
    /// The category color for this program based on its age group
    private var categoryColor: Color {
        dataManager.categoryColor(for: program.ageGroup)
    }
    
    
    // MARK: - Location for Map
    /// Get the location for the map - either from organization location or use a default
    private var mapLocation: Location? {
        if let locationId = program.locationId {
            return dataManager.locations.first { $0.id == locationId }
        }
        return nil
    }
    
    /// Map center coordinate from organization settings
    private var mapCoordinate: CLLocationCoordinate2D {
        // Use location coordinates if available
        if let location = mapLocation,
           let lat = location.latitude,
           let lon = location.longitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Try to get coordinates from organization's first location with coordinates
        if let firstLocationWithCoords = dataManager.locations.first(where: { $0.hasCoordinates }),
           let lat = firstLocationWithCoords.latitude,
           let lon = firstLocationWithCoords.longitude,
           CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Default fallback (Hong Kong) - a known valid coordinate
        return CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694)
    }
    
    // MARK: - Schedule Display
    /// Format the recurring days for display
    private var scheduleDisplay: String {
        let days = program.recurringDays
        if days.isEmpty {
            return "No schedule set"
        }
        let dayNames = days.map { $0.shortName }.joined(separator: ", ")
        if let time = program.defaultSessionTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "\(dayNames) • \(formatter.string(from: time))"
        }
        return dayNames
    }
    
    var body: some View {
        page.environment(\.skillLevelProgram, program.id)
    }

    /// The page; its photos show skill levels in this group (SkillTier).
    @ViewBuilder
    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero header with integrated stats
                heroHeader
                
                // Content sections
                VStack(spacing: 20) {
                    // Training level — read by the session plan generator.
                    ProgramLevelCard(program: $program, enrolledStudents: enrolledStudents)

                    // Training phases - PRIMARY CONTENT
                    phasesSection

                    // What the phase's plans train vs its focus (November 2026).
                    PhaseCoverageCard(program: program)
                    
                    // Enrolled athletes - elegant display
                    athletesSection

                    // Who has outgrown the group, in age or level (25 Nov 2026).
                    GroupFitCard(program: program)
                    
                    // Objectives (moved to bottom)
                    if !program.objectives.isEmpty {
                        objectivesSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
        }
        .filmRoomPage()
        .sheet(isPresented: $showingCyclePlanner) {
            CyclePlannerSheet(
                program: program,
                defaultStart: CyclePlanner.nextCycleStart(programId: program.id, phases: dataManager.microCycles)
                    ?? program.startDate ?? Date()
            ) { result in
                let zh = LocalizationManager.shared.currentLanguage == .chinese
                cycleResultMessage = zh
                    ? "已创建 \(result.phases) 个阶段 · 新增 \(result.sessionsCreated) 节课 · 生成 \(result.sessionsPlanned) 份计划"
                    : "\(result.phases) phases · \(result.sessionsCreated) new sessions · \(result.sessionsPlanned) plans"
                if let fresh = dataManager.programs.first(where: { $0.id == program.id }) { program = fresh }
            }
            .environmentObject(dataManager)
        }
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailingCompat) {
                Menu {
                    Button {
                        showingManagePhases = true
                    } label: {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "管理阶段" : "Manage Phases",
                            systemImage: "square.stack.3d.up"
                        )
                    }

                    Button(action: { showingSkillTargets = true }) {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "技能目标" : "Skill Targets",
                            systemImage: "chart.bar.doc.horizontal"
                        )
                    }

                    Divider()

                    Button(action: { showingParentSummary = true }) {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "分享给家长" : "Share with Parents",
                            systemImage: "square.and.arrow.up"
                        )
                    }

                    Button(action: { choosingCardBackdrop = true }) {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "打印球员卡（A3）" : "Print Player Cards (A3)",
                            systemImage: "rectangle.stack.badge.person.crop"
                        )
                    }
                    .disabled(isExportingCards || program.enrolledStudentIds.isEmpty)

                    Button(action: { showingEditProgram = true }) {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "编辑训练计划" : "Edit Program",
                            systemImage: "pencil"
                        )
                    }

                    if duplicateSessionCount > 0 {
                        Button(action: { showingDedupeConfirmation = true }) {
                            Label(
                                LocalizationManager.shared.currentLanguage == .chinese
                                    ? "清理重复课程（\(duplicateSessionCount)）"
                                    : "Clean up duplicates (\(duplicateSessionCount))",
                                systemImage: "rectangle.compress.vertical"
                            )
                        }
                    }

                    Divider()

                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Label(
                            LocalizationManager.shared.currentLanguage == .chinese ? "删除训练计划" : "Delete Program",
                            systemImage: "trash"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: $showingManagePhases) {
            PhasesListView(program: program)
                .environmentObject(dataManager)
        }
        .navigationDestination(isPresented: $showingSessionsList) {
            ProgramSessionsListView(program: program)
                .environmentObject(dataManager)
        }
        .onAppear {
            selectedStudentIds = Set(program.enrolledStudentIds)
            refreshProgramFromDataManager()
        }
        // Always pick up upstream writes — without this, opening the same
        // program from two different entry points (programs list +
        // dashboard tile + a session that references it) leaves the local
        // `@State program` frozen at view-init time and risks a stale
        // overwrite when `updateProgram` is called from this screen.
        .onChange(of: dataManager.programs) { _, _ in
            refreshProgramFromDataManager()
        }
        .sheet(isPresented: $showingEditStudents) {
            // Unified picker — same look + feel as session attendance and
            // the create-program flow, with photo, search, and Recent/A→Z/
            // Age filter chips.
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
                program = updated
            }
        }
        .sheet(isPresented: $showingAddPhase) {
            AddPhaseOnboardingView(program: program, nextPhaseNumber: microCycles.count + 1)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingEditProgram) {
            EditProgramView(program: $program)
        }
        .onChange(of: showingEditProgram) { _, isShowing in
            if !isShowing {
                // Refresh program from dataManager after edit sheet closes
                refreshProgramFromDataManager()
            }
        }
        .onChange(of: showingEditStudents) { _, isShowing in
            if !isShowing {
                refreshProgramFromDataManager()
            }
        }
        .sheet(isPresented: $showingSkillTargets) {
            ProgramSkillTargetsSheet(program: $program)
        }
        .sheet(isPresented: $showingParentSummary) {
            ParentProgramSummaryView(program: program)
        }
        .alert(LocalizationManager.shared.currentLanguage == .chinese ? "删除训练计划？" : "Delete Program?", isPresented: $showingDeleteConfirmation) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "删除" : "Delete", role: .destructive) { deleteProgram() }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese ? "这将永久删除\"\(program.name)\"及其所有阶段和课程。" : "This will permanently delete \"\(program.name)\" and all its phases and sessions.")
        }
        .alert(
            LocalizationManager.shared.currentLanguage == .chinese ? "清理重复课程？" : "Clean up duplicate sessions?",
            isPresented: $showingDedupeConfirmation
        ) {
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "取消" : "Cancel", role: .cancel) { }
            Button(LocalizationManager.shared.currentLanguage == .chinese ? "清理" : "Clean up", role: .destructive) {
                let removed = dataManager.dedupeProgramSessions(forProgramId: program.id)
                let isCN = LocalizationManager.shared.currentLanguage == .chinese
                dedupeResultMessage = removed == 0
                    ? (isCN ? "未发现重复课程。" : "No duplicates found.")
                    : (isCN ? "已删除 \(removed) 条重复课程。" : "Removed \(removed) duplicate session\(removed == 1 ? "" : "s").")
            }
        } message: {
            Text(LocalizationManager.shared.currentLanguage == .chinese
                 ? "将删除 \(duplicateSessionCount) 条重复课程，保留每天内容最丰富的那条（按已排课、笔记、出勤判断）。此操作无法撤销。"
                 : "Will remove \(duplicateSessionCount) duplicate session\(duplicateSessionCount == 1 ? "" : "s"), keeping the most populated one per day (by drills, notes, attendance). This can't be undone.")
        }
        .alert(
            LocalizationManager.shared.currentLanguage == .chinese ? "清理完成" : "Cleanup complete",
            isPresented: Binding(get: { dedupeResultMessage != nil },
                                 set: { if !$0 { dedupeResultMessage = nil } })
        ) {
            Button("OK", role: .cancel) { dedupeResultMessage = nil }
        } message: {
            Text(dedupeResultMessage ?? "")
        }
        .sheet(isPresented: $choosingCardBackdrop) {
            CardBackdropSheet { exportPlayerCards(backdrop: $0) }
        }
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
    }

    /// The A3 print sheet of player cards for the program's athletes
    /// (AthleteCardRenderer).
    @MainActor
    private func exportPlayerCards(backdrop: CardBackdrop) {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        isExportingCards = true
        Task { @MainActor in
            defer { isExportingCards = false }
            let cards = dataManager.athleteCards(forProgram: program, backdrop: backdrop)
            guard !cards.isEmpty else {
                cardExportError = isChinese ? "没有可导出的球员" : "No players to export"
                return
            }
            guard let pdfData = AthleteCardRenderer.printSheet(cards) else {
                cardExportError = isChinese ? "生成 PDF 失败" : "Failed to generate PDF"
                return
            }
            let month = AthleteCardMonth.label(Date(), chinese: isChinese)
            let safeName = program.name.replacingOccurrences(of: "/", with: "-")
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

    /// The cascade lives in the manager (phases + sessions). The view's job
    /// is the confirmation it already shows.
    private func deleteProgram() {
        dataManager.deleteProgram(program)
        dismiss()
    }

    /// Phase delete orphans its sessions, in the manager. This used to be the
    /// ONE of four call sites that deleted them — which is exactly why the
    /// same action behaved differently depending on where you invoked it.
    private func deletePhase(_ phase: MicroCycle) {
        dataManager.deleteMicroCycle(phase)
    }
    
    /// Refresh the program state from dataManager to ensure we have latest data
    private func refreshProgramFromDataManager() {
        if let updatedProgram = dataManager.programs.first(where: { $0.id == program.id }) {
            program = updatedProgram
            selectedStudentIds = Set(updatedProgram.enrolledStudentIds)
        }
    }
    
    // MARK: - Hero Header with Map Background
    /// The average of the stars the coach gave this program's last eight
    /// rated classes — nil with fewer than three.
    private var classRating: Double? {
        let rated = dataManager.sessionEvents
            .filter { $0.programId == program.id && !SessionLifecycle.didNotHappen($0) && ($0.rating ?? 0) > 0 }
            .sorted { $0.startTime > $1.startTime }.prefix(8).compactMap(\.rating)
        return rated.count >= 3 ? Double(rated.reduce(0, +)) / Double(rated.count) : nil
    }

    // MARK: - The group's average rating
    /// The average of the enrolled athletes' evaluations on the eight skills
    /// (nil until someone is rated). It averaged a stored A/B/C grade nothing
    /// ever set, so it always read 0.0 (25 Nov 2026).
    private var averageRating: Double? {
        let ratings = enrolledStudents.compactMap { student in
            dataManager.players.first { $0.studentId == student.id }?.skills.axisAverage
        }
        return ratings.isEmpty ? nil : ratings.reduce(0, +) / Double(ratings.count)
    }
    
    // Look up custom mascot icon from category
    private var customMascotIcon: UIImage? {
        let matchingCategory = dataManager.ageCategories.first {
            $0.shortName.uppercased() == program.ageGroup.rawValue.uppercased()
        }
        return matchingCategory?.customIconImage
    }
    
    private var heroHeader: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let format = program.format

        return VStack(spacing: 14) {
            // Title block — left-aligned, Apple-Health idiom. Mascot tile sits
            // on the right at avatar-size; no oversized performance ring.
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.resolvedDisplayName(in: dataManager.programs))
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(program.ageGroup.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor, in: Capsule())

                        FormatBadge(format: format, size: .compact)

                    }

                    Text(scheduleDisplay + " · " + (isChinese ? "\(program.durationWeeks) 周" : "\(program.durationWeeks) wks"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                mascotTile
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Stats row — four cells, glassEffect, semantic typography.
            HStack(spacing: 0) {
                compactStat(value: "\(enrolledStudents.count)",
                            label: isChinese ? "学员" : "Athletes",
                            color: Color.accentColor)
                compactStatDivider
                compactStat(value: "\(microCycles.count)",
                            label: isChinese ? "阶段" : "Phases",
                            color: Color.accentColor)
                compactStatDivider
                Button {
                    showingSessionsList = true
                } label: {
                    compactStat(value: "\(sessionCount)",
                                label: isChinese ? "课程" : "Sessions",
                                color: Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(sessionCount == 0)
                compactStatDivider
                compactStat(value: averageRating.map { String(format: "%.1f", $0) } ?? "–",
                            label: isChinese ? "平均评分" : "Avg rating",
                            color: categoryColor)
                // How the classes went, by the coach's own stars (25 Nov 2026:
                // the rating was entered on each session and read nowhere).
                if let stars = classRating {
                    compactStatDivider
                    compactStat(value: String(format: "%.1f★", stars),
                                label: isChinese ? "近期课堂" : "Recent classes",
                                color: .orange)
                        .accessibilityIdentifier("program.classRating")
                }
            }
            .padding(.vertical, 14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.horizontal, 16)

            // Coach + location — single row, neutral chrome.
            if let coachId = program.coachId,
               let coach = dataManager.staffCoaches.first(where: { $0.id == coachId }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.avatarColor(coach.avatarColor))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(coach.initials)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(coach.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(coach.role.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if let location = mapLocation {
                        Label(location.name, systemImage: "mappin.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var mascotTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(categoryColor.opacity(0.14))
                .frame(width: 60, height: 60)

            if let customIcon = customMascotIcon {
                Image(uiImage: customIcon)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else {
                // The age category itself, not its mascot symbol (Luther,
                // October 2026). A coach-uploaded category icon still wins.
                Text(program.ageGroup.rawValue)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(categoryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: 60, height: 60)
    }
    
    private func compactStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var compactStatDivider: some View {
        Divider().frame(height: 32)
    }
    
    // MARK: - Objectives Section
    private var objectivesSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: isChinese ? "目标" : "OBJECTIVES",
                count: program.objectives.count
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(program.objectives.enumerated()), id: \.offset) { _, objective in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "target")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(programColor)
                            .frame(width: 18, alignment: .center)
                        Text(objective)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// Reusable section header — mono uppercase title + tertiary count, the
    /// same shape every section on this page uses for visual consistency.
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .monospaced()
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Athletes Section
    /// One layout regardless of count: section header with native bordered
    /// Manage button, then either an empty state or a 2-column grid of
    /// `AthleteCard`s — every enrolled athlete, however many.
    private var athletesSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    title: isChinese ? "学员" : "ATHLETES",
                    count: enrolledStudents.count
                )
                Spacer()
                Button {
                    showingEditStudents = true
                } label: {
                    Label(
                        enrolledStudents.isEmpty
                            ? (isChinese ? "添加" : "Add")
                            : (isChinese ? "管理" : "Manage"),
                        systemImage: enrolledStudents.isEmpty ? "plus" : "pencil"
                    )
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(programColor)
            }

            if enrolledStudents.isEmpty {
                Button { showingEditStudents = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(programColor)
                            .frame(width: 44, height: 44)
                            .background(programColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "暂无报名学员" : "No athletes enrolled yet")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(isChinese ? "添加学员以跟踪进度" : "Add athletes to track their progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
            } else {
                // The whole roster, always (18 Nov 2026, Luther: "show the full
                // list always" — it stopped at six behind "View all").
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(enrolledStudents) { student in
                        NavigationLink(destination: StudentDetailView(student: student)) {
                            AthleteCard(student: student, accentColor: programColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Athlete Card
/// Compact roster cell. Horizontal: avatar · name + age · format dot. Sized
/// to fit a 2-column grid comfortably without truncating common names.
struct AthleteCard: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student
    let accentColor: Color

    private var ageText: String {
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        if let age = student.age {
            return isCN ? "\(age) 岁" : "\(age) yrs"
        }
        return isCN ? "学员" : "Athlete"
    }

    var body: some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(student.primaryDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(ageText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            FormatBadge(format: dataManager.studentFormat(student), size: .mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: 10))
    }
}

// MARK: - Phases Section Extension
extension FlightyProgramDetailView {
    /// Phases as a single glassEffect card. Read-style: tap a phase to open
    /// detail, swipe-to-delete. Mass-delete and reorder live in the dedicated
    /// `PhasesListView` (reachable from the program toolbar's "Manage Phases").
    /// Empty state surfaces both **Generate from FEB** (primary) and **Add
    /// manually** (secondary) — same template-aware idiom as
    /// `PhasesListView`'s empty state.
    var phasesSection: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(
                    title: isChinese ? "训练阶段" : "PHASES",
                    count: microCycles.count
                )
                Spacer()
                if hasEmptyPhases && !program.recurringDays.isEmpty {
                    Button {
                        let n = dataManager.materializeMissingSessions(forProgramId: program.id)
                        if n > 0 { HapticFeedback.notification(.success) }
                    } label: {
                        Label(isChinese ? "生成课程" : "Generate sessions",
                              systemImage: "calendar.badge.plus")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(programColor)
                }
                // Reorder, rename and delete phases (PhasesListView — it lived
                // only in the ⋯ menu; 18 Nov 2026, Luther: "add a button to
                // manage phases").
                if !microCycles.isEmpty {
                    Button {
                        showingManagePhases = true
                    } label: {
                        Label(isChinese ? "管理" : "Manage", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(programColor)
                    .accessibilityIdentifier("program.managePhases")
                }
                Button {
                    showingAddPhase = true
                } label: {
                    Label(isChinese ? "添加" : "Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(programColor)
            }

            if microCycles.isEmpty {
                phasesEmptyState
            } else {
                VStack(spacing: 8) {
                    if let message = cycleResultMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(microCycles) { cycle in
                        NavigationLink(destination: FlightyMicroCycleDetailView(microCycle: cycle, program: program)) {
                            phaseRow(cycle)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deletePhase(cycle) } label: {
                                Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                            }
                        }
                    }
                    // Every cycle has a target date; the next one starts the
                    // day after the last phase (and is what the attention
                    // reminder points at).
                    Button {
                        showingCyclePlanner = true
                    } label: {
                        Label(isChinese ? "规划下一周期" : "Plan the next cycle", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(programColor)
                    .padding(.top, 4)
                    .accessibilityIdentifier("cycle.planNext")
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var phasesEmptyState: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let templateCount = PhaseTemplateStore.shared.defaultPhases(for: program.ageGroup).count
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(programColor)
                    .frame(width: 44, height: 44)
                    .background(programColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isChinese ? "暂无阶段" : "No phases yet")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(isChinese
                         ? "按目标日期、水平和训练库为 \(program.ageGroup.rawValue) 规划阶段、课程与计划，或手动添加。"
                         : "Phases, sessions and plans for \(program.ageGroup.rawValue) from a target date, level and the library — or add one by hand.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 10) {
                if templateCount > 0 {
                    Button {
                        showingCyclePlanner = true
                    } label: {
                        Label(
                            isChinese ? "规划周期" : "Plan a cycle",
                            systemImage: "wand.and.stars"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(programColor)
                }

                Button {
                    showingAddPhase = true
                } label: {
                    Text(isChinese ? "添加阶段" : "Add Phase")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func phaseRow(_ cycle: MicroCycle) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(programColor.opacity(0.16))
                    .frame(width: 32, height: 32)
                Text("\(cycle.phaseNumber)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(programColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !cycle.focus.isEmpty {
                        Text(cycle.focus.prefix(2).map { $0.displayName }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if cycle.focus.count > 2 {
                            Text("+\(cycle.focus.count - 2)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            Text(isChinese ? "\(cycle.durationWeeks) 周" : "\(cycle.durationWeeks)w")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.tertiary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: .rect(cornerRadius: 10))
    }

    private func generatePhasesFromTemplate() {
        let templates = PhaseTemplateStore.shared.defaultPhases(for: program.ageGroup)
        guard !templates.isEmpty else { return }
        let cal = Calendar.current
        var cursor: Date = program.startDate ?? cal.startOfDay(for: Date())
        for (i, template) in templates.enumerated() {
            let phase = template.instantiate(
                programId: program.id,
                phaseNumber: microCycles.count + i + 1,
                startingOn: cursor
            )
            dataManager.addMicroCycle(phase)
            // Materialize the phase's sessions on the program's recurring
            // weekday(s) so the calendar reflects the schedule immediately.
            dataManager.materializeSessions(for: phase)
            let endDate = cal.date(byAdding: .day, value: template.weeks * 7, to: cursor) ?? cursor
            cursor = cal.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
    }
}

// MARK: - Flighty MicroCycle Detail View (Phase Detail)
struct FlightyMicroCycleDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    /// The phase as opened; the page reads the STORED one (`microCycle`), so
    /// an edit shows at once.
    let initialCycle: MicroCycle
    let program: Program?

    init(microCycle: MicroCycle, program: Program?) {
        self.initialCycle = microCycle
        self.program = program
    }

    var microCycle: MicroCycle {
        dataManager.microCycles.first { $0.id == initialCycle.id } ?? initialCycle
    }

    @State private var showingAddSession = false
    @State private var showingEditPhase = false
    
    var phaseSessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { $0.microCycleId == microCycle.id }
            .sorted { $0.date < $1.date }
    }
    
    var accentColor: Color {
        program.map { Color(hex: $0.colorHex) } ?? .blue
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero header
                phaseHeader
                
                // Stats
                phaseStats
                
                // Content
                VStack(spacing: 20) {
                    // Sessions
                    sessionsSection
                    
                    // Focus areas
                    if !microCycle.focus.isEmpty {
                        focusSection
                    }
                    
                    // Objectives
                    if !microCycle.objectives.isEmpty {
                        objectivesSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(20)
            }
        }
        .filmRoomPage()
        .navigationBarTitleDisplayModeCompat(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailingCompat) {
                Button {
                    showingEditPhase = true
                } label: {
                    Label(LocalizationManager.shared.currentLanguage == .chinese ? "编辑阶段" : "Edit Phase",
                          systemImage: "pencil")
                }
                .accessibilityIdentifier("phase.edit")
                Button {
                    showingAddSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditPhase) {
            EditPhaseSheet(phase: microCycle)
                .environmentObject(dataManager)
        }
        .sheet(isPresented: $showingAddSession) {
            FlightyCreateSessionView(
                microCycle: microCycle,
                program: program,
                sessionNumber: phaseSessions.count + 1
            )
        }
    }

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    /// Reusable section header matching the program detail's idiom.
    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .monospaced()
                .foregroundStyle(.tertiary)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Phase Header
    private var phaseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text((isChinese ? "阶段 " : "PHASE ") + "\(microCycle.phaseNumber)")
                    .font(.caption.weight(.bold))
                    .monospaced()
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.14), in: Capsule())

                if let program {
                    Label(program.mascot.displayName, systemImage: program.mascot.icon)
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                }
            }

            Text(microCycle.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            if let description = microCycle.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Phase Stats
    private var phaseStats: some View {
        HStack(spacing: 0) {
            phaseStat(value: "\(microCycle.durationWeeks)",
                      label: isChinese ? "周" : "Weeks")
            divider
            phaseStat(value: "\(microCycle.intensity)/10",
                      label: isChinese ? "强度" : "Intensity")
            divider
            phaseStat(value: "\(microCycle.volume)/10",
                      label: isChinese ? "训练量" : "Volume")
            divider
            phaseStat(value: "\(phaseSessions.count)",
                      label: isChinese ? "课程" : "Sessions")
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var divider: some View {
        Divider().frame(height: 32)
    }

    private func phaseStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(accentColor)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sessions Section
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(isChinese ? "课程" : "SESSIONS", count: phaseSessions.count)
                Spacer()
                Button {
                    showingAddSession = true
                } label: {
                    Label(isChinese ? "添加" : "Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(accentColor)
            }

            if phaseSessions.isEmpty {
                Button {
                    showingAddSession = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 44, height: 44)
                            .background(accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(isChinese ? "尚未排程" : "No sessions scheduled")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(isChinese ? "点按以创建第一节课" : "Tap to schedule the first one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(phaseSessions) { session in
                        NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .architect)) {
                            FlightyPhaseSessionRow(session: session, accentColor: accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Focus Section
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(isChinese ? "训练重点" : "FOCUS AREAS",
                          count: microCycle.focus.count)

            FlowLayout(spacing: 8) {
                ForEach(microCycle.focus, id: \.self) { focus in
                    Label(focus.displayName, systemImage: focus.icon)
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Objectives Section
    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(isChinese ? "目标" : "OBJECTIVES",
                          count: microCycle.objectives.count)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(microCycle.objectives.enumerated()), id: \.offset) { _, objective in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "target")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 18, alignment: .center)
                        Text(objective)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Flighty Phase Session Row (Light Theme)
struct FlightyPhaseSessionRow: View {
    let session: SessionEvent
    var accentColor: Color = .blue
    
    private var isPast: Bool {
        session.endTime < Date()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Session type icon
            Image(systemName: session.sessionType.icon)
                .font(.system(size: 16))
                .foregroundColor(accentColor)
                .frame(width: 40, height: 40)
                .background(accentColor.opacity(0.12))
                .cornerRadius(10)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isPast ? .gray : .black)
                    .lineLimit(1)
                
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(session.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 11))
                    }
                    
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(session.startTime.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                    }
                    
                    HStack(spacing: 3) {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                        Text("\(session.durationMinutes)m")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(12)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(12)
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
}

// MARK: - Program Skill Targets Sheet
struct ProgramSkillTargetsSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    
    @Binding var program: Program
    
    @State private var targets: ProgramSkillTargets
    @State private var hasChanges = false
    
    init(program: Binding<Program>) {
        self._program = program
        self._targets = State(initialValue: program.wrappedValue.skillTargets ?? ProgramSkillTargets())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    overallTargetCard
                    skillSlidersSection
                    if !program.enrolledStudentIds.isEmpty {
                        athletesComparisonSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(16)
            }
            .filmRoomPage()
            .navigationTitle("Skill Targets")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTargets() }
                        .fontWeight(.semibold)
                        .disabled(!hasChanges)
                }
            }
        }
    }
    
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(program.mascotColor)
                    .frame(width: 50, height: 50)
                Image(systemName: program.mascotIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("SKILL EXPECTATIONS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(program.mascotColor)
                Text(program.resolvedDisplayName(in: dataManager.programs))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(program.ageGroup.displayName) • \(program.enrolledCount) athletes")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private var overallTargetCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Overall Target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.1f", targets.overallTarget))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(targets.overallTarget >= 7 ? .green : .orange)
                Text("/ 10")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(targets.overallTarget >= 7 ? Color.green : Color.orange)
                        .frame(width: geometry.size.width * targets.overallTarget / 10, height: 12)
                }
            }
            .frame(height: 12)
            Text("Athletes should aim to meet or exceed these skill levels")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private var skillSlidersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SKILL TARGETS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 14) {
                skillSlider(label: "Scoring", value: $targets.scoring, color: .orange, icon: "scope")
                skillSlider(label: "Playmaking", value: $targets.playmaking, color: .blue, icon: "arrow.triangle.branch")
                skillSlider(label: "Rebounding", value: $targets.rebounding, color: .purple, icon: "arrow.up.arrow.down")
                skillSlider(label: "Defense", value: $targets.defense, color: .red, icon: "shield.fill")
                skillSlider(label: "Athleticism", value: $targets.athleticism, color: .green, icon: "figure.run")
                skillSlider(label: "Intangibles", value: $targets.intangibles, color: .teal, icon: "star.fill")
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private func skillSlider(label: String, value: Binding<Int>, color: Color, icon: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 28)
            }
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); hasChanges = true }
            ), in: 1...10, step: 1)
            .tint(color)
        }
    }
    
    private var athletesComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ENROLLED ATHLETES")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(program.enrolledStudentIds.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(program.mascotColor)
                    .cornerRadius(8)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(enrolledStudentsWithSkills, id: \.student.id) { item in
                    athleteRow(student: item.student, player: item.player)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
    
    private var enrolledStudentsWithSkills: [(student: Student, player: Player?)] {
        program.enrolledStudentIds.compactMap { studentId in
            guard let student = dataManager.students.first(where: { $0.id == studentId }) else { return nil }
            let player = dataManager.players.first(where: { $0.studentId == studentId })
            return (student, player)
        }
    }
    
    private func athleteRow(student: Student, player: Player?) -> some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(student.primaryDisplayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let player = player {
                    let belowCount = targets.skillsBelowTarget(player.skills)
                    if belowCount == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Meets all targets")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.green)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("\(belowCount) skill\(belowCount > 1 ? "s" : "") below target")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    }
                } else {
                    Text("No skills evaluated")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let player = player {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f", player.skills.overallRating))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(player.skills.overallRating >= targets.overallTarget ? .green : .orange)
                    let diff = player.skills.overallRating - targets.overallTarget
                    Text(diff >= 0 ? "+\(String(format: "%.1f", diff))" : String(format: "%.1f", diff))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(diff >= 0 ? .green : .orange)
                }
            }
        }
        .padding(10)
        .background(.quaternary)
        .cornerRadius(10)
    }
    
    private func saveTargets() {
        targets.lastUpdatedDate = Date()
        program.skillTargets = targets
        program.updatedAt = Date()
        dataManager.updateProgram(program)
        HapticFeedback.notification(.success)
        dismiss()
    }
}

// MARK: - Program Sessions List
/// Chronological list of every SessionEvent attached to a program. Reachable
/// from the Sessions stat in the program header — useful when phases haven't
/// been set up yet and the per-phase sessions list is therefore empty.
struct ProgramSessionsListView: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program

    private var accentColor: Color { Color(hex: program.colorHex) }

    /// All sessions for this program, sorted oldest → newest so the list reads
    /// as a timeline. (Past sessions float up; the most recent / next sits at
    /// the bottom.)
    private var sessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { $0.programId == program.id }
            .sorted { $0.date < $1.date }
    }

    /// Group by month so a long list stays scannable.
    private struct MonthGroup: Identifiable {
        let id: Date
        let label: String
        let sessions: [SessionEvent]
    }

    private var groupedSessions: [MonthGroup] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: sessions) { event -> Date in
            cal.date(from: cal.dateComponents([.year, .month], from: event.date)) ?? event.date
        }
        return buckets.keys.sorted().map { monthStart in
            MonthGroup(
                id: monthStart,
                label: monthStart.formatted(.dateTime.month(.wide).year()),
                sessions: (buckets[monthStart] ?? []).sorted { $0.date < $1.date }
            )
        }
    }

    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return List {
            if sessions.isEmpty {
                Section {
                    ContentUnavailableView(
                        isChinese ? "暂无课程" : "No sessions",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(isChinese
                                          ? "添加阶段并安排课程后，它们会出现在这里。"
                                          : "Schedule sessions on a phase and they'll show up here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedSessions) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .architect)) {
                                FlightyPhaseSessionRow(session: session, accentColor: accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.label)
                                .textCase(nil)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("·").foregroundStyle(.tertiary)
                            Text("^[\(group.sessions.count) session](inflect: true)")
                                .textCase(nil)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isChinese ? "课程" : "Sessions")
        .navigationBarTitleDisplayModeCompat(.inline)
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        FlightyProgramDetailView(
            program: Program(
                name: "Spring Training",
                ageGroup: .u12,
                colorHex: "#FF6B35",
                mascot: .lion,
                stars: .two
            )
        )
        .environmentObject(DataManager.shared)
    }
}
