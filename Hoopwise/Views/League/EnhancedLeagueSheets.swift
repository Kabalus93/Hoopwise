import SwiftUI

// MARK: - Enhanced Create Team Sheet
struct EnhancedCreateTeamSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    
    @State private var teamName = ""
    @State private var shortName = ""
    @State private var selectedColorIndex = 0
    @State private var selectedMascot: TeamMascotType?
    @State private var selectedPlayers: Set<UUID> = []
    @State private var selectedCoachId: UUID?
    @State private var homeVenue = ""
    @State private var searchText = ""
    @State private var selectedTab = 0
    
    let colorOptions: [(color: Color, hex: String)] = [
        (.blue, "#3B82F6"), (.red, "#EF4444"), (.green, "#22C55E"), (.orange, "#F97316"),
        (.purple, "#A855F7"), (.pink, "#EC4899"), (.yellow, "#EAB308"), (.cyan, "#06B6D4")
    ]
    
    var body: some View {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        return ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(isChinese ? "取消" : "Cancel") { isPresented = false }.font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(isChinese ? "创建队伍" : "Create Team").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Spacer()
                    Button(isChinese ? "创建" : "Create") { createTeam() }.font(.system(size: 14, weight: .semibold)).foregroundColor(!teamName.isEmpty ? .green : .white.opacity(0.3)).disabled(teamName.isEmpty)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                
                // Tab Picker
                HStack(spacing: 0) {
                    ForEach([isChinese ? "信息" : "Info", isChinese ? "球员" : "Players", isChinese ? "教练" : "Coach"], id: \.self) { tab in
                        let index = [isChinese ? "信息" : "Info", isChinese ? "球员" : "Players", isChinese ? "教练" : "Coach"].firstIndex(of: tab) ?? 0
                        Button(action: { withAnimation { selectedTab = index } }) {
                            Text(tab).font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundColor(selectedTab == index ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(selectedTab == index ? Color.white.opacity(0.1) : Color.clear)
                        }
                    }
                }.background(Color.white.opacity(0.05)).cornerRadius(8).padding(.horizontal, 16).padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case 0: teamInfoSection
                        case 1: playersSection
                        case 2: coachSection
                        default: EmptyView()
                        }
                    }.padding(16).padding(.bottom, 40)
                }
            }
        }
    }
    
    private var teamInfoSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Team Name").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField("Enter team name", text: $teamName).textFieldStyle(.plain).font(.system(size: 15)).foregroundColor(.white)
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Short Name (3 letters)").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField("e.g., LAK", text: $shortName).textFieldStyle(.plain).font(.system(size: 15)).foregroundColor(.white)
                    .padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    .onChange(of: shortName) { _, newValue in shortName = String(newValue.uppercased().prefix(3)) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Team Color").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(0..<colorOptions.count, id: \.self) { i in
                        Circle().fill(colorOptions[i].color).frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.white, lineWidth: selectedColorIndex == i ? 3 : 0))
                            .onTapGesture { selectedColorIndex = i }
                    }
                }
            }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Home Venue (Optional)").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                if !dataManager.locations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(dataManager.locations) { loc in
                                Button(action: { homeVenue = loc.name }) {
                                    Text(loc.name).font(.system(size: 12)).foregroundColor(homeVenue == loc.name ? .white : .white.opacity(0.6))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Capsule().fill(homeVenue == loc.name ? Color.blue.opacity(0.4) : Color.white.opacity(0.1)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                TextField("Or enter custom venue...", text: $homeVenue).textFieldStyle(.plain).font(.system(size: 14)).foregroundColor(.white)
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
        }
    }
    
    private var playersSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                TextField("Search players...", text: $searchText).textFieldStyle(.plain).font(.system(size: 14)).foregroundColor(.white)
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            
            HStack {
                Text("Selected Players").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("\(selectedPlayers.count)").font(.system(size: 12, weight: .bold)).foregroundColor(.cyan)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Color.cyan.opacity(0.2)))
            }
            
            let filtered = searchText.isEmpty ? dataManager.students : dataManager.students.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            ForEach(filtered) { student in
                PlayerSelectionRow(student: student, isSelected: selectedPlayers.contains(student.id)) {
                    if selectedPlayers.contains(student.id) { selectedPlayers.remove(student.id) } else { selectedPlayers.insert(student.id) }
                }
            }
        }
    }
    
    private var coachSection: some View {
        VStack(spacing: 12) {
            Text("Assign a Coach").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: { selectedCoachId = nil }) {
                HStack(spacing: 12) {
                    Circle().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "person.slash").font(.system(size: 16)).foregroundColor(.white.opacity(0.5)))
                    Text("No Coach Assigned").font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.6))
                    Spacer()
                    if selectedCoachId == nil { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.green) }
                }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(selectedCoachId == nil ? Color.white.opacity(0.1) : Color.white.opacity(0.05)))
            }.buttonStyle(.plain)
            
            ForEach(dataManager.staffCoaches) { coach in
                Button(action: { selectedCoachId = coach.id }) {
                    HStack(spacing: 12) {
                        Circle().fill(Color.avatarColor(coach.avatarColor)).frame(width: 40, height: 40)
                            .overlay(Text(coach.initials).font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coach.name).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                            Text(coach.role.rawValue).font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        }
                        Spacer()
                        if selectedCoachId == coach.id { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundColor(.green) }
                    }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(selectedCoachId == coach.id ? Color.white.opacity(0.1) : Color.white.opacity(0.05)))
                }.buttonStyle(.plain)
            }
        }
    }
    
    private func createTeam() {
        let sn = shortName.isEmpty ? String(teamName.prefix(3)).uppercased() : shortName
        let team = Team(name: teamName, shortName: sn, colorHex: colorOptions[selectedColorIndex].hex, mascotType: selectedMascot,
                       playerIds: Array(selectedPlayers), coachId: selectedCoachId,
                       coachName: selectedCoachId.flatMap { id in dataManager.staffCoaches.first { $0.id == id }?.name },
                       homeVenue: homeVenue.isEmpty ? nil : homeVenue)
        dataManager.addTeam(team)
        isPresented = false
    }
}

