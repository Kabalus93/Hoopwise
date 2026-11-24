import SwiftUI
import SwiftData

// A PLAYER ON A TEAM (23 Nov 2026, Luther, markup on this page: "make this
// page better — useful, complete, expressive … also add a scheduler, for
// example a session to have the athlete work on the skills he'll need for
// his position. Also a way to export plays focused on him."). Opened from the
// team's roster.
//
// Who he is on this team; the skills his roles ask for; each ROLE with its
// play, number and standard; the WORKOUT those roles add up to; a POSITION
// WORKOUT scheduled in one sheet (a team session with only him on it — never
// billed — whose plan is his drills and his plays); and HIS PLAYS exported as
// one PDF, every play followed from his role.

struct TeamWorkoutView: View {
    let teamId: UUID
    let playerId: UUID
    @EnvironmentObject var dataManager: DataManager
    @Query(sort: [SortDescriptor(\JournalPlay.order), SortDescriptor(\JournalPlay.createdAt)])
    private var library: [JournalPlay]
    @State private var openDrill: DrillItem?
    @State private var scheduling = false
    @State private var exporting = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var team: Team? { dataManager.teams.first { $0.id == teamId } }
    private var athlete: Student? { dataManager.students.first { $0.id == playerId } }
    private var person: Student? {
        athlete ?? dataManager.staffCoaches.first { $0.id == playerId }?.asGuestPlayer(dataManager: dataManager)
    }

    var body: some View {
        let book = team?.playbook ?? TeamPlaybook()
        let roles = book.playerRoles(of: playerId)
        let items = book.workout(for: playerId)
        let drills = items.compactMap { item in dataManager.drills.first { $0.id == item.drillId } }
        let minutes = drills.reduce(0) { $0 + $1.durationMinutes }
        let tint = Color(hex: team?.colorHex ?? "#2A78D6")
        ScrollView {
            VStack(spacing: 16) {
                header(roles: roles, drills: drills.count, minutes: minutes, tint: tint)
                actions(roles: roles, drills: drills, tint: tint)
                if roles.isEmpty {
                    card(isChinese ? "还没有号位" : "NO ROLE YET", icon: "person.crop.circle.badge.questionmark", tint: .orange) {
                        Text(isChinese ? "打开战术手册里的一个战术，在“拆解”里把这名队员放到一个号位上：这里就会出现要练的技术、练习和战术。"
                                       : "Open a play in the playbook and put this player on a role in its breakdown: the skills, drills and plays for that role then show here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    skillsCard(book.skills(of: playerId), tint: tint)
                    rolesCard(roles, tint: tint)
                    workoutCard(items, minutes: minutes)
                }
                sessionsCard(tint: tint)
            }
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .padding(16)
            .padding(.bottom, 80)
        }
        .background(FilmRoomPageBackground())
        .navigationTitle(person?.primaryDisplayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $openDrill) { drill in
            NavigationStack {
                DrillDetailView(drill: drill)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isChinese ? "完成" : "Done") { openDrill = nil }
                        }
                    }
            }
            .environmentObject(dataManager)
        }
        .sheet(isPresented: $scheduling) {
            if let team, let athlete {
                PositionWorkoutSheet(team: team, athlete: athlete, drills: drills, plays: uniqueRefs(roles))
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $exporting) {
            if let team {
                PlayerPlaysShareSheet(team: team, playerId: playerId, playerName: person?.primaryDisplayName ?? "",
                                      roles: roles, library: library)
                    .environmentObject(dataManager)
            }
        }
    }

    private func uniqueRefs(_ roles: [TeamPlaybook.PlayerRole]) -> [SessionPlayRef] {
        var seen = Set<String>()
        return roles.filter { seen.insert($0.key).inserted }.map(\.ref)
    }

    // MARK: Header

