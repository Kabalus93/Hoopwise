import SwiftUI

// MARK: - Hub
/// Organization administration. Sub-section sidebar across the top —
/// Coaches / Locations / Organization / Profile — each section is fully
/// editable on Mac via the shared DataManager.
struct HubMacView: View {
    @State private var section: HubSection = .coaches

    enum HubSection: String, CaseIterable, Identifiable {
        case coaches, locations, organization, profile
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var systemImage: String {
            switch self {
            case .coaches: return "person.2.badge.key"
            case .locations: return "mappin.and.ellipse"
            case .organization: return "building.2.fill"
            case .profile: return "person.crop.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionTabs
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            Divider()
            Group {
                switch section {
                case .coaches: CoachesSection()
                case .locations: LocationsSection()
                case .organization: OrganizationSection()
                case .profile: CoachProfileSection()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Hub")
    }

    private var sectionTabs: some View {
        HStack(spacing: 6) {
            ForEach(HubSection.allCases) { s in
                Button {
                    section = s
                } label: {
                    Label(s.label, systemImage: s.systemImage)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(s == section ? Color.accentColor.opacity(0.15) : Color.clear, in: .capsule)
                        .foregroundStyle(s == section ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - Coaches

private struct CoachesSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selected: StaffCoach.ID?
    @State private var search = ""

    private var filtered: [StaffCoach] {
        let base = dataManager.staffCoaches.sorted { $0.name < $1.name }
        guard !search.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search coaches", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(.quinary, in: .rect(cornerRadius: 6))
                .padding(12)

                List(selection: $selected) {
                    if filtered.isEmpty {
                        Text("No staff coaches yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { coach in
                            CoachRow(coach: coach)
                                .tag(coach.id)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        dataManager.deleteStaffCoach(coach)
                                        if selected == coach.id { selected = nil }
                                    }
                                }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 320, idealWidth: 360)

            if let id = selected, let coach = dataManager.staffCoaches.first(where: { $0.id == id }) {
                CoachDetailView(coach: coach).id(coach.id)
            } else {
                EmptyDetail(systemImage: "person.crop.circle", title: "Select a Coach")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addCoach() } label: { Label("Add Coach", systemImage: "plus") }
            }
        }
    }

    private func addCoach() {
        let coach = StaffCoach(name: "New Coach")
        dataManager.addStaffCoach(coach)
        selected = coach.id
    }
}

private struct CoachRow: View {
    let coach: StaffCoach
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(coach.role.color.opacity(0.18)).frame(width: 32, height: 32)
                .overlay(Image(systemName: coach.role.icon).font(.caption.weight(.bold)).foregroundStyle(coach.role.color))
            VStack(alignment: .leading, spacing: 1) {
                Text(coach.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(coach.role.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !coach.isActive {
                Text("Inactive").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: .capsule).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CoachDetailView: View {
    let coach: StaffCoach
    @EnvironmentObject var dataManager: DataManager
    @State private var name: String = ""
    @State private var chineseName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var role: CoachRole = .assistant
    @State private var accessLevel: AccessLevel = .coachingStaff
    @State private var isActive = true
    @State private var dirty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                Form {
                    Section("Identity") {
                        TextField("English Name", text: $name).onChange(of: name) { _, _ in dirty = true }
                        TextField("Chinese Name", text: $chineseName).onChange(of: chineseName) { _, _ in dirty = true }
                    }
                    Section("Contact") {
                        TextField("Email", text: $email).onChange(of: email) { _, _ in dirty = true }
                        TextField("Phone", text: $phone).onChange(of: phone) { _, _ in dirty = true }
                    }
                    Section("Role") {
                        Picker("Role", selection: $role) {
                            ForEach(CoachRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .onChange(of: role) { _, _ in dirty = true }
                        Picker("Access", selection: $accessLevel) {
                            ForEach(AccessLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .onChange(of: accessLevel) { _, _ in dirty = true }
                        Toggle("Active", isOn: $isActive).onChange(of: isActive) { _, _ in dirty = true }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    if dirty {
                        Text("Unsaved changes").font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("Saved").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Discard") { load() }.disabled(!dirty)
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty)
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { load() }
        .onChange(of: coach.id) { _, _ in load() }
        .navigationTitle(coach.displayName)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Circle().fill(coach.role.color.gradient).frame(width: 76, height: 76)
                .overlay(Text(coach.initials).font(.system(size: 26, weight: .bold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(coach.displayName).font(.system(size: 26, weight: .bold))
                Text(coach.role.rawValue).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func load() {
        name = coach.name
        chineseName = coach.chineseName ?? ""
        email = coach.email ?? ""
        phone = coach.phone ?? ""
        role = coach.role
        accessLevel = coach.accessLevel
        isActive = coach.isActive
        dirty = false
    }

    private func save() {
        var copy = coach
        copy.name = name
        copy.chineseName = chineseName.isEmpty ? nil : chineseName
        copy.email = email.isEmpty ? nil : email
        copy.phone = phone.isEmpty ? nil : phone
        copy.role = role
        copy.accessLevel = accessLevel
        copy.isActive = isActive
        copy.updatedAt = Date()
        dataManager.updateStaffCoach(copy)
        dirty = false
    }
}

// MARK: - Locations

private struct LocationsSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selected: Location.ID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    if dataManager.locations.isEmpty {
                        Text("No locations yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(dataManager.locations) { loc in
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(loc.name).font(.subheadline.weight(.medium))
                                    if let city = loc.city, !city.isEmpty {
                                        Text(city).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if !loc.isActive { Text("Inactive").font(.caption2).foregroundStyle(.secondary) }
                            }
                            .tag(loc.id)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    dataManager.deleteLocation(loc)
                                    if selected == loc.id { selected = nil }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 320, idealWidth: 360)

            if let id = selected, let loc = dataManager.locations.first(where: { $0.id == id }) {
                LocationDetailView(location: loc).id(loc.id)
            } else {
                EmptyDetail(systemImage: "mappin.and.ellipse", title: "Select a Location")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { add() } label: { Label("Add Location", systemImage: "plus") }
            }
        }
    }

    private func add() {
        let loc = Location(name: "New Location")
        dataManager.addLocation(loc)
        selected = loc.id
    }
}

private struct LocationDetailView: View {
    let location: Location
    @EnvironmentObject var dataManager: DataManager
    @State private var name = ""
    @State private var address = ""
    @State private var city = ""
    @State private var contactPhone = ""
    @State private var courtCount = 1
    @State private var isActive = true
    @State private var dirty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(location.name).font(.system(size: 26, weight: .bold))

                Form {
                    Section("Identity") {
                        TextField("Name", text: $name).onChange(of: name) { _, _ in dirty = true }
                    }
                    Section("Address") {
                        TextField("Street", text: $address).onChange(of: address) { _, _ in dirty = true }
                        TextField("City", text: $city).onChange(of: city) { _, _ in dirty = true }
                    }
                    Section("Logistics") {
                        Stepper("Courts: \(courtCount)", value: $courtCount, in: 1...10)
                            .onChange(of: courtCount) { _, _ in dirty = true }
                        TextField("Contact Phone", text: $contactPhone).onChange(of: contactPhone) { _, _ in dirty = true }
                        Toggle("Active", isOn: $isActive).onChange(of: isActive) { _, _ in dirty = true }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Text(dirty ? "Unsaved changes" : "Saved").font(.caption).foregroundStyle(dirty ? .orange : .secondary)
                    Spacer()
                    Button("Discard") { load() }.disabled(!dirty)
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty)
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { load() }
        .onChange(of: location.id) { _, _ in load() }
        .navigationTitle(location.name)
    }

    private func load() {
        name = location.name
        address = location.address ?? ""
        city = location.city ?? ""
        contactPhone = location.contactPhone ?? ""
        courtCount = location.courtCount
        isActive = location.isActive
        dirty = false
    }

    private func save() {
        var copy = location
        copy.name = name
        copy.address = address.isEmpty ? nil : address
        copy.city = city.isEmpty ? nil : city
        copy.contactPhone = contactPhone.isEmpty ? nil : contactPhone
        copy.courtCount = courtCount
        copy.isActive = isActive
        copy.updatedAt = Date()
        dataManager.updateLocation(copy)
        dirty = false
    }
}

// MARK: - Organization

private struct OrganizationSection: View {
    @EnvironmentObject var dataManager: DataManager
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    StatPill(title: "Coaches", value: "\(dataManager.staffCoaches.count)")
                    StatPill(title: "Locations", value: "\(dataManager.locations.count)")
                    StatPill(title: "Athletes", value: "\(dataManager.students.count)")
                    StatPill(title: "Programs", value: "\(dataManager.programs.count)")
                }

                SectionBlock(title: "Coaching Staff at a Glance") {
                    if dataManager.staffCoaches.isEmpty {
                        EmptyPanel(systemImage: "person.2", text: "No staff coaches yet.")
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(dataManager.staffCoaches) { CoachRow(coach: $0).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                        }
                    }
                }

                SectionBlock(title: "Active Programs") {
                    let active = dataManager.programs.filter { $0.status == .active }
                    if active.isEmpty {
                        EmptyPanel(systemImage: "list.clipboard", text: "No active programs.")
                    } else {
                        VStack(spacing: 6) {
                            ForEach(active) { program in
                                HStack(spacing: 10) {
                                    Circle().fill(Color(hex: program.colorHex)).frame(width: 22, height: 22)
                                    Text(program.name).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(program.enrolledStudentIds.count) athletes").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Coach profile (the logged-in coach)

private struct CoachProfileSection: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var name = ""
    @State private var email = ""
    @State private var dirty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("My Profile").font(.system(size: 26, weight: .bold))

                Form {
                    Section("Identity") {
                        TextField("Name", text: $name).onChange(of: name) { _, _ in dirty = true }
                        TextField("Email", text: $email).onChange(of: email) { _, _ in dirty = true }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Text(dirty ? "Unsaved changes" : "Saved").font(.caption).foregroundStyle(dirty ? .orange : .secondary)
                    Spacer()
                    Button("Save") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!dirty)
                }
                .padding(.horizontal, 4)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { load() }
    }

    private func load() {
        name = dataManager.coach.name
        email = dataManager.coach.email
        dirty = false
    }

    private func save() {
        var copy = dataManager.coach
        copy.name = name
        copy.email = email
        dataManager.updateCoach(copy)
        dirty = false
    }
}