// MARK: - Player Selection Row
struct PlayerSelectionRow: View {
    let student: Student
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Circle().fill(Color.avatarColor(student.avatarColor)).frame(width: 36, height: 36)
                    .overlay(Text(student.initials).font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(student.displayName).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    if let age = student.age { Text("\(age) years old").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)) }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundColor(isSelected ? .green : .white.opacity(0.3))
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.green.opacity(0.1) : Color.white.opacity(0.05)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Enhanced Schedule Game Sheet
struct EnhancedScheduleGameSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataManager: DataManager
    @State private var homeTeamId: UUID?
    @State private var awayTeamId: UUID?
    @State private var gameDate = Date()
    @State private var selectedLocationId: UUID?
    @State private var customVenue = ""
    @State private var selectedRefereeId: UUID?
    
    private var canSchedule: Bool { homeTeamId != nil && awayTeamId != nil && homeTeamId != awayTeamId }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { isPresented = false }.font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text("Schedule Game").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Spacer()
                    Button("Schedule") { scheduleGame() }.font(.system(size: 14, weight: .semibold)).foregroundColor(canSchedule ? .green : .white.opacity(0.3)).disabled(!canSchedule)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 20) {
                        teamsSection
                        dateTimeSection
                        locationSection
                        refereeSection
                        if homeTeamId != nil && awayTeamId != nil { gamePreview }
                    }.padding(16).padding(.bottom, 40)
                }
            }
        }
    }
    
    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAMS").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 6) {
                Text("Home Team").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                teamPicker(selection: $homeTeamId, excluding: awayTeamId)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Away Team").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                teamPicker(selection: $awayTeamId, excluding: homeTeamId)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private func teamPicker(selection: Binding<UUID?>, excluding: UUID?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dataManager.teams.filter { $0.id != excluding }) { team in
                    Button(action: { selection.wrappedValue = team.id }) {
                        HStack(spacing: 6) {
                            TeamLogoView(team: team, size: 24)
                            Text(team.shortName).font(.system(size: 12, weight: .semibold))
                        }.foregroundColor(selection.wrappedValue == team.id ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(selection.wrappedValue == team.id ? team.primaryColor.opacity(0.5) : Color.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    
    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATE & TIME").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            DatePicker("", selection: $gameDate, displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.graphical).colorScheme(.dark).accentColor(.cyan)
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOCATION").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            if !dataManager.locations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dataManager.locations) { loc in
                            Button(action: { selectedLocationId = loc.id; customVenue = loc.name }) {
                                HStack(spacing: 6) {
                                    Image(systemName: loc.courtType.icon).font(.system(size: 12))
                                    Text(loc.name).font(.system(size: 12))
                                }.foregroundColor(selectedLocationId == loc.id ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(selectedLocationId == loc.id ? Color.blue.opacity(0.4) : Color.white.opacity(0.1)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle").font(.system(size: 14)).foregroundColor(.white.opacity(0.4))
                TextField("Or enter custom venue...", text: $customVenue).textFieldStyle(.plain).font(.system(size: 14)).foregroundColor(.white)
            }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var refereeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("REFEREE (Optional)").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: { selectedRefereeId = nil }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.slash").font(.system(size: 12))
                            Text(LocalizationManager.shared.currentLanguage == .chinese ? "无" : "None").font(.system(size: 12))
                        }.foregroundColor(selectedRefereeId == nil ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(selectedRefereeId == nil ? Color.gray.opacity(0.4) : Color.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                    
                    ForEach(dataManager.staffCoaches) { coach in
                        Button(action: { selectedRefereeId = coach.id }) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.avatarColor(coach.avatarColor)).frame(width: 20, height: 20)
                                    .overlay(Text(String(coach.name.prefix(1))).font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                                Text(coach.name.components(separatedBy: " ").first ?? coach.name).font(.system(size: 12))
                            }.foregroundColor(selectedRefereeId == coach.id ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(selectedRefereeId == coach.id ? Color.purple.opacity(0.4) : Color.white.opacity(0.1)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private var gamePreview: some View {
        VStack(spacing: 12) {
            Text("PREVIEW").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.4)).frame(maxWidth: .infinity, alignment: .leading)
            if let homeId = homeTeamId, let awayId = awayTeamId,
               let home = dataManager.teams.first(where: { $0.id == homeId }),
               let away = dataManager.teams.first(where: { $0.id == awayId }) {
                HStack(spacing: 0) {
                    VStack(spacing: 4) { TeamLogoView(team: away, size: 36); Text(away.shortName).font(.system(size: 11, weight: .semibold)).foregroundColor(.white) }.frame(maxWidth: .infinity)
                    VStack(spacing: 4) {
                        Text("VS").font(.system(size: 12, weight: .bold)).foregroundColor(.white.opacity(0.4))
                        Text(gameDate.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    }
                    VStack(spacing: 4) { TeamLogoView(team: home, size: 36); Text(home.shortName).font(.system(size: 11, weight: .semibold)).foregroundColor(.white) }.frame(maxWidth: .infinity)
                }.padding(.vertical, 16)
                .background(LinearGradient(colors: [away.primaryColor.opacity(0.2), home.primaryColor.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                .cornerRadius(12)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
    
    private func scheduleGame() {
        guard let homeId = homeTeamId, let awayId = awayTeamId else { return }
        let game = Game(homeTeamId: homeId, awayTeamId: awayId, date: gameDate, venue: customVenue.isEmpty ? nil : customVenue, locationId: selectedLocationId, refereeId: selectedRefereeId, status: .scheduled)
        dataManager.addGame(game)
        isPresented = false
    }
}
