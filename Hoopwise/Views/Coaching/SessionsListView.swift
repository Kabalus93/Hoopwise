import SwiftUI

// MARK: - Sessions List View (Recreated)
struct SessionsListView: View {
    @EnvironmentObject var dataManager: DataManager
    let programId: UUID?
    
    var sessions: [SessionEvent] {
        if let programId = programId {
            return dataManager.sessionEvents.filter { $0.programId == programId }
        }
        return dataManager.sessionEvents
    }
    
    var body: some View {
        List {
            ForEach(sessions) { session in
                NavigationLink(destination: FlightySessionPageView(session: session, accessMode: .execution)) {
                    VStack(alignment: .leading) {
                        Text(session.title)
                            .font(.headline)
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }
}
