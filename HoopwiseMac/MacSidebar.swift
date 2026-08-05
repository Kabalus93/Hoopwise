import SwiftUI

struct MacSidebar: View {
    @EnvironmentObject var dataManager: DataManager
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach([SidebarSection.today, .assistant, .athletes, .sessions], id: \.self) { s in
                    sidebarRow(s)
                }
            } header: {
                Text("Coaching").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach([SidebarSection.programs, .drills, .playbook, .courtEditor], id: \.self) { s in
                    sidebarRow(s)
                }
            } header: {
                Text("Library").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach([SidebarSection.sales, .league, .hub], id: \.self) { s in
                    sidebarRow(s)
                }
            } header: {
                Text("Organization").font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            CoachAvatar()
            VStack(alignment: .leading, spacing: 1) {
                Text(dataManager.coach.name.isEmpty ? "Coach" : dataManager.coach.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("Active")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.bar)
    }
}

private struct CoachAvatar: View {
    @EnvironmentObject var dataManager: DataManager
    var body: some View {
        let initials = String(dataManager.coach.name.split(separator: " ").compactMap { $0.first }.prefix(2)).uppercased()
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.18))
            Text(initials.isEmpty ? "C" : initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 28, height: 28)
    }
}
