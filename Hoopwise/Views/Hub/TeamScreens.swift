import SwiftData
import SwiftUI

// Hub → TEAMS, the places (November 2026, Luther: "meant to be reflected upon
// and visited, contemplated even … similar blocks as the home screen"). A
// team page is blocks — the team, who we are and what we work on, the
// playbook, what our system asks of each player (standards), each player's
// workout, the roster, recent practices — and every block opens its detail.
// The Standards come from PLAY BREAKDOWNS: a play's numbered roles, each with
// the skills it needs (the drill library's activity types), the drills that
// build them, a line of standard and who plays it (TeamPlaybook).

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

/// A team's members resolved: athletes, then organization coaches.
struct TeamRoster {
    let athletes: [Student]
    let coaches: [StaffCoach]
    var count: Int { athletes.count + coaches.count }

    @MainActor
    init(team: Team, dataManager: DataManager) {
        athletes = team.playerIds.compactMap { id in dataManager.students.first { $0.id == id } }
        coaches = team.playerIds.compactMap { id in dataManager.staffCoaches.first { $0.id == id } }
    }

    /// Everyone as display players (coaches as `asGuestPlayer`).
    @MainActor
    func everyone(_ dataManager: DataManager) -> [Student] {
        athletes + coaches.map { $0.asGuestPlayer(dataManager: dataManager) }
    }
}

extension ActivityType {
    /// The skills a role can need — the library's types without the warm-up,
    /// games and rule options.
    static var skills: [ActivityType] { allCases.filter { ![.warmup, .games, .rules].contains($0) } }
}

/// One block of a team page: a glass card with a small header.
private struct TeamBlock<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .monospaced()
            } icon: {
                Image(systemName: icon).font(.caption)
            }
            .foregroundStyle(tint)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

// MARK: - Teams list

struct TeamsScreen: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var creating = false

    private var teams: [Team] {
        dataManager.teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            if teams.isEmpty {
                ContentUnavailableView {
                    Label(isChinese ? "还没有球队" : "No teams yet", systemImage: "person.3.sequence")
                } description: {
                    Text(isChinese ? "建一支你执教的球队：队员、战术、标准和每个人的训练都在这里。"
                                   : "Create a team you coach: its players, its plays, its standards and each player's workout live here.")
                } actions: {
                    Button(isChinese ? "新建球队" : "New Team") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(teams) { team in
                        NavigationLink(destination: TeamDetailView(teamId: team.id)) {
                            TeamCard(team: team)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("teams.row")
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isChinese ? "球队" : "Teams")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(isChinese ? "新建球队" : "New Team")
                    .accessibilityIdentifier("teams.new")
            }
        }
        .sheet(isPresented: $creating) { TeamEditorSheet(team: nil) }
    }
}

