import SwiftData
import SwiftUI

// Hub → TEAMS (November 2026, Luther: "where teams I coach appear … the
// athletes in it and their profiles, picked from Student Intelligence or
// Organization … the plays we practice and run"). A team is the existing
// SDTeam record (the retired League's): name, colours, roster (athlete AND
// coach ids in `playerIds`), coach, home venue — plus its playbook
// (TeamPlaybook in `playbookData`).

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

/// The team's badge: its colour with its short name.
struct TeamBadge: View {
    let team: Team
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(hex: team.colorHex).gradient)
            Text(team.shortName.isEmpty ? String(team.name.prefix(2)).uppercased() : team.shortName)
                .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .frame(width: size, height: size)
    }
}


// MARK: - New / edit team

struct TeamEditorSheet: View {
    let team: Team?
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var shortName: String
    @State private var colorHex: String
    @State private var venue: String
    @State private var coachId: UUID?

    static let colors = ["#E94560", "#FF7A00", "#F2C200", "#2DB55D", "#0FA3B1", "#007AFF",
                         "#5856D6", "#AF52DE", "#1C1C1E", "#8E8E93"]

    init(team: Team?) {
        self.team = team
        _name = State(initialValue: team?.name ?? "")
        _shortName = State(initialValue: team?.shortName ?? "")
        _colorHex = State(initialValue: team?.colorHex ?? "#007AFF")
        _venue = State(initialValue: team?.homeVenue ?? "")
        _coachId = State(initialValue: team?.coachId)
    }

    private var preview: Team {
        Team(name: name.isEmpty ? (isChinese ? "球队" : "Team") : name,
             shortName: shortName.isEmpty ? String(name.prefix(3)) : shortName,
             colorHex: colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TeamBadge(team: preview, size: 76).frame(maxWidth: .infinity) }
                    .listRowBackground(Color.clear)
                Section(isChinese ? "球队" : "Team") {
                    TextField(isChinese ? "队名" : "Team name", text: $name)
                        .accessibilityIdentifier("team.form.name")
                    TextField(isChinese ? "简称（最多 3 个字母）" : "Short name (up to 3 letters)", text: $shortName)
                        .textInputAutocapitalization(.characters)
                    TextField(isChinese ? "主场" : "Home venue", text: $venue)
                }
                Section(isChinese ? "颜色" : "Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Self.colors, id: \.self) { hex in
                            Button { colorHex = hex } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: colorHex == hex ? 3 : 0))
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(colorHex == hex ? 0.5 : 0), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(isChinese ? "教练" : "Coach") {
                    Picker(isChinese ? "主教练" : "Head coach", selection: $coachId) {
                        Text(isChinese ? "无" : "None").tag(UUID?.none)
                        ForEach(dataManager.staffCoaches) { coach in
                            Text(coach.name).tag(UUID?.some(coach.id))
                        }
                    }
                }
            }
            .navigationTitle(team == nil ? (isChinese ? "新建球队" : "New Team") : (isChinese ? "编辑球队" : "Edit Team"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(team == nil ? (isChinese ? "创建" : "Create") : (isChinese ? "保存" : "Save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("team.form.save")
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let short = String((shortName.isEmpty ? cleanName : shortName).uppercased().prefix(3))
        let coachName = coachId.flatMap { id in dataManager.staffCoaches.first { $0.id == id }?.name }
        if var existing = team {
            existing.name = cleanName
            existing.shortName = short
            existing.colorHex = colorHex
            existing.homeVenue = venue.isEmpty ? nil : venue
            existing.coachId = coachId
            existing.coachName = coachName
            existing.updatedAt = Date()
            dataManager.updateTeam(existing)
        } else {
            dataManager.addTeam(Team(name: cleanName, shortName: short, colorHex: colorHex,
                                     coachId: coachId, coachName: coachName,
                                     homeVenue: venue.isEmpty ? nil : venue,
                                     createdByCoachId: dataManager.loggedInCoachId))
        }
        HapticFeedback.notification(.success)
        dismiss()
    }
}