    private func header(roles: [TeamPlaybook.PlayerRole], drills: Int, minutes: Int, tint: Color) -> some View {
        let plays = Set(roles.map(\.key)).count
        return VStack(spacing: 16) {
            HStack(spacing: 16) {
                if let person { StudentAvatarView(student: person, size: 76) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(person?.primaryDisplayName ?? "").font(.title2.weight(.bold)).foregroundStyle(.white).lineLimit(2)
                    if let second = person?.secondaryNameLine {
                        Text(second).font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 6) {
                        Text(team?.name ?? "").font(.footnote.weight(.semibold))
                        if athlete == nil {
                            Text(isChinese ? "教练" : "Coach")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.white.opacity(0.25), in: .capsule)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                stat("\(roles.count)", isChinese ? "号位" : (roles.count == 1 ? "Role" : "Roles"))
                stat("\(plays)", isChinese ? "战术" : (plays == 1 ? "Play" : "Plays"))
                stat("\(drills)", isChinese ? "练习" : (drills == 1 ? "Drill" : "Drills"))
                stat("\(minutes)", isChinese ? "分钟" : "Minutes")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("team.player.header")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2.weight(.medium)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Schedule · Export

    private func actions(roles: [TeamPlaybook.PlayerRole], drills: [DrillItem], tint: Color) -> some View {
        HStack(spacing: 12) {
            if athlete != nil {
                Button { scheduling = true } label: {
                    Label(isChinese ? "安排个人训练" : "Schedule a workout", systemImage: "calendar.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(drills.isEmpty && roles.isEmpty)
                .accessibilityIdentifier("team.player.schedule")
            }
            Button { exporting = true } label: {
                Label(isChinese ? "导出战术" : "Export plays", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
            .disabled(roles.isEmpty)
            .accessibilityIdentifier("team.player.export")
        }
    }

    // MARK: Cards

    private func card<Content: View>(_ title: String, icon: String, tint: Color, trailing: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title).font(.caption2.weight(.bold)).monospaced()
                } icon: { Image(systemName: icon).font(.caption) }
                .foregroundStyle(tint)
                Spacer()
                if let trailing { Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit() }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.filmCard))
    }

    private func skillTitle(_ raw: String) -> String { ActivityType(rawValue: raw)?.title ?? raw }
    private func skillIcon(_ raw: String) -> String { ActivityType(rawValue: raw)?.icon ?? "circle" }

    private func skillsCard(_ skills: [(skill: String, count: Int)], tint: Color) -> some View {
        card(isChinese ? "需要的技术" : "SKILLS NEEDED", icon: "bolt.fill", tint: .orange) {
            if skills.isEmpty {
                Text(isChinese ? "这些号位还没有写需要的技术。" : "These roles have no skills written yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(skills, id: \.skill) { item in
                        HStack(spacing: 6) {
                            Image(systemName: skillIcon(item.skill)).font(.caption)
                            Text(skillTitle(item.skill)).font(.subheadline.weight(.medium))
                            if item.count > 1 {
                                Text("×\(item.count)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                    }
                }
            }
        }
    }

    private func rolesCard(_ roles: [TeamPlaybook.PlayerRole], tint: Color) -> some View {
        card(isChinese ? "号位" : "ROLES", icon: "person.fill.viewfinder", tint: tint) {
            VStack(spacing: 0) {
                ForEach(roles) { item in
                    let found = library.first { $0.isNamed(by: item.ref) }
                    NavigationLink(destination: PlayBreakdownView(teamId: teamId, ref: item.ref)) {
                        HStack(alignment: .top, spacing: 12) {
                            if let found {
                                JournalPlayThumbnail(diagram: found.conceptPart?.sortedSteps.first?.diagram,
                                                     court: found.court, width: 84, height: 60)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text("\(item.role.number)")
                                        .font(.footnote.weight(.bold)).foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(tint))
                                    Text(verbatim: found?.name ?? item.playName).font(.body.weight(.semibold)).lineLimit(1)
                                }
                                Text(item.role.standard.isEmpty ? (isChinese ? "还没有写标准" : "No standard written yet") : item.role.standard)
                                    .font(.subheadline)
                                    .foregroundStyle(item.role.standard.isEmpty ? .tertiary : .secondary)
                                    .multilineTextAlignment(.leading)
                                if !item.role.skills.isEmpty {
                                    Text(item.role.skills.map(skillTitle).joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("team.player.role")
                    if item.id != roles.last?.id { Divider() }
                }
            }
        }
    }

    private func workoutCard(_ items: [TeamPlaybook.WorkoutItem], minutes: Int) -> some View {
        card(isChinese ? "个人训练" : "WORKOUT", icon: "figure.basketball", tint: .green,
             trailing: items.isEmpty ? nil : (isChinese ? "\(minutes) 分钟" : "\(minutes) min")) {
            if items.isEmpty {
                Text(isChinese ? "这些号位还没有配练习：在战术拆解里给号位加练习。"
                               : "These roles have no drills yet — add drills to a role in the play's breakdown.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let drill = dataManager.drills.first { $0.id == item.drillId }
                        Button { openDrill = drill } label: {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Color(.tertiarySystemFill)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(drill?.localizedName ?? (isChinese ? "已删除的练习" : "Deleted drill"))
                                        .font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text(([drill.map { isChinese ? "\($0.durationMinutes) 分钟" : "\($0.durationMinutes) min" }]
                                          + [isChinese ? "用于 " + item.sources.joined(separator: "、") : "for " + item.sources.joined(separator: ", ")])
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 9)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(drill == nil)
                        .accessibilityIdentifier("team.player.drill")
                        if index < items.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    /// Position workouts already scheduled for him on this team.
    @ViewBuilder
    private func sessionsCard(tint: Color) -> some View {
        let sessions = dataManager.sessionEvents
            .filter { $0.curriculum.teamId == teamId && $0.sessionType == .teamPractice && $0.attendeeIds == [playerId] }
            .sorted { $0.startTime > $1.startTime }
        if !sessions.isEmpty {
            card(isChinese ? "个人训练课" : "POSITION WORKOUTS", icon: "calendar", tint: .indigo) {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(5)) { session in
                        NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(session.startTime.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                        .font(.body.weight(.medium))
                                    Text(session.startTime.formatted(date: .omitted, time: .shortened)
                                         + " · " + (isChinese ? "\(session.curriculum.skillDrillIds.count + session.curriculum.warmupDrillIds.count) 个练习"
                                                              : "\(session.curriculum.skillDrillIds.count + session.curriculum.warmupDrillIds.count) drills"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.startTime > Date() {
                                    Text(isChinese ? "即将进行" : "Upcoming").font(.caption.weight(.semibold)).foregroundStyle(tint)
                                } else if session.actualAttendeeIds.contains(playerId) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("team.player.session")
                    }
                }
            }
        }
    }
}

// MARK: - Schedule a position workout

/// One sheet: when, how long, where, which of his drills, his plays. It makes
/// a TEAM session (never billed) with only him on it, planned with those
/// drills and plays.
struct PositionWorkoutSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let team: Team
    let athlete: Student
    let drills: [DrillItem]
    let plays: [SessionPlayRef]

    @State private var start: Date
    @State private var minutes: Int
    @State private var venue: String
    @State private var chosen: Set<UUID>
    @State private var includePlays = true

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    init(team: Team, athlete: Student, drills: [DrillItem], plays: [SessionPlayRef]) {
        self.team = team
        self.athlete = athlete
        self.drills = drills
        self.plays = plays
        let total = drills.reduce(0) { $0 + $1.durationMinutes }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _start = State(initialValue: cal.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
        _minutes = State(initialValue: [30, 45, 60, 90].first { $0 >= total } ?? 90)
        _venue = State(initialValue: team.homeVenue ?? "")
        _chosen = State(initialValue: Set(drills.map(\.id)))
    }

    private var chosenMinutes: Int { drills.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.durationMinutes } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(isChinese ? "时间" : "When", selection: $start)
                        .accessibilityIdentifier("workout.date")
                    Picker(isChinese ? "时长" : "Length", selection: $minutes) {
                        ForEach([30, 45, 60, 90], id: \.self) { m in Text(isChinese ? "\(m) 分钟" : "\(m) min").tag(m) }
                    }
                    TextField(isChinese ? "场地" : "Venue", text: $venue)
                } footer: {
                    Text(isChinese ? "这是一节只有 \(athlete.primaryDisplayName) 的球队课：记出勤，不扣课时。"
                                   : "A team session with only \(athlete.primaryDisplayName) on it: attendance is recorded, nothing is billed.")
                }
                Section {
                    if drills.isEmpty {
                        Text(isChinese ? "这些号位还没有配练习；课上可以再加。" : "These roles have no drills yet — you can add some on the session.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(drills) { drill in
                        let on = chosen.contains(drill.id)
                        Button {
                            if on { chosen.remove(drill.id) } else { chosen.insert(drill.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(drill.localizedName).foregroundStyle(.primary)
                                    Text(isChinese ? "\(drill.durationMinutes) 分钟" : "\(drill.durationMinutes) min")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workout.drill")
                    }
                } header: {
                    Text(isChinese ? "练习" : "Drills")
                } footer: {
                    if !drills.isEmpty {
                        Text(isChinese ? "已选 \(chosen.count) 个 · 约 \(chosenMinutes) 分钟" : "\(chosen.count) chosen · about \(chosenMinutes) min")
                    }
                }
                if !plays.isEmpty {
                    Section {
                        Toggle(isOn: $includePlays) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(isChinese ? "带上这些战术" : "Include the plays")
                                Text(plays.map(\.name).joined(separator: isChinese ? "、" : ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isChinese ? "安排个人训练" : "Position workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "安排" : "Schedule") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("workout.save")
                }
            }
        }
    }

    private func save() {
        var curriculum = SessionCurriculum()
        curriculum.teamId = team.id
        curriculum.skillDrillIds = drills.filter { chosen.contains($0.id) }.map(\.id)
        curriculum.skillsMinutes = max(chosenMinutes, 10)
        curriculum.warmupMinutes = 0
        curriculum.gameMinutes = 0
        if includePlays { curriculum.plays = plays }
        let place = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        dataManager.createSession(SessionCreation.Intent(
            group: .unassigned,
            sessionType: .teamPractice,
            start: start,
            durationMinutes: minutes,
            title: isChinese ? "\(athlete.primaryDisplayName) · 个人训练" : "\(athlete.primaryDisplayName) · Position workout",
            location: place.isEmpty ? nil : place,
            roster: [athlete.id],
            curriculum: curriculum,
            createdByCoachId: dataManager.loggedInCoachId))
        dismiss()
    }
}

// MARK: - His plays, as one PDF

/// Every play he has a role in, each as a player sheet followed from his
/// role (PlaySheetDocument) — one PDF, a long image, or the printer.
struct PlayerPlaysShareSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    let team: Team
    let playerId: UUID
    let playerName: String
    let roles: [TeamPlaybook.PlayerRole]
    let library: [JournalPlay]

    @State private var faces = true
    /// Asked each time, like every play sheet.
    @State private var defenders: Bool?
    @State private var pdf: Data?
    @State private var preview: UIImage?
    @State private var sharing: [Any]?

    private var chinese: Bool { AreaLanguage.isChinese(.exports) }
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var found: [(TeamPlaybook.PlayerRole, JournalPlay)] {
        roles.compactMap { role in library.first { $0.isNamed(by: role.ref) }.map { (role, $0) } }
    }
    private var hasDefense: Bool {
        found.contains { $0.1.sortedParts.contains { $0.sortedSteps.contains { !$0.diagram.defense.isEmpty } } }
    }
    private var ready: Bool { !found.isEmpty && (!hasDefense || defenders != nil) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SwiftUI.Group {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                            .accessibilityIdentifier("playerPlays.preview")
                    } else if found.isEmpty {
                        Text(isChinese ? "这些战术已不在战术库中。" : "These plays are no longer in the library.")
                            .foregroundStyle(.secondary).frame(height: 300)
                    } else {
                        ProgressView().frame(height: 300)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(FilmRoomPageBackground())
                Form {
                    Section {
                        ForEach(found, id: \.0.id) { role, play in
                            HStack {
                                Text(verbatim: play.name)
                                Spacer()
                                Text(isChinese ? "\(role.role.number) 号位" : "Role \(role.role.number)").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(isChinese ? "\(playerName) 的战术" : "\(playerName)'s plays")
                    } footer: {
                        Text(isChinese ? "每个战术一份球员单：这名队员的跑位加粗标色，每一步写明要做什么，附上号位标准和练习。"
                                       : "One player sheet per play: this player's moves in bold colour, the job at each step, with the role's standard and drills.")
                    }
                    Section {
                        Toggle(isChinese ? "球场上显示照片" : "Faces on the court", isOn: $faces)
                    }
                    if hasDefense {
                        Section {
                            Picker(isChinese ? "防守球员" : "Defenders", selection: $defenders) {
                                Text(isChinese ? "显示" : "Show").tag(Optional(true))
                                Text(isChinese ? "隐藏" : "Hide").tag(Optional(false))
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("playerPlays.defenders")
                        } header: {
                            Text(isChinese ? "防守球员" : "Defenders")
                        } footer: {
                            if defenders == nil {
                                Text(isChinese ? "每次都要选：这些单子要画防守吗？" : "Choose each time: should these sheets show the defense?")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { share(pdfFile: true) } label: { Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("playerPlays.sharePDF")
                    Button(action: printSheets) { Label(isChinese ? "打印" : "Print", systemImage: "printer").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button { share(pdfFile: false) } label: { Label(isChinese ? "长图" : "Image", systemImage: "photo").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .disabled(!ready || pdf == nil)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle(isChinese ? "导出战术" : "Export plays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: sharing) }
            }
        }
        .presentationSizing(.page)
        .onAppear(perform: render)
        .onChange(of: faces) { render() }
        .onChange(of: defenders) { render() }
    }

    private func sheets() -> [PlaySheet] {
        found.map { role, play in
            var cast = dataManager.teamPlayCast(teamId: team.id, ref: play.planRef, chinese: chinese)
            // He is the one on his role on these sheets.
            cast?.lineup[role.role.number] = playerId
            let numbers = play.conceptPart?.sortedSteps.first?.diagram.offense.map(\.number).sorted() ?? []
            let all = Set(numbers + (cast?.seats.map(\.number) ?? [])).sorted()
            let seat = cast?.seats.first { $0.number == role.role.number }
            var sheet = PlaySheet(
                playName: play.name, category: play.category, court: play.court,
                situation: play.situation, idea: play.concept, parts: PlaySheet.parts(of: play),
                teamName: team.name, teamColor: UIColor(Color(hex: team.colorHex)),
                academy: ProgramGuideStore.academyName,
                roles: all.map { PlaySheet.Role(number: $0, name: cast?.person(for: $0)?.name) },
                bubbles: faces ? (cast?.bubbles(photos: true) ?? [:]) : [:],
                showsDefense: defenders ?? true, chinese: chinese)
            sheet.focus = role.role.number
            sheet.focusName = cast?.person(for: role.role.number)?.name ?? playerName
            sheet.focusStandard = seat?.standard ?? role.role.standard
            sheet.focusDrills = seat?.drillNames ?? []
            return sheet
        }
    }

    private func render() {
        guard !found.isEmpty else { return }
        let data = PlaySheetDocument.pdf(sheets())
        pdf = data
        preview = PlaySheetDocument.preview(pdf: data, width: 900)
    }

    private var fileStem: String {
        "\(playerName)_\(team.name)".components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
    }

    private func share(pdfFile: Bool) {
        guard let pdf else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlaySheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if pdfFile {
            let url = dir.appendingPathComponent("Plays_\(fileStem).pdf")
            try? pdf.write(to: url)
            sharing = [url]
        } else if let jpeg = PlaySheetDocument.longImage(pdf: pdf) {
            let url = dir.appendingPathComponent("Plays_\(fileStem).jpg")
            try? jpeg.write(to: url)
            sharing = [url]
        }
    }

    private func printSheets() {
        guard let pdf else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = playerName
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true)
    }
}
