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
    }

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

/// The game's plan at the top of its session's Plan tab.
struct SessionGamePlanCard: View {
    @EnvironmentObject private var dataManager: DataManager
    @Binding var session: SessionEvent
    let canEdit: Bool
    @State private var editing = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var team: Team? { session.curriculum.teamId.flatMap { id in dataManager.teams.first { $0.id == id } } }
    private var plan: GamePlan { session.curriculum.gamePlan ?? GamePlan() }

    var body: some View {
        let tint = team.map { Color(hex: $0.colorHex) } ?? .red
        let roster = AttendanceMath.expectedIds(of: session, programs: dataManager.programs)
        let bench = roster.filter { !plan.starters.contains($0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
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

            section(isChinese ? "首发" : "STARTERS") {
                if plan.starters.isEmpty {
                    Text(isChinese ? "还没有定首发。" : "No starters picked yet.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        GameDayLineupStrip(starters: plan.starters, size: 46, showsNames: true)
                    }
                    if !bench.isEmpty {
                        Text(isChinese ? "替补 \(bench.count) 人" : "\(bench.count) on the bench")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !plan.cleanKeys.isEmpty {
                section(isChinese ? "比赛要点" : "KEYS TO THE GAME") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(plan.cleanKeys.enumerated()), id: \.offset) { i, key in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(tint))
                                Text(key).font(.body)
                            }
                        }
                    }
                }
            }

            if !plan.opponentNotes.isEmpty {
                section(isChinese ? "对手情况" : "OPPONENT") {
                    Text(plan.opponentNotes).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
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
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
    }
}
