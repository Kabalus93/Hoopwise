import SwiftUI
import Combine

// MARK: - Flighty Actionable Dashboard
/// A clean, Flighty-inspired home screen with full-width horizontal cards
struct FlightyActionableDashboard: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var currentTime = Date()
    @State private var selectedStudent: Student?
    @State private var selectedSession: SessionEvent?
    @State private var selectedProgram: Program?
    @State private var selectedContract: Contract?
    @State private var showingProfile = false
    @State private var briefingExpanded = false
    @State private var showingAllAttentionItems = false
    @State private var attentionCategoryFocus: AttentionCategory?
    @State private var showingAllPlayers = false
    @State private var selectedLiveGame: Game?
    @State private var showingLiveScoring = false
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    // MARK: - Computed Properties
    
    private var todaySessions: [SessionEvent] {
        dataManager.sessionEvents
            .filter { Calendar.current.isDateInToday($0.date) && $0.status != .cancelled }
            .sorted { $0.startTime < $1.startTime }
    }

    private func effectivePerformanceGrade(for student: Student) -> PerformanceGrade {
        if let override = student.performanceGrade {
            return override
        }

        let skills = Dictionary(uniqueKeysWithValues: dataManager.players.map { ($0.studentId, $0.skills) })
        return StudentPerformanceGrader.computeGrade(
            for: student,
            allStudents: dataManager.students,
            sessions: dataManager.sessionEvents,
            skills: skills
        )
    }
    
    private var todaysPlayers: [Student] {
        // Get players from today's sessions - either from session attendeeIds or from program enrollment
        var playerIds = Set<UUID>()
        
        for session in todaySessions {
            // First try session attendeeIds
            if !session.attendeeIds.isEmpty {
                playerIds.formUnion(session.attendeeIds)
            }
            // Fall back to program enrolled students
            else if let programId = session.programId,
                    let program = dataManager.programs.first(where: { $0.id == programId }) {
                playerIds.formUnion(program.enrolledStudentIds)
            }
        }
        
        return dataManager.students.filter { playerIds.contains($0.id) }
    }
    
    /// Surfaces only **private bundles running low** — the only contract kind
    /// where "X sessions left" is meaningful. PAYG and group contracts have no
    /// inherent quota, so they never appear in the attention card.
    private var expiringContracts: [(contract: Contract, student: Student)] {
        return dataManager.students.compactMap { student -> (contract: Contract, student: Student)? in
            guard let contract = dataManager.currentContract(for: student.id) else { return nil }
            guard contract.kind == .privateBundle else { return nil }
            let remaining = contract.bundleRedemptionsRemaining ?? .max
            guard remaining <= 3 else { return nil }
            return (contract, student)
        }.sorted { ($0.contract.bundleRedemptionsRemaining ?? 0) < ($1.contract.bundleRedemptionsRemaining ?? 0) }
    }
    
    private var unplannedSessions: [SessionEvent] {
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.sessionEvents.filter { session in
            session.date >= now &&
            session.date <= twoWeeksFromNow &&
            session.status == .scheduled &&
            session.curriculum.totalDrillCount == 0
        }.sorted { $0.date < $1.date }
    }
    
    private var programsNeedingPlanning: [Program] {
        let now = Date()
        let twoWeeksFromNow = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        return dataManager.programs.filter { program in
            program.status == .active || program.status == .draft
        }.filter { program in
            let phases = dataManager.microCycles.filter { $0.programId == program.id }
            // Only show if program has no phases AND has sessions in the next 2 weeks
            guard phases.isEmpty else { return false }
            let hasSoonSessions = dataManager.sessionEvents.contains { session in
                session.programId == program.id && session.date >= now && session.date <= twoWeeksFromNow
            }
            return hasSoonSessions || (program.startDate ?? Date.distantFuture) <= twoWeeksFromNow
        }
    }
    
    private var liveGames: [Game] {
        dataManager.games.filter { $0.status == .live }
    }
    
    /// The session the engine is currently running. Source of truth for
    /// "is there a live session right now" — checking SessionEvent.status
    /// alone is unreliable because in-progress can lag the engine's lifecycle.
    private var liveSession: SessionEvent? {
        LiveSessionEngine.shared.session
    }
    
    /// Computed once per render. The dashboard reads this for both the
    /// hero counter and the category chip row, so we centralise it here
    /// instead of recomputing twice.
    private var attentionInbox: AttentionInbox {
        AttentionInbox.compute(from: dataManager, now: currentTime)
    }

    /// Backwards-compat alias for places that still talk about the count.
    private var totalActionItems: Int { attentionInbox.totalCount }
    
    /// What surfaces the hero player and why. The "why" drives a small
    /// reason chip on the card so the coach knows at a glance why this
    /// person was singled out.
    private struct HeroPick {
        let student: Student
        /// Short, badge-sized reason. nil = no chip, just first today's player.
        let reason: String?
        /// Severity of the reason — colours the chip background.
        let severity: AttentionSeverity?
    }

    /// Hero pick rule, optimised for a busy coach walking onto the court:
    ///
    /// 1. **Returning after dormancy** — a today's player who hasn't
    ///    attended a session in 14+ days. They get re-engaged today.
    /// 2. **Bundle running low** — private bundle ≤ 3 sessions left;
    ///    coach should mention renewal.
    /// 3. **Brand-new** — student created in the last 14 days with zero
    ///    past attendance; this is their first session.
    /// 4. **Birthday** — quick win for rapport.
    /// 5. **Fallback** — first today's player, no reason chip.
    private var heroPick: HeroPick? {
        guard !todaysPlayers.isEmpty else { return nil }
        let isCN = LocalizationManager.shared.currentLanguage == .chinese
        let cal = Calendar.current
        let now = currentTime
        let dormancyCutoff = cal.date(byAdding: .day, value: -AttentionInbox.dormancyDays, to: now) ?? now

        // Build last-attended map once so each candidate check is O(1).
        var lastAttended: [UUID: Date] = [:]
        for s in dataManager.sessionEvents
            where (s.status == .completed || s.endTime < now) {
            for studentId in s.actualAttendeeIds {
                let prior = lastAttended[studentId]
                if prior == nil || s.endTime > prior! {
                    lastAttended[studentId] = s.endTime
                }
            }
        }

        // 1. Returning after dormancy
        if let returning = todaysPlayers.first(where: { student in
            guard let last = lastAttended[student.id] else { return false }
            return last < dormancyCutoff
        }) {
            let days = Int(now.timeIntervalSince(lastAttended[returning.id] ?? now) / 86400)
            return HeroPick(
                student: returning,
                reason: isCN ? "回归 · 间隔 \(days) 天" : "Welcome back · \(days)d gap",
                severity: .attention
            )
        }

        // 2. Bundle running low (≤3 sessions)
        if let lowBundle = todaysPlayers.first(where: { student in
            guard let contract = dataManager.currentContract(for: student.id),
                  contract.kind == .privateBundle else { return false }
            return (contract.bundleRedemptionsRemaining ?? .max) <= 3
        }) {
            let remaining = dataManager.currentContract(for: lowBundle.id)?
                .bundleRedemptionsRemaining ?? 0
            return HeroPick(
                student: lowBundle,
                reason: isCN
                    ? "剩 \(remaining) 节"
                    : "\(remaining) session\(remaining == 1 ? "" : "s") left",
                severity: remaining <= 1 ? .urgent : .attention
            )
        }

        // 3. Brand-new student (≤14d enrolled, zero prior attendance)
        if let newcomer = todaysPlayers.first(where: { student in
            student.createdAt >= dormancyCutoff && lastAttended[student.id] == nil
        }) {
            return HeroPick(
                student: newcomer,
                reason: isCN ? "首次上课" : "First session",
                severity: .attention
            )
        }

        // 4. Birthday today
        if let birthday = todaysPlayers.first(where: { student in
            guard let dob = student.birthdate else { return false }
            return cal.component(.month, from: dob) == cal.component(.month, from: now)
                && cal.component(.day, from: dob) == cal.component(.day, from: now)
        }) {
            return HeroPick(
                student: birthday,
                reason: isCN ? "今天生日 🎂" : "Birthday 🎂",
                severity: .attention
            )
        }

        // 5. Fallback — first today's player, no reason
        return HeroPick(student: todaysPlayers[0], reason: nil, severity: nil)
    }

    /// Compatibility shim — older code reads `heroPlayer`. New rendering
    /// goes through `heroPick`.
    private var heroPlayer: Student? { heroPick?.student }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        if let session = liveSession {
                            LiveSessionActivityCard(session: session)
                        }

                        todayBriefingCard

                        if !liveGames.isEmpty {
                            liveGameAlert
                        }

                        if totalActionItems > 0 {
                            attentionRequiredCard
                        }

                        if !todaysPlayers.isEmpty {
                            todaysPlayersCard
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 120)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(navTitle)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    profileToolbarButton
                }
                #else
                ToolbarItem(placement: .navigation) {
                    profileToolbarButton
                }
                #endif
            }
            .onReceive(timer) { _ in
                currentTime = Date()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .fullScreenCoverCompat(isPresented: $showingProfile) {
                FlightyCoachProfileView()
            }
            .navigationDestination(item: $selectedSession) { session in
                FlightySessionPageView(session: session, accessMode: .architect)
            }
            .navigationDestination(item: $selectedProgram) { program in
                FlightyProgramDetailView(program: program)
            }
            .sheet(item: $selectedStudent) { student in
                StudentQuickPeepView(student: student, sessionId: nil)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingAllAttentionItems) {
                AllAttentionItemsSheet(
                    expiringContracts: expiringContracts,
                    unplannedSessions: unplannedSessions,
                    programsNeedingPlanning: programsNeedingPlanning,
                    onSelectStudent: { selectedStudent = $0 },
                    onSelectSession: { selectedSession = $0 },
                    onSelectProgram: { selectedProgram = $0 }
                )
            }
            .sheet(item: $attentionCategoryFocus) { category in
                AttentionFocusedSheet(
                    category: category,
                    onSelectStudent: { selectedStudent = $0 },
                    onSelectSession: { selectedSession = $0 },
                    onSelectProgram: { selectedProgram = $0 }
                )
            }
            .sheet(isPresented: $showingAllPlayers) {
                AllPlayersSheet(
                    players: todaysPlayers,
                    dataManager: dataManager,
                    onSelectStudent: { selectedStudent = $0 }
                )
            }
            .sheet(isPresented: $showingLiveScoring) {
                if let game = selectedLiveGame {
                    LiveScoringView(game: Binding(
                        get: { dataManager.games.first { $0.id == game.id } ?? game },
                        set: { dataManager.updateGame($0) }
                    ))
                }
            }
        }
    }
    
    // MARK: - Navigation Chrome (iOS 26 native)

    private var navTitle: String {
        let first = dataManager.coach.name.components(separatedBy: " ").first ?? "Coach"
        return "\(greeting) \(first)"
    }

    private var profileToolbarButton: some View {
        Button {
            showingProfile = true
        } label: {
            profileAvatar
                .frame(width: 32, height: 32)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(.quaternary, lineWidth: 0.5)
                }
                .accessibilityLabel("Coach Profile")
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: showingProfile)
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let imageData = dataManager.coach.profileImageData, !imageData.isEmpty {
            DataImageView(data: imageData, size: 32)
        } else if let imageUrlString = dataManager.coach.profileImageUrl, !imageUrlString.isEmpty {
            if imageUrlString.hasPrefix("http") {
                AsyncImage(url: URL(string: imageUrlString)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        defaultCoachAvatarContent
                    }
                }
            } else {
                LocalImageView(path: imageUrlString, size: 32)
            }
        } else {
            defaultCoachAvatarContent
        }
    }
    
    /// Helper view to load images from Data
    private struct DataImageView: View {
        let data: Data
        let size: CGFloat
        
        var body: some View {
            if let image = loadImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                EmptyView()
            }
        }
        
        private func loadImage() -> Image? {
            #if os(iOS)
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
            #else
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
            #endif
        }
    }
    
    /// Helper view to load local images from file path
    private struct LocalImageView: View {
        let path: String
        let size: CGFloat
        
        var body: some View {
            if let image = loadLocalImage() {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                EmptyView()
            }
        }
        
        private func loadLocalImage() -> Image? {
            #if os(iOS)
            let fileURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let fileURL = fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
            #else
            let fileURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
            guard let fileURL = fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
            #endif
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch hour {
        case 5..<12: return isChinese ? "早上好，" : "Good morning,"
        case 12..<17: return isChinese ? "下午好，" : "Good afternoon,"
        case 17..<21: return isChinese ? "晚上好，" : "Good evening,"
        default: return isChinese ? "晚安，" : "Good night,"
        }
    }
    
    private var defaultCoachAvatarContent: some View {
        ZStack {
            Circle().fill(Color.accentColor.gradient)
            Text(dataManager.coach.initials.isEmpty ? "?" : dataManager.coach.initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }
    
    // MARK: - Today's Briefing Card (Expandable)
    private var todayBriefingCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let hasSessions = !todaySessions.isEmpty

        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    briefingExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(hasSessions ? Color.accentColor : Color.secondary)
                                .frame(width: 8, height: 8)
                                .symbolEffect(.pulse, options: .repeating, isActive: hasSessions)
                            Text(isChinese ? "今日简报" : "TODAY'S BRIEFING")
                                .font(.caption.weight(.bold))
                                .monospaced()
                                .foregroundStyle(hasSessions ? Color.accentColor : .secondary)
                        }

                        Text(hasSessions
                             ? (isChinese ? "今天有 \(todaySessions.count) 节课" : "^[\(todaySessions.count) session](inflect: true) today")
                             : (isChinese ? "今天没有课程" : "No sessions scheduled"))
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText(value: Double(todaySessions.count)))
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(briefingExpanded ? 180 : 0))
                        .padding(8)
                        .background(.quaternary, in: Circle())
                }
                .padding(20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: briefingExpanded)

            if briefingExpanded && hasSessions {
                Divider().padding(.leading, 20)
                VStack(spacing: 0) {
                    ForEach(Array(todaySessions.enumerated()), id: \.element.id) { index, session in
                        briefingSessionRow(session, isLast: index == todaySessions.count - 1 && dataManager.todayReminders.isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if briefingExpanded && !dataManager.todayReminders.isEmpty {
                if hasSessions { Divider().padding(.leading, 20) }
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Label {
                            Text(isChinese ? "今日提醒" : "TODAY'S REMINDERS")
                                .font(.caption2.weight(.bold))
                                .monospaced()
                        } icon: {
                            Image(systemName: "bell.badge")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    ForEach(Array(dataManager.todayReminders.enumerated()), id: \.element.id) { index, reminder in
                        briefingReminderRow(reminder, isLast: index == dataManager.todayReminders.count - 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
    
    private func briefingReminderRow(_ reminder: Reminder, isLast: Bool) -> some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let currentCoachId = dataManager.loggedInCoachId ?? dataManager.coach.id
        let isSharedWithMe = reminder.isSharedWith(coachId: currentCoachId)
        let creatorName = isSharedWithMe ? dataManager.staffCoaches.first { $0.id == reminder.creatorCoachId }?.name : nil
        let taggedStudentNames = reminder.taggedStudentIds.compactMap { id in
            dataManager.students.first { $0.id == id }?.name
        }
        
        return HStack(spacing: 12) {
            Button {
                dataManager.toggleReminderCompletion(reminder)
            } label: {
                Circle()
                    .stroke(reminder.statusColor, lineWidth: 2)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: reminder.isCompleted)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if reminder.priority == .high {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if !taggedStudentNames.isEmpty {
                        Label {
                            Text(taggedStudentNames.count == 1 ? taggedStudentNames[0] : "\(taggedStudentNames.count)")
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "person.fill").font(.caption2)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    if let creatorName = creatorName {
                        Label {
                            Text(isChinese ? "来自\(creatorName)" : "From \(creatorName)")
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "arrow.turn.down.right").font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().padding(.leading, 46)
            }
        }
    }
    
    private func briefingSessionRow(_ session: SessionEvent, isLast: Bool) -> some View {
        let program = session.programId.flatMap { pid in dataManager.programs.first { $0.id == pid } }
        let isPast = session.endTime < currentTime
        let isNow = session.startTime <= currentTime && session.endTime >= currentTime
        // Effective player count: prefer the session's own attendee list,
        // fall through to the program's enrolled roster when the session
        // hasn't been customised. Matches what `todaysPlayers` does.
        let playerCount: Int = {
            if !session.attendeeIds.isEmpty { return session.attendeeIds.count }
            return program?.enrolledStudentIds.count ?? 0
        }()
        let format = dataManager.sessionFormat(session)

        return Button { selectedSession = session } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.footnote.bold())
                        .monospacedDigit()
                        .foregroundStyle(isNow ? AnyShapeStyle(Color.accentColor) : (isPast ? AnyShapeStyle(HierarchicalShapeStyle.tertiary) : AnyShapeStyle(HierarchicalShapeStyle.primary)))
                        .frame(width: 55, alignment: .leading)

                    Circle()
                        .fill(isNow ? Color.accentColor : (isPast ? Color.secondary.opacity(0.3) : Color.green))
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse, options: .repeating, isActive: isNow)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            // Program / venue context — replaces the deprecated
                            // mascot badge. Falls back to the session's own
                            // location if the program has none.
                            if let program = program {
                                Label {
                                    Text(program.resolvedDisplayName(in: dataManager.programs))
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                } icon: {
                                    Image(systemName: format.icon).font(.caption2)
                                }
                                .foregroundStyle(format.tint.opacity(isPast ? 0.5 : 1))
                            } else if let location = session.location, !location.isEmpty {
                                Label {
                                    Text(location).font(.caption.weight(.medium)).lineLimit(1)
                                } icon: {
                                    Image(systemName: "mappin").font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }

                            Text("^[\(playerCount) player](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText(value: Double(playerCount)))
                        }
                    }

                    Spacer()

                    if isNow {
                        Text("NOW")
                            .font(.caption2.bold())
                            .monospaced()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor, in: .rect(cornerRadius: 6))
                    } else if isPast {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green.opacity(0.6))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())

                if !isLast {
                    Divider().padding(.leading, 80)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Live Game Alert
    private var liveGameAlert: some View {
        let game = liveGames.first ?? Game(id: UUID(), homeTeamId: UUID(), awayTeamId: UUID(), homeScore: 0, awayScore: 0, date: Date(), status: .scheduled, createdAt: Date(), updatedAt: Date())
        let homeTeam = dataManager.teams.first { $0.id == game.homeTeamId }
        let awayTeam = dataManager.teams.first { $0.id == game.awayTeamId }

        return Button {
            selectedLiveGame = game
            showingLiveScoring = true
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .monospaced()
                }

                Spacer()

                HStack(spacing: 8) {
                    Text(awayTeam?.shortName ?? "AWY").font(.caption.bold())
                    Text("\(game.awayScore) – \(game.homeScore)")
                        .font(.callout.bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(homeTeam?.shortName ?? "HME").font(.caption.bold())
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .controlSize(.extraLarge)
        .tint(.red)
        .sensoryFeedback(.impact, trigger: showingLiveScoring)
    }
    
    // MARK: - Attention Required Card
    private var attentionRequiredCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let inbox = attentionInbox
        let urgent = inbox.mostUrgent

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(isChinese ? "需要关注" : "ATTENTION REQUIRED")
                        .font(.caption2.weight(.bold))
                        .monospaced()
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                }
                .foregroundStyle(.white.secondary)

                Text("\(inbox.totalCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(inbox.totalCount)))

                Text(isChinese ? "项需要您关注" : "items need your attention")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.secondary)

                if let urgent = urgent {
                    Button {
                        attentionCategoryFocus = urgent.category
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: urgent.icon).font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(urgent.title)
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                                if let ctx = urgent.timeContext {
                                    Text(ctx)
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.75))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Category chips — only show categories with items so the row
            // never looks padded with empties.
            let activeCategories = AttentionCategory.allCases
                .filter { inbox.count(in: $0) > 0 }
            if !activeCategories.isEmpty {
                HStack(spacing: 8) {
                    ForEach(activeCategories) { category in
                        attentionCategoryChip(
                            category: category,
                            count: inbox.count(in: category)
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, activeCategories.count > 0 ? 8 : 0)
            }

            // De-emphasized "see everything" link — only useful when there's
            // more than one category in play; for a single-category inbox
            // the chip itself already does the job.
            if activeCategories.count > 1 {
                Button {
                    showingAllAttentionItems = true
                } label: {
                    HStack(spacing: 4) {
                        Text(isChinese ? "查看全部" : "See everything")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
                .sensoryFeedback(.selection, trigger: showingAllAttentionItems)
            }
        }
        .background(Color.red.gradient, in: .rect(cornerRadius: 24))
    }

    private func attentionCategoryChip(category: AttentionCategory, count: Int) -> some View {
        Button {
            attentionCategoryFocus = category
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: category.icon)
                        .font(.subheadline.weight(.semibold))
                    Text("\(count)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                }
                Text(category.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.18), in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: attentionCategoryFocus == category)
    }
    
    // MARK: - Today's Players Card
    private var todaysPlayersCard: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        let hero = heroPlayer
        let heroGrade = hero.map { effectivePerformanceGrade(for: $0) }
        let player = hero.flatMap { s in dataManager.players.first { $0.studentId == s.id } }

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if let hero = hero { selectedStudent = hero }
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text(isChinese ? "今日学员" : "TODAY'S ATHLETES")
                                .font(.caption2.weight(.bold))
                                .monospaced()
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)

                        if let hero = hero {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(hero.name)
                                    .font(.title2.bold())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                FormatBadge(format: dataManager.studentFormat(hero), size: .compact)
                            }

                            if let pick = heroPick, let reason = pick.reason {
                                heroReasonChip(reason: reason, severity: pick.severity ?? .attention)
                            }

                            // Align by the caption baselines so "performance"
                            // and "focus area" sit on the same line even when
                            // the value fonts above them differ in size.
                            HStack(alignment: .lastTextBaseline, spacing: 16) {
                                if let heroGrade = heroGrade {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(heroGrade == .ungraded ? "–" : heroGrade.displayName)
                                            .font(.title2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(Color.accentColor)
                                        Text(isChinese ? "能力评级" : "performance")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if let player = player, let focus = player.skills.lowestSkill {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(focus)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text(isChinese ? "重点提升" : "focus area")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        } else {
                            Text("\(todaysPlayers.count)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .contentTransition(.numericText(value: Double(todaysPlayers.count)))
                            Text(isChinese ? "今日学员" : "players today")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let hero = hero {
                        heroPlayerAvatar(hero)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: selectedStudent?.id)

            Button {
                showingAllPlayers = true
            } label: {
                HStack {
                    HStack(spacing: -8) {
                        ForEach(todaysPlayers.prefix(3)) { student in
                            miniAvatar(student)
                        }
                        if todaysPlayers.count > 3 {
                            ZStack {
                                Circle().fill(.quaternary).frame(width: 28, height: 28)
                                Text("+\(todaysPlayers.count - 3)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Text(isChinese ? "查看全部 \(todaysPlayers.count) 名学员" : "See all \(todaysPlayers.count) players")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .sensoryFeedback(.selection, trigger: showingAllPlayers)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
    
    /// Small reason chip shown below the hero player's name. Tells the
    /// coach *why* this athlete was singled out so it's not a black-box pick.
    private func heroReasonChip(reason: String, severity: AttentionSeverity) -> some View {
        let tint: Color = {
            switch severity {
            case .urgent:    return .red
            case .attention: return .orange
            case .fyi:       return .blue
            }
        }()
        return Text(reason)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: .capsule)
    }

    // Hero player avatar with profile picture — fully cached, never network.
    private func heroPlayerAvatar(_ student: Student) -> some View {
        StudentAvatarView(student: student, size: 72)
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
    }
    
    // Initials avatar fallback
    private func initialsAvatar(_ student: Student, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: size, height: size)
            Text(student.initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 3))
    }
    
    // Mini avatar for the preview stack — fully cached.
    private func miniAvatar(_ student: Student) -> some View {
        Group {
            StudentAvatarView(student: student, size: 28)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        }
    }
    
    private func miniInitialsAvatar(_ student: Student) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: student.avatarColor))
                .frame(width: 28, height: 28)
            Text(student.initials)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
    }
    
    private func avatarColor(for color: AvatarColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .teal: return .teal
        case .pink: return .pink
        case .indigo: return .indigo
        }
    }
}

// MARK: - Skills Evaluation Extension
extension SkillsEvaluation {
    var lowestSkill: String? {
        let skills: [(String, Int)] = [
            ("Shooting", shooting),
            ("Ball Handling", ballHandling),
            ("Defense", defense),
            ("Basketball IQ", basketballIQ),
            ("Athleticism", athleticism),
            ("Teamwork", teamwork)
        ]
        return skills.min(by: { $0.1 < $1.1 })?.0
    }
}

// MARK: - All Attention Items Sheet
/// Three things compete for the coach's attention this week: sessions that
/// have no drills planned, programs that have no phases, and contracts that
/// are about to run out. The dashboard rolls them up into a single counter
/// — this sheet is what they get when they tap "All Attention Items."
///
/// Design notes:
/// - One inset-grouped list, sectioned by category. No segmented filter
///   (the previous "Today/Tomorrow/This Week" chips fragmented an already
///   small list and hid most rows behind taps).
/// - Sessions are grouped by relative date inside their section (Today,
///   Tomorrow, weekday name, then "Later") so May 3 / May 5 / May 6 don't
///   merge into noise.
/// - Each row only shows what's true: the `12:00 AM` placeholder time
///   appears as "Time TBD"; the cryptic `TRN` prefix is gone in favour of
///   a tinted SF Symbol per session type.
/// - Native swipe actions on session rows: Skip (leading, orange) and
///   Delete (trailing, destructive). Tap = open the planning screen.
/// - Empty state when nothing's left to handle.
struct AllAttentionItemsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager

    let expiringContracts: [(contract: Contract, student: Student)]
    let unplannedSessions: [SessionEvent]
    let programsNeedingPlanning: [Program]
    var onSelectStudent: (Student) -> Void
    var onSelectSession: (SessionEvent) -> Void
    var onSelectProgram: (Program) -> Void

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var totalCount: Int {
        unplannedSessions.count + programsNeedingPlanning.count + expiringContracts.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if totalCount == 0 {
                    emptyState
                } else {
                    List {
                        if !unplannedSessions.isEmpty {
                            sessionsSections
                        }
                        if !programsNeedingPlanning.isEmpty {
                            programsSection
                        }
                        if !expiringContracts.isEmpty {
                            contractsSection
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(isChinese ? "需要关注" : "Attention")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label(isChinese ? "全部就绪" : "You're all set", systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        } description: {
            Text(isChinese
                 ? "未来两周内没有需要安排的课程、阶段或合同。"
                 : "Nothing needs your attention in the next two weeks.")
        }
    }

    // MARK: - Sessions sections (grouped by relative date)

    @ViewBuilder
    private var sessionsSections: some View {
        let groups = sessionsByRelativeDate()
        ForEach(groups, id: \.label) { group in
            Section {
                ForEach(group.sessions, id: \.id) { session in
                    Button {
                        dismiss()
                        onSelectSession(session)
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            dataManager.deleteSessionEvent(session)
                        } label: {
                            Label(isChinese ? "删除" : "Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            var updated = session
                            updated.status = .skipped
                            dataManager.updateSessionEvent(updated)
                        } label: {
                            Label(isChinese ? "跳过" : "Skip", systemImage: "forward.fill")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                HStack {
                    Text(group.label)
                    Spacer()
                    Text("\(group.sessions.count)")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            } footer: {
                if group == groups.first {
                    Text(isChinese
                         ? "这些课程没有训练内容。点按可立即编排。"
                         : "These sessions have no drills planned. Tap to plan now.")
                }
            }
        }
    }

    private func sessionRow(_ session: SessionEvent) -> some View {
        HStack(spacing: 12) {
            // Tinted glyph by session type — replaces the cryptic TRN prefix.
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(typeTint(session.sessionType).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: session.sessionType.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(typeTint(session.sessionType))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    FormatBadge(format: dataManager.sessionFormat(session), size: .mini)

                    Text(timeLine(for: session))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func timeLine(for session: SessionEvent) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: session.startTime)
        let hasTime = !(comps.hour == 0 && comps.minute == 0)

        if hasTime {
            return session.startTime.formatted(date: .omitted, time: .shortened)
        }
        return isChinese ? "时间待定" : "Time TBD"
    }

    private func typeTint(_ type: SessionType) -> Color {
        switch type {
        case .training:   return AppTheme.avatarBlue
        case .scrimmage:  return AppTheme.avatarOrange
        case .gamePrep:   return AppTheme.avatarPurple
        case .recovery:   return AppTheme.avatarGreen
        case .assessment: return AppTheme.amber
        }
    }

    private struct DateGroup: Equatable {
        let label: String
        let sessions: [SessionEvent]
        static func == (l: DateGroup, r: DateGroup) -> Bool { l.label == r.label }
    }

    private func sessionsByRelativeDate() -> [DateGroup] {
        let cal = Calendar.current
        let sorted = unplannedSessions.sorted { $0.date < $1.date }
        let weekStart = cal.startOfDay(for: Date())
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart

        var todays: [SessionEvent] = []
        var tomorrows: [SessionEvent] = []
        var thisWeek: [(label: String, sessions: [SessionEvent])] = []
        var later: [SessionEvent] = []

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = isChinese ? "M月d日 EEEE" : "EEEE, MMM d"
        weekdayFormatter.locale = Locale(identifier: isChinese ? "zh_CN" : "en_US")

        var bucketsByDay: [Date: [SessionEvent]] = [:]
        for s in sorted {
            if cal.isDateInToday(s.date) {
                todays.append(s)
            } else if cal.isDateInTomorrow(s.date) {
                tomorrows.append(s)
            } else if s.date < weekEnd {
                let day = cal.startOfDay(for: s.date)
                bucketsByDay[day, default: []].append(s)
            } else {
                later.append(s)
            }
        }

        for (day, sessions) in bucketsByDay.sorted(by: { $0.key < $1.key }) {
            thisWeek.append((label: weekdayFormatter.string(from: day), sessions: sessions))
        }

        var result: [DateGroup] = []
        if !todays.isEmpty {
            result.append(.init(label: isChinese ? "今天" : "Today", sessions: todays))
        }
        if !tomorrows.isEmpty {
            result.append(.init(label: isChinese ? "明天" : "Tomorrow", sessions: tomorrows))
        }
        for bucket in thisWeek {
            result.append(.init(label: bucket.label, sessions: bucket.sessions))
        }
        if !later.isEmpty {
            result.append(.init(label: isChinese ? "稍后" : "Later", sessions: later))
        }
        return result
    }

    // MARK: - Programs section

    private var programsSection: some View {
        Section {
            ForEach(programsNeedingPlanning, id: \.id) { program in
                Button {
                    dismiss()
                    onSelectProgram(program)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.avatarPurple.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.avatarPurple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(isChinese ? "尚未划分阶段" : "No phases set up yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(isChinese ? "训练计划" : "Programs")
        }
    }

    // MARK: - Contracts section

    private var contractsSection: some View {
        Section {
            ForEach(expiringContracts, id: \.contract.id) { item in
                Button {
                    dismiss()
                    onSelectStudent(item.student)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.warningColor.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.warningColor)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.student.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(remainingLine(for: item.contract))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(isChinese ? "即将到期合同" : "Expiring Contracts")
        }
    }

    private func remainingLine(for contract: Contract) -> String {
        let remaining = contract.bundleRedemptionsRemaining ?? 0
        if isChinese {
            return "剩余 \(remaining) 节课"
        }
        return "\(remaining) session\(remaining == 1 ? "" : "s") left"
    }
}

// MARK: - All Players Sheet
/// Today's players, in the same Apple-Health/Settings idiom as the rest of
/// the app — searchable inset-grouped list with an AgeBadge per row and the
/// next session date inline. Tapping pushes the unified `StudentDetailView`
/// directly inside the sheet's NavigationStack so the experience matches
/// the Students tab.
struct AllPlayersSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var envDataManager: DataManager
    let players: [Student]
    let dataManager: DataManager
    var onSelectStudent: (Student) -> Void

    @State private var searchText = ""

    private var filtered: [Student] {
        guard !searchText.isEmpty else { return players }
        return players.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.chineseName ?? "").localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No players today",
                            systemImage: "person.2.slash",
                            description: Text(searchText.isEmpty
                                              ? "Programs scheduled for today will surface their roster here."
                                              : "No matches.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(filtered) { student in
                            NavigationLink {
                                StudentDetailView(student: student)
                            } label: {
                                AllPlayersRow(student: student)
                            }
                        }
                    } header: {
                        Text("\(filtered.count) attending today")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(LocalizationManager.shared.currentLanguage == .chinese ? "今日学员" : "Today's Athletes")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Row
private struct AllPlayersRow: View {
    @EnvironmentObject var dataManager: DataManager
    let student: Student

    private var nextSessionToday: SessionEvent? {
        let cal = Calendar.current
        return dataManager.sessionEvents
            .filter { event in
                cal.isDateInToday(event.date)
                    && event.attendeeIds.contains(student.id)
                    && event.status != .cancelled
            }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private var enrolledProgram: Program? {
        dataManager.programs.first { $0.enrolledStudentIds.contains(student.id) }
    }

    private var ageGroupCode: String? { enrolledProgram?.ageGroup.rawValue }

    private var contractStatus: ContractStatus? {
        dataManager.currentContract(for: student.id)?.status
    }

    var body: some View {
        HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(student.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let chinese = student.chineseName, !chinese.isEmpty {
                        Text(chinese)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let age = student.age {
                        Text("· \(age)y")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    FormatBadge(format: dataManager.studentFormat(student), size: .mini)
                    if let code = ageGroupCode {
                        AgeBadge(shortName: code, tint: .accentColor, size: .xsmall)
                    }
                    if let session = nextSessionToday {
                        Text(session.startTime, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if let status = contractStatus {
                    statusPill(status)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusPill(_ status: ContractStatus) -> some View {
        let color: Color = {
            switch status {
            case .active: return .green
            case .pending: return .orange
            case .completed: return .blue
            case .expired: return .red
            case .cancelled: return .gray
            }
        }()
        Text(status.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Live Session Activity Card
/// Compact, engine-driven status card. Tappable — opens the live session
/// screen via a global notification handled by `MainTabView`.
struct LiveSessionActivityCard: View {
    @EnvironmentObject var dataManager: DataManager
    @ObservedObject private var engine = LiveSessionEngine.shared
    let session: SessionEvent

    private var program: Program? {
        session.programId.flatMap { programId in
            dataManager.programs.first { $0.id == programId }
        }
    }

    private var ageGroupLabel: String? { program?.ageGroup.rawValue }
    private var subtitleParts: [String] {
        var parts: [String] = []
        if let location = program?.locationName ?? session.location, !location.isEmpty {
            parts.append(location)
        }
        if let age = ageGroupLabel { parts.append(age) }
        return parts
    }
    private func formatTime(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openLiveSession, object: nil)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Top row: live pip + age badge + chevron
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.isPaused ? Color.secondary : Color.red)
                            .frame(width: 8, height: 8)
                            .symbolEffect(.pulse, options: .repeating, isActive: !engine.isPaused)
                        Text(engine.isPaused ? "PAUSED" : "LIVE")
                            .font(.caption2.weight(.bold))
                            .monospaced()
                            .foregroundStyle(engine.isPaused ? Color.secondary : Color.red)
                    }
                    if let age = ageGroupLabel {
                        AgeBadge(shortName: age, tint: .accentColor, size: .xsmall)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                // Title + secondary line (location · age)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !subtitleParts.isEmpty {
                        Text(subtitleParts.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Drill / time line
                HStack(spacing: 8) {
                    if let current = engine.currentDrill {
                        Image(systemName: "figure.basketball")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(current.drill.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("\(engine.currentDrillIndex + 1) of \(engine.drills.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("Session complete")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatTime(engine.sessionRemainingSeconds))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                }

                // Progress bar
                ProgressView(value: engine.sessionProgress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: engine.currentDrillIndex)
    }
}

// MARK: - Preview
#Preview {
    FlightyActionableDashboard()
        .environmentObject(DataManager.shared)
}
