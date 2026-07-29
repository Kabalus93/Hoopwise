import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
import AVKit
#endif

// MARK: - DrillMediaPicker
/// Add-media sheet attached to the drill detail screen.
///
/// Phase 1 shipped photo library + camera (.image).
/// Phase 2 adds video clips (.videoClip) and YouTube links (.youtube).
/// Phase 3 will add the court diagram editor and Instagram paste — they
/// remain visible here as "coming soon" rows.
struct DrillMediaPicker: View {
    let drillId: UUID
    let existingMediaCount: Int
    let onAdded: (DrillMedia) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showVideoCamera = false
    @State private var showYouTubeSheet = false
    @State private var showInstagramSheet = false
    @State private var showDiagramEditor = false
    @State private var isProcessing = false
    @State private var processingMessage: String?
    @State private var errorMessage: String?

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    var body: some View {
        NavigationStack {
            List {
                photoSection
                videoSection
                diagramSection
                linkSection
            }
            .navigationTitle(isChinese ? "添加素材" : "Add Visual")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
            }
            .overlay { processingOverlay }
        }
        .alert(isChinese ? "添加失败" : "Couldn't add media",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task { await handlePhotoItem(newValue) }
        }
        .onChange(of: videoItem) { _, newValue in
            guard let newValue else { return }
            Task { await handleVideoItem(newValue) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(mediaTypes: ["public.image"]) { result in
                showCamera = false
                if case .image(let image) = result {
                    Task { await persist(image: image) }
                }
            }
        }
        .fullScreenCover(isPresented: $showVideoCamera) {
            CameraImagePicker(mediaTypes: ["public.movie"]) { result in
                showVideoCamera = false
                if case .video(let url) = result {
                    Task { await persistVideo(at: url) }
                }
            }
        }
        .sheet(isPresented: $showYouTubeSheet) {
            RemoteLinkSheet(kind: .youtube) { parsed in
                Task { await persistRemoteLink(parsed) }
            }
        }
        .sheet(isPresented: $showInstagramSheet) {
            RemoteLinkSheet(kind: .instagram) { parsed in
                Task { await persistRemoteLink(parsed) }
            }
        }
        .fullScreenCover(isPresented: $showDiagramEditor) {
            CourtDiagramEditor(
                drillId: drillId,
                existingMediaCount: existingMediaCount,
                onSave: { media in
                    onAdded(media)
                    dismiss()
                }
            )
        }
        #endif
    }

