import SwiftUI
import AVKit
import AVFoundation
import Photos

// A VIDEO IN THE VAULT and its composer (26 Nov 2026). The vault takes videos
// as well as photos (the same index; the clip stays in Photos). A video opens
// here: it plays, and "Make a video with their stats" opens the composer —
// pick the overlay, the numbers, the frame and the part of the clip; the
// preview plays the overlay exactly as it will be exported.

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

// MARK: - One video

struct VaultVideoView: View {
    let studentId: UUID
    let entry: VaultPhoto
    let asset: PHAsset
    var pushed = false
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var composing = false
    @State private var confirmingRemove = false

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let date = entry.takenAt {
                Text(date.formatted(date: .abbreviated, time: .shortened) + " · " + VideoTime.text(asset.duration))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { player?.pause(); composing = true } label: {
                Label(isChinese ? "加上数据制作视频" : "Make a video with their stats", systemImage: "wand.and.stars")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("media.makeVideo")
        }
        .padding()
        .navigationTitle(isChinese ? "视频" : "Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pushed {
                ToolbarItem(placement: .confirmationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label(isChinese ? "从照片库中移出（视频保留）" : "Remove from vault (stays in Photos)", systemImage: "minus.circle")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog(isChinese ? "从这位学员的照片中移出？" : "Remove from this athlete's media?",
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(isChinese ? "移出" : "Remove", role: .destructive) {
                dataManager.setVault(studentId: studentId) { $0.removeAll { $0.id == entry.id } }
                dismiss()
            }
        } message: {
            Text(isChinese ? "视频仍保留在“照片”App 中。" : "The video stays in your Photos library.")
        }
        .task {
            if let av = await VideoPost.asset(for: asset) { player = AVPlayer(playerItem: AVPlayerItem(asset: av)) }
        }
        .onDisappear { player?.pause() }
        .fullScreenCover(isPresented: $composing) {
            if let student = dataManager.students.first(where: { $0.id == studentId }) {
                VideoPostComposer(student: student, clip: .photos(asset)).environmentObject(dataManager)
            }
        }
    }
}

enum VideoTime {
    static func text(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - The composer

struct VideoPostComposer: View {
    enum Clip {
        case photos(PHAsset)
        case asset(AVAsset)      // DEBUG gallery
    }

    let student: Student
    let clip: Clip
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var source: AVAsset?
    @State private var total: Double = 0
    @State private var start: Double = 0
    @State private var length: Double = 15
    @State private var template: VideoOverlayTemplate = .lowerThird
    @State private var stats: AthletePostFacts.Source = .lastGame
    @State private var aspect: VideoPostAspect = .story
    @State private var cut: VideoPost.Cut?
    @State private var player = AVPlayer()
    @State private var overlay: CALayer?
    @State private var exporting = false
    @State private var failed: String?
    @State private var sharing: [Any]?

    private var chinese: Bool { AreaLanguage.isChinese(.playerCard) }

    var facts: AthletePostFacts {
        let program = dataManager.programs.first { $0.id == student.programId }
        var f = AthletePostFacts.make(student: student, jersey: dataManager.player(for: student.id)?.jerseyNumber,
                                      colorHex: program?.colorHex ?? "#2A78D6",
                                      academy: ProgramGuideStore.academyName,
                                      sessions: dataManager.sessionEvents, source: stats, chinese: chinese)
        #if DEBUG
        if !f.hasStats, ProcessInfo.processInfo.environment["HOOPWISE_POST_SAMPLE"] == "1" { f = AthletePostDebug.sample(f) }
        #endif
        return f
    }

    /// The lengths offered: what fits in the clip, up to a minute.
    private var lengths: [Double] {
        let options: [Double] = [10, 15, 30, 60].filter { $0 < total }
        return options + [min(total, VideoPost.longest)]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                preview
                if !facts.hasStats {
                    Text(isChinese ? "这段时间没有比赛数据 — 换一个范围，或先记录比赛。"
                                   : "No game stats for this — try another range, or score a game first.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                templateStrip
                HStack {
                    Picker(isChinese ? "数据" : "Stats", selection: $stats) {
                        ForEach(AthletePostFacts.Source.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("videoPost.source")
                    Picker("", selection: $aspect) {
                        ForEach(VideoPostAspect.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                    .accessibilityIdentifier("videoPost.aspect")
                }
                trim
                consentLine
                Button(action: export) {
                    Group {
                        if exporting {
                            HStack(spacing: 10) { ProgressView().tint(.white); Text(isChinese ? "正在生成视频…" : "Making the video…") }
                        } else {
                            Label(isChinese ? "分享视频" : "Share video", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(cut == nil || exporting)
                .accessibilityIdentifier("videoPost.share")
                if let failed {
                    Text(failed).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle(isChinese ? "制作视频" : "Make a video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "完成" : "Done") { player.pause(); dismiss() } }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: sharing) }
            }
        }
        .task { await load() }
        .onChange(of: start) { _, _ in recut() }
        .onChange(of: length) { _, _ in recut() }
        .onChange(of: aspect) { _, _ in recut() }
        .onChange(of: template) { _, _ in rebuildOverlay() }
        .onChange(of: stats) { _, _ in rebuildOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === player.currentItem else { return }
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear { player.pause() }
    }

    // MARK: Parts

    private var preview: some View {
        let size = aspect.size
        return GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack {
                Color.black
                if cut != nil {
                    VideoPostPreview(player: player, overlay: overlay, renderSize: size)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: size.width * scale, height: size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onTapGesture { player.seek(to: .zero); player.play() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isChinese ? "预览" : "Preview")
        .accessibilityIdentifier("videoPost.preview")
    }

    private var templateStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VideoOverlayTemplate.allCases) { t in
                        let on = template == t
                        Button { template = t } label: {
                            Label(t.title(chinese: isChinese), systemImage: t.symbol)
                                .font(.subheadline.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 14).frame(minHeight: 38)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .id(t)
                        .accessibilityIdentifier("videoPost.template.\(t.rawValue)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .onChange(of: template) { _, t in withAnimation { proxy.scrollTo(t, anchor: .center) } }
        }
    }

    @ViewBuilder private var trim: some View {
        if total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isChinese ? "片段" : "Clip").font(.subheadline.weight(.semibold))
                    Text("\(VideoTime.text(start)) – \(VideoTime.text(min(total, start + length)))")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        ForEach(lengths, id: \.self) { l in
                            Button(VideoTime.text(l)) { length = l }
                        }
                    } label: {
                        Label(VideoTime.text(min(length, total)), systemImage: "timer").font(.subheadline)
                    }
                    .accessibilityIdentifier("videoPost.length")
                }
                if total - length > 0.5 {
                    Slider(value: $start, in: 0...max(0, total - length))
                        .accessibilityIdentifier("videoPost.start")
                }
            }
        }
    }

    private var consentLine: some View {
        let mayPost = dataManager.mayPublishMedia(for: student.id)
        return Label(mayPost ? (isChinese ? "已记录肖像发布同意，可以公开发布。" : "Publication consent on record — fine to post publicly.")
                             : (isChinese ? "没有记录肖像发布同意：只发给家长，不要公开发布。" : "No publication consent on record — share with the family, don't post publicly."),
                     systemImage: mayPost ? "checkmark.seal" : "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(mayPost ? Color.green : Color.orange)
    }

    // MARK: Work

    private func load() async {
        switch clip {
        case .photos(let asset): source = await VideoPost.asset(for: asset)
        case .asset(let av): source = av
        }
        guard let source else { failed = isChinese ? "无法读取这段视频。" : "This video could not be read."; return }
        total = (try? await source.load(.duration).seconds) ?? 0
        length = min(15, total, VideoPost.longest)
        recut()
    }

    @State private var cutTask: Task<Void, Never>?

    private func recut() {
        guard let source else { return }
        cutTask?.cancel()
        let s = start, l = length, a = aspect
        cutTask = Task {
            // Let a dragged slider settle.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let c = try? await VideoPost.cut(source, start: s, length: l, aspect: a),
                  !Task.isCancelled else { return }
            cut = c
            let item = AVPlayerItem(asset: c.composition)
            item.videoComposition = c.videoComposition
            player.replaceCurrentItem(with: item)
            player.isMuted = true
            rebuildOverlay()
            player.play()
        }
    }

    private func rebuildOverlay() {
        guard let cut else { return }
        overlay = VideoOverlay.layer(template, facts: facts, size: cut.renderSize, duration: cut.duration)
        player.seek(to: .zero)
        player.play()
    }

    private func export() {
        guard let cut else { return }
        #if targetEnvironment(simulator)
        // The Simulator's renderer crashes in the video compositor's overlay
        // pass (AVVideoCompositionCoreAnimationTool); devices and the Mac run it.
        failed = "Video export doesn't run in the Simulator — use a device or the Mac."
        return
        #endif
        exporting = true
        failed = nil
        player.pause()
        let layer = VideoOverlay.layer(template, facts: facts, size: cut.renderSize, duration: cut.duration)
        let name = "\(student.primaryDisplayName) \(template.rawValue)"
        Task {
            do {
                let url = try await VideoPost.export(cut, overlay: layer, name: name)
                sharing = [url]
            } catch {
                failed = (isChinese ? "视频生成失败：" : "Couldn't make the video: ") + error.localizedDescription
            }
            exporting = false
        }
    }
}

// MARK: - The preview: the player with the overlay riding its clock

struct VideoPostPreview: UIViewRepresentable {
    let player: AVPlayer
    let overlay: CALayer?
    let renderSize: CGSize

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ v: PreviewView, context: Context) {
        v.playerLayer.player = player
        v.renderSize = renderSize
        v.show(overlay, item: player.currentItem)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var renderSize: CGSize = CGSize(width: 1080, height: 1920) { didSet { setNeedsLayout() } }
        private var sync: AVSynchronizedLayer?
        private weak var shown: CALayer?

        func show(_ overlay: CALayer?, item: AVPlayerItem?) {
            guard overlay !== shown || sync?.playerItem !== item else { return }
            sync?.removeFromSuperlayer()
            sync = nil
            shown = overlay
            guard let overlay, let item else { return }
            let s = AVSynchronizedLayer(playerItem: item)
            s.addSublayer(overlay)
            layer.addSublayer(s)
            sync = s
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let sync, let overlay = shown, renderSize.width > 0 else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sync.frame = bounds
            let scale = min(bounds.width / renderSize.width, bounds.height / renderSize.height)
            overlay.anchorPoint = .zero
            overlay.bounds = CGRect(origin: .zero, size: renderSize)
            overlay.position = CGPoint(x: (bounds.width - renderSize.width * scale) / 2,
                                       y: (bounds.height - renderSize.height * scale) / 2)
            overlay.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            CATransaction.commit()
        }
    }
}
