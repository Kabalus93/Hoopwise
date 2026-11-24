import SwiftUI
import Combine

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
    /// The player being carried (in-app drag, 21 Nov 2026 — the system drag
    /// and drop crashed on the court) and where the finger is, in the
    /// page's content space.
    @State private var carrying: (pid: UUID, at: CGPoint)?
    /// Every drop target's frame in the content space: "t.p" slots, "team.t"
    /// rows, "roster".
    @State private var targetFrames: [String: CGRect] = [:]
    /// The visible part of the page, for scrolling while carrying.
    @State private var visibleRect: CGRect = .zero
    @State private var scrollPosition = ScrollPosition()
    /// How far the page can scroll (content height − visible height).
    @State private var maxScroll: CGFloat = 0
    /// The hold began on no player: ignore the rest of this gesture.
    @State private var carryMissed = false
    /// The page's scroll view on screen.
    @State private var scrollFrame: CGRect = .zero
    @State private var liftTick = 0
    /// True while a carry gesture is under way; going false with a player
    /// still carried means the gesture was cancelled — put it back.
    @GestureState private var carryGestureActive = false
    /// When a carry last ended — the Button under it must not open options.
    @State private var carryEndedAt = Date.distantPast
    @State private var dropTick = 0
    private let edgeTimer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    static let space = "createGame.content"
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
                settingsCard
                if isBattleRoyal {
                    battleRoyalSection
                } else {
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
              .coordinateSpace(name: Self.space)
              .simultaneousGesture(pageCarryGesture)
              .onPreferenceChange(TargetFrameKey.self) { targetFrames = $0 }
            }
            .scrollPosition($scrollPosition)
            // The carried player rides above everything, under the finger.
            .overlay {
                GeometryReader { g in
                    carriedGhost(origin: g.frame(in: .global).origin)
                }
                .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { scrollFrame = $0 }
            .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { old, rect in
                visibleRect = rect
                // The page moved under a carried player: keep it under the
                // finger. Only scrolling that HAPPENED counts.
                // Targets are re-measured on screen as the page moves; the
                // finger stays where it is — nothing to adjust.
                if let at = carrying?.at {
                    let k = target(at: at)
                    if k != dropTargetKey { dropTargetKey = k }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height) } action: { _, v in maxScroll = v }
            .onReceive(edgeTimer) { _ in scrollWhileCarrying() }
            .onChange(of: carryGestureActive) { _, active in
                if !active {
                    carryMissed = false
                    if carrying != nil { finishCarry(false) }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: liftTick)
            .sensoryFeedback(.impact(weight: .light), trigger: dropTick)
            .sensoryFeedback(.selection, trigger: dropTargetKey)
            .filmRoomPage()
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

    // MARK: - Sections

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

    // MARK: - Settings (one compact card)
    //
    // 20 Nov 2026, Luther: the settings "take unreasonable space — make it
    // smarter". One card: the game type, then four chips — format, minutes,
    // basket value, who is in the pool — each a tap-to-change menu showing
    // its value. Explanations went; the choices say what they are.

    private var settingsCard: some View {
        SetupCard {
            Picker(isChinese ? "比赛模式" : "Game type", selection: $gameType) {
                ForEach(SessionGameType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                if !isBattleRoyal {
                    settingChip(isChinese ? "人数" : "Format", value: "\(playersPerSide)v\(playersPerSide)", id: "setup.format") {
                        Picker("", selection: $playersPerSide) {
                            ForEach(2...5, id: \.self) { n in Text("\(n)v\(n)").tag(n) }
                        }
                    }
                }
                settingChip(isChinese ? "时长" : "Time", value: isChinese ? "\(durationMinutes) 分钟" : "\(durationMinutes) min", id: "setup.duration") {
                    Picker("", selection: Binding(get: { durationMinutes }, set: { durationMinutes = $0; durationManuallyEdited = true })) {
                        ForEach(durationChoices, id: \.self) { m in
                            Text(isChinese ? "\(m) 分钟" : "\(m) min").tag(m)
                        }
                    }
                }
                settingChip(isChinese ? "每球" : "Basket", value: isChinese ? "\(basketValue) 分" : "\(basketValue) pt\(basketValue == 1 ? "" : "s")", id: "setup.basket") {
                    Picker("", selection: $basketValue) {
                        ForEach(1...3, id: \.self) { v in Text(isChinese ? "\(v) 分" : "\(v) pt\(v == 1 ? "" : "s")").tag(v) }
                    }
                }
                settingChip(isChinese ? "球员" : "Players",
                            value: showOnlyPresent ? (isChinese ? "到场 \(presentCount)" : "Present \(presentCount)")
                                                   : (isChinese ? "全部 \(totalCount)" : "All \(totalCount)"),
                            id: "setup.pool") {
                    Picker("", selection: $showOnlyPresent) {
                        Text(isChinese ? "已到场 (\(presentCount))" : "Present (\(presentCount))").tag(true)
                        Text(isChinese ? "全部 (\(totalCount))" : "All (\(totalCount))").tag(false)
                    }
                }
            }

            if showOnlyPresent && presentCount == 0 {
                Button { showOnlyPresent = false } label: {
                    Label(isChinese ? "没有人到场，使用全部球员" : "No one is marked present — use the full roster",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A compact setting: its name small, its value big, a menu on tap.
    private func settingChip<Choices: View>(_ title: String, value: String, id: String,
                                            @ViewBuilder choices: () -> Choices) -> some View {
        Menu {
            choices()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var durationChoices: [Int] {
        Array(Set([2, 3, 4, 5, 6, 8, 10, 12, 15, 20, durationMinutes])).sorted()
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
                if hasPreviousConfig {
                    Toggle(isOn: $usePreviousConfig.animation()) {
                        Label(isChinese ? "沿用上次分队" : "Last game's teams", systemImage: "clock.arrow.circlepath")
                    }
                    .toggleStyle(.button)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("setup.reuse")
                }
                Text("\(teams.count) / \(maxTeams)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
        .contentShape(Rectangle())
        .dropTarget("team.\(index)")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.team.\(index)")
    }

    /// One slot of a team: a player (tap = options; press, hold and carry
    /// to move) or an empty place.
    @ViewBuilder
    private func slot(teamIndex: Int, position: Int, playerId: UUID?, color: Color, starter: Bool) -> some View {
        let key = "\(teamIndex).\(position)"
        let targeted = dropTargetKey == key && carrying?.pid != playerId
        Group {
            if let pid = playerId, let s = student(pid) {
                Button { if Date().timeIntervalSince(carryEndedAt) > 0.4 { optionsFor = pid } } label: {
                    playerBubble(s, ring: color, solidRing: starter, highlighted: targeted)
                }
                .buttonStyle(.plain)
                .popover(isPresented: optionsBinding(pid)) { optionsPopover(pid: pid, currentTeam: teamIndex) }
                .carryable(pid, in: self)
                .accessibilityIdentifier("setup.slot.\(key)")
            } else {
                emptySlot(starter: starter, color: color, highlighted: targeted)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("setup.slot.\(key)")
            }
        }
        .scaleEffect(targeted ? 1.08 : 1)
        .animation(.snappy(duration: 0.18), value: targeted)
        .dropTarget(key)
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
                Image(systemName: "person.crop.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: slotSize + 22), spacing: 8)], spacing: 12) {
                    ForEach(rosterIds, id: \.self) { pid in
                        if let s = student(pid) {
                            Button { if Date().timeIntervalSince(carryEndedAt) > 0.4 { optionsFor = pid } } label: {
                                playerBubble(s, ring: nil, solidRing: true, highlighted: false)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: optionsBinding(pid)) { optionsPopover(pid: pid, currentTeam: nil) }
                            .carryable(pid, in: self)
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
        .dropTarget("roster")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setup.roster")
    }

    // MARK: - Carrying a player (in-app drag, like the Home Screen)
    //
    // 21 Nov 2026, Luther: the system drag and drop crashed on the court —
    // its preview is rendered outside the page (no data for the photo) and
    // the drop wrote the teams while the page redrew. Now: press and hold
    // lifts the player (a bump), it follows the finger above everything,
    // the slot under it swells, letting go drops it — on a player = swap, on
    // an empty slot or a team row = join, on the roster = off the team;
    // anywhere else = back where it was. The page scrolls near its edges.
    // No hints.

    fileprivate func isCarrying(_ pid: UUID) -> Bool { carrying?.pid == pid }

    /// ONE carry gesture for the whole page (a gesture on each player broke:
    /// when a drop swapped players, the slot's still-running gesture picked
    /// up the newcomer). Hold 0.3 s on a player, then move. It runs
    /// alongside everything — the players' Buttons still take a tap, and a
    /// swipe that moves before the hold completes still scrolls the page.
    fileprivate var pageCarryGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($carryGestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if carrying == nil {
                    guard !carryMissed else { return }
                    // Whose photo is under the finger where the hold began?
                    guard let hit = targetFrames.first(where: { $0.key.hasPrefix("p.") && $0.value.contains(drag.startLocation) }),
                          let pid = UUID(uuidString: String(hit.key.dropFirst(2))) else {
                        carryMissed = true
                        return
                    }
                    optionsFor = nil
                    withAnimation(.snappy(duration: 0.2)) { carrying = (pid, drag.location) }
                    liftTick += 1
                    dropTargetKey = target(at: drag.location)
                } else {
                    carrying?.at = drag.location
                    let k = target(at: drag.location)
                    if k != dropTargetKey { dropTargetKey = k }
                }
            }
            .onEnded { _ in finishCarry(true) }
    }

    /// The drop target under a point: a slot first, then a team row, then
    /// the roster.
    private func target(at p: CGPoint) -> String? {
        if let k = targetFrames.first(where: { !$0.key.hasPrefix("team.") && !$0.key.hasPrefix("p.") && $0.key != "roster"
                                                && $0.value.insetBy(dx: -6, dy: -6).contains(p) })?.key { return k }
        if let k = targetFrames.first(where: { $0.key.hasPrefix("team.") && $0.value.contains(p) })?.key { return k }
        if targetFrames["roster"]?.contains(p) == true { return "roster" }
        return nil
    }

    private func finishCarry(_ dropped: Bool) {
        guard let c = carrying else { return }
        let key = dropTargetKey
        withAnimation(.snappy(duration: 0.28)) {
            if dropped, let key {
                if key == "roster" {
                    if !unassignedIds.contains(c.pid) { unassign(c.pid) }
                } else if key.hasPrefix("team."), let t = Int(key.dropFirst(5)), teams.indices.contains(t) {
                    if !teams[t].playerIds.contains(c.pid) { addToTeam(c.pid, t) }
                } else {
                    let parts = key.split(separator: ".")
                    if parts.count == 2, let t = Int(parts[0]), let pos = Int(parts[1]), teams.indices.contains(t) {
                        place(c.pid, team: t, position: pos)
                    }
                }
                dropTick += 1
            }
            carrying = nil
            dropTargetKey = nil
        }
        carryEndedAt = Date()
    }

    /// Near the top or bottom of what is visible, the page scrolls under
    /// the carried player.
    private func scrollWhileCarrying() {
        guard let c = carrying, scrollFrame.height > 0, visibleRect.height > 0 else { return }
        let edge: CGFloat = 90, step: CGFloat = 14
        var y = visibleRect.minY
        if c.at.y < scrollFrame.minY + edge { y -= step } else if c.at.y > scrollFrame.maxY - edge { y += step }
        y = min(max(0, y), maxScroll)
        guard abs(y - visibleRect.minY) > 0.5 else { return }
        scrollPosition.scrollTo(y: y)
    }

    @ViewBuilder
    private func carriedGhost(origin: CGPoint) -> some View {
        if let c = carrying, let s = student(c.pid) {
            playerBubble(s, ring: teams.first { $0.playerIds.contains(c.pid) }.map { $0.displayColor(for: colorScheme) },
                         solidRing: true, highlighted: false)
                .scaleEffect(1.2)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                .position(x: c.at.x - origin.x, y: c.at.y - origin.y - 10)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
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
                    .fill(Color.filmCard))
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

// MARK: - In-app carry

private struct TargetFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    /// Registers this view as a drop target under `key`.
    func dropTarget(_ key: String) -> some View {
        background(GeometryReader { g in
            // SCREEN space: the finger's screen position is the one number
            // that always matched reality (named-space frames came back
            // ~70 pt off inside the page). Re-measured as the page scrolls.
            Color.clear.preference(key: TargetFrameKey.self, value: [key: g.frame(in: .global)])
        })
    }

    /// Press, hold and carry this player; the original fades while carried.
    func carryable(_ pid: UUID, in sheet: CreateGameSheet) -> some View {
        opacity(sheet.isCarrying(pid) ? 0.0 : 1)
            .dropTarget("p.\(pid)")
    }
}
