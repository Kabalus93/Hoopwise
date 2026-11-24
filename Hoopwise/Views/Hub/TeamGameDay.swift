import SwiftUI

// GAME DAY (23 Nov 2026 — model in Models/GamePlan.swift). The team page's
// Game Day block schedules a game and opens its plan; the same sheet edits
// it later; the game's session page shows the plan on its Plan tab.

/// Schedule a game, or edit one: when and against whom, the lineup, the
/// plays to run, keys to the game, opponent notes.
struct GameDaySheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let team: Team
    /// nil = a new game.
    let editing: SessionEvent?
    var onSaved: (SessionEvent) -> Void = { _ in }

    @State private var opponent: String
    @State private var isHome: Bool
    @State private var start: Date
    @State private var minutes: Int
    @State private var venue: String
    @State private var starters: [UUID]
    @State private var plays: [SessionPlayRef]
    @State private var keys: [String]
    @State private var opponentNotes: String
    @State private var subs: [PlannedSub]
    @State private var defense: GameDefense?
    @State private var defenseNote: String
    @State private var threats: [OpponentPlayer]
    @State private var confirmingDelete = false
    @FocusState private var focusedKey: Int?

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    init(team: Team, editing: SessionEvent? = nil, onSaved: @escaping (SessionEvent) -> Void = { _ in }) {
        self.team = team
        self.editing = editing
        self.onSaved = onSaved
        let plan = editing?.curriculum.gamePlan ?? GamePlan()
        _opponent = State(initialValue: plan.opponent)
        _isHome = State(initialValue: plan.isHome)
        _start = State(initialValue: editing?.startTime ?? Self.defaultStart())
        _minutes = State(initialValue: editing.map { max(20, $0.durationMinutes) } ?? 60)
        _venue = State(initialValue: editing?.location ?? team.homeVenue ?? "")
        _starters = State(initialValue: plan.starters)
        _plays = State(initialValue: editing?.curriculum.plays ?? [])
        _keys = State(initialValue: plan.keys.isEmpty ? [""] : plan.keys)
        _opponentNotes = State(initialValue: plan.opponentNotes)
        _subs = State(initialValue: plan.subs)
        _defense = State(initialValue: plan.defense)
        _defenseNote = State(initialValue: plan.defenseNote)
        _threats = State(initialValue: plan.threats)
    }

    private var benchAthletes: [Student] { athletes.filter { !starters.contains($0.id) } }
    private var startingAthletes: [Student] { starters.compactMap { id in athletes.first { $0.id == id } } }
    private static let whenPresets: [(String, String)] = [
        ("Early first half", "上半场开始不久"), ("Mid first half", "上半场中段"), ("Late first half", "上半场末"),
        ("Start of second half", "下半场开始"), ("Mid second half", "下半场中段"), ("Late in the game", "比赛末段"),
    ]

    /// Next Saturday at 10:00 — a likely game slot, changed in one tap.
    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 10, minute: 0, weekday: 7),
                                matchingPolicy: .nextTime) ?? Date()
        return next
    }

    private var athletes: [Student] {
        team.playerIds.compactMap { id in dataManager.students.first { $0.id == id } }
    }

    private var playbookSections: [(TeamPlaybook.Kind, [SessionPlayRef])] {
        let book = team.playbook
        return TeamPlaybook.Kind.allCases.compactMap { kind in
            let list = book[kind].plays
            return list.isEmpty ? nil : (kind, list)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(isChinese ? "比赛" : "Game") {
                    TextField(isChinese ? "对手" : "Opponent", text: $opponent)
                        .accessibilityIdentifier("gameDay.opponent")
                    Picker(isChinese ? "主客场" : "Where", selection: $isHome) {
                        Text(isChinese ? "主场" : "Home").tag(true)
                        Text(isChinese ? "客场" : "Away").tag(false)
                    }
                    .pickerStyle(.segmented)
                    DatePicker(isChinese ? "时间" : "Tip-off", selection: $start)
                        .accessibilityIdentifier("gameDay.date")
                    Picker(isChinese ? "时长" : "Length", selection: $minutes) {
                        ForEach([30, 40, 60, 90, 120], id: \.self) { m in
                            Text(isChinese ? "\(m) 分钟" : "\(m) min").tag(m)
                        }
                        if ![30, 40, 60, 90, 120].contains(minutes) {
                            Text(isChinese ? "\(minutes) 分钟" : "\(minutes) min").tag(minutes)
                        }
                    }
                    TextField(isChinese ? "场地" : "Venue", text: $venue)
                }

                Section {
                    if athletes.isEmpty {
                        Text(isChinese ? "球队还没有学员。" : "The team has no athletes yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(athletes) { student in
                        Button { toggle(student.id) } label: { lineupRow(student) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("gameDay.player")
                    }
                } header: {
                    Text(isChinese ? "阵容" : "Lineup")
                } footer: {
                    if !athletes.isEmpty {
                        Text(isChinese ? "点一下设为首发（按点击顺序），再点一下回到替补。首发 \(starters.count) 人。"
                                       : "Tap to start a player (in the order you tap), tap again for the bench. \(starters.count) starting.")
                    }
                }

                Section {
                    ForEach($subs) { $sub in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Picker(isChinese ? "上场" : "In", selection: $sub.playerIn) {
                                    ForEach(benchAthletes) { Text($0.primaryDisplayName).tag($0.id) }
                                    if !benchAthletes.contains(where: { $0.id == sub.playerIn }),
                                       let other = athletes.first(where: { $0.id == sub.playerIn }) {
                                        Text(other.primaryDisplayName).tag(other.id)
                                    }
                                }
                                .labelsHidden()
                                Text(isChinese ? "换下" : "for").foregroundStyle(.secondary)
                                Picker(isChinese ? "下场" : "Out", selection: $sub.playerOut) {
                                    Text(isChinese ? "需要休息的人" : "Whoever needs a rest").tag(UUID?.none)
                                    ForEach(startingAthletes) { Text($0.primaryDisplayName).tag(UUID?.some($0.id)) }
                                }
                                .labelsHidden()
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: 8) {
                                TextField(isChinese ? "什么时候，例如：上半场中段" : "When — like: mid first half", text: $sub.when)
                                    .accessibilityIdentifier("gameDay.sub.when")
                                Menu {
                                    ForEach(Self.whenPresets, id: \.0) { en, zh in
                                        Button(isChinese ? zh : en) { sub.when = isChinese ? zh : en }
                                    }
                                } label: {
                                    Image(systemName: "clock").frame(width: 32, height: 32)
                                }
                                .accessibilityLabel(isChinese ? "常用时间" : "Common times")
                            }
                            // When the live screen calls for it.
                            HStack(spacing: 6) {
                                Image(systemName: "bell").foregroundStyle(.secondary)
                                Text(isChinese ? "提醒" : "Prompt").foregroundStyle(.secondary)
                                Picker(isChinese ? "第几节" : "Period", selection: $sub.period) {
                                    Text(isChinese ? "任意一节" : "Any period").tag(Int?.none)
                                    ForEach(1...4, id: \.self) { Text(isChinese ? "第 \($0) 节" : "Period \($0)").tag(Int?.some($0)) }
                                }
                                .labelsHidden()
                                .accessibilityIdentifier("gameDay.sub.period")
                                Picker(isChinese ? "第几分钟" : "Minute", selection: $sub.minute) {
                                    Text(isChinese ? "不定时间" : "No set minute").tag(Int?.none)
                                    ForEach(Array(0...20), id: \.self) { Text(isChinese ? "第 \($0) 分钟" : "at \($0):00").tag(Int?.some($0)) }
                                }
                                .labelsHidden()
                                .accessibilityIdentifier("gameDay.sub.minute")
                                Spacer(minLength: 0)
                            }
                            .font(.subheadline)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("gameDay.sub")
                    }
                    .onDelete { subs.remove(atOffsets: $0) }
                    Button {
                        let planned = Set(subs.map(\.playerIn))
                        if let next = benchAthletes.first(where: { !planned.contains($0.id) }) ?? benchAthletes.first {
                            subs.append(PlannedSub(playerIn: next.id))
                        }
                    } label: {
                        Label(isChinese ? "计划一次换人" : "Plan a sub", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(benchAthletes.isEmpty)
                    .accessibilityIdentifier("gameDay.addSub")
                } header: {
                    Text(isChinese ? "轮换" : "Rotation")
                } footer: {
                    Text(benchAthletes.isEmpty
                         ? (isChinese ? "先定首发；其余的人是替补，可以在这里计划换人。" : "Pick the starters first — everyone else is the bench and can be planned in here.")
                         : (isChinese ? "谁上场、换下谁、什么时候。计分页面会在替补席上方列出这些换人；定了第几节、第几分钟的，时间一到会变成橙色并震动提醒。" : "Who comes in, for whom, and when. The scoring screen lists these above the bench; one with a period and minute turns orange and buzzes when the clock gets there."))
                }

                Section {
                    Picker(isChinese ? "防守" : "Defense", selection: $defense) {
                        Text(isChinese ? "未定" : "Not set").tag(GameDefense?.none)
                        ForEach(GameDefense.allCases) { Text($0.title(chinese: isChinese)).tag(GameDefense?.some($0)) }
                    }
                    .accessibilityIdentifier("gameDay.defense")
                    TextField(isChinese ? "怎么防，例如：所有掩护都换防" : "How — like: switch every screen",
                              text: $defenseNote, axis: .vertical)
                        .accessibilityIdentifier("gameDay.defenseNote")
                } header: {
                    Text(isChinese ? "我们的防守" : "Our defense")
                }

                Section {
                    if playbookSections.isEmpty {
                        Text(isChinese ? "战术手册里还没有战术；先在球队页面的战术手册中添加。"
                                       : "The playbook has no plays yet — add them in the team's Playbook first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(playbookSections, id: \.0) { kind, list in
                        ForEach(list, id: \.key) { ref in
                            let on = plays.contains { $0.key == ref.key }
                            Button {
                                if on { plays.removeAll { $0.key == ref.key } } else { plays.append(ref) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: kind.icon).foregroundStyle(kind.tint).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ref.name).foregroundStyle(.primary)
                                        Text(kind.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("gameDay.play")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } header: {
                    Text(isChinese ? "要打的战术" : "Plays to run")
                }

                Section {
                    ForEach(keys.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(.secondary).frame(width: 18)
                            TextField(isChinese ? "例如：每个球都要卡位" : "Like: box out on every shot",
                                      text: Binding(get: { keys.indices.contains(i) ? keys[i] : "" },
                                                    set: { if keys.indices.contains(i) { keys[i] = $0 } }),
                                      axis: .vertical)
                                .focused($focusedKey, equals: i)
                                .accessibilityIdentifier("gameDay.key")
                        }
                    }
                    .onDelete { keys.remove(atOffsets: $0); if keys.isEmpty { keys = [""] } }
                    Button {
                        keys.append("")
                        focusedKey = keys.count - 1
                    } label: {
                        Label(isChinese ? "再加一条" : "Add a key", systemImage: "plus")
                    }
                    .accessibilityIdentifier("gameDay.addKey")
                } header: {
                    Text(isChinese ? "比赛要点" : "Keys to the game")
                }

                Section {
                    TextField(isChinese ? "他们是谁，要注意什么：最好的球员、防守方式…"
                                        : "Who they are and what to watch for: their best players, their defense…",
                              text: $opponentNotes, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("gameDay.opponentNotes")
                } header: {
                    Text(isChinese ? "对手情况" : "Opponent notes")
                }

                Section {
                    ForEach($threats) { $t in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                TextField("#", text: $t.number)
                                    .keyboardType(.numbersAndPunctuation)
                                    .frame(width: 52)
                                    .accessibilityIdentifier("gameDay.threat.number")
                                TextField(isChinese ? "要注意什么，例如：左手，底角投篮" : "What to know — like: left hand, corner shooter",
                                          text: $t.note, axis: .vertical)
                                    .accessibilityIdentifier("gameDay.threat.note")
                            }
                            Picker(isChinese ? "谁来防" : "Guarded by", selection: $t.guardedBy) {
                                Text(isChinese ? "未定" : "Not set").tag(UUID?.none)
                                ForEach(athletes) { Text($0.primaryDisplayName).tag(UUID?.some($0.id)) }
                            }
                            .accessibilityIdentifier("gameDay.threat.guard")
                        }
                    }
                    .onDelete { threats.remove(atOffsets: $0) }
                    Button { threats.append(OpponentPlayer()) } label: {
                        Label(isChinese ? "添加对方球员" : "Add one of their players", systemImage: "plus")
                    }
                    .accessibilityIdentifier("gameDay.addThreat")
                } header: {
                    Text(isChinese ? "对方球员与对位" : "Their players and matchups")
                }

                if editing != nil {
                    Section {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Label(isChinese ? "删除这场比赛" : "Delete this game", systemImage: "trash")
                        }
                        .accessibilityIdentifier("gameDay.delete")
                    }
                }
            }
            .navigationTitle(editing == nil ? (isChinese ? "安排比赛" : "Schedule a game") : (isChinese ? "比赛计划" : "Game plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("gameDay.save")
                }
            }
            .confirmationDialog(isChinese ? "删除这场比赛？" : "Delete this game?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button(isChinese ? "删除" : "Delete", role: .destructive) {
                    if let editing, let stored = dataManager.sessionEvents.first(where: { $0.id == editing.id }) {
                        dataManager.deleteSessionEvent(stored)
                    }
                    dismiss()
                }
            } message: {
                Text(isChinese ? "比赛、它的计划、出勤和比分都会删除。" : "The game goes with its plan, attendance and score.")
            }
        }
        .environmentObject(dataManager)
    }

    private func lineupRow(_ student: Student) -> some View {
        let order = starters.firstIndex(of: student.id)
        return HStack(spacing: 12) {
            StudentAvatarView(student: student, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(student.primaryDisplayName).foregroundStyle(.primary)
                if let second = student.secondaryNameLine {
                    Text(second).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let order {
                Text(isChinese ? "首发 \(order + 1)" : "Starter \(order + 1)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: team.colorHex)))
            } else {
                Text(isChinese ? "替补" : "Bench")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ id: UUID) {
        if let i = starters.firstIndex(of: id) { starters.remove(at: i) } else { starters.append(id) }
    }

    private func save() {
        var plan = editing?.curriculum.gamePlan ?? GamePlan()
        plan.opponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.isHome = isHome
        plan.starters = starters.filter { id in athletes.contains { $0.id == id } }
        plan.keys = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        plan.opponentNotes = opponentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.subs = subs.filter { sub in athletes.contains { $0.id == sub.playerIn } && !plan.starters.contains(sub.playerIn) }
            .map { sub in
                var s = sub
                s.when = s.when.trimmingCharacters(in: .whitespacesAndNewlines)
                if let out = s.playerOut, !plan.starters.contains(out) { s.playerOut = nil }
                return s
            }
        plan.defense = defense
        plan.defenseNote = defenseNote.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.threats = threats.filter { t in
            !t.number.trimmingCharacters(in: .whitespaces).isEmpty || !t.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let place = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = plan.title(team: team.name, chinese: isChinese)

        if let editing {
            // Onto the STORED session (never a rebuilt record); games, marks
            // and results keep the store's values (keepLiveFields).
            var session = dataManager.sessionEvents.first { $0.id == editing.id } ?? editing
            session.curriculum.gamePlan = plan
            session.curriculum.plays = plays
            session.title = title
            session.date = start
            session.startTime = start
            session.endTime = start.addingTimeInterval(TimeInterval(minutes * 60))
            session.location = place.isEmpty ? nil : place
            dataManager.updateSessionEvent(session)
            onSaved(session)
        } else {
            var curriculum = SessionCurriculum()
            curriculum.teamId = team.id
            curriculum.gamePlan = plan
            curriculum.plays = plays
            let result = dataManager.createSession(SessionCreation.Intent(
                group: .unassigned,
                sessionType: .game,
                start: start,
                durationMinutes: minutes,
                title: title,
                location: place.isEmpty ? nil : place,
                roster: athletes.map(\.id),
                curriculum: curriculum,
                createdByCoachId: dataManager.loggedInCoachId))
            onSaved(result.session)
        }
        dismiss()
    }
}

/// A row of starters' photos.
struct GameDayLineupStrip: View {
    @EnvironmentObject private var dataManager: DataManager
    let starters: [UUID]
    var size: CGFloat = 34
    var showsNames = false

    var body: some View {
        let people = starters.compactMap { id in dataManager.students.first { $0.id == id } }
        HStack(alignment: .top, spacing: showsNames ? 12 : -8) {
            ForEach(people) { student in
                VStack(spacing: 4) {
                    StudentAvatarView(student: student, size: size)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: showsNames ? 0 : 2))
                    if showsNames {
                        Text(student.primaryDisplayName)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: size + 24)
                    }
                }
            }
        }
    }
}

/// The game's plan on its session's Plan tab (rebuilt 24 Nov 2026, Luther:
/// "how can we make the plan page for games actually useful?"): the game and
/// its keys, then LINEUP AND ROTATION beside THE OPPONENT (stacked when
/// narrow). The calls by situation are the plays card under it.
struct SessionGamePlanCard: View {
    @EnvironmentObject private var dataManager: DataManager
    @Binding var session: SessionEvent
    let canEdit: Bool
    @State private var editing = false
    @State private var sharingSheet = false
    @State private var width: CGFloat = 0

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var team: Team? { session.curriculum.teamId.flatMap { id in dataManager.teams.first { $0.id == id } } }
    private var plan: GamePlan { session.curriculum.gamePlan ?? GamePlan() }
    private var tint: Color { team.map { Color(hex: $0.colorHex) } ?? .red }
    private var roster: [UUID] { AttendanceMath.expectedIds(of: session, programs: dataManager.programs) }
    private func student(_ id: UUID?) -> Student? { id.flatMap { id in dataManager.students.first { $0.id == id } } }

    /// Roll call has started: someone carries a mark.
    private var rollCallStarted: Bool {
        !session.actualAttendeeIds.isEmpty || !session.excusedAbsences.isEmpty || !session.unexcusedAbsences.isEmpty
    }
    private func notHere(_ id: UUID) -> Bool { rollCallStarted && !session.actualAttendeeIds.contains(id) }

    var body: some View {
        let hasOpponent = !plan.opponentNotes.isEmpty || !plan.cleanThreats.isEmpty
        VStack(spacing: 12) {
            gameCard
            if width >= 700, hasOpponent {
                HStack(alignment: .top, spacing: 12) {
                    lineupCard
                    opponentCard
                }
            } else {
                lineupCard
                if hasOpponent { opponentCard }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("gameDay.planCard")
        .sheet(isPresented: $editing) {
            if let team {
                GameDaySheet(team: team, editing: session) { saved in
                    session.curriculum.gamePlan = saved.curriculum.gamePlan
                    session.curriculum.plays = saved.curriculum.plays
                    session.title = saved.title
                    session.date = saved.date
                    session.startTime = saved.startTime
                    session.endTime = saved.endTime
                    session.location = saved.location
                }
                .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $sharingSheet) {
            GameSheetShareSheet(session: session)
                .environmentObject(dataManager)
                .presentationSizing(.page)
        }
    }

    // MARK: The game and its keys

    private var gameCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(isChinese ? "比赛日" : "GAME DAY").font(.caption2.weight(.bold)).monospaced()
                    } icon: { Image(systemName: "flag.checkered").font(.caption) }
                    .foregroundStyle(tint)
                    Text((plan.isHome ? "vs " : "@ ") + plan.opponentName(chinese: isChinese))
                        .font(.title2.weight(.bold))
                    Text(plan.isHome ? (isChinese ? "主场" : "Home") : (isChinese ? "客场" : "Away"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let score = GameDay.score(of: session) {
                    Text(score.text(chinese: isChinese))
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle(score.isFinal ? (score.won ? Color.green : (score.tied ? Color.secondary : Color.red)) : Color.primary)
                        .accessibilityIdentifier("gameDay.score")
                }
                Button { sharingSheet = true } label: {
                    if width >= 500 {
                        Label(isChinese ? "计划单" : "Game sheet", systemImage: "printer")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Image(systemName: "printer").font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(isChinese ? "比赛计划单" : "Game sheet")
                .accessibilityIdentifier("gameDay.sheet")
                if canEdit, team != nil {
                    Button { editing = true } label: {
                        Label(isChinese ? "编辑" : "Edit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("gameDay.editPlan")
                }
            }

            section(isChinese ? "比赛要点" : "KEYS TO THE GAME") {
                if plan.cleanKeys.isEmpty {
                    Text(isChinese ? "还没有要点。两三条就够：全队要做到的事。" : "No keys yet. Two or three is enough: what the team must do.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(plan.cleanKeys.enumerated()), id: \.offset) { i, key in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(tint))
                                Text(key).font(.title3.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
        .gamePlanCard(tint: tint)
    }

    // MARK: Lineup and rotation

    private var lineupCard: some View {
        let starters = plan.starters.filter { roster.contains($0) }
        let bench = roster.filter { !starters.contains($0) }
        let subs = plan.validSubs(roster: roster)
        return VStack(alignment: .leading, spacing: 14) {
            cardTitle(isChinese ? "阵容与轮换" : "LINEUP AND ROTATION", "person.3.fill")
            section(isChinese ? "首发 \(starters.count)" : "STARTERS · \(starters.count)") {
                if starters.isEmpty {
                    Text(isChinese ? "还没有定首发。" : "No starters picked yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    people(starters, size: 50, ring: true)
                }
            }
            if !bench.isEmpty {
                section(isChinese ? "替补 \(bench.count)" : "BENCH · \(bench.count)") {
                    people(bench, size: 40, ring: false)
                }
            }
            if !subs.isEmpty {
                section(isChinese ? "计划换人" : "PLANNED SUBS") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(subs) { sub in
                            HStack(spacing: 8) {
                                if let s = student(sub.playerIn) { StudentAvatarView(student: s, size: 28) }
                                Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundStyle(.green)
                                if let out = student(sub.playerOut) {
                                    StudentAvatarView(student: out, size: 28).opacity(0.75)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(subLine(sub)).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if !sub.whenLine.isEmpty {
                                        Text(sub.whenLine).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("game.sub")
                        }
                    }
                }
            }
        }
        .gamePlanCard(tint: nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game.lineup")
    }

    private func subLine(_ sub: PlannedSub) -> String {
        let into = student(sub.playerIn)?.primaryDisplayName ?? ""
        if let out = student(sub.playerOut)?.primaryDisplayName {
            return isChinese ? "\(into) 换下 \(out)" : "\(into) in for \(out)"
        }
        return isChinese ? "\(into) 上场" : "\(into) comes in"
    }

    private func people(_ ids: [UUID], size: CGFloat, ring: Bool) -> some View {
        FlowLayout(spacing: 12) {
            ForEach(ids, id: \.self) { id in
                if let s = student(id) {
                    let away = notHere(id)
                    VStack(spacing: 4) {
                        StudentAvatarView(student: s, size: size)
                            .overlay(Circle().strokeBorder(ring ? tint : .clear, lineWidth: 2))
                            .opacity(away ? 0.35 : 1)
                        Text(s.primaryDisplayName)
                            .font(.caption.weight(ring ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(away ? .secondary : .primary)
                        if away {
                            Text(isChinese ? "未到" : "Not here").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                        }
                    }
                    .frame(width: size + 34)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: The opponent

    private var opponentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle((isChinese ? "对手 · " : "OPPONENT · ") + plan.opponentName(chinese: isChinese).uppercased(), "binoculars.fill")
            if !plan.opponentNotes.isEmpty {
                Text(plan.opponentNotes).font(.body)
            }
            if !plan.cleanThreats.isEmpty {
                section(isChinese ? "对方球员与对位" : "THEIR PLAYERS · WHO GUARDS THEM") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.cleanThreats) { t in
                            HStack(alignment: .center, spacing: 10) {
                                Text(t.label.isEmpty ? "—" : t.label)
                                    .font(.subheadline.weight(.heavy)).monospacedDigit()
                                    .frame(minWidth: 40, minHeight: 28)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemFill)))
                                Text(t.note).font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let g = student(t.guardedBy) {
                                    HStack(spacing: 6) {
                                        StudentAvatarView(student: g, size: 26)
                                        Text(g.primaryDisplayName).font(.caption.weight(.semibold)).lineLimit(1)
                                    }
                                    .padding(.trailing, 8).padding(.leading, 3).padding(.vertical, 3)
                                    .background(Capsule().fill(tint.opacity(0.16)))
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("game.threat")
                        }
                    }
                }
            }
        }
        .gamePlanCard(tint: nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game.opponent")
    }

    private func cardTitle(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title).font(.caption.weight(.bold)).lineLimit(1)
        } icon: {
            Image(systemName: symbol).font(.caption).foregroundStyle(tint)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
    }
}

private extension View {
    func gamePlanCard(tint: Color?) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder((tint ?? Color.primary).opacity(tint == nil ? 0.08 : 0.25), lineWidth: 1))
    }
}
