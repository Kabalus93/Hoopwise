import SwiftUI
import PhotosUI

// The coach's profile and the Add / Edit Coach form (November 2026, Luther:
// "very messy … make it look better and intentional … show the game stats
// too, their last attended practice, their position when playing 5v5,
// tendencies"). Both read like the Organization page they open from: a
// header, then native grouped sections. A coach's games are the scrimmages
// and game prep sessions they played in (SessionCurriculum.coachIds), read
// through the same GameStatsReport as an athlete's.

// MARK: - Shared pieces

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

/// A small capsule: the role, "You", "Inactive".
private struct CoachTag: View {
    let text: String
    let tint: Color
    var filled = true

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(filled ? tint : tint.opacity(0.14), in: .capsule)
    }
}

/// A tendency as a chip: icon and word in its colour.
struct TendencyChip: View {
    let tendency: PlayerTendency
    var selected = true

    var body: some View {
        // An explicit row, not a Label: inside a Form a Label became an
        // icon-only, tall pill.
        HStack(spacing: 5) {
            Image(systemName: tendency.icon)
            Text(tendency.label).lineLimit(1)
        }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(selected ? tendency.tint : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? tendency.tint.opacity(0.14) : Color(.tertiarySystemFill), in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? tendency.tint.opacity(0.35) : .clear, lineWidth: 1))
            .fixedSize()
    }
}

/// The coach's photo, else their initials on their colour.
private struct CoachAvatar: View {
    let coach: StaffCoach
    var image: UIImage?
    let size: CGFloat
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        if let photo = image ?? OrgCoachRow.photo(of: coach, dataManager: dataManager) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            PanelAvatar(initials: coach.initials.isEmpty ? "?" : coach.initials,
                        color: Color.avatarColor(coach.avatarColor), size: size)
        }
    }
}

extension DataManager {
    /// The sessions a coach played in (scrimmage / game prep), newest last.
    func sessionsPlayed(byCoach id: UUID) -> [SessionEvent] {
        sessionEvents
            .filter { $0.curriculum.coachIds.contains(id) && !SessionLifecycle.didNotHappen($0) }
            .sorted { $0.startTime < $1.startTime }
    }
}

// MARK: - Profile

struct CoachProfileDetailView: View {
    let coach: StaffCoach
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager
    @State private var showingEdit = false

    /// The stored coach, so an edit shows at once.
    private var current: StaffCoach { dataManager.staffCoaches.first { $0.id == coach.id } ?? coach }
    private var programs: [Program] { dataManager.programs.filter { $0.coachId == coach.id } }
    private var played: [SessionEvent] { dataManager.sessionsPlayed(byCoach: coach.id) }
    private var lastPlayed: SessionEvent? { played.last { $0.startTime <= Date() } }
    private var report: GameStatsReport.PlayerReport { GameStatsReport.player(coach.id, sessions: played) }

    private var names: (primary: String, secondary: String?) {
        let zh = current.chineseName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !zh.isEmpty, zh != current.name else { return (current.name, nil) }
        return isChinese ? (zh, current.name) : (current.name, zh)
    }

