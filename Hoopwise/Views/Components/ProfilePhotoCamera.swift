#if os(iOS)
import SwiftUI
import AVFoundation
import Combine
import UIKit

// MARK: - Profile photo camera
//
// October 2026 (Luther's request, a sanctioned exception to the iOS UI
// freeze). The profile photo used UIImagePickerController in a sheet: it
// opened on the FRONT camera, the sheet cropped its controls, and its
// square crop step came after the shot. Coaches photograph a child in front
// of them, quickly, and the result is shown in a circle — so this camera:
// - opens on the BACK camera (flip available),
// - is full screen with the controls inside the safe area,
// - shows the avatar's circle as a mask, and
// - crops the captured photo to exactly that circle's square, so the framing
//   on screen is the framing saved. No edit step.

struct ProfilePhotoCamera: View {
    /// Receives the square photo (or nothing, on cancel).
    let onFinish: (UIImage?) -> Void

    @StateObject private var camera = ProfileCameraModel()
    @State private var circleRect: CGRect = .zero

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * 0.8
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
            let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                width: diameter, height: diameter)

            ZStack {
                Color.black

                CameraPreview(session: camera.session, previewLayer: camera.previewLayer)

                // The mask: everything outside the avatar circle is dimmed.
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .mask {
                        Rectangle()
                            .overlay {
                                Circle()
                                    .frame(width: diameter, height: diameter)
                                    .position(center)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)

                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .allowsHitTesting(false)

                Text(camera.message ?? (isChinese ? "把脸放进圆圈里" : "Fit the face in the circle"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: center.x, y: circle.maxY + 36)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    controls
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
                }
            }
            .onAppear { circleRect = circle }
            .onChange(of: proxy.size) { _, _ in circleRect = circle }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var controls: some View {
        HStack {
            Button {
                onFinish(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel(isChinese ? "取消" : "Cancel")

            Spacer()

            Button {
                camera.capture(circle: circleRect) { image in
                    if let image { onFinish(image) }
                }
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: 64, height: 64)
                }
            }
            .disabled(!camera.isRunning || camera.isCapturing)
            .accessibilityLabel(isChinese ? "拍照" : "Take photo")

            Spacer()

            Button {
                camera.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .disabled(!camera.canFlip)
            .accessibilityLabel(isChinese ? "切换摄像头" : "Switch camera")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
    }
}

// MARK: - Preview

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let previewLayer: AVCaptureVideoPreviewLayer

    final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        view.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

// MARK: - Model

@MainActor
final class ProfileCameraModel: NSObject, ObservableObject {
    nonisolated let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "hoopwise.profile-camera")
    private var position: AVCaptureDevice.Position = .back
    private var pending: ((UIImage?) -> Void)?
    private var pendingCircle: CGRect = .zero

    @Published var isRunning = false
    @Published var isCapturing = false
    @Published var message: String?
    @Published var canFlip = false

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
    }

    func start() async {
        let isChinese = LocalizationManager.shared.currentLanguage == .chinese
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                message = isChinese ? "需要相机权限（设置 › Hoopwise）" : "Camera access is off (Settings › Hoopwise)"
                return
            }
        default:
            message = isChinese ? "需要相机权限（设置 › Hoopwise）" : "Camera access is off (Settings › Hoopwise)"
            return
        }
        canFlip = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        let configured = await configure(position: .back)
        if !configured {
            message = isChinese ? "没有可用的相机" : "No camera available"
            return
        }
        isRunning = true
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
        isRunning = false
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        Task {
            if await configure(position: next) { position = next }
        }
    }

    private func configure(position: AVCaptureDevice.Position) async -> Bool {
        let session = session
        let output = output
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    continuation.resume(returning: false)
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                for existing in session.inputs { session.removeInput(existing) }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    session.addOutput(output)
                    // Speed over quality: this is a 1024px avatar, not a print.
                    output.maxPhotoQualityPrioritization = .speed
                }
                session.commitConfiguration()
                if !session.isRunning { session.startRunning() }
                continuation.resume(returning: true)
            }
        }
    }

    /// Captures and crops to `circle` (in the preview's coordinates).
    func capture(circle: CGRect, completion: @escaping (UIImage?) -> Void) {
        guard isRunning, !isCapturing else { return }
        isCapturing = true
        pending = completion
        pendingCircle = circle
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .speed
        output.capturePhoto(with: settings, delegate: self)
    }

    /// The circle's square, as a normalized rect in the sensor's coordinates —
    /// the same space the captured CGImage is in before orientation.
    fileprivate func normalizedCrop() -> CGRect {
        previewLayer.metadataOutputRectConverted(fromLayerRect: pendingCircle)
    }

    fileprivate func finish(_ image: UIImage?) {
        isCapturing = false
        let completion = pending
        pending = nil
        completion?(image)
    }
}

extension ProfileCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil,
              let cgImage = photo.cgImageRepresentation() else {
            Task { @MainActor in self.finish(nil) }
            return
        }
        let orientationRaw = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 6
        Task { @MainActor in
            let crop = self.normalizedCrop()
            let image = ProfileCameraModel.cropped(cgImage, normalized: crop, orientationRaw: orientationRaw)
            self.finish(image)
        }
    }

    /// Crops the sensor-oriented image to the normalized rect, then applies
    /// the photo's orientation and scales to a 1024px square.
    nonisolated static func cropped(_ cgImage: CGImage, normalized: CGRect, orientationRaw: UInt32) -> UIImage? {
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        var rect = CGRect(x: normalized.minX * width, y: normalized.minY * height,
                          width: normalized.width * width, height: normalized.height * height)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        // Square it (aspect-fill rounding can leave a pixel or two).
        let side = min(rect.width, rect.height)
        rect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side).integral
        guard side > 0, let piece = cgImage.cropping(to: rect) else { return nil }
        let orientation = UIImage.Orientation(cgOrientation: CGImagePropertyOrientation(rawValue: orientationRaw) ?? .right)
        let oriented = UIImage(cgImage: piece, scale: 1, orientation: orientation)
        let target = CGSize(width: 1024, height: 1024)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            oriented.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

private extension UIImage.Orientation {
    init(cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
#endif
