import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Avatar Picker
/// Image upload helper used by athlete and coach detail views. Uses
/// `NSOpenPanel` (sandbox-safe via `files.user-selected.read-write`),
/// downscales to a sensible avatar size, stores as JPEG `Data` for
/// CloudKit-friendly persistence.
enum AvatarPicker {
    /// Maximum dimension (in pixels) we keep for avatar storage.
    /// Anything larger is proportionally downscaled before encoding.
    static let maxEdge: CGFloat = 512
    /// JPEG compression quality; 0.85 hits a good size/quality trade-off.
    static let compression: CGFloat = 0.85

    /// Opens a file picker, returns compressed JPEG `Data`. Returns `nil` if
    /// the user cancels or the chosen file fails to decode.
    @MainActor
    static func chooseImage() -> Data? {
        let panel = NSOpenPanel()
        panel.title = "Choose Photo"
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        return resizeAndEncode(image)
    }

    /// Downscale an `NSImage` to fit within `maxEdge` and re-encode as JPEG.
    /// Returns nil if the image is empty or encoding fails.
    static func resizeAndEncode(_ image: NSImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let largest = max(image.size.width, image.size.height)
        let scale = largest > maxEdge ? maxEdge / largest : 1.0
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
}

// MARK: - Edit Avatar Button

/// Compact button you can drop next to a photo. Shows the current image as a
/// thumbnail, opens the picker on click, calls back with the new data.
struct EditAvatarButton: View {
    let currentData: Data?
    let initials: String
    let avatarColor: AvatarColor
    let size: CGFloat
    let onPicked: (Data) -> Void
    let onCleared: () -> Void

    var body: some View {
        Menu {
            Button("Choose Photo…") {
                if let data = AvatarPicker.chooseImage() {
                    onPicked(data)
                }
            }
            if currentData != nil {
                Divider()
                Button("Remove Photo", role: .destructive) { onCleared() }
            }
        } label: {
            ZStack {
                AthletePhoto(imageData: currentData, initials: initials,
                             color: Color.avatarColor(avatarColor), size: size)
                Circle().fill(.black.opacity(0.001))
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.18))
                            .foregroundStyle(.white)
                            .padding(size * 0.10)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(2)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Change photo")
    }
}
