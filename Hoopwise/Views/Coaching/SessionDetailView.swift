import SwiftUI

// MARK: - Session Detail View (Recreated - Legacy)
/// This is a legacy view - FlightySessionPageView is the primary implementation
struct SessionDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let session: SessionEvent
    
    var body: some View {
        FlightySessionPageView(session: session, accessMode: .execution)
    }
}
