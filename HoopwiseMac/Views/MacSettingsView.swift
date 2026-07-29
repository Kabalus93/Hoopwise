import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject var dataManager: DataManager

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            profileTab.tabItem { Label("Profile", systemImage: "person.crop.circle") }
            dataTab.tabItem { Label("Data", systemImage: "internaldrive") }
        }
        .frame(width: 520, height: 380)
    }

    private var generalTab: some View {
        Form {
            Text("Hoopwise").font(.title3.weight(.semibold))
            Text("Coaching workspace for Mac").foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var profileTab: some View {
        Form {
            LabeledContent("Coach", value: dataManager.coach.name.isEmpty ? "—" : dataManager.coach.name)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var dataTab: some View {
        Form {
            Button("Refresh All Data") {
                Task { await dataManager.refreshAllCaches() }
            }
            LabeledContent("Athletes", value: "\(dataManager.students.count)")
            LabeledContent("Sessions", value: "\(dataManager.sessionEvents.count)")
            LabeledContent("Programs", value: "\(dataManager.programs.count)")
        }
        .formStyle(.grouped)
        .padding()
    }
}
