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
    /// What a basket is worth in this game. Remembered between games — the
    /// coach sets it for what the session is working on.
    @AppStorage(SessionGame.basketValueDefaultsKey) private var basketValue: Int = 2
    /// Players a side (2v2 … 5v5) — remembered between games.
    @AppStorage("game.playersPerSide") private var playersPerSide: Int = 5
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    /// The slot (or "roster") a drag is over, for its highlight.
    @State private var dropTargetKey: String?
    /// The player whose options are open (a tap on him).
    @State private var optionsFor: UUID?
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
            ScrollView {
              VStack(alignment: .leading, spacing: 22) {
                gameTypeSection
                durationSection
                basketValueSection
                playersFilterSection
                if isBattleRoyal {
                    battleRoyalSection
                } else {
                    if hasPreviousConfig { previousConfigSection }
                    teamsSection
                    unassignedSection
                }
                if let reason = blockingReason {
                    SetupCard {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.subheadline)
                    }
                }
              }
              .padding(.horizontal, 20)
              .padding(.vertical, 16)
              .frame(maxWidth: 860)
              .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
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
            .onChange(of: playersPerSide) { _, _ in normalizeStarters() }
        }
    }

    // MARK: - Sections

    private var gameTypeSection: some View {
        SetupCard {
            Picker("Game Type", selection: $gameType) {
                ForEach(SessionGameType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !isBattleRoyal {
                Picker(isChinese ? "人数" : "Players a side", selection: $playersPerSide) {
                    ForEach(2...5, id: \.self) { n in Text("\(n)v\(n)").tag(n) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup.format")
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

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
        SetupCard {
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

    private var basketValueSection: some View {
        SetupCard {
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { value in
                    let isSelected = basketValue == value
                    Button {
                        basketValue = value
                    } label: {
                        Text(isChinese ? "\(value) 分" : "\(value) pt\(value == 1 ? "" : "s")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.accentColor : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("setup.basket.\(value)")
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .sensoryFeedback(.selection, trigger: basketValue)
        } header: {
            Text(isChinese ? "每球标准分值" : "Standard basket value")
        } footer: {
            Text(isChinese
                 ? "比赛中点击球员即记这个分值；其他分值在比赛页上方随时可选。"
                 : "Tapping a player in the game scores this. The other values stay one tap away above the players.")
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
        SetupCard {
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
        SetupCard {
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
    //
    // TEAMS AS SLOTS (20 Nov 2026, Luther): each team is a row of photo
    // slots with names — the first `playersPerSide` are STARTERS, then the
    // bench. Everything moves by drag and drop (onto a slot = take that
    // slot, swapping with whoever was there; onto the roster = unassign),
    // and a tap on any player shows the same moves as a menu.

    private var slotSize: CGFloat { sizeClass == .regular ? 60 : 50 }

    private var teamsSection: some View {
        SetupCard {
            ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                if index > 0 { Divider() }
                teamRow(index: index, team: team)
            }

            if teams.count < maxTeams {
                Divider()
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
                 ? "拖动球员到位置上，或点一下球员选择去向。前 \(playersPerSide) 个位置是首发。"
                 : "Drag players onto a slot, or tap one for options. The first \(playersPerSide) slots are the starters.")
        }
    }

    private func teamRow(index: Int, team: GameTeam) -> some View {
        let color = team.displayColor(for: colorScheme)
        let sc = starterCount(index)
        let starters = Array(team.playerIds.prefix(sc))
        let bench = Array(team.playerIds.dropFirst(sc))
        let benchSlots = max(2, bench.count + 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                colorPickerMenu(for: index, currentHex: team.colorHex)
                VStack(alignment: .leading, spacing: 1) {
                    Text(GameTeam.localizedColorName(team.name))
                        .font(.body.weight(.semibold))
                    Text(isChinese
                         ? "首发 \(starters.count)/\(playersPerSide) · 替补 \(bench.count)"
                         : "\(starters.count)/\(playersPerSide) starters · \(bench.count) bench")
                        .font(.subheadline)
                        .foregroundStyle(starters.count < playersPerSide ? .orange : .secondary)
                        .monospacedDigit()
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

            FlowLayout(spacing: 8) {
                ForEach(0..<playersPerSide, id: \.self) { i in
                    slot(teamIndex: index, position: i, playerId: i < starters.count ? starters[i] : nil,
                         color: color, starter: true)
                }
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: slotSize)
                    .padding(.horizontal, 2)
                ForEach(0..<benchSlots, id: \.self) { j in
                    slot(teamIndex: index, position: playersPerSide + j,
                         playerId: j < bench.count ? bench[j] : nil, color: color, starter: false)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.team.\(index)")
    }

    /// One slot of a team: a player (photo + name, tap = options, drag to
    /// move) or an empty place (drop target).
    @ViewBuilder
    private func slot(teamIndex: Int, position: Int, playerId: UUID?, color: Color, starter: Bool) -> some View {
        let key = "\(teamIndex).\(position)"
        let targeted = dropTargetKey == key
        Group {
            if let pid = playerId, let s = student(pid) {
                Button { optionsFor = pid } label: {
                    playerBubble(s, ring: color, solidRing: starter, highlighted: targeted)
                }
                .buttonStyle(.plain)
                .popover(isPresented: optionsBinding(pid)) { optionsPopover(pid: pid, currentTeam: teamIndex) }
                .draggable(pid.uuidString) { playerBubble(s, ring: color, solidRing: true, highlighted: false) }
                .accessibilityIdentifier("setup.slot.\(key)")
            } else {
                emptySlot(starter: starter, color: color, highlighted: targeted)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("setup.slot.\(key)")
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let pid = UUID(uuidString: raw) else { return false }
            withAnimation(.snappy) { place(pid, team: teamIndex, position: position) }
            return true
        } isTargeted: { on in
            if on { dropTargetKey = key } else if dropTargetKey == key { dropTargetKey = nil }
        }
    }

    private func playerBubble(_ s: Student, ring: Color?, solidRing: Bool, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            StudentAvatarView(student: s, size: slotSize)
                .overlay {
                    if let ring {
                        Circle().strokeBorder(ring, style: StrokeStyle(lineWidth: 2.5, dash: solidRing ? [] : [4, 3]))
                            .padding(-3)
                    }
                }
                .overlay {
                    if highlighted { Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-6) }
                }
            Text(s.primaryDisplayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .frame(width: slotSize + 14, height: 28, alignment: .top)
        }
        .contentShape(Rectangle())
    }

    private func emptySlot(starter: Bool, color: Color, highlighted: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .strokeBorder(highlighted ? Color.accentColor : color.opacity(starter ? 0.7 : 0.4),
                              style: StrokeStyle(lineWidth: highlighted ? 3 : 1.5, dash: [5, 4]))
                .background(Circle().fill(highlighted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
                .frame(width: slotSize, height: slotSize)
                .overlay {
                    Image(systemName: "plus").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            Text(starter ? (isChinese ? "首发" : "Starter") : (isChinese ? "替补" : "Bench"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: slotSize + 14, height: 28, alignment: .top)
        }
        .contentShape(Rectangle())
    }

    /// The moves a tap on a player offers.
    @ViewBuilder
    private func playerMenu(pid: UUID, currentTeam: Int?) -> some View {
        if let current = currentTeam, let at = teams[current].playerIds.firstIndex(of: pid) {
            if at >= starterCount(current) {
                Button { act { makeStarter(pid, team: current) } } label: {
                    Label(isChinese ? "改为首发" : "Make a starter", systemImage: "arrow.up.circle")
                }
            } else {
                Button { act { place(pid, team: current, position: playersPerSide + benchCount(current)) } } label: {
                    Label(isChinese ? "移到替补" : "Move to the bench", systemImage: "arrow.down.circle")
                }
            }
        }
        ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
            if index != currentTeam {
                Button { act { addToTeam(pid, index) } } label: {
                    Label {
                        Text(isChinese ? "到\(GameTeam.localizedColorName(team.name))" : "To \(GameTeam.localizedColorName(team.name))")
                    } icon: {
                        Circle().fill(Color(hex: team.colorHex)).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                    }
                }
            }
        }
        if currentTeam != nil {
            Divider()
            Button(role: .destructive) { act { unassign(pid) } } label: {
                Label(isChinese ? "移回名单" : "Back to the roster", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private func optionsBinding(_ pid: UUID) -> Binding<Bool> {
        Binding(get: { optionsFor == pid }, set: { if !$0, optionsFor == pid { optionsFor = nil } })
    }

    private func act(_ change: () -> Void) {
        optionsFor = nil
        withAnimation(.snappy) { change() }
    }

    private func optionsPopover(pid: UUID, currentTeam: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let s = student(pid) {
                Text(s.primaryDisplayName)
                    .font(.headline)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            }
            playerMenu(pid: pid, currentTeam: currentTeam)
        }
        .buttonStyle(OptionRowStyle())
        .padding(.bottom, 8)
        .frame(minWidth: 240, alignment: .leading)
        .presentationCompactAdaptation(.popover)
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

    // MARK: - Roster (unassigned)

    private var rosterIds: [UUID] {
        availableStudents.map(\.id).filter { unassignedIds.contains($0) }
    }

    private var unassignedSection: some View {
        SetupCard {
            if rosterIds.isEmpty {
                Text(isChinese ? "所有人都已分队。把球员拖到这里移出队伍。" : "Everyone has a team. Drag a player here to take them off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: slotSize + 22), spacing: 8)], spacing: 12) {
                    ForEach(rosterIds, id: \.self) { pid in
                        if let s = student(pid) {
                            Button { optionsFor = pid } label: {
                                playerBubble(s, ring: nil, solidRing: true, highlighted: false)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: optionsBinding(pid)) { optionsPopover(pid: pid, currentTeam: nil) }
                            .draggable(pid.uuidString) { playerBubble(s, ring: nil, solidRing: true, highlighted: false) }
                            .accessibilityIdentifier("setup.roster.player")
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            if !teams.isEmpty && !rosterIds.isEmpty {
                Menu {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                        Button {
                            assignAllUnassigned(to: index)
                        } label: {
                            Text(isChinese
                                 ? "全部分配到\(GameTeam.localizedColorName(team.name))"
                                 : "Assign all to \(GameTeam.localizedColorName(team.name))")
                        }
                    }
                    if teams.count >= 2 {
                        Divider()
                        Button { distributeUnassignedBalanced() } label: {
                            Label(isChinese ? "按能力均衡分配" : "Balance by skill", systemImage: "scale.3d")
                        }
                        Button { distributeUnassignedEvenly() } label: {
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
                Text(isChinese ? "名单" : "Roster")
                Spacer()
                Text("\(rosterIds.count)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .overlay {
            if dropTargetKey == "roster" {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let pid = UUID(uuidString: raw) else { return false }
            withAnimation(.snappy) { unassign(pid) }
            return true
        } isTargeted: { on in
            if on { dropTargetKey = "roster" } else if dropTargetKey == "roster" { dropTargetKey = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.roster")
    }

    // MARK: - Moving players

    private func student(_ id: UUID) -> Student? {
        enrolledStudents.first { $0.id == id }
    }

    /// Bench → starters: the first open starter place, else swap with the
    /// last starter.
    private func makeStarter(_ pid: UUID, team: Int) {
        normalizeStarters()
        let n = starterCount(team)
        place(pid, team: team, position: n < playersPerSide ? n : playersPerSide - 1)
    }

    /// Put a player at a slot. Onto someone: they swap places (the other
    /// goes where the dragged one came from — another slot, another team or
    /// the roster). Onto an empty starter slot: he joins the starters; onto
    /// an empty bench slot: the end of the bench.
    private func place(_ pid: UUID, team: Int, position: Int) {
        guard teams.indices.contains(team) else { return }
        normalizeStarters()
        let sc = starterCount(team)
        let ids = teams[team].playerIds
        let occupant: UUID?
        if position < playersPerSide {
            occupant = position < sc ? ids[position] : nil
        } else {
            let b = position - playersPerSide
            occupant = sc + b < ids.count ? ids[sc + b] : nil
        }
        if occupant == pid { return }

        var from: (team: Int, index: Int)? = nil
        for t in teams.indices {
            if let i = teams[t].playerIds.firstIndex(of: pid) { from = (t, i) }
        }

        if let occupant, let at = teams[team].playerIds.firstIndex(of: occupant) {
            if let from {
                teams[from.team].playerIds[from.index] = occupant
            } else {
                unassignedIds.insert(occupant)
            }
            teams[team].playerIds[at] = pid
            unassignedIds.remove(pid)
            return
        }

        // An empty slot.
        if let from {
            if from.index < starterCount(from.team) { teams[from.team].starters = starterCount(from.team) - 1 }
            teams[from.team].playerIds.remove(at: from.index)
        }
        unassignedIds.remove(pid)
        if position < playersPerSide {
            let n = starterCount(team)
            teams[team].playerIds.insert(pid, at: n)
            teams[team].starters = n + 1
        } else {
            teams[team].playerIds.append(pid)
        }
    }

    /// Onto a team by a menu or a quick assign: a free starter place first,
    /// else the end of the bench.
    private func addToTeam(_ pid: UUID, _ team: Int) {
        let n = starterCount(team)
        place(pid, team: team, position: n < playersPerSide ? n : playersPerSide + benchCount(team))
    }

    private func starterCount(_ team: Int) -> Int {
        let t = teams[team]
        return min(t.starters ?? t.playerIds.count, playersPerSide, t.playerIds.count)
    }

    private func benchCount(_ team: Int) -> Int {
        teams[team].playerIds.count - starterCount(team)
    }

    /// Every team's starter count written down and within the format.
    private func normalizeStarters() {
        for t in teams.indices { teams[t].starters = starterCount(t) }
    }

    private func unassign(_ pid: UUID) {
        for t in teams.indices { teams[t].playerIds.removeAll { $0 == pid } }
        unassignedIds.insert(pid)
    }

    // MARK: - Battle Royal

    private var battleRoyalSection: some View {
        SetupCard {
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
        basketValue = game.basketValue
        if let n = game.playersPerSide { playersPerSide = n }
        let pool = Set(availableStudents.map(\.id))
        teams = game.teams.map { team in
            GameTeam(
                id: UUID(),
                name: team.name,
                colorHex: team.colorHex,
                playerIds: team.playerIds.filter { pool.contains($0) }
            )
        }
        for i in teams.indices { teams[i].starters = game.teams[i].starters }
        normalizeStarters()
        let assigned = Set(teams.flatMap(\.playerIds))
        unassignedIds = pool.subtracting(assigned)
    }

    private func assign(playerId: UUID, toTeamAt index: Int) {
        guard teams.indices.contains(index) else { return }
        addToTeam(playerId, index)
    }

    private func assignAllUnassigned(to teamIndex: Int) {
        guard teams.indices.contains(teamIndex) else { return }
        for pid in unassignedIds { addToTeam(pid, teamIndex) }
    }

    /// Round-robin shuffle — kept as an option for the "I just want random
    /// teams" case (e.g. mixing kids who always pair up). Default is the
    /// skill-balanced version below.
    private func distributeUnassignedEvenly() {
        guard !teams.isEmpty else { return }
        let shuffled = Array(unassignedIds).shuffled()
        for (i, pid) in shuffled.enumerated() {
            addToTeam(pid, i % teams.count)
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
            addToTeam(pid, pick.key)
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
                basketValue: basketValue,
                status: .ready
            )
            for pid in battleRoyalIds {
                newGame.playerStats.append(
                    SessionPlayerStats(playerId: pid, gameId: newGame.id, teamId: pid)
                )
            }
        } else {
            normalizeStarters()
            newGame = SessionGame(
                sessionId: session.id,
                gameNumber: session.games.count + 1,
                gameType: gameType,
                teams: teams,
                durationMinutes: durationMinutes,
                basketValue: basketValue,
                status: .ready
            )
            newGame.playersPerSide = playersPerSide
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

/// A row in a player's options popover.
private struct OptionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
    }
}

/// A grouped card with a header and footer — the setup page's sections.
/// (Not a Form: inside a List, iOS drags the whole ROW, so a player could
/// not be dragged on his own.)
private struct SetupCard<Content: View, Header: View, Footer: View>: View {
    let content: Content
    let header: Header
    let footer: Footer

    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.content = content(); self.header = header(); self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }
}

extension SetupCard where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyView() })
    }
}

extension SetupCard where Header == EmptyView {
    init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyView() }, footer: footer)
    }
}

extension SetupCard where Header == EmptyView, Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}
