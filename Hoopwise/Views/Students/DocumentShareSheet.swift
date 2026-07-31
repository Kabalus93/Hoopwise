import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lets a rendered document URL drive `.sheet(item:)`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if os(iOS)
/// System share sheet, so a statement or agreement goes straight to WeChat.
struct DocumentShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
