import SwiftUI

struct FlightyMascotSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedMascot: ProgramMascot

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ProgramMascot.allCases, id: \.self) { mascot in
                        flightyMascotCard(mascot)
                    }
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("CHOOSE MASCOT")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    private func flightyMascotCard(_ mascot: ProgramMascot) -> some View {
        let isSelected = selectedMascot == mascot
        return Button(action: {
            selectedMascot = mascot
            dismiss()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [mascot.color, mascot.color.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: mascot.icon)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 3)
                )
                .shadow(color: mascot.color.opacity(isSelected ? 0.5 : 0.2), radius: isSelected ? 10 : 4, x: 0, y: 4)

                Text(mascot.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? mascot.color : .white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? mascot.color.opacity(0.15) : Color(hex: "#1a1a2e"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? mascot.color : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}
