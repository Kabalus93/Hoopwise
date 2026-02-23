import SwiftUI

// MARK: - Coach Profile View (Recreated - Legacy)
/// This is a legacy view - FlightyCoachProfileView is the primary implementation
struct CoachProfileView: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        FlightyCoachProfileView()
    }
}

// MARK: - Edit Coach Profile View
struct EditCoachProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        FlightyCoachProfileView()
    }
}
