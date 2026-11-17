import SwiftUI

/// The card header's background: a deep gradient in `color` with a FIBA
/// court drawn over it in hairlines (CourtArtwork — each session type has its
/// own angle). Original artwork, drawn in code.
struct CardCourtBackground: View {
    let color: Color
    var style: CourtArtStyle = .halfCourt

    var body: some View {
        ZStack {
            LinearGradient(colors: [color, color.opacity(0.75), .black.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            CourtArtwork(style: style)
        }
    }
}