/// A team in the list: its colour, badge, name, coach, counts and faces.
private struct TeamCard: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        let roster = TeamRoster(team: team, dataManager: dataManager)
        let colour = Color(hex: team.colorHex)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TeamBadge(team: team, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name).font(.title3.weight(.bold)).foregroundStyle(.white)
                    if let coach = team.coachName, !coach.isEmpty {
                        Text(isChinese ? "教练 \(coach)" : "Coach \(coach)")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: -10) {
                ForEach(roster.everyone(dataManager).prefix(6)) { player in
                    StudentAvatarView(student: player, size: 30)
                        .overlay(Circle().stroke(colour, lineWidth: 2))
                }
                Spacer()
                Text([isChinese ? "\(roster.count) 名队员" : "\(roster.count) players",
                      isChinese ? "\(team.playbook.playCount) 个战术" : "\(team.playbook.playCount) plays"]
                    .joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(18)
        .background(LinearGradient(colors: [colour, colour.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - A team

struct TeamDetailView: View {
    let teamId: UUID
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]

    @State private var addingPlayers = false
    @State private var editing = false
    @State private var editingFocus = false
    @State private var confirmingDelete = false
    @State private var openStudent: Student?
    @State private var openCoach: StaffCoach?
    @State private var pickingFor: TeamPlaybook.Kind?

    private var team: Team? { dataManager.teams.first { $0.id == teamId } }

    var body: some View {
        if let team {
            content(team)
        } else {
            ContentUnavailableView(isChinese ? "球队已删除" : "Team deleted", systemImage: "person.3.sequence")
        }
    }

    private func content(_ team: Team) -> some View {
        let roster = TeamRoster(team: team, dataManager: dataManager)
        return ScrollView {
            VStack(spacing: 16) {
                hero(team, roster: roster)
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) { focusBlock(team); playbookBlock(team); standardsBlock(team) }
                        VStack(spacing: 16) { rosterBlock(team, roster: roster); practicesBlock(team) }
                    }
                } else {
                    focusBlock(team)
                    playbookBlock(team)
                    standardsBlock(team)
                    rosterBlock(team, roster: roster)
                    practicesBlock(team)
                }
            }
            .padding(16)
            .padding(.bottom, 60)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = true } label: { Label(isChinese ? "编辑球队" : "Edit Team", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label(isChinese ? "删除球队" : "Delete Team", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityIdentifier("team.menu")
            }
        }
        .sheet(isPresented: $editing) { TeamEditorSheet(team: team) }
        .sheet(isPresented: $editingFocus) { TeamFocusSheet(team: team) }
        .sheet(isPresented: $addingPlayers) { TeamAddPlayersSheet(team: team) }
        .sheet(item: $openStudent) { student in
            NavigationStack {
                StudentDetailView(student: student)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isChinese ? "完成" : "Done") { openStudent = nil }
                        }
                    }
            }
        }
        .sheet(item: $openCoach) { CoachProfileDetailView(coach: $0) }
        .sheet(item: $pickingFor) { kind in
            SessionPlayPicker(library: library, selected: team.playbook[kind].plays) { chosen in
                TeamStore.update(teamId, in: dataManager) { $0.playbook[kind].plays = chosen }
            }
        }
        .alert(isChinese ? "删除这支球队？" : "Delete this team?", isPresented: $confirmingDelete) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                dataManager.deleteTeam(team)
                dismiss()
            }
        } message: {
            Text(isChinese ? "队员和战术本身不会被删除，只删除这支球队。" : "Its players and plays stay in the app; only the team goes.")
        }
    }

    // MARK: Blocks

    private func hero(_ team: Team, roster: TeamRoster) -> some View {
        let colour = Color(hex: team.colorHex)
        let coach = team.coachId.flatMap { id in dataManager.staffCoaches.first { $0.id == id } }
        let subtitle = [coach.map { isChinese ? "教练 \($0.name)" : "Coach \($0.name)" }, team.homeVenue]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                TeamBadge(team: team, size: 64)
                Text(team.name).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 8)
            if !roster.athletes.isEmpty || !roster.coaches.isEmpty {
                TodaysRosterCluster(
                    members: TodaysRosterCluster.members(hero: nil, students: roster.everyone(dataManager),
                                                         sessions: dataManager.sessionEvents),
                    total: roster.count,
                    scale: sizeClass == .regular ? 1.5 : 1.1,
                    onSelect: open,
                    onMore: { })
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [colour, colour.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 26, style: .continuous))
    }

    private func open(_ player: Student) {
        if let coach = dataManager.staffCoaches.first(where: { $0.id == player.id }) { openCoach = coach } else { openStudent = player }
    }

    /// FOCUS NOW: the plays practice works on. A team practice builds its
    /// plan from them (their role drills, the skills they need, the plays)
    /// and shows who plays which role.
    private func focusBlock(_ team: Team) -> some View {
        let book = team.playbook
        let plays = book.focusPlays
        return TeamBlock(title: isChinese ? "当前重点" : "Focus now", icon: "scope") {
            VStack(alignment: .leading, spacing: 10) {
                if plays.isEmpty {
                    Text(book.playCount == 0
                         ? (isChinese ? "先在战术本里添加战术，再选出当前要练的。" : "Add plays to the playbook, then pick the ones practice works on now.")
                         : (isChinese ? "选出当前要练的战术。球队训练会用它们的号位练习、所需技术和战术来生成计划。"
                                      : "Pick the plays practice works on now. Team practices build their plan from them — the roles' drills, the skills they need, the plays."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(plays, id: \.key) { ref in
                            let found = library.first { $0.isNamed(by: ref) }
                            let roles = book.breakdowns[ref.key]?.roles ?? []
                            let drills = Set(roles.flatMap(\.drillIds)).count
                            NavigationLink(destination: PlayBreakdownView(teamId: teamId, ref: ref)) {
                                HStack(spacing: 12) {
                                    if let found {
                                        JournalPlayThumbnail(diagram: found.conceptPart?.sortedSteps.first?.diagram,
                                                             court: found.court, width: 56, height: 40)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: found?.name ?? ref.name).font(.body.weight(.medium)).lineLimit(1)
                                        Text(roles.isEmpty
                                             ? (isChinese ? "还没拆解" : "Not broken down yet")
                                             : (isChinese ? "\(roles.count) 个号位 · \(drills) 个练习" : "\(roles.count) roles · \(drills) drills"))
                                            .font(.caption).foregroundStyle(roles.isEmpty ? .orange : .secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 6)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("team.focus.play")
                        }
                    }
                    let skills = book.skills(in: plays).compactMap { ActivityType(rawValue: $0)?.title }
                    if !skills.isEmpty {
                        Text((isChinese ? "需要的技术：" : "Skills it needs: ") + skills.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if book.playCount > 0 {
                    Button { editingFocus = true } label: {
                        Text(plays.isEmpty ? (isChinese ? "选择战术" : "Choose plays") : (isChinese ? "更改" : "Change"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("team.focus.edit")
                }
            }
        }
    }

    private func playbookBlock(_ team: Team) -> some View {
        let book = team.playbook
        let filled = TeamPlaybook.Kind.allCases.filter { !book[$0].isEmpty }
        let empty = TeamPlaybook.Kind.allCases.filter { book[$0].isEmpty }
        return TeamBlock(title: isChinese ? "战术本" : "Playbook", icon: "sportscourt", tint: .orange) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(filled) { kind in
                    NavigationLink(destination: TeamSectionView(teamId: teamId, kind: kind)) {
                        sectionTile(kind, section: book[kind])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("team.section.\(kind.rawValue)")
                }
                if !empty.isEmpty {
                    Menu {
                        ForEach(empty) { kind in
                            Button { pickingFor = kind } label: { Label(kind.title, systemImage: kind.icon) }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.title3.weight(.semibold))
                            Text(isChinese ? "添加板块" : "Add a section").font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .foregroundStyle(.secondary)
                        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .accessibilityIdentifier("team.addSection")
                }
            }
        }
    }

    private func sectionTile(_ kind: TeamPlaybook.Kind, section: TeamPlaybook.Section) -> some View {
        let first = section.plays.first.flatMap { ref in library.first { $0.isNamed(by: ref) } }
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground))
                if let first {
                    JournalPlayThumbnail(diagram: first.conceptPart?.sortedSteps.first?.diagram, court: first.court,
                                         width: 120, height: 60)
                } else {
                    Image(systemName: kind.icon).font(.title2).foregroundStyle(kind.tint)
                }
            }
            .frame(height: 64)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(section.plays.isEmpty ? (isChinese ? "备注" : "Notes")
                     : (isChinese ? "\(section.plays.count) 个战术" : "\(section.plays.count) \(section.plays.count == 1 ? "play" : "plays")"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(0.08), in: .rect(cornerRadius: 16))
    }

    private func standardsBlock(_ team: Team) -> some View {
        let demands = team.playbook.skillDemands
        return TeamBlock(title: isChinese ? "标准" : "Standards", icon: "chart.bar.doc.horizontal", tint: .purple) {
            if demands.isEmpty {
                Text(isChinese ? "打开一个战术，按号位拆解它：每个号位需要的技术、练习和标准。体系对每个人的要求会汇总在这里。"
                               : "Open a play and break it down by numbered role — the skills, drills and standard each needs. What your system asks of each player adds up here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                NavigationLink(destination: TeamStandardsView(teamId: teamId)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "我们的体系最依赖：" : "Our system leans on")
                            .font(.subheadline).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(demands.prefix(6)) { demand in
                                HStack(spacing: 4) {
                                    Text(ActivityType(rawValue: demand.skill)?.title ?? demand.skill)
                                    Text("\(demand.roles.count)").foregroundStyle(.secondary)
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.purple.opacity(0.12), in: .capsule)
                                .fixedSize()
                            }
                        }
                        HStack {
                            Text(isChinese ? "看每项技术来自哪里" : "See where each comes from").font(.footnote.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("team.standards")
            }
        }
    }

    /// The team's people in ONE block (Luther: Workouts and Roster were
    /// redundant): who they are, the roles they play, their workout. A row
    /// opens the player's workout; ⋯ opens the profile or removes them.
    private func rosterBlock(_ team: Team, roster: TeamRoster) -> some View {
        let book = team.playbook
        let people = roster.everyone(dataManager)
        return TeamBlock(title: isChinese ? "队员 · \(roster.count)" : "Roster · \(roster.count)", icon: "person.3.fill") {
            VStack(spacing: 0) {
                ForEach(people) { player in
                    let isCoach = roster.coaches.contains { $0.id == player.id }
                    let drills = book.workout(for: player.id).count
                    let roles = book.roles(of: player.id)
                    HStack(spacing: 8) {
                        NavigationLink(destination: TeamWorkoutView(teamId: teamId, playerId: player.id)) {
                            HStack(spacing: 12) {
                                StudentAvatarView(student: player, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(player.primaryDisplayName).font(.body.weight(.medium)).lineLimit(1)
                                        if isCoach {
                                            Text(isChinese ? "教练" : "Coach")
                                                .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                                .padding(.horizontal, 7).padding(.vertical, 2)
                                                .background(Color.indigo, in: .capsule)
                                        }
                                    }
                                    Text(roles.isEmpty ? (isChinese ? "还没有分配号位" : "No role yet") : roles.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                if drills > 0 {
                                    Text(isChinese ? "\(drills) 个练习" : (drills == 1 ? "1 drill" : "\(drills) drills"))
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.green)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(isCoach ? "team.coach" : "team.athlete")
                        Menu {
                            Button { open(player) } label: {
                                Label(isChinese ? "查看资料" : "View profile", systemImage: "person.crop.circle")
                            }
                            Button(role: .destructive) {
                                TeamStore.update(teamId, in: dataManager) { team in
                                    team.playerIds.removeAll { $0 == player.id }
                                }
                            } label: { Label(isChinese ? "移出球队" : "Remove from team", systemImage: "minus.circle") }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 30, height: 30)
                        }
                        .accessibilityIdentifier("team.member.menu")
                    }
                    if player.id != people.last?.id { Divider().padding(.leading, 52) }
                }
                Button { addingPlayers = true } label: {
                    Label(isChinese ? "添加队员" : "Add Players", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
                .accessibilityIdentifier("team.addPlayers")
            }
        }
    }

    @ViewBuilder
    private func practicesBlock(_ team: Team) -> some View {
        let practices = dataManager.sessionEvents
            .filter { $0.curriculum.teamId == team.id }
            .sorted { $0.startTime > $1.startTime }
        TeamBlock(title: isChinese ? "球队训练" : "Practices", icon: "calendar", tint: .indigo) {
            if practices.isEmpty {
                Text(isChinese ? "在“课程”中新建“球队训练”，选择这支球队。"
                               : "In Sessions, create a Team Practice and pick this team.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(practices.prefix(4)) { session in
                        NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.startTime.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                        .font(.body.weight(.medium))
                                    Text(session.startTime.formatted(date: .omitted, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.startTime < Date() && !SessionLifecycle.didNotHappen(session) {
                                    Text(isChinese ? "\(session.actualAttendeeIds.count) 人到场" : "\(session.actualAttendeeIds.count) present")
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Writing a team

enum TeamStore {
    @MainActor
    static func update(_ teamId: UUID, in dataManager: DataManager, _ change: (inout Team) -> Void) {
        guard var team = dataManager.teams.first(where: { $0.id == teamId }) else { return }
        change(&team)
        team.updatedAt = Date()
        dataManager.updateTeam(team)
    }
}

// MARK: - Focus

/// Pick the plays practice works on now, from the team's playbook.
struct TeamFocusSheet: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String>

    init(team: Team) {
        self.team = team
        _chosen = State(initialValue: Set(team.playbook.focus))
    }

    var body: some View {
        let book = team.playbook
        NavigationStack {
            List {
                ForEach(TeamPlaybook.Kind.allCases.filter { !book[$0].plays.isEmpty }) { kind in
                    Section(kind.title) {
                        ForEach(book[kind].plays, id: \.key) { ref in
                            let on = chosen.contains(ref.key)
                            let roles = book.breakdowns[ref.key]?.roles.count ?? 0
                            Button {
                                if on { chosen.remove(ref.key) } else { chosen.insert(ref.key) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: ref.name).foregroundStyle(.primary)
                                        Text(roles == 0 ? (isChinese ? "还没拆解" : "Not broken down yet")
                                                        : (isChinese ? "\(roles) 个号位" : "\(roles) roles"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color.accentColor : .secondary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("team.focus.option")
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "当前重点" : "Focus now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") {
                        TeamStore.update(team.id, in: dataManager) { team in
                            team.playbook.focus = team.playbook.allPlays.map(\.ref.key).filter(chosen.contains)
                        }
                        dismiss()
                    }
                    .accessibilityIdentifier("team.focus.save")
                }
            }
        }
    }
}

// MARK: - Add players

struct TeamAddPlayersSheet: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        let taken = Set(team.playerIds)
        AthletePickerSheet(
            title: isChinese ? "添加队员" : "Add Players",
            students: dataManager.students.filter { !taken.contains($0.id) },
            accentColor: Color(hex: team.colorHex),
            banner: AthletePickerSheet.Banner(
                title: isChinese ? "加入 \(team.name)" : "Join \(team.name)",
                subtitle: isChinese ? "从学员和组织里的教练中选择。不影响项目和合约。"
                                    : "Pick athletes and coaches from your organization. Programs and contracts are not touched.",
                icon: "person.3.sequence.fill",
                tint: Color(hex: team.colorHex)),
            confirmLabel: isChinese ? "添加" : "Add",
            showSelectionCounter: false,
            coaches: dataManager.staffCoaches
                .filter { $0.isActive && !taken.contains($0.id) }
                .map { $0.asGuestPlayer(dataManager: dataManager) }
        ) { ids in
            TeamStore.update(team.id, in: dataManager) { team in
                team.playerIds.append(contentsOf: ids.filter { !team.playerIds.contains($0) })
            }
        }
    }
}

// MARK: - A playbook section

struct TeamSectionView: View {
    let teamId: UUID
    let kind: TeamPlaybook.Kind
    @EnvironmentObject var dataManager: DataManager
    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]
    @State private var picking = false
    @State private var notes: String?
    @State private var noteSave: Task<Void, Never>?

    private var team: Team? { dataManager.teams.first { $0.id == teamId } }

    var body: some View {
        let section = team?.playbook[kind] ?? TeamPlaybook.Section()
        let book = team?.playbook ?? TeamPlaybook()
        List {
            Section {
                ForEach(Array(section.plays.enumerated()), id: \.element) { index, ref in
                    let found = library.first { $0.isNamed(by: ref) }
                    let roles = book.breakdowns[ref.key]?.roles.count ?? 0
                    NavigationLink(destination: PlayBreakdownView(teamId: teamId, ref: ref)) {
                        HStack(spacing: 12) {
                            if let found {
                                JournalPlayThumbnail(diagram: found.conceptPart?.sortedSteps.first?.diagram,
                                                     court: found.court, width: 56, height: 46)
                            } else {
                                Image(systemName: "questionmark.square.dashed").font(.title3).foregroundStyle(.tertiary)
                                    .frame(width: 56, height: 46)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: found?.name ?? ref.name).font(.body.weight(.medium))
                                Text(roles > 0 ? (isChinese ? "已拆解 · \(roles) 个号位" : "Broken down · \(roles) roles")
                                               : (isChinese ? "点开拆解" : "Tap to break it down"))
                                    .font(.caption)
                                    .foregroundStyle(roles > 0 ? Color.green : .secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("team.play")
                    .swipeActions {
                        Button(role: .destructive) {
                            TeamStore.update(teamId, in: dataManager) { $0.playbook[kind].plays.remove(at: index) }
                        } label: { Label(isChinese ? "移除" : "Remove", systemImage: "minus.circle") }
                    }
                }
                .onMove { from, to in
                    TeamStore.update(teamId, in: dataManager) { $0.playbook[kind].plays.move(fromOffsets: from, toOffset: to) }
                }
                Button { picking = true } label: {
                    Label(isChinese ? "添加战术" : "Add plays", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text(kind.hint)
            }
            Section(kind == .defense ? (isChinese ? "理念与体系" : "Philosophy & schemes") : (isChinese ? "备注" : "Notes")) {
                TextField(isChinese ? "写下要点…" : "Write it down…", text: Binding(
                    get: { notes ?? section.notes },
                    set: { text in
                        notes = text
                        noteSave?.cancel()
                        noteSave = Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            guard !Task.isCancelled else { return }
                            saveNotes()
                        }
                    }), axis: .vertical)
                    .lineLimit(3...12)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: saveNotes)
        .sheet(isPresented: $picking) {
            SessionPlayPicker(library: library, selected: section.plays) { chosen in
                TeamStore.update(teamId, in: dataManager) { $0.playbook[kind].plays = chosen }
            }
        }
    }

    private func saveNotes() {
        guard let notes else { return }
        self.notes = nil
        TeamStore.update(teamId, in: dataManager) { $0.playbook[kind].notes = notes }
    }
}

// MARK: - Breaking a play down

struct PlayBreakdownView: View {
    let teamId: UUID
    let ref: SessionPlayRef
    @EnvironmentObject var dataManager: DataManager
    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]
    @State private var stepIndex = 0
    @State private var editingRole: Int?
    @State private var openPlay = false

    private var team: Team? { dataManager.teams.first { $0.id == teamId } }
    private var play: JournalPlay? { library.first { $0.isNamed(by: ref) } }
    private var breakdown: PlayBreakdown? { team?.playbook.breakdowns[ref.key] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let play, let part = play.conceptPart, !part.sortedSteps.isEmpty {
                    JournalPlayStepPlayer(part: part, index: $stepIndex)
                    Button { openPlay = true } label: {
                        Label(isChinese ? "在战术库中打开" : "Open in Plays", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text(isChinese ? "这个战术已不在战术库中。" : "This play is no longer in the library.")
                        .foregroundStyle(.secondary)
                }

                if let breakdown, !breakdown.roles.isEmpty {
                    Text(isChinese ? "号位" : "Roles")
                        .font(.title3.weight(.bold))
                        .padding(.top, 4)
                    Text(isChinese ? "每个号位需要的技术、练习和标准，以及谁来打。" : "What each role needs — skills, drills, a standard — and who plays it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(breakdown.roles) { role in
                        Button { editingRole = role.number } label: { roleCard(role) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("breakdown.role.\(role.number)")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(isChinese ? "拆解这个战术" : "Break this play down").font(.title3.weight(.bold))
                        Text(isChinese ? "为战术里的每个号位写下需要的技术、对应的练习和标准，再分配给队员。每个人的个人训练会自动生成。"
                                       : "For each numbered role in the play, choose the skills it needs, the drills that build them and a standard — then say who plays it. Each player's workout builds itself.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(action: startBreakdown) {
                            Label(isChinese ? "开始拆解" : "Break it down", systemImage: "square.split.2x2")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("breakdown.start")
                    }
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                }
            }
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(play?.name ?? ref.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: { editingRole.map { RoleRef(number: $0) } }, set: { editingRole = $0?.number })) { role in
            RoleEditorSheet(teamId: teamId, ref: ref, number: role.number)
        }
        .sheet(isPresented: $openPlay) {
            if let play {
                NavigationStack {
                    JournalPlayScreen(play: play)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(isChinese ? "完成" : "Done") { openPlay = false }
                            }
                        }
                }
            }
        }
    }

    private struct RoleRef: Identifiable { let number: Int; var id: Int { number } }

    private func roleCard(_ role: PlayBreakdown.Role) -> some View {
        let players = role.playerIds.compactMap { id -> Student? in
            dataManager.students.first { $0.id == id }
                ?? dataManager.staffCoaches.first { $0.id == id }?.asGuestPlayer(dataManager: dataManager)
        }
        return HStack(alignment: .top, spacing: 14) {
            Text("\(role.number)")
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(role.standard.isEmpty ? (isChinese ? "点按写下这个号位的标准" : "Tap to set this role's standard") : role.standard)
                    .font(role.standard.isEmpty ? .subheadline : .body.weight(.semibold))
                    .foregroundStyle(role.standard.isEmpty ? .secondary : .primary)
                if !role.skills.isEmpty {
                    Text(role.skills.compactMap { ActivityType(rawValue: $0)?.title }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.purple)
                }
                HStack(spacing: 10) {
                    Label(isChinese ? "\(role.drillIds.count) 个练习" : "\(role.drillIds.count) drills", systemImage: "figure.basketball")
                    if !players.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(players.prefix(4)) { StudentAvatarView(student: $0, size: 24) }
                        }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// Roles from the play's numbered players (step 1), else 1–5.
    private func startBreakdown() {
        let numbers = play?.conceptPart?.sortedSteps.first?.diagram.offense.map(\.number).sorted() ?? []
        let roles = (numbers.isEmpty ? Array(1...5) : numbers).map { PlayBreakdown.Role(number: $0) }
        TeamStore.update(teamId, in: dataManager) {
            $0.playbook.breakdowns[ref.key] = PlayBreakdown(playName: play?.name ?? ref.name, roles: roles)
        }
    }
}

// MARK: - A role

struct RoleEditorSheet: View {
    let teamId: UUID
    let ref: SessionPlayRef
    let number: Int
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var role: PlayBreakdown.Role
    @State private var pickingDrills = false

    init(teamId: UUID, ref: SessionPlayRef, number: Int) {
        self.teamId = teamId
        self.ref = ref
        self.number = number
        let stored = DataManager.shared.teams.first { $0.id == teamId }?.playbook.breakdowns[ref.key]?
            .roles.first { $0.number == number }
        _role = State(initialValue: stored ?? PlayBreakdown.Role(number: number))
    }

    private var team: Team? { dataManager.teams.first { $0.id == teamId } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isChinese ? "例如：卡位、接球、两传一读" : "e.g. Seal, catch, two-pass read", text: $role.standard, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("role.standard")
                } header: {
                    Text(isChinese ? "标准" : "Standard")
                } footer: {
                    Text(isChinese ? "这个号位打好是什么样子。" : "What good looks like in this role.")
                }

                Section(isChinese ? "需要的技术" : "Skills it needs") {
                    FlowLayout(spacing: 8) {
                        ForEach(ActivityType.skills) { skill in
                            let on = role.skills.contains(skill.rawValue)
                            Button {
                                if on { role.skills.removeAll { $0 == skill.rawValue } } else { role.skills.append(skill.rawValue) }
                            } label: {
                                Text(skill.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(on ? .white : .primary)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(on ? Color.purple : Color(.tertiarySystemFill), in: .capsule)
                                    .fixedSize()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(role.drillIds, id: \.self) { id in
                        let drill = dataManager.drills.first { $0.id == id }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(drill?.localizedName ?? (isChinese ? "已删除的练习" : "Deleted drill"))
                            if let activity = drill?.libraryActivity {
                                Text("\(activity.age.title) · \(activity.type.title)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { role.drillIds.remove(atOffsets: $0) }
                    Button { pickingDrills = true } label: {
                        Label(isChinese ? "添加练习" : "Add drills", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("role.addDrills")
                } header: {
                    Text(isChinese ? "练习" : "Drills")
                } footer: {
                    Text(role.skills.isEmpty ? (isChinese ? "先选技术，练习列表会按技术筛选。" : "Choose skills first and the drill list narrows to them.")
                                             : (isChinese ? "按上面的技术筛选。" : "Narrowed to the skills above."))
                }

                if let team {
                    let roster = TeamRoster(team: team, dataManager: dataManager).everyone(dataManager)
                    Section(isChinese ? "谁来打" : "Who plays it") {
                        if roster.isEmpty {
                            Text(isChinese ? "球队还没有队员。" : "The team has no players yet.").foregroundStyle(.secondary)
                        }
                        ForEach(roster) { player in
                            let on = role.playerIds.contains(player.id)
                            Button {
                                if on { role.playerIds.removeAll { $0 == player.id } } else { role.playerIds.append(player.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    StudentAvatarView(student: player, size: 32)
                                    Text(player.primaryDisplayName).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Color.accentColor : .secondary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("role.player")
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "\(number) 号位" : "Role \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save", action: save).accessibilityIdentifier("role.save")
                }
            }
            .sheet(isPresented: $pickingDrills) {
                SkillDrillPicker(skills: role.skills, selected: role.drillIds) { role.drillIds = $0 }
            }
        }
    }

    private func save() {
        TeamStore.update(teamId, in: dataManager) { team in
            var breakdown = team.playbook.breakdowns[ref.key] ?? PlayBreakdown(playName: ref.name)
            if let i = breakdown.roles.firstIndex(where: { $0.number == number }) {
                breakdown.roles[i] = role
            } else {
                breakdown.roles.append(role)
                breakdown.roles.sort { $0.number < $1.number }
            }
            team.playbook.breakdowns[ref.key] = breakdown
        }
        dismiss()
    }
}

/// Drills for a role: library activities of the chosen skills (every age),
/// and the coach's personal drills; search across all.
struct SkillDrillPicker: View {
    let skills: [String]
    let selected: [UUID]
    let onDone: ([UUID]) -> Void
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: [UUID]
    @State private var search = ""

    init(skills: [String], selected: [UUID], onDone: @escaping ([UUID]) -> Void) {
        self.skills = skills
        self.selected = selected
        self.onDone = onDone
        _chosen = State(initialValue: selected)
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private func matches(_ drill: DrillItem) -> Bool {
        query.isEmpty || DrillFinder.typedMatch(query, in: [drill.name, drill.localizedName, drill.description] + drill.instructions)
    }

    private var personal: [DrillItem] {
        dataManager.drills.filter { !$0.isLibraryDrill && matches($0) }
            .sorted { $0.localizedName < $1.localizedName }
    }

    /// Library drills by skill, youngest age first.
    private func library(_ skill: String) -> [DrillItem] {
        let ages = ActivityAge.allCases
        func rank(_ drill: DrillItem) -> Int {
            guard let age = drill.libraryActivity?.age else { return -1 }
            return ages.firstIndex(of: age) ?? 0
        }
        let drills = dataManager.drills.filter { $0.tags.contains("type:\(skill)") && matches($0) }
        return drills.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a.localizedName < b.localizedName
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !personal.isEmpty {
                    Section(isChinese ? "个人" : "Personal") { ForEach(personal) { row($0) } }
                }
                ForEach(skills.isEmpty ? ActivityType.skills.map(\.rawValue) : skills, id: \.self) { skill in
                    let drills = library(skill)
                    if !drills.isEmpty {
                        Section(ActivityType(rawValue: skill)?.title ?? skill) { ForEach(drills) { row($0) } }
                    }
                }
            }
            .searchable(text: $search, prompt: isChinese ? "搜索练习" : "Search drills")
            .navigationTitle(isChinese ? "添加练习" : "Add drills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "取消" : "Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "完成" : "Done") { onDone(chosen); dismiss() }
                        .accessibilityIdentifier("drillPick.done")
                }
            }
        }
    }

    private func row(_ drill: DrillItem) -> some View {
        let on = chosen.contains(drill.id)
        return Button {
            if on { chosen.removeAll { $0 == drill.id } } else { chosen.append(drill.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(drill.localizedName).foregroundStyle(.primary)
                    if let activity = drill.libraryActivity {
                        Text("\(activity.age.title) · \(activity.block.title)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
            }
        }
        .accessibilityIdentifier("drillPick.row")
    }
}

// MARK: - Standards and workouts

struct TeamStandardsView: View {
    let teamId: UUID
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        let book = dataManager.teams.first { $0.id == teamId }?.playbook ?? TeamPlaybook()
        List {
            ForEach(book.skillDemands) { demand in
                Section {
                    ForEach(demand.roles, id: \.self) { Text($0) }
                } header: {
                    HStack {
                        Text(ActivityType(rawValue: demand.skill)?.title ?? demand.skill)
                        Text("\(demand.roles.count)").foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isChinese ? "标准" : "Standards")
    }
}

struct TeamWorkoutView: View {
    let teamId: UUID
    let playerId: UUID
    @EnvironmentObject var dataManager: DataManager
    @State private var openDrill: DrillItem?

    var body: some View {
        let book = dataManager.teams.first { $0.id == teamId }?.playbook ?? TeamPlaybook()
        let items = book.workout(for: playerId)
        let name = dataManager.students.first { $0.id == playerId }?.primaryDisplayName
            ?? dataManager.staffCoaches.first { $0.id == playerId }?.name ?? ""
        List {
            Section {
                ForEach(book.roles(of: playerId), id: \.self) { Text($0) }
            } header: {
                Text(isChinese ? "号位" : "Roles")
            } footer: {
                if book.roles(of: playerId).isEmpty {
                    Text(isChinese ? "在战术拆解里把这名队员分配到号位。" : "Assign this player to a role in a play breakdown.")
                }
            }
            if !items.isEmpty {
                Section(isChinese ? "个人训练" : "Workout") {
                    ForEach(items) { item in
                        let drill = dataManager.drills.first { $0.id == item.drillId }
                        Button { openDrill = drill } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drill?.localizedName ?? (isChinese ? "已删除的练习" : "Deleted drill")).foregroundStyle(.primary)
                                Text(item.sources.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .sheet(item: $openDrill) { drill in
            NavigationStack {
                DrillDetailView(drill: drill)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isChinese ? "完成" : "Done") { openDrill = nil }
                        }
                    }
            }
        }
    }
}

// MARK: - The team on a team practice's plan

/// The top of a team practice's Plan — where the team page and the session
/// meet: the plays the team is working on (its FOCUS), one button that
/// builds the plan from them (their roles' drills as Skills, a warm-up for the
/// skills they need, the plays), and WHO DOES WHAT — each person here, the
/// role they play in those plays and its standard.
struct SessionTeamPlanCard: View {
    let teamId: UUID
    let rosterIds: [UUID]
    let durationMinutes: Int
    let canEdit: Bool
    @Binding var curriculum: SessionCurriculum
    let onChange: () -> Void
    @EnvironmentObject var dataManager: DataManager
    @State private var openTeam = false
    @State private var confirmingRebuild = false

    var body: some View {
        if let team = dataManager.teams.first(where: { $0.id == teamId }) {
            card(team)
        }
    }

    private func card(_ team: Team) -> some View {
        let book = team.playbook
        let plays = book.focusPlays
        let colour = Color(hex: team.colorHex)
        let people = rosterIds.compactMap(person)
        let withParts = people.filter { !book.parts(of: $0.id, in: plays).isEmpty }
        let without = people.filter { book.parts(of: $0.id, in: plays).isEmpty }
        let planIsEmpty = curriculum.warmupDrillIds.isEmpty && curriculum.skillDrillIds.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TeamBadge(team: team, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team.name).font(.headline)
                    Text(isChinese ? "球队训练 · 不计费" : "Team practice · never billed")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { openTeam = true } label: {
                    Text(isChinese ? "球队" : "Team").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(colour)
                .accessibilityIdentifier("session.openTeam")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "正在练" : "WORKING ON").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                if plays.isEmpty {
                    Text(isChinese ? "球队还没有当前重点。在球队页面选出要练的战术，计划就能从中生成。"
                                   : "The team has no focus yet. Pick the plays practice works on in the team page and the plan builds from them.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(plays, id: \.key) { ref in
                            Text(verbatim: ref.name)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(colour.opacity(0.16), in: .capsule)
                                .fixedSize()
                        }
                    }
                    let skills = book.skills(in: plays).compactMap { ActivityType(rawValue: $0)?.title }
                    if !skills.isEmpty {
                        Text((isChinese ? "需要的技术：" : "Skills: ") + skills.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if canEdit && !plays.isEmpty {
                Button {
                    if planIsEmpty { build(book, plays) } else { confirmingRebuild = true }
                } label: {
                    Label(planIsEmpty ? (isChinese ? "用球队重点生成计划" : "Build the plan from the team")
                                      : (isChinese ? "按球队重点重新生成" : "Rebuild from the team"),
                          systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(colour)
                .accessibilityIdentifier("session.buildFromTeam")
            }

            if !withParts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isChinese ? "谁打什么" : "WHO DOES WHAT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    ForEach(withParts) { player in
                        HStack(alignment: .top, spacing: 10) {
                            StudentAvatarView(student: player, size: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.primaryDisplayName).font(.subheadline.weight(.semibold))
                                ForEach(Array(book.parts(of: player.id, in: plays).enumerated()), id: \.offset) { _, part in
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text("\(part.role.number)")
                                            .font(.caption2.weight(.heavy).monospacedDigit())
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(colour, in: Circle())
                                        Text(partLine(part, single: plays.count == 1))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("session.teamPart")
                    }
                    if !without.isEmpty {
                        Text((isChinese ? "这些战术里没有号位：" : "No role in these plays: ") + without.map(\.primaryDisplayName).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colour.opacity(0.08), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(colour.opacity(0.25), lineWidth: 1))
        .accessibilityIdentifier("session.teamPlan")
        .alert(isChinese ? "重新生成计划？" : "Rebuild the plan?", isPresented: $confirmingRebuild) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "重新生成" : "Rebuild") { build(book, plays) }
        } message: {
            Text(isChinese ? "热身和技能会换成球队重点的练习；已添加的战术保留。"
                           : "Warm-up and Skills are replaced with the focus plays' drills; plays already in the plan stay.")
        }
        .sheet(isPresented: $openTeam) {
            NavigationStack {
                TeamDetailView(teamId: teamId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(isChinese ? "完成" : "Done") { openTeam = false }
                        }
                    }
            }
        }
    }

    /// With one focus play its name would repeat on every row: the role's
    /// standard alone then.
    private func partLine(_ part: TeamPlaybook.Part, single: Bool) -> String {
        let standard = part.role.standard
        if single { return standard.isEmpty ? (isChinese ? "\(part.role.number) 号位" : "Role \(part.role.number)") : standard }
        return standard.isEmpty ? part.playName : "\(part.playName) — \(standard)"
    }

    private func person(_ id: UUID) -> Student? {
        dataManager.students.first { $0.id == id }
            ?? dataManager.staffCoaches.first { $0.id == id }?.asGuestPlayer(dataManager: dataManager)
    }

    private func build(_ book: TeamPlaybook, _ plays: [SessionPlayRef]) {
        curriculum = book.practicePlan(plays: plays, drills: dataManager.drills,
                                       durationMinutes: durationMinutes, keeping: curriculum)
        onChange()
        HapticFeedback.notification(.success)
    }
}

// MARK: - On a profile

/// Team practices a person was expected at (roster or team coach) or marked
/// at, that happened and have begun. Never billed — this is the record.
@MainActor
func teamPractices(of memberId: UUID, in dataManager: DataManager) -> [SessionEvent] {
    dataManager.sessionEvents
        .filter { session in
            session.sessionType == .teamPractice
                && !SessionLifecycle.didNotHappen(session)
                && session.startTime <= Date()
                && (session.attendeeIds.contains(memberId)
                    || session.curriculum.coachIds.contains(memberId)
                    || session.actualAttendeeIds.contains(memberId)
                    || session.excusedAbsences.contains(memberId))
        }
        .sorted { $0.startTime > $1.startTime }
}

/// "Team practices · 6 of 8" with a list behind it — in the athlete
/// profile's contract section and on the coach profile.
struct TeamPracticeRecordRow: View {
    let memberId: UUID
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        let practices = teamPractices(of: memberId, in: dataManager)
        if !practices.isEmpty {
            let attended = practices.filter { $0.actualAttendeeIds.contains(memberId) }.count
            NavigationLink(destination: TeamPracticeRecordView(memberId: memberId)) {
                HStack(spacing: 12) {
                    Image(systemName: SessionType.teamPractice.icon)
                        .foregroundStyle(.indigo)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isChinese ? "球队训练" : "Team practices").font(.subheadline.weight(.semibold))
                        Text(isChinese ? "到场 \(attended) / \(practices.count) · 不计费" : "\(attended) of \(practices.count) attended · never billed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.indigo.opacity(0.08), in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.teamPractices")
        }
    }
}

struct TeamPracticeRecordView: View {
    let memberId: UUID
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        List(teamPractices(of: memberId, in: dataManager)) { session in
            let team = session.curriculum.teamId.flatMap { id in dataManager.teams.first { $0.id == id } }
            let mark: (String, Color) = session.actualAttendeeIds.contains(memberId)
                ? (isChinese ? "到场" : "Present", .green)
                : session.excusedAbsences.contains(memberId)
                    ? (isChinese ? "请假" : "Excused", .orange)
                    : (isChinese ? "缺席" : "Absent", .secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    Text([team?.name, session.startTime.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(mark.0).font(.subheadline.weight(.semibold)).foregroundStyle(mark.1)
            }
        }
        .navigationTitle(isChinese ? "球队训练" : "Team practices")
    }
}

/// The athlete's (or coach's) workout from every team they play a role in.
struct TeamWorkoutProfileSection: View {
    let memberId: UUID
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        let teams = dataManager.teams.filter { !$0.playbook.workout(for: memberId).isEmpty }
        if !teams.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.basketball").foregroundStyle(.green)
                    Text(isChinese ? "球队个人训练" : "Team workout").font(.headline)
                }
                ForEach(teams) { team in
                    let items = team.playbook.workout(for: memberId)
                    NavigationLink(destination: TeamWorkoutView(teamId: team.id, playerId: memberId)) {
                        HStack(spacing: 12) {
                            TeamBadge(team: team, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(team.name).font(.subheadline.weight(.semibold))
                                Text([team.playbook.roles(of: memberId).joined(separator: ", "),
                                      isChinese ? "\(items.count) 个练习" : "\(items.count) drills"]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.teamWorkout")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }
    }
}
