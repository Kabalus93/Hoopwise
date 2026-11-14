#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Background picker (after the shot)
//
// November 2026 (Luther's request, sanctioned with ProfileBackgroundRemoval).
// Shown by ProfilePhotoCamera after the shutter when "Remove Photo
// Backgrounds" is on, and by Edit Student's "Remove Background" for a photo
// already saved. The subject is cut out once (Vision, off the main thread);
// each swatch recolours at once; "Original" keeps the photo as taken.
// From the camera, a photo with no subject found goes straight through
// unchanged (`passThroughWhenNoSubject`) — the capture is never held up.

struct ProfileBackgroundPicker: View {
    let image: UIImage
    /// Camera: the left button retakes and a failed cut-out passes the photo
    /// straight through. Edit Student: the left button cancels.
    var fromCamera = true
    /// The finished photo, or nil for retake / cancel.
    let onFinish: (UIImage?) -> Void

    private enum Stage: Equatable { case working, ready, noSubject }
    private static let original = "original"

    @State private var stage: Stage = .working
    @State private var cutout: ProfileBackgroundRemoval.Cutout?
    @State private var selected: String = UserDefaults.standard.string(forKey: ProfileBackgroundRemoval.lastColorKey)
        ?? ProfileBackgroundRemoval.palette[0]
    @State private var rendered: [String: UIImage] = [:]

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    private var shown: UIImage {
        selected == Self.original ? image : (rendered[selected] ?? image)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * 0.8
            VStack(spacing: 0) {
                Spacer(minLength: max(proxy.safeAreaInsets.top, 20))
                ZStack {
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

                if stage == .ready { swatches.padding(.bottom, 24) }

                controls
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await prepare() }
        .onChange(of: selected) { _, hex in Task { await render(hex) } }
    }

    private var caption: String {
        switch stage {
        case .working: return isChinese ? "正在去除背景…" : "Removing the background…"
        case .ready: return isChinese ? "选择背景颜色" : "Pick a background"
        case .noSubject: return isChinese ? "没有找到人物，照片保持原样" : "No one found — the photo stays as taken"
        }
    }

    private var swatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                swatch(Self.original) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .accessibilityLabel(isChinese ? "原图" : "Original")
                ForEach(ProfileBackgroundRemoval.palette, id: \.self) { hex in
                    swatch(hex) { Color(hex: hex) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    private func swatch<Fill: View>(_ id: String, @ViewBuilder fill: () -> Fill) -> some View {
        Button { selected = id } label: {
            fill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(.white, lineWidth: selected == id ? 2.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("backgroundPicker.swatch.\(id)")
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

            Button(isChinese ? "使用照片" : "Use Photo") { finish() }
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

    private func finish() {
        if selected != Self.original, stage == .ready {
            UserDefaults.standard.set(selected, forKey: ProfileBackgroundRemoval.lastColorKey)
        }
        onFinish(stage == .ready ? shown : image)
    }

    // MARK: Work

    private func prepare() async {
        guard let cg = Self.upright(image) else { return noSubject() }
        let found = await Task.detached(priority: .userInitiated) {
            ProfileBackgroundRemoval.cutOut(cg)
        }.value
        guard let found else { return noSubject() }
        cutout = found
        if selected != Self.original { await render(selected) }
        stage = .ready
    }

    private func noSubject() {
        if fromCamera { onFinish(image) } else { stage = .noSubject }
    }

    private func render(_ hex: String) async {
        guard hex != Self.original, rendered[hex] == nil, let cutout else { return }
        let output = await Task.detached(priority: .userInitiated) {
            ProfileBackgroundRemoval.composite(cutout, hex: hex)
        }.value
        if let output { rendered[hex] = UIImage(cgImage: output) }
    }

    /// The photo as an upright CGImage (a saved JPEG may carry an orientation).
    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            .cgImage
    }
}
#endif