    // MARK: - Sections
    @ViewBuilder
    private var photoSection: some View {
        Section {
            #if os(iOS)
            PhotosPicker(selection: $photoItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                sourceRow(
                    icon: "photo.on.rectangle.angled",
                    title: isChinese ? "从相册选择图片" : "Choose Photo",
                    subtitle: isChinese ? "存到本地，球场离线可看" : "Saved locally — works courtside"
                )
            }
            .buttonStyle(.plain)

            Button {
                showCamera = true
            } label: {
                sourceRow(
                    icon: "camera.fill",
                    title: isChinese ? "拍照" : "Take Photo",
                    subtitle: isChinese ? "立即拍一张图" : "Snap a reference now"
                )
            }
            .buttonStyle(.plain)
            #endif
        } header: {
            Text(isChinese ? "图片" : "Photos")
        } footer: {
            Text(isChinese
                 ? "图片会压缩到约 400KB，存在设备上。"
                 : "Photos compress to ~400KB on-device.")
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        Section {
            #if os(iOS)
            Button {
                showVideoCamera = true
            } label: {
                sourceRow(
                    icon: "video.fill",
                    title: isChinese ? "录制视频" : "Record Video",
                    subtitle: isChinese ? "用相机拍，自动压缩到 1080p" : "Captured & compressed to 1080p"
                )
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $videoItem,
                         matching: .videos,
                         photoLibrary: .shared()) {
                sourceRow(
                    icon: "film.stack.fill",
                    title: isChinese ? "从相册选择视频" : "Choose Video",
                    subtitle: isChinese ? "保存到训练，可离线播放" : "Stored locally — plays offline"
                )
            }
            .buttonStyle(.plain)
            #endif
        } header: {
            Text(isChinese ? "视频" : "Videos")
        } footer: {
            Text(isChinese
                 ? "视频会重新编码为 H.264 MP4，方便离线播放。导入需要几秒。"
                 : "Videos are re-encoded to H.264 MP4 for reliable offline playback. Takes a few seconds.")
        }
    }

    @ViewBuilder
    private var diagramSection: some View {
        Section {
            #if os(iOS)
            Button {
                showDiagramEditor = true
            } label: {
                sourceRow(
                    icon: "scribble.variable",
                    title: isChinese ? "绘制战术图" : "Draw Court Diagram",
                    subtitle: isChinese ? "在半场上画战术，导出 JPEG" : "Sketch a play on a half-court · exports JPEG"
                )
            }
            .buttonStyle(.plain)
            #endif
        } header: {
            Text(isChinese ? "战术图" : "Diagrams")
        } footer: {
            Text(isChinese
                 ? "支持手指或 Apple Pencil 绘制，保存后存在设备上。"
                 : "Draw with finger or Apple Pencil. Saved locally — works offline.")
        }
    }

    @ViewBuilder
    private var linkSection: some View {
        Section {
            #if os(iOS)
            Button {
                showYouTubeSheet = true
            } label: {
                sourceRow(
                    icon: "play.rectangle.fill",
                    title: isChinese ? "粘贴 YouTube 链接" : "Paste YouTube Link",
                    subtitle: isChinese ? "封面会缓存，正片需联网" : "Thumbnail cached · playback needs signal"
                )
            }
            .buttonStyle(.plain)

            Button {
                showInstagramSheet = true
            } label: {
                sourceRow(
                    icon: "camera.aperture",
                    title: isChinese ? "粘贴 Instagram 链接" : "Paste Instagram Link",
                    subtitle: isChinese ? "打开 Instagram 应用观看" : "Opens in the Instagram app"
                )
            }
            .buttonStyle(.plain)
            #endif
        } header: {
            Text(isChinese ? "在线参考" : "Online References")
        } footer: {
            Text(isChinese
                 ? "YouTube 的封面会下载到本地缓存，Instagram 因为平台限制不能内嵌播放。"
                 : "YouTube thumbnails cache locally for offline browsing. Instagram blocks embeds, so the link deep-links into their app.")
        }
    }

    @ViewBuilder
    private var processingOverlay: some View {
        if isProcessing {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.primary)
                    Text(processingMessage ?? (isChinese ? "处理中…" : "Processing…"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Row styles
    private func sourceRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.accent)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func upcomingRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(isChinese ? "敬请期待" : "Soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .opacity(0.85)
    }

    // MARK: - Persistence (iOS)
    #if os(iOS)
    @MainActor
    private func handlePhotoItem(_ item: PhotosPickerItem) async {
        beginProcessing(isChinese ? "处理图片…" : "Processing photo…")
        defer { endProcessing() }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = isChinese ? "图片无法读取" : "That photo couldn't be loaded"
                return
            }
            await persist(image: image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func persist(image: UIImage) async {
        beginProcessing(isChinese ? "保存图片…" : "Saving photo…")
        defer { endProcessing() }

        let mediaId = UUID()
        guard let primaryPath = DrillMediaStorage.shared.saveImage(
            image, drillId: drillId, mediaId: mediaId
        ) else {
            errorMessage = isChinese ? "保存失败" : "Couldn't save photo"
            return
        }
        let thumbPath = DrillMediaStorage.shared.saveThumbnail(
            image, drillId: drillId, mediaId: mediaId
        )

        let media = DrillMedia(
            id: mediaId,
            drillId: drillId,
            kind: .image,
            localPath: primaryPath,
            thumbnailPath: thumbPath,
            sortOrder: existingMediaCount
        )
        onAdded(media)
        HapticFeedback.notification(.success)
        dismiss()
    }

    /// Video import — first copies the bytes to a stable temp location (so we
    /// can hand the path to AVAssetExportSession), then re-encodes into our
    /// DrillMedia folder.
    @MainActor
    private func handleVideoItem(_ item: PhotosPickerItem) async {
        beginProcessing(isChinese ? "导入视频…" : "Importing video…")
        defer { endProcessing() }

        do {
            guard let movie = try await item.loadTransferable(type: VideoFileTransferable.self) else {
                errorMessage = isChinese ? "视频无法读取" : "That video couldn't be loaded"
                return
            }
            await persistVideo(at: movie.url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func persistVideo(at sourceURL: URL) async {
        beginProcessing(isChinese ? "压缩视频…" : "Compressing video…")
        defer { endProcessing() }

        let mediaId = UUID()
        guard let result = await DrillMediaStorage.shared.importVideo(
            from: sourceURL, drillId: drillId, mediaId: mediaId
        ) else {
            errorMessage = isChinese ? "视频导入失败" : "Couldn't import that video"
            return
        }

        let media = DrillMedia(
            id: mediaId,
            drillId: drillId,
            kind: .videoClip,
            localPath: result.videoRelativePath,
            thumbnailPath: result.thumbnailRelativePath,
            sortOrder: existingMediaCount,
            durationSeconds: result.durationSeconds
        )
        onAdded(media)
        HapticFeedback.notification(.success)
        dismiss()
    }

    @MainActor
    private func persistRemoteLink(_ parsed: DrillMediaURL) async {
        guard let kind = parsed.kind, let urlString = parsed.canonicalString else { return }
        beginProcessing(isChinese ? "保存链接…" : "Saving link…")
        defer { endProcessing() }

        let mediaId = UUID()
        // Best-effort thumbnail: YouTube exposes one, Instagram doesn't —
        // the call returns nil for Instagram and the carousel falls back to
        // the kind-tinted placeholder.
        var thumbnailPath: String?
        if let thumbURL = parsed.thumbnailURL {
            thumbnailPath = await DrillMediaStorage.shared.cacheRemoteThumbnail(
                from: thumbURL, drillId: drillId, mediaId: mediaId
            )
        }

        let media = DrillMedia(
            id: mediaId,
            drillId: drillId,
            kind: kind,
            localPath: nil,
            remoteURL: urlString,
            thumbnailPath: thumbnailPath,
            sortOrder: existingMediaCount
        )
        onAdded(media)
        HapticFeedback.notification(.success)
        dismiss()
    }

    private func beginProcessing(_ message: String) {
        processingMessage = message
        isProcessing = true
    }

    private func endProcessing() {
        isProcessing = false
        processingMessage = nil
    }
    #endif
}

// MARK: - RemoteLinkSheet
#if os(iOS)
/// Single-field URL paste sheet shared by YouTube and Instagram. Validates
/// against `DrillMediaURL.parse` and only enables the Add button when the
/// link resolves to the *expected* kind — so pasting a YouTube URL into the
/// Instagram sheet stays disabled with a clear error message.
struct RemoteLinkSheet: View {
    enum Kind {
        case youtube, instagram

        var mediaKind: DrillMediaKind {
            switch self {
            case .youtube: return .youtube
            case .instagram: return .instagram
            }
        }

        var placeholder: String {
            switch self {
            case .youtube:   return "https://youtube.com/..."
            case .instagram: return "https://instagram.com/p/..."
            }
        }
    }

    let kind: Kind
    let onSubmit: (DrillMediaURL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var isChinese: Bool {
        LocalizationManager.shared.currentLanguage == .chinese
    }

    private var parsed: DrillMediaURL { DrillMediaURL.parse(text) }

    private var matchesExpectedKind: Bool {
        switch (kind, parsed) {
        case (.youtube, .youtube), (.instagram, .instagram): return true
        default: return false
        }
    }

    private var title: String {
        switch kind {
        case .youtube:   return isChinese ? "粘贴 YouTube 链接" : "Paste YouTube Link"
        case .instagram: return isChinese ? "粘贴 Instagram 链接" : "Paste Instagram Link"
        }
    }

    private var sectionHeader: String {
        switch kind {
        case .youtube:   return isChinese ? "YouTube 链接" : "YouTube Link"
        case .instagram: return isChinese ? "Instagram 链接" : "Instagram Link"
        }
    }

    private var emptyFooter: String {
        switch kind {
        case .youtube:
            return isChinese
                ? "支持 youtube.com/watch、youtu.be、shorts 和 embed 链接。"
                : "Accepts youtube.com/watch, youtu.be, shorts, and embed links."
        case .instagram:
            return isChinese
                ? "支持 instagram.com/p、reel 和 tv 链接。点击后会跳转到 Instagram 应用。"
                : "Accepts instagram.com/p, reel, and tv links. Opens in the Instagram app."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind.placeholder, text: $text, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .lineLimit(1...3)
                } header: {
                    Text(sectionHeader)
                } footer: {
                    footer
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "取消" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isChinese ? "添加" : "Add") {
                        let value = parsed
                        dismiss()
                        onSubmit(value)
                    }
                    .disabled(!matchesExpectedKind)
                }
            }
            .onAppear { focused = true }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if text.isEmpty {
            Text(emptyFooter)
        } else {
            switch parsed {
            case .youtube(let id, _):
                if kind == .youtube {
                    Text(isChinese ? "识别到视频 ID：\(id)" : "Detected video ID: \(id)")
                        .foregroundStyle(.green)
                } else {
                    Text(isChinese ? "这是 YouTube 链接，请用上面的 YouTube 项。"
                                   : "That's a YouTube link — use the YouTube option above.")
                        .foregroundStyle(.orange)
                }
            case .instagram(let code, _):
                if kind == .instagram {
                    Text(isChinese ? "识别到帖子代码：\(code)" : "Detected post code: \(code)")
                        .foregroundStyle(.green)
                } else {
                    Text(isChinese ? "这是 Instagram 链接，请用 Instagram 项。"
                                   : "That's an Instagram link — use the Instagram option.")
                        .foregroundStyle(.orange)
                }
            case .unsupported:
                Text(isChinese ? "无法识别这条链接" : "Couldn't recognize that link")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - VideoFileTransferable
/// Adapter so PhotosPicker can deliver a video as a stable URL we can hand
/// to AVAssetExportSession. We copy the bytes out of the PhotoKit sandbox
/// into a temp file because the URL handed to `loadTransferable` is
/// invalidated as soon as the call returns.
struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("DrillMediaImport", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let dest = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFileTransferable(url: dest)
        }
    }
}

// MARK: - CameraImagePicker
/// UIImagePickerController wrapper that supports both photo and video capture.
/// (PhotosPicker doesn't expose camera; UIImagePickerController is still the
/// only path for live capture without dropping into AVFoundation directly.)
struct CameraImagePicker: UIViewControllerRepresentable {
    enum Result {
        case image(UIImage)
        case video(URL)
        case cancelled
    }

    let mediaTypes: [String]
    let onPick: (Result) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.mediaTypes = mediaTypes
        if mediaTypes.contains("public.movie") {
            picker.videoQuality = .typeHigh
            picker.cameraCaptureMode = .video
            picker.videoMaximumDuration = 180 // 3 min cap — coaching clips
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Result) -> Void
        init(onPick: @escaping (Result) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                onPick(.video(url))
            } else if let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) {
                onPick(.image(image))
            } else {
                onPick(.cancelled)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(.cancelled)
        }
    }
}
#endif
