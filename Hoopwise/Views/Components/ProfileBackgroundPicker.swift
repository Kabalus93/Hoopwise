#if os(iOS)
import SwiftUI
import UIKit

// MARK: - The cut-out, before it is saved
//
// November 2026 (Luther's request, sanctioned with ProfileBackgroundRemoval).
// Shown by ProfilePhotoCamera after the shutter when "Remove Photo
// Backgrounds" is on, and by Edit Student's "Remove Background" for a photo
// already saved. The subject is cut out once (Vision, off the main thread) and
// shown over the athlete's SKILL LEVEL colour (Models/SkillTier.swift — 20 Nov
// 2026: the colour is no longer picked here; it is painted live behind the
// transparent photo everywhere). "Cut out | Original" keeps the photo as taken
// when Vision got it wrong. From the camera, a photo with no subject found
// goes straight through unchanged — the capture is never held up.

struct ProfileBackgroundPicker: View {
    let image: UIImage
    /// The colour shown behind the cut-out here (the athlete's level).
    var backdropHex: String = PhotoPalette.unranked
    /// Camera: the left button retakes and a failed cut-out passes the photo
    /// straight through. Edit Student: the left button cancels.
    var fromCamera = true
    /// The finished photo (transparent when cut out), or nil for retake / cancel.
    let onFinish: (UIImage?) -> Void

    private enum Stage: Equatable { case working, ready, noSubject }

    @State private var stage: Stage = .working
    @State private var cutOut: UIImage?
    @State private var keepOriginal = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var shown: UIImage { keepOriginal ? image : (cutOut ?? image) }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * 0.8
            VStack(spacing: 0) {
                Spacer(minLength: max(proxy.safeAreaInsets.top, 20))
                ZStack {
                    Circle().fill(Color(hex: backdropHex)).frame(width: diameter, height: diameter)
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    if stage == .working {
                        Circle().fill(.black.opacity(0.35)).frame(width: diameter, height: diameter)
                        ProgressView().tint(.white).scaleEffect(1.4)
                    }
                }
                .accessibilityIdentifier("backgroundPicker.preview")

                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.top, 20)

                Spacer()

                if stage == .ready {
                    Picker("", selection: $keepOriginal) {
                        Text(isChinese ? "抠图" : "Cut out").tag(false)
                        Text(isChinese ? "原图" : "Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("backgroundPicker.mode")
                }

                controls
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .environment(\.colorScheme, .dark)
        .task { await prepare() }
    }

    private var caption: String {
        switch stage {
        case .working: return isChinese ? "正在去除背景…" : "Removing the background…"
        case .ready: return isChinese ? "背景颜色显示该学员在组内的水平" : "The colour behind shows their level in the group"
        case .noSubject: return isChinese ? "没有找到人物，照片保持原样" : "No one found — the photo stays as taken"
        }
    }

    private var controls: some View {
        HStack {
            Button(fromCamera ? (isChinese ? "重拍" : "Retake") : (isChinese ? "取消" : "Cancel")) {
                onFinish(nil)
            }
            .font(.headline)
            .frame(minWidth: 96, minHeight: 50)
            .background(.white.opacity(0.15), in: Capsule())

            Spacer()

            Button(isChinese ? "使用照片" : "Use Photo") { onFinish(stage == .ready ? shown : image) }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(minWidth: 120, minHeight: 50)
                .background(.white, in: Capsule())
                .disabled(stage == .working)
                .accessibilityIdentifier("backgroundPicker.use")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
    }

    // MARK: Work

    private func prepare() async {
        guard let cg = Self.upright(image) else { return noSubject() }
        let result = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let cutout = ProfileBackgroundRemoval.cutOut(cg) else { return nil }
            return ProfileBackgroundRemoval.transparent(cutout)
        }.value
        guard let result else { return noSubject() }
        cutOut = UIImage(cgImage: result)
        stage = .ready
    }

    private func noSubject() {
        if fromCamera { onFinish(image) } else { stage = .noSubject }
    }

    /// The photo as an upright CGImage (a saved JPEG may carry an orientation).
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            .cgImage
    }
}

extension UIImage {
    /// The bytes to store as a profile photo: HEIC with transparency for a
    /// cut-out, JPEG otherwise (ProfilePhotoEncoding).
    func profilePhotoData(quality: Double = 0.7) -> Data? {
        guard let cg = ProfileBackgroundPicker.upright(self) else { return jpegData(compressionQuality: quality) }
        return ProfilePhotoEncoding.data(for: cg, quality: quality) ?? jpegData(compressionQuality: quality)
    }
}
#endif