    var body: some View {
        NavigationStack {
            List {
                Section { header }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                if report.games > 0 {
                    Section { statTiles }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                onTheFloor
                recentGames
                teamsSection
                coaching
                contact

                if let notes = current.notes, !notes.isEmpty {
                    Section(isChinese ? "备注" : "Notes") {
                        Text(notes).font(.body)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .navigationTitle(isChinese ? "教练" : "Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "编辑" : "Edit") { showingEdit = true }
                        .accessibilityIdentifier("coach.edit")
                }
            }
            .sheet(isPresented: $showingEdit) {
                AddEditCoachView(coach: current)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CoachAvatar(coach: current, size: 96)
            VStack(spacing: 2) {
                Text(names.primary)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if let secondary = names.secondary {
                    Text(secondary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                CoachTag(text: current.role.localizedName, tint: current.role.color)
                if let position = current.playerPosition {
                    CoachTag(text: position.short, tint: .indigo, filled: false)
                }
                if current.id == dataManager.loggedInCoachId {
                    CoachTag(text: isChinese ? "我" : "You", tint: .accentColor, filled: false)
                }
                if !current.isActive {
                    CoachTag(text: isChinese ? "停用" : "Inactive", tint: .secondary, filled: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var statTiles: some View {
        let avg = report.average
        return HStack(spacing: 10) {
            tile("\(report.games)", isChinese ? "比赛" : "Games")
            tile(String(format: "%.1f", avg[.points] ?? 0), isChinese ? "场均得分" : "PTS / game")
            tile(String(format: "%.1f", avg[.rebounds] ?? 0), isChinese ? "场均篮板" : "REB / game")
            tile(String(format: "%.1f", avg[.assists] ?? 0), isChinese ? "场均助攻" : "AST / game")
        }
        .accessibilityIdentifier("coach.statTiles")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
    }

    // MARK: On the floor

    @ViewBuilder
    private var onTheFloor: some View {
        Section {
            LabeledContent(isChinese ? "位置" : "Position") {
                Text(current.playerPosition.map { "\($0.name) · \($0.short)" } ?? (isChinese ? "未设置" : "Not set"))
                    .foregroundStyle(current.playerPosition == nil ? .tertiary : .secondary)
            }
            if !current.playerTendencies.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(current.playerTendencies) { TendencyChip(tendency: $0) }
                }
                .padding(.vertical, 4)
            }
            LabeledContent(isChinese ? "最近一次上场" : "Last played") {
                if let last = lastPlayed {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(last.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        Text("\(last.sessionType.localizedLabel) · \(last.title)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text(isChinese ? "还没有" : "Not yet").foregroundStyle(.tertiary)
                }
            }
            if report.games > 0 {
                LabeledContent(isChinese ? "胜负" : "Record") {
                    Text("\(report.record.won)–\(report.record.lost)").monospacedDigit()
                }
            }
        } header: {
            Text(isChinese ? "场上" : "On the floor")
        } footer: {
            if played.isEmpty {
                Text(isChinese ? "把教练加入对抗赛或赛前准备课，他们的比赛数据会显示在这里。"
                               : "Add this coach to a scrimmage or game prep session and their games show here.")
            }
        }
    }

    /// Team practices (never billed — this is their attendance record) and
    /// the coach's workout from the teams they play a role in.
    @ViewBuilder
    private var teamsSection: some View {
        let practices = teamPractices(of: current.id, in: dataManager)
        let teams = dataManager.teams.filter { !$0.playbook.workout(for: current.id).isEmpty }
        if !practices.isEmpty || !teams.isEmpty {
            Section(isChinese ? "球队" : "Teams") {
                if !practices.isEmpty {
                    let attended = practices.filter { $0.actualAttendeeIds.contains(current.id) }.count
                    NavigationLink(destination: TeamPracticeRecordView(memberId: current.id)) {
                        LabeledContent(isChinese ? "球队训练" : "Team practices") {
                            Text(isChinese ? "到场 \(attended) / \(practices.count)" : "\(attended) of \(practices.count)")
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("profile.teamPractices")
                }
                ForEach(teams) { team in
                    NavigationLink(destination: TeamWorkoutView(teamId: team.id, playerId: current.id)) {
                        LabeledContent(isChinese ? "\(team.name) 个人训练" : "\(team.name) workout") {
                            Text(isChinese ? "\(team.playbook.workout(for: current.id).count) 个练习"
                                           : "\(team.playbook.workout(for: current.id).count) drills")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentGames: some View {
        let recent = Array(report.recent.prefix(5))
        if !recent.isEmpty {
            Section(isChinese ? "最近比赛" : "Recent games") {
                ForEach(recent) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.subheadline.weight(.medium))
                            Text(isChinese ? "第 \(item.game.gameNumber) 场" : "Game \(item.game.gameNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(item.line.points) PTS · \(item.line.rebounds) REB · \(item.line.assists) AST")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let won = item.won {
                            CoachTag(text: won ? (isChinese ? "胜" : "W") : (isChinese ? "负" : "L"),
                                     tint: won ? .green : .red, filled: false)
                        }
                    }
                }
            }
        }
    }

    // MARK: Coaching

    @ViewBuilder
    private var coaching: some View {
        Section(isChinese ? "执教" : "Coaching") {
            if programs.isEmpty {
                Text(isChinese ? "没有负责的项目" : "No programs assigned")
                    .foregroundStyle(.tertiary)
            }
            ForEach(programs) { program in
                LabeledContent(program.name) {
                    Text(isChinese ? "\(program.enrolledStudentIds.count) 名学员" : "\(program.enrolledStudentIds.count) athletes")
                        .monospacedDigit()
                }
            }
            if !current.ageGroups.isEmpty {
                LabeledContent(isChinese ? "年龄组" : "Age groups") {
                    Text(AgeGroup.allCases.filter(current.ageGroups.contains).map(\.rawValue).joined(separator: " · "))
                }
            }
            if !current.coachingSpecializations.isEmpty {
                LabeledContent(isChinese ? "专长" : "Specialties") {
                    Text(current.coachingSpecializations.joined(separator: " · "))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var contact: some View {
        let email = current.email?.trimmingCharacters(in: .whitespaces) ?? ""
        let phone = current.phone?.trimmingCharacters(in: .whitespaces) ?? ""
        if !email.isEmpty || !phone.isEmpty {
            Section(isChinese ? "联系方式" : "Contact") {
                if !phone.isEmpty, let url = URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))") {
                    Link(destination: url) {
                        LabeledContent(isChinese ? "电话" : "Phone", value: phone)
                    }
                }
                if !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                    Link(destination: url) {
                        LabeledContent(isChinese ? "邮箱" : "Email", value: email)
                    }
                }
            }
        }
    }
}

extension SessionType {
    var localizedLabel: String {
        guard isChinese else { return displayName }
        switch self {
        case .training: return "训练"
        case .scrimmage: return "对抗赛"
        case .gamePrep: return "赛前准备"
        case .recovery: return "恢复"
        case .assessment: return "测评"
        case .teamPractice: return "球队训练"
        }
    }
}

// MARK: - Add / Edit

struct AddEditCoachView: View {
    let coach: StaffCoach?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: DataManager

    /// The coach being edited, as a draft: saving writes it back whole, so
    /// what the form does not show (photo, hire date, organization) is kept —
    /// the old form rebuilt the record and erased the photo on every save.
    @State private var draft: StaffCoach
    @State private var newSpecialty = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var confirmingDelete = false
    @State private var programToReassign: Program?

    private var isEditing: Bool { coach != nil }

    init(coach: StaffCoach?) {
        self.coach = coach
        _draft = State(initialValue: coach ?? StaffCoach(name: ""))
        _photo = State(initialValue: coach?.profileImageData.flatMap(UIImage.init(data:)))
    }

    private var programs: [Program] {
        guard let coach else { return [] }
        return dataManager.programs.filter { $0.coachId == coach.id }
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section { photoHeader }
                    .listRowBackground(Color.clear)

                Section(isChinese ? "姓名" : "Name") {
                    TextField(isChinese ? "英文名（必填）" : "English name (required)", text: $draft.name)
                        .textContentType(.name)
                        .accessibilityIdentifier("coach.form.name")
                    TextField(isChinese ? "中文名" : "Chinese name", text: optional($draft.chineseName))
                }

                Section(isChinese ? "联系方式" : "Contact") {
                    TextField(isChinese ? "电话" : "Phone", text: optional($draft.phone))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField(isChinese ? "邮箱" : "Email", text: optional($draft.email))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Picker(isChinese ? "角色" : "Role", selection: $draft.role) {
                        ForEach(CoachRole.allCases, id: \.self) { role in
                            Label(role.localizedName, systemImage: role.icon).tag(role)
                        }
                    }
                    Picker(isChinese ? "权限" : "Access", selection: $draft.accessLevel) {
                        ForEach(AccessLevel.allCases, id: \.self) { level in
                            Text(level.localizedName).tag(level)
                        }
                    }
                    Toggle(isChinese ? "在职" : "Active", isOn: $draft.isActive)
                } header: {
                    Text(isChinese ? "角色与权限" : "Role & access")
                } footer: {
                    Text(draft.accessLevel.localizedDescription)
                }

                onTheFloor
                coachingSection

                if isEditing && !programs.isEmpty {
                    Section {
                        ForEach(programs) { program in
                            HStack {
                                Text(program.name)
                                Spacer()
                                Button(isChinese ? "转给…" : "Reassign…") { programToReassign = program }
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text(isChinese ? "负责项目" : "Programs")
                    } footer: {
                        Text(isChinese ? "删除教练前，先把项目转给其他教练。" : "Hand programs to another coach before removing this one.")
                    }
                }

                Section(isChinese ? "备注" : "Notes") {
                    TextField(isChinese ? "备注" : "Notes", text: optional($draft.notes), axis: .vertical)
                        .lineLimit(2...6)
                }

                if isEditing {
                    Section {
                        Button(isChinese ? "删除教练" : "Delete Coach", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isEditing ? (isChinese ? "编辑教练" : "Edit Coach") : (isChinese ? "添加教练" : "Add Coach"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "保存" : "Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("coach.form.save")
                }
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            // Your own photo may live on your profile rather than the staff record.
            .onAppear { if photo == nil { photo = OrgCoachRow.photo(of: draft, dataManager: dataManager) } }
            .alert(isChinese ? "删除这位教练？" : "Delete this coach?", isPresented: $confirmingDelete) {
                Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
                Button(isChinese ? "删除" : "Delete", role: .destructive) { delete() }
            } message: {
                Text(isChinese ? "将从所有设备上永久删除，无法恢复。" : "This removes them from every device and can't be undone.")
            }
            .sheet(item: $programToReassign) { program in
                ReassignProgramSheet(program: program, currentCoachId: coach?.id)
            }
        }
    }

    // MARK: Sections

    private var photoHeader: some View {
        VStack(spacing: 10) {
            CoachAvatar(coach: draft, image: photo, size: 96)
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(photo == nil ? (isChinese ? "添加照片" : "Add photo") : (isChinese ? "更换照片" : "Change photo"))
                    .font(.subheadline.weight(.semibold))
            }
            if photo != nil {
                Button(isChinese ? "移除照片" : "Remove photo", role: .destructive) {
                    photo = nil
                    draft.profileImageData = nil
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var onTheFloor: some View {
        Section {
            Picker(isChinese ? "位置" : "Position", selection: Binding(
                get: { draft.playerPosition?.rawValue ?? "" },
                set: { draft.playerPosition = PlayerPosition(rawValue: $0) })) {
                Text("—").tag("")
                ForEach(PlayerPosition.allCases) { Text($0.short).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("coach.form.position")
            FlowLayout(spacing: 8) {
                ForEach(PlayerTendency.allCases) { tendency in
                    let on = draft.playerTendencies.contains(tendency)
                    Button {
                        var list = draft.playerTendencies
                        if on { list.removeAll { $0 == tendency } } else { list.append(tendency) }
                        draft.playerTendencies = list
                    } label: {
                        TendencyChip(tendency: tendency, selected: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(isChinese ? "场上" : "On the floor")
        } footer: {
            Text(isChinese ? "教练在对抗赛和赛前准备课上场时使用。"
                           : "For when coaches play in scrimmages and game prep.")
        }
    }

    private var coachingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(isChinese ? "年龄组" : "Age groups")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(AgeGroup.allCases, id: \.self) { age in
                        let on = draft.ageGroups.contains(age)
                        Button {
                            if on { draft.ageGroups.removeAll { $0 == age } } else { draft.ageGroups.append(age) }
                        } label: {
                            Text(age.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(on ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
            ForEach(draft.coachingSpecializations, id: \.self) { specialty in
                Text(specialty)
            }
            .onDelete { offsets in
                var list = draft.coachingSpecializations
                list.remove(atOffsets: offsets)
                draft.coachingSpecializations = list
            }
            HStack {
                TextField(isChinese ? "添加专长，如：投篮" : "Add a specialty, e.g. Shooting", text: $newSpecialty)
                    .onSubmit(addSpecialty)
                Button(action: addSpecialty) { Image(systemName: "plus.circle.fill") }
                    .disabled(newSpecialty.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(isChinese ? "执教" : "Coaching")
        }
    }

    // MARK: Actions

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" },
                set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func addSpecialty() {
        let clean = newSpecialty.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !draft.coachingSpecializations.contains(clean) else { return }
        draft.coachingSpecializations.append(clean)
        newSpecialty = ""
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            // A square-ish 600 pt photo is plenty for a profile.
            let side: CGFloat = 600
            let scale = min(1, side / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            await MainActor.run {
                photo = resized
                draft.profileImageData = resized.jpegData(compressionQuality: 0.8)
            }
        }
    }

    private func save() {
        var saved = draft
        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
        saved.updatedAt = Date()
        if saved.hireDate == nil { saved.hireDate = Date() }
        if isEditing { dataManager.updateStaffCoach(saved) } else { dataManager.addStaffCoach(saved) }
        HapticFeedback.notification(.success)
        dismiss()
    }

    private func delete() {
        guard let coach else { dismiss(); return }
        dataManager.deleteStaffCoach(coach)
        HapticFeedback.notification(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dismiss() }
    }
}

extension AccessLevel {
    var localizedName: String {
        guard isChinese else { return rawValue }
        switch self {
        case .admin: return "管理员"
        case .coachingStaff: return "教练组"
        }
    }

    var localizedDescription: String {
        guard isChinese else { return description }
        switch self {
        case .admin: return "可查看和管理所有数据。"
        case .coachingStaff: return "只能查看和管理自己负责的学员、项目、课程和合约。"
        }
    }
}
