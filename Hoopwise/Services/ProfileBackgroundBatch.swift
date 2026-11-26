import SwiftUI
import ImageIO
import OSLog
import CryptoKit

/// EVERY PHOTO AT ONCE (26 Nov 2026, Luther: "a button to auto remove
/// background from all photos and fill backgrounds"). Photos taken before the
/// level colours — or picked from the library — still carry their own
/// background, so no level shows behind them. This runs the same on-device
/// cut-out as the camera over every athlete photo that still has a
/// background, and stores the result transparent; the level colour is then
/// drawn behind it like any other.
///
/// IT CAN BE UNDONE (same day, Luther: "that's too high risk, I still want to
/// be able to undo"). Before a photo is replaced its ORIGINAL is put aside as
/// a file on this device (Application Support/PhotoOriginals/<athlete id>),
/// with a fingerprint of the cut-out written in its place. "Put the original
/// photos back" restores each original — but only where the athlete's photo
/// is still that cut-out, so a photo retaken since is never overwritten by an
/// older one. The originals are files on THIS device, not synced (a synced
/// original would be a schema field): undo works on the device that ran it.
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

// MARK: - The originals, kept for undo

extension ProfileBackgroundBatch {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("PhotoOriginals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func originalURL(_ id: UUID) -> URL? { folder?.appendingPathComponent(id.uuidString + ".original") }
    private static func markURL(_ id: UUID) -> URL? { folder?.appendingPathComponent(id.uuidString + ".cutout") }

    nonisolated static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Puts the original aside before it is replaced. False = it could not be
    /// kept, and then the photo must NOT be replaced.
    static func keepOriginal(_ original: Data, cutout: Data, for id: UUID) -> Bool {
        guard let file = originalURL(id), let mark = markURL(id) else { return false }
        do {
            try original.write(to: file, options: .atomic)
            try Data(fingerprint(cutout).utf8).write(to: mark, options: .atomic)
            return true
        } catch {
            try? FileManager.default.removeItem(at: file)
            return false
        }
    }

    /// The athletes whose original can be put back now: an original is kept
    /// and their photo is still the cut-out made from it.
    static func restorable(in students: [Student]) -> [Student] {
        students.filter { student in
            guard let file = originalURL(student.id), let mark = markURL(student.id),
                  FileManager.default.fileExists(atPath: file.path),
                  let wanted = try? String(contentsOf: mark, encoding: .utf8),
                  let current = student.profileImageData else { return false }
            return fingerprint(current) == wanted
        }
    }

    static func original(for id: UUID) -> Data? {
        originalURL(id).flatMap { try? Data(contentsOf: $0) }
    }

    /// Once put back (or no longer wanted), the kept original goes.
    static func forgetOriginal(for id: UUID) {
        for url in [originalURL(id), markURL(id)].compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
    }
}

#if DEBUG
extension ProfileBackgroundBatch {
    /// HOOPWISE_PHOTO_BATCH=1 (demo store only): runs the batch at launch and
    /// logs counts to hoopwise.mac / background — no names, no photos.
    @MainActor static func debugRunIfAsked(dataManager: DataManager) {
        let mode = ProcessInfo.processInfo.environment["HOOPWISE_PHOTO_BATCH"]
        guard mode == "1" || mode == "undo", ScreenshotStore.url != nil else { return }
        let log = Logger(subsystem: "hoopwise.mac", category: "background")
        Task {
            try? await Task.sleep(for: .seconds(3))
            if mode == "undo" {
                // =undo: puts every restorable original back.
                var back = 0
                for student in restorable(in: dataManager.students) {
                    guard var stored = dataManager.students.first(where: { $0.id == student.id }),
                          let original = original(for: student.id) else { continue }
                    stored.profileImageData = original
                    stored.thumbnailImageData = makeProfileThumbnailData(from: original)
                    dataManager.updateStudent(stored)
                    forgetOriginal(for: student.id)
                    back += 1
                }
                log.notice("photoBatch undo back \(back, privacy: .public) candidates \(candidates(in: dataManager.students).count, privacy: .public) restorable \(restorable(in: dataManager.students).count, privacy: .public)")
                return
            }
            let ids = candidates(in: dataManager.students).map(\.id)
            log.notice("photoBatch candidates \(ids.count, privacy: .public) of \(dataManager.students.filter { $0.profileImageData != nil }.count, privacy: .public) photos")
            var done = 0, unchanged = 0
            for id in ids {
                guard var student = dataManager.students.first(where: { $0.id == id }), let data = student.profileImageData else { continue }
                let result = await Task.detached { cutOut(data) }.value
                if let result, keepOriginal(data, cutout: result.photo, for: id) {
                    student.profileImageData = result.photo
                    student.thumbnailImageData = result.thumbnail
                    dataManager.updateStudent(student)
                    done += 1
                } else { unchanged += 1 }
            }
            log.notice("photoBatch done \(done, privacy: .public) unchanged \(unchanged, privacy: .public) left \(candidates(in: dataManager.students).count, privacy: .public) restorable \(restorable(in: dataManager.students).count, privacy: .public)")
        }
    }
}
#endif

/// The sheet that runs it: remove the backgrounds, or put the originals back.
struct PhotoBackgroundBatchSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case ready, running, finished }
    private enum Job { case remove, undo }
    @State private var phase: Phase = .ready
    @State private var job: Job = .remove
    @State private var total = 0
    @State private var done = 0
    @State private var unchanged = 0
    @State private var work: Task<Void, Never>?

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var waiting: Int { ProfileBackgroundBatch.candidates(in: dataManager.students).count }
    private var restorable: Int { ProfileBackgroundBatch.restorable(in: dataManager.students).count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.minus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 28)
                switch phase {
                case .ready: ready
                case .running:
                    Text(zh ? "正在处理 \(min(done + unchanged + 1, total)) / \(total)" : "Working on \(min(done + unchanged + 1, total)) of \(total)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    ProgressView(value: Double(done + unchanged), total: Double(max(total, 1)))
                    Text(zh ? "请保持此页面打开。" : "Keep this page open until it finishes.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button(zh ? "停止" : "Stop", role: .destructive) { work?.cancel() }
                        .accessibilityIdentifier("photoBatch.stop")
                case .finished:
                    Text(job == .remove
                         ? (zh ? "已去除 \(done) 张照片的背景" : "^[\(done) photo](inflect: true) cut out")
                         : (zh ? "已恢复 \(done) 张原始照片" : "^[\(done) original photo](inflect: true) put back"))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    if unchanged > 0 {
                        Text(job == .remove
                             ? (zh ? "\(unchanged) 张保持原样：未找到人物，或无法保留原图。"
                                   : "^[\(unchanged) photo](inflect: true) left as \(unchanged == 1 ? "it was" : "they were"): no person was found, or the original could not be kept.")
                             : (zh ? "\(unchanged) 张未恢复。" : "^[\(unchanged) photo](inflect: true) not put back."))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if job == .remove, done > 0 {
                        Text(zh ? "原始照片保留在本设备上，可随时在这里恢复。"
                                : "The originals are kept on this device — you can put them back from here at any time.")
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
                    Button(phase == .ready ? (zh ? "关闭" : "Close") : (zh ? "完成" : "Done")) { dismiss() }
                        .disabled(phase == .running)
                }
            }
            .interactiveDismissDisabled(phase == .running)
        }
        .onDisappear { work?.cancel() }
    }

    @ViewBuilder private var ready: some View {
        Text(waiting == 0
             ? (zh ? "没有带背景的照片了" : "No photo has a background left to remove")
             : (zh ? "\(waiting) 张照片仍带有背景" : "^[\(waiting) photo](inflect: true) still \(waiting == 1 ? "has" : "have") a background"))
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
        Text(zh
             ? "在本机上把人物从每张照片里抠出来。每张原始照片都会保留在本设备上，可以在这里恢复。找不到人物的照片保持原样。照片不会离开设备。"
             : "The person is cut out of each photo on this device. Every original is kept on this device, and you can put them back from here. A photo in which no person is found is left as it is. Photos never leave the device.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        if waiting > 0 {
            Button { run(.remove) } label: {
                Text(zh ? "去除 \(waiting) 张照片的背景" : "Remove the background of ^[\(waiting) photo](inflect: true)")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("photoBatch.start")
        }
        if restorable > 0 {
            Button { run(.undo) } label: {
                Label(zh ? "恢复 \(restorable) 张原始照片" : "Put ^[\(restorable) original photo](inflect: true) back",
                      systemImage: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("photoBatch.undo")
            Text(zh ? "只在执行过去除背景的这台设备上可以恢复。之后重拍过的照片不会被替换。"
                    : "Undo works on the device that removed the backgrounds. A photo retaken since is not replaced.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func run(_ which: Job) {
        job = which
        let ids = (which == .remove ? ProfileBackgroundBatch.candidates(in: dataManager.students)
                                    : ProfileBackgroundBatch.restorable(in: dataManager.students)).map(\.id)
        total = ids.count; done = 0; unchanged = 0
        phase = .running
        work = Task {
            for id in ids {
                if Task.isCancelled { break }
                // The stored record as it is NOW (an edit elsewhere is kept).
                guard var student = dataManager.students.first(where: { $0.id == id }),
                      let data = student.profileImageData else { unchanged += 1; continue }
                switch which {
                case .remove:
                    let result = await Task.detached(priority: .userInitiated) {
                        ProfileBackgroundBatch.cutOut(data)
                    }.value
                    if Task.isCancelled { break }
                    // No original kept = no change: the photo is only ever
                    // replaced when it can be put back.
                    if let result, ProfileBackgroundBatch.keepOriginal(data, cutout: result.photo, for: id) {
                        student.profileImageData = result.photo
                        student.thumbnailImageData = result.thumbnail
                        dataManager.updateStudent(student)
                        done += 1
                    } else {
                        unchanged += 1
                    }
                case .undo:
                    if let original = ProfileBackgroundBatch.original(for: id) {
                        student.profileImageData = original
                        student.thumbnailImageData = makeProfileThumbnailData(from: original)
                        dataManager.updateStudent(student)
                        ProfileBackgroundBatch.forgetOriginal(for: id)
                        done += 1
                    } else {
                        unchanged += 1
                    }
                }
                await Task.yield()
            }
            phase = .finished
        }
    }
}

/// EVALUATE THE LEVELS (26 Nov 2026, Luther: the second button — "evaluate
/// the levels and set backgrounds"). Works every athlete's level out again
/// now (it otherwise follows by itself half a second after any change) and
/// shows the result: how many at each level, in its colour, and how many
/// have none. The colour behind a cut-out photo IS the level, drawn live —
/// so evaluating sets every background at once and nothing is written into
/// the photos.
struct LevelEvaluationSheet: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var evaluatedAt: Date?

    private var zh: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        let students = dataManager.students
        let tiers = students.compactMap { dataManager.skillTier(for: $0.id) }
        let none = students.count - tiers.count
        let cutOuts = students.filter { $0.profileImageData.map(ProfilePhotoEncoding.isTransparent(data:)) ?? false }.count
        let withBackground = ProfileBackgroundBatch.candidates(in: students).count
        return NavigationStack {
            List {
                Section {
                    ForEach(SkillTier.allCases, id: \.self) { tier in
                        row(Color(hex: tier.hex), tier.title(chinese: zh), tiers.filter { $0 == tier }.count)
                    }
                    row(Color(hex: PhotoPalette.unranked), zh ? "没有水平" : "No level", none)
                } header: {
                    Text(zh ? "组内水平" : "Level in the group")
                } footer: {
                    Text(zh
                         ? "水平按学员与本组平均的差距计算：技能评估占 65%，近期比赛表现占 35%。至少评估四项技能或打过三场比赛才有水平；一个组至少要有三名可比较的学员。私教学员没有水平。"
                         : "A level compares an athlete with their own group's average: 65% your skills evaluation, 35% recent games. It needs four rated skills or three games, and a group needs three athletes who can be compared. Private clients have no level.")
                }
                Section {
                    row(nil, zh ? "已去除背景的照片" : "Photos with the background removed", cutOuts)
                    row(nil, zh ? "仍带背景的照片" : "Photos that still have a background", withBackground)
                } header: {
                    Text(zh ? "照片背景" : "Photo backgrounds")
                } footer: {
                    Text(zh
                         ? "水平的颜色显示在已去除背景的照片后面，并随水平变化自动更新。仍带背景的照片不显示水平——可在「去除照片背景」中处理。"
                         : "The level's colour shows behind a photo whose background was removed, and follows the level by itself. A photo that still has its background shows none — use Remove Photo Backgrounds for those.")
                }
                Section {
                    Button {
                        dataManager.rebuildSkillTiers()
                        evaluatedAt = Date()
                    } label: {
                        Label(zh ? "重新评估水平" : "Evaluate the Levels Again", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("levels.evaluate")
                } footer: {
                    if let evaluatedAt {
                        Text((zh ? "已于 " : "Evaluated at ") + evaluatedAt.formatted(date: .omitted, time: .standard))
                    }
                }
            }
            .navigationTitle(zh ? "评估水平" : "Evaluate Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(zh ? "完成" : "Done") { dismiss() } }
            }
            .onAppear {
                dataManager.rebuildSkillTiers()
                evaluatedAt = Date()
            }
        }
        .accessibilityIdentifier("levels.sheet")
    }

    private func row(_ colour: Color?, _ title: String, _ count: Int) -> some View {
        HStack(spacing: 10) {
            if let colour { Circle().fill(colour).frame(width: 12, height: 12) }
            Text(title)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
