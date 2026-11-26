import SwiftUI
import ImageIO
import OSLog

/// EVERY PHOTO AT ONCE (26 Nov 2026, Luther: "a button to auto remove
/// background from all photos and fill backgrounds"). Photos taken before the
/// level colours — or picked from the library — still carry their own
/// background, so no level shows behind them. This runs the same on-device
/// cut-out as the camera over every athlete photo that still has a
/// background, and stores the result transparent; the level colour is then
/// drawn behind it like any other.
///
/// The original photo is NOT kept (as with a single Remove Background).
/// A photo in which no person is found is left exactly as it was.
enum ProfileBackgroundBatch {
    /// Athletes whose photo still has its own background.
    static func candidates(in students: [Student]) -> [Student] {
        students.filter { student in
            guard let data = student.profileImageData else { return false }
            return !ProfilePhotoEncoding.isTransparent(data: data)
        }
    }

    /// The photo cut out, and its thumbnail. Nil when no person was found
    /// (always nil on the simulator — Vision's model does not run there).
    nonisolated static func cutOut(_ data: Data) -> (photo: Data, thumbnail: Data?)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              // Upright, at the stored size (a photo keeps its orientation in metadata).
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary),
              let cutout = ProfileBackgroundRemoval.cutOut(image),
              let transparent = ProfileBackgroundRemoval.transparent(cutout),
              ProfilePhotoEncoding.isTransparent(transparent),
              let photo = ProfilePhotoEncoding.data(for: transparent, quality: 0.8) else { return nil }
        return (photo, ProfilePhotoEncoding.thumbnail(from: photo, maxDimension: 360))
    }
}

#if DEBUG
extension ProfileBackgroundBatch {
    /// HOOPWISE_PHOTO_BATCH=1 (demo store only): runs the batch at launch and
    /// logs counts to hoopwise.mac / background — no names, no photos.
    @MainActor static func debugRunIfAsked(dataManager: DataManager) {
        guard ProcessInfo.processInfo.environment["HOOPWISE_PHOTO_BATCH"] == "1", ScreenshotStore.url != nil else { return }
        let log = Logger(subsystem: "hoopwise.mac", category: "background")
        Task {
            try? await Task.sleep(for: .seconds(3))
            let ids = candidates(in: dataManager.students).map(\.id)
            log.notice("photoBatch candidates \(ids.count, privacy: .public) of \(dataManager.students.filter { $0.profileImageData != nil }.count, privacy: .public) photos")
            var done = 0, unchanged = 0
            for id in ids {
                guard var student = dataManager.students.first(where: { $0.id == id }), let data = student.profileImageData else { continue }
                let result = await Task.detached { cutOut(data) }.value
                if let result {
                    student.profileImageData = result.photo
                    student.thumbnailImageData = result.thumbnail
                    dataManager.updateStudent(student)
                    done += 1
                } else { unchanged += 1 }
            }
            log.notice("photoBatch done \(done, privacy: .public) unchanged \(unchanged, privacy: .public) left \(candidates(in: dataManager.students).count, privacy: .public)")
        }
    }
}
#endif

/// The sheet that runs it: says what will happen, then counts as it goes.
struct PhotoBackgroundBatchSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case ready, running, finished }
    @State private var phase: Phase = .ready
    @State private var total = 0
    @State private var done = 0
    @State private var unchanged = 0
    @State private var work: Task<Void, Never>?

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var waiting: Int { ProfileBackgroundBatch.candidates(in: dataManager.students).count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)
                switch phase {
                case .ready:
                    Text(waiting == 0
                         ? (zh ? "所有照片都已去除背景" : "Every photo already has its background removed")
                         : (zh ? "\(waiting) 张照片仍带有背景" : "^[\(waiting) photo](inflect: true) still \(waiting == 1 ? "has" : "have") a background"))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(zh
                         ? "在本机上把人物从每张照片里抠出来，照片后面显示该学员在组内的水平颜色。原始照片不会保留，此操作无法撤销。找不到人物的照片保持原样。照片不会离开设备。"
                         : "The person is cut out of each photo on this device, and the colour of their level in the group shows behind them. The original photos are not kept, and this cannot be undone. A photo in which no person is found is left as it is. Photos never leave the device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if waiting > 0 {
                        Button { start() } label: {
                            Text(zh ? "去除 \(waiting) 张照片的背景" : "Remove the background of ^[\(waiting) photo](inflect: true)")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("photoBatch.start")
                    }
                case .running:
                    Text(zh ? "正在处理 \(done + unchanged + 1) / \(total)" : "Working on \(min(done + unchanged + 1, total)) of \(total)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(value: Double(done + unchanged), total: Double(max(total, 1)))
                    Text(zh ? "请保持此页面打开。" : "Keep this page open until it finishes.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(zh ? "停止" : "Stop", role: .destructive) { work?.cancel() }
                        .accessibilityIdentifier("photoBatch.stop")
                case .finished:
                    Text(zh ? "已完成 \(done) 张" : "^[\(done) photo](inflect: true) done")
                        .font(.title3.weight(.semibold))
                    if unchanged > 0 {
                        Text(zh ? "\(unchanged) 张未找到人物，保持原样。"
                                : "^[\(unchanged) photo](inflect: true) left as \(unchanged == 1 ? "it was" : "they were"): no person was found.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .navigationTitle(zh ? "去除照片背景" : "Remove Photo Backgrounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(phase == .ready ? (zh ? "取消" : "Cancel") : (zh ? "完成" : "Done")) { dismiss() }
                        .disabled(phase == .running)
                }
            }
            .interactiveDismissDisabled(phase == .running)
        }
        .onDisappear { work?.cancel() }
    }

    private func start() {
        let ids = ProfileBackgroundBatch.candidates(in: dataManager.students).map(\.id)
        total = ids.count; done = 0; unchanged = 0
        phase = .running
        work = Task {
            for id in ids {
                if Task.isCancelled { break }
                // The stored record as it is NOW (an edit elsewhere is kept).
                guard var student = dataManager.students.first(where: { $0.id == id }),
                      let data = student.profileImageData else { unchanged += 1; continue }
                let result = await Task.detached(priority: .userInitiated) {
                    ProfileBackgroundBatch.cutOut(data)
                }.value
                if Task.isCancelled { break }
                if let result {
                    student.profileImageData = result.photo
                    student.thumbnailImageData = result.thumbnail
                    dataManager.updateStudent(student)
                    done += 1
                } else {
                    unchanged += 1
                }
                await Task.yield()
            }
            phase = .finished
        }
    }
}
