import SwiftUI

// MARK: - Program Detail View (Recreated - Legacy)
/// This is a legacy view - FlightyProgramDetailView is the primary implementation
struct ProgramDetailView: View {
    @EnvironmentObject var dataManager: DataManager
    let program: Program
    
    var body: some View {
        FlightyProgramDetailView(program: program)
    }
}
