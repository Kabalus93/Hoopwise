import SwiftUI

// MARK: - Create Game Sheet
/// Native-Form layout for creating an in-session scrimmage game.
/// One screen, one Form, all decisions visible at once. Inline validation so
/// the Create button is only enabled when the configuration will actually work.
struct CreateGameSheet: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss

    @Binding var session: SessionEvent
    let enrolledStudents: [Student]
    let programColor: Color
    let onSave: () -> Void

    // Configuration
    @State private var gameType: SessionGameType = .twoTeam
    @State private var durationMinutes: Int = 5
    @State private var showOnlyPresent: Bool = true
    /// Tracks whether the coach has manually edited the duration. Once true
    /// we stop auto-snapping the duration when team count changes —
    /// otherwise their custom value gets clobbered every time they add a team.
    @State private var durationManuallyEdited: Bool = false

    // Team mode state
    @State private var teams: [GameTeam] = []
    @State private var unassignedIds: Set<UUID> = []

    // Battle royal state
    @State private var battleRoyalIds: Set<UUID> = []

    // Optional reuse of last game's setup
    @State private var hasPreviousConfig: Bool = false
    @State private var usePreviousConfig: Bool = false

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    // MARK: - Derived state

    private var presentStudents: [Student] {
        enrolledStudents.filter { session.actualAttendeeIds.contains($0.id) }
    }

    private var availableStudents: [Student] {
        showOnlyPresent ? presentStudents : enrolledStudents
    }

    private var presentCount: Int { presentStudents.count }
    private var totalCount: Int { enrolledStudents.count }

    private var isBattleRoyal: Bool { gameType.isIndividual }

    private var minTeams: Int { gameType.requiredTeams }
    private var maxTeams: Int { gameType == .twoTeam ? 6 : 4 }

    /// Reasons we can't create the game yet, in priority order.
    private var blockingReason: String? {
        if isBattleRoyal {
            if battleRoyalIds.count < 2 {
                return isChinese
                    ? "至少选择 2 名球员"
                    : "Pick at least 2 players"
            }
            return nil
        }
        if teams.count < minTeams {
            return isChinese
                ? "至少需要 \(minTeams) 支队伍"
                : "Need at least \(minTeams) teams"
        }
        if let empty = teams.first(where: { $0.playerIds.isEmpty }) {
            let teamName = GameTeam.localizedColorName(empty.name)
            return isChinese
                ? "\(teamName)还没有球员"
                : "\(teamName) has no players yet"
        }
        return nil
    }

    private var canCreate: Bool { blockingReason == nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                gameTypeSection
                durationSection
                playersFilterSection
                if isBattleRoyal {
                    battleRoyalSection
                } else {
                    if hasPreviousConfig { previousConfigSection }
                    teamsSection
                    if !unassignedIds.isEmpty { unassignedSection }
                }
                if let reason = blockingReason {
                    Section {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(isChinese ? "创建比赛" : "Create Game")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "创建" : "Create") { createGame() }
                        .fontWeight(.semibold)
                        .disabled(!canCreate)
                }
            }
            .onAppear {
                loadInitialState()
                if !durationManuallyEdited { durationMinutes = defaultDurationForLayout }
            }
            .onChange(of: gameType) { _, newType in
                adjustForGameType(newType)
                if !durationManuallyEdited { durationMinutes = defaultDurationForLayout }
            }
            .onChange(of: teams.count) { _, _ in
                if !durationManuallyEdited { durationMinutes = defaultDurationForLayout }
            }
            .onChange(of: showOnlyPresent) { _, _ in refreshUnassigned() }
        }
    }

    // MARK: - Sections

    private var gameTypeSection: some View {
        Section {
            Picker("Game Type", selection: $gameType) {
                ForEach(SessionGameType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            HStack(spacing: 8) {
                Image(systemName: gameType.icon)
                    .foregroundStyle(.secondary)
                Text(gameType.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(isChinese ? "比赛模式" : "Format")
        }
    }

    private var durationSection: some View {
        Section {
            // Quick presets — tuned for the team count. With 2 teams the
            // standard 5-minute scrimmage gives both sides enough touches;
            // 3+ teams rotate faster (3 min) so everyone plays sooner.
            HStack(spacing: 8) {
                ForEach(durationPresets, id: \.self) { mins in
                    presetChip(minutes: mins)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            Stepper(value: $durationMinutes, in: 1...120, step: 1) {
                HStack {
                    Text(isChinese ? "时长" : "Duration")
                    Spacer()
                    Text("\(durationMinutes) \(isChinese ? "分钟" : "min")")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(durationMinutes)))
                }
            }
            .sensoryFeedback(.increase, trigger: durationMinutes)
            .onChange(of: durationMinutes) { _, _ in durationManuallyEdited = true }
        } footer: {
            Text(presetFooter)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Default minutes for the current team layout. Tuned to roster sizes
    /// the user actually runs:
    /// - 2 teams: 5 min — long enough for momentum, short enough to rotate
    /// - 3+ teams: 3 min — more rounds, less court hogging
    /// - Battle royal: 5 min — same rationale as 2 teams
    private var defaultDurationForLayout: Int {
        if isBattleRoyal { return 5 }
        return teams.count >= 3 ? 3 : 5
    }

    private var durationPresets: [Int] {
        if isBattleRoyal { return [3, 5, 8, 10] }
        return teams.count >= 3 ? [2, 3, 4, 5] : [3, 5, 8, 10]
    }

    private var presetFooter: String {
        if isBattleRoyal {
            return isChinese
                ? "大乱斗默认 5 分钟。可点上方按钮快速切换或用滑杆微调。"
                : "Battle royal defaults to 5 min. Tap a preset or use the stepper for custom."
        }
        return teams.count >= 3
            ? (isChinese
               ? "3 队及以上默认 3 分钟，让每个人更快上场。"
               : "3+ teams default to 3 min so everyone rotates in sooner.")
            : (isChinese
               ? "2 队默认 5 分钟。"
               : "2 teams default to 5 min.")
    }

    private func presetChip(minutes: Int) -> some View {
        let isSelected = durationMinutes == minutes
        return Button {
            durationMinutes = minutes
            durationManuallyEdited = true
        } label: {
            Text("\(minutes) \(isChinese ? "分" : "min")")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private var playersFilterSection: some View {
        Section {
            Picker(isChinese ? "球员池" : "Player Pool", selection: $showOnlyPresent) {
                Text("\(isChinese ? "已到场" : "Present") (\(presentCount))").tag(true)
                Text("\(isChinese ? "全部" : "All") (\(totalCount))").tag(false)
            }
            .pickerStyle(.segmented)

            if showOnlyPresent && presentCount == 0 {
                Button {
                    showOnlyPresent = false
                } label: {
                    Label(
                        isChinese ? "没有人到场，使用全部球员" : "No present players — use full roster",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(isChinese ? "球员池" : "Players")
        } footer: {
            if isBattleRoyal {
                Text(isChinese
                     ? "在大乱斗里，每个人为自己得分。"
                     : "In Battle Royal, every player scores for themselves.")
            } else {
                Text(isChinese
                     ? "切换到“到场”只显示出席的球员。"
                     : "Toggle Present to limit team-building to attendees.")
            }
        }
    }

    private var previousConfigSection: some View {
        Section {
            Toggle(isOn: $usePreviousConfig.animation()) {
                Label(isChinese ? "沿用上次分队" : "Reuse Last Game's Teams",
                      systemImage: "clock.arrow.circlepath")
            }
            .onChange(of: usePreviousConfig) { _, useIt in
                if useIt, let last = session.games.last(where: { !$0.gameType.isIndividual }) {
                    loadPreviousConfiguration(from: last)
                } else {
                    setupDefaultTeams()
                    refreshUnassigned()
                    distributeUnassignedBalanced()
                }
            }
        }
    }

    // MARK: - Teams

    private var teamsSection: some View {
        Section {
            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                teamRow(index: index, team: team)
            }

            if teams.count < maxTeams {
                Button {
                    addTeam()
                } label: {
                    Label(isChinese ? "添加队伍" : "Add Team", systemImage: "plus")
                }
            }
        } header: {
            HStack {
                Text(isChinese ? "队伍" : "Teams")
                Spacer()
                Text("\(teams.count) / \(maxTeams)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(isChinese
                 ? "点击下方未分配球员的队伍颜色即可分配。"
                 : "Tap an unassigned player below, then a team color to assign them.")
        }
    }

    private func teamRow(index: Int, team: GameTeam) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                colorPickerMenu(for: index, currentHex: team.colorHex)

                VStack(alignment: .leading, spacing: 1) {
                    Text(GameTeam.localizedColorName(team.name))
                        .font(.body.weight(.medium))
                    Text("^[\(team.playerIds.count) player](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if teams.count > minTeams {
                    Button(role: .destructive) {
                        removeTeam(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !team.playerIds.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(team.playerIds, id: \.self) { pid in
                        if let s = enrolledStudents.first(where: { $0.id == pid }) {
                            Button {
                                teams[index].playerIds.removeAll { $0 == pid }
                                unassignedIds.insert(pid)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(firstName(of: s))
                                        .font(.caption.weight(.medium))
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(Color(hex: team.colorHex).opacity(0.18))
                                )
                                .overlay(
                                    Capsule().strokeBorder(Color(hex: team.colorHex).opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func colorPickerMenu(for index: Int, currentHex: String) -> some View {
        let usedHexes = Set(teams.enumerated().compactMap { $0.offset == index ? nil : $0.element.colorHex })
        return Menu {
            ForEach(GameTeam.presetColors, id: \.hex) { preset in
                let taken = usedHexes.contains(preset.hex)
                Button {
                    teams[index].colorHex = preset.hex
                    teams[index].name = preset.name
                } label: {
                    HStack {
                        Circle().fill(Color(hex: preset.hex)).frame(width: 14, height: 14)
                        Text(GameTeam.localizedColorName(preset.name))
                        if taken {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(taken)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: currentHex))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
        }
    }

    // MARK: - Unassigned

    private var unassignedSection: some View {
        Section {
            ForEach(Array(unassignedIds), id: \.self) { pid in
                if let s = enrolledStudents.first(where: { $0.id == pid }) {
                    unassignedRow(student: s)
                }
            }

            if !teams.isEmpty {
                Menu {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                        Button {
                            assignAllUnassigned(to: index)
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
                                Text(isChinese
                                     ? "全部分配到\(GameTeam.localizedColorName(team.name))"
                                     : "Assign all to \(GameTeam.localizedColorName(team.name))")
                            }
                        }
                    }

                    if teams.count >= 2 {
                        Divider()
                        Button {
                            distributeUnassignedBalanced()
                        } label: {
                            Label(isChinese ? "按能力均衡分配" : "Balance by skill", systemImage: "scale.3d")
                        }
                        Button {
                            distributeUnassignedEvenly()
                        } label: {
                            Label(isChinese ? "随机均匀分配" : "Distribute randomly", systemImage: "shuffle")
                        }
                    }
                } label: {
                    Label(isChinese ? "快速分配…" : "Quick assign…", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            HStack {
                Text(isChinese ? "未分配" : "Unassigned")
                Spacer()
                Text("\(unassignedIds.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func unassignedRow(student: Student) -> some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 28)
            Text(student.primaryDisplayName)
                .font(.body)
            Spacer()
            Menu {
                ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                    Button {
                        assign(playerId: student.id, toTeamAt: index)
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: team.colorHex)).frame(width: 12, height: 12)
                            Text(GameTeam.localizedColorName(team.name))
                        }
                    }
                }
            } label: {
                Label(isChinese ? "分配" : "Assign", systemImage: "person.badge.plus")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: - Battle Royal

    private var battleRoyalSection: some View {
        Section {
            HStack {
                Button {
                    battleRoyalIds = Set(availableStudents.map(\.id))
                } label: {
                    Text(isChinese ? "全选" : "Select All")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    battleRoyalIds.removeAll()
                } label: {
                    Text(isChinese ? "全部取消" : "Deselect")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(battleRoyalIds.isEmpty)

                Spacer()

                Text("\(battleRoyalIds.count)/\(availableStudents.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(availableStudents) { s in
                Button {
                    if battleRoyalIds.contains(s.id) { battleRoyalIds.remove(s.id) }
                    else { battleRoyalIds.insert(s.id) }
                } label: {
                    HStack(spacing: 10) {
                        StudentAvatarView(student: s, size: 28)
                        Text(s.primaryDisplayName).foregroundStyle(.primary)
                        Spacer()
                        if battleRoyalIds.contains(s.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: battleRoyalIds.contains(s.id))
            }
        } header: {
            Text(isChinese ? "参赛球员" : "Participants")
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        if isBattleRoyal {
            battleRoyalIds = Set(availableStudents.map(\.id))
            return
        }

        if let last = session.games.last(where: { !$0.gameType.isIndividual }) {
            hasPreviousConfig = true
            usePreviousConfig = true
            loadPreviousConfiguration(from: last)
        } else {
            setupDefaultTeams()
            refreshUnassigned()
            // Pre-fill skill-balanced teams so the coach lands on a fair
            // setup by default. They can still tap "Quick assign…" or
            // drag players if they want to override.
            distributeUnassignedBalanced()
        }
    }

    private func adjustForGameType(_ newType: SessionGameType) {
        if newType.isIndividual {
            battleRoyalIds = Set(availableStudents.map(\.id))
            return
        }
        // Switching back to a team mode after Battle Royal
        if teams.isEmpty { setupDefaultTeams() }
        while teams.count < newType.requiredTeams { addTeam() }
        refreshUnassigned()
    }

    private func setupDefaultTeams() {
        teams = (0..<gameType.requiredTeams).map { i in
            let preset = GameTeam.presetColors[i % GameTeam.presetColors.count]
            return GameTeam(name: preset.name, colorHex: preset.hex)
        }
    }

    private func addTeam() {
        let usedHexes = Set(teams.map(\.colorHex))
        if let next = GameTeam.presetColors.first(where: { !usedHexes.contains($0.hex) }) {
            teams.append(GameTeam(name: next.name, colorHex: next.hex))
        }
    }

    private func removeTeam(at index: Int) {
        unassignedIds.formUnion(teams[index].playerIds)
        teams.remove(at: index)
    }

    private func refreshUnassigned() {
        let pool = Set(availableStudents.map(\.id))
        // Drop any assignments that are no longer in the pool, push them out as unassigned-but-hidden:
        // simpler approach — keep team assignments stable but unassignedIds only shows what's in pool.
        for i in teams.indices {
            teams[i].playerIds = teams[i].playerIds.filter { pool.contains($0) }
        }
        let assigned = Set(teams.flatMap(\.playerIds))
        unassignedIds = pool.subtracting(assigned)
    }

    private func loadPreviousConfiguration(from game: SessionGame) {
        gameType = game.gameType
        durationMinutes = game.durationMinutes
        let pool = Set(availableStudents.map(\.id))
        teams = game.teams.map { team in
            GameTeam(
                id: UUID(),
                name: team.name,
                colorHex: team.colorHex,
                playerIds: team.playerIds.filter { pool.contains($0) }
            )
        }
        let assigned = Set(teams.flatMap(\.playerIds))
        unassignedIds = pool.subtracting(assigned)
    }

    private func assign(playerId: UUID, toTeamAt index: Int) {
        guard teams.indices.contains(index) else { return }
        unassignedIds.remove(playerId)
        if !teams[index].playerIds.contains(playerId) {
            teams[index].playerIds.append(playerId)
        }
    }

    private func assignAllUnassigned(to teamIndex: Int) {
        guard teams.indices.contains(teamIndex) else { return }
        for pid in unassignedIds {
            if !teams[teamIndex].playerIds.contains(pid) {
                teams[teamIndex].playerIds.append(pid)
            }
        }
        unassignedIds.removeAll()
    }

    /// Round-robin shuffle — kept as an option for the "I just want random
    /// teams" case (e.g. mixing kids who always pair up). Default is the
    /// skill-balanced version below.
    private func distributeUnassignedEvenly() {
        guard !teams.isEmpty else { return }
        let shuffled = Array(unassignedIds).shuffled()
        for (i, pid) in shuffled.enumerated() {
            let teamIdx = i % teams.count
            teams[teamIdx].playerIds.append(pid)
        }
        unassignedIds.removeAll()
    }

    /// Skill-balanced auto-assign using a snake-draft over the player skill
    /// ratings. The strongest player goes to the team with the lowest
    /// current total, then the next, and so on. Teams end up as close in
    /// total skill as the roster allows.
    ///
    /// Players without an evaluation default to a neutral 5.0 — they
    /// don't tank or boost a team, just get distributed.
    private func distributeUnassignedBalanced() {
        guard !teams.isEmpty else { return }

        // Existing assignments contribute to each team's running rating
        // so adding more players continues the balance instead of
        // re-balancing from scratch.
        var ratingByTeam: [Int: Double] = Dictionary(
            uniqueKeysWithValues: teams.indices.map { ($0, totalSkill(of: teams[$0].playerIds)) }
        )

        // Sort unassigned by skill descending — strongest go first so the
        // weakest team always picks up the next-best to catch up.
        let sortedIds = unassignedIds.sorted { lhs, rhs in
            playerSkill(lhs) > playerSkill(rhs)
        }

        for pid in sortedIds {
            // Pick the team with the lowest current rating. Tiebreak by the
            // smaller roster size — never pile onto a team that's already
            // numerically larger.
            guard let pick = ratingByTeam.min(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return teams[lhs.key].playerIds.count < teams[rhs.key].playerIds.count
            }) else { continue }
            teams[pick.key].playerIds.append(pid)
            ratingByTeam[pick.key, default: 0] += playerSkill(pid)
        }
        unassignedIds.removeAll()
    }

    /// Look up the overall skill rating (1–10) for a student. 5.0 fallback
    /// when no evaluation has been recorded — keeps dormant players neutral.
    private func playerSkill(_ studentId: UUID) -> Double {
        if let player = dataManager.players.first(where: { $0.studentId == studentId }) {
            return player.skills.overallRating
        }
        return 5.0
    }

    private func totalSkill(of ids: [UUID]) -> Double {
        ids.reduce(0) { $0 + playerSkill($1) }
    }

    private func createGame() {
        var newGame: SessionGame
        if isBattleRoyal {
            newGame = SessionGame(
                sessionId: session.id,
                gameNumber: session.games.count + 1,
                gameType: gameType,
                teams: [],
                durationMinutes: durationMinutes,
                status: .ready
            )
            for pid in battleRoyalIds {
                newGame.playerStats.append(
                    SessionPlayerStats(playerId: pid, gameId: newGame.id, teamId: pid)
                )
            }
        } else {
            newGame = SessionGame(
                sessionId: session.id,
                gameNumber: session.games.count + 1,
                gameType: gameType,
                teams: teams,
                durationMinutes: durationMinutes,
                status: .ready
            )
        }
        // Optimistic local append for the binding-driven UI, then a
        // field-level write so a stale parent `@State session` can no
        // longer overwrite siblings (games, photo, attendance) on the
        // canonical SDSessionEvent.
        session.games.append(newGame)
        dataManager.appendSessionGame(toSessionId: session.id, game: newGame)
        dismiss()
    }

    // MARK: - Helpers

    private func firstName(of student: Student) -> String {
        student.name.components(separatedBy: " ").first ?? student.name
    }
}
