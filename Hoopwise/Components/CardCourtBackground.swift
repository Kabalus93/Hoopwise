import SwiftUI

/// The card header's background: a deep gradient in `color` with a FIBA
/// court drawn over it in hairlines (CourtArtwork — each session type has its
/// own angle). Original artwork, drawn in code.
struct CardCourtBackground: View {
    let color: Color
    var style: CourtArtStyle = .halfCourt

    var body: some View {
        if FilmRoom.isOn {
            // The Mac: no court and no billboard — a quiet wash of the colour.
            LinearGradient(colors: [color.opacity(0.38), color.opacity(0.14)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
        ZStack {
            LinearGradient(colors: [color, color.opacity(0.75), .black.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            CourtArtwork(style: style)
        }
        }
    }
}

