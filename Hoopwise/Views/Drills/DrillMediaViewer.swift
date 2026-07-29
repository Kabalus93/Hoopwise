import SwiftUI
import AVKit
#if os(iOS)
import UIKit
import WebKit
#endif

// MARK: - DrillMediaViewer
/// Full-screen paging viewer for a drill's media. Phase 1 only handles
/// `.image` (zoomable). Other kinds show a labeled placeholder so the carousel
/// never silently breaks — they'll be filled in by Phase 2 (video, YouTube)
/// and Phase 3 (court diagrams, Instagram).
struct DrillMediaViewer: View {
    let media: [DrillMedia]
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(media: [DrillMedia], initialIndex: Int) {
        self.media = media
        _currentIndex = State(initialValue: max(0, min(initialIndex, media.count - 1)))
    }

    private var sortedMedia: [DrillMedia] {
        media.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            TabView(selection: $currentIndex) {
                ForEach(Array(sortedMedia.enumerated()), id: \.element.id) { index, item in
                    DrillMediaPage(media: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            #else
            // macOS: simpler stacked view; macOS tier of this feature is Phase 4.
            if let first = sortedMedia.first {
                DrillMediaPage(media: first)
            }
            #endif

            topBar
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.45), in: Circle())
            }

            Spacer()

            if sortedMedia.count > 1 {
                Text("\(currentIndex + 1) / \(sortedMedia.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }

            Spacer()

            // Reserve the trailing slot for symmetry; future "edit caption"
            // button can land here.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }
}

// MARK: - DrillMediaPage
/// Per-kind rendering inside the full-screen pager. Each branch is responsible
/// for filling the available space; the caller sets the black backdrop.
private struct DrillMediaPage: View {
    let media: DrillMedia

    var body: some View {
        switch media.kind {
        case .image, .courtDiagram:
            imagePage
        case .videoClip:
            videoClipPage
        case .youtube:
            youtubePage
        case .instagram:
            instagramPage
        }
    }

    @ViewBuilder
    private var instagramPage: some View {
        // Instagram blocks anonymous embedding, so the best UX is a cached
        // thumbnail preview + a deep link to open the post in the Instagram
        // app (falls back to the browser if the app isn't installed).
        VStack(spacing: 18) {
            #if os(iOS)
            if let path = media.thumbnailPath,
               let image = DrillMediaStorage.shared.loadImage(at: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 30)
            } else {
                instagramGradientPlaceholder
                    .frame(width: 220, height: 220)
            }
            #else
            instagramGradientPlaceholder
                .frame(width: 220, height: 220)
            #endif

            VStack(spacing: 4) {
                Text(chineseFirst("Instagram 帖子", "Instagram post"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                if let caption = media.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            }

            if let urlString = media.remoteURL, let url = URL(string: urlString) {
                Link(destination: url) {
                    Label(chineseFirst("在 Instagram 中打开", "Open in Instagram"),
                          systemImage: "arrow.up.right.square.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.22), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var instagramGradientPlaceholder: some View {
        ZStack {
            // Instagram's brand gradient — communicates the platform at a
            // glance when no thumbnail is cached.
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.34, blue: 0.40),
                    Color(red: 0.85, green: 0.22, blue: 0.55),
                    Color(red: 0.49, green: 0.28, blue: 0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "camera.aperture")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var videoClipPage: some View {
        #if os(iOS)
        if let relative = media.localPath,
           let url = DrillMediaStorage.shared.videoFileURL(at: relative) {
            // VideoPlayer is the iOS 14+ SwiftUI wrapper around AVPlayerViewController.
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        } else {
            comingSoonPage(systemImage: "video.slash.fill",
                           message: chineseFirst("视频文件缺失", "Video file missing"))
        }
        #else
        comingSoonPage(systemImage: "video.fill",
                       message: chineseFirst("视频暂仅在 iOS 上播放", "Video playback is iOS-only"))
        #endif
    }

    @ViewBuilder
    private var youtubePage: some View {
        #if os(iOS)
        if let urlString = media.remoteURL,
           case .youtube(let id, _) = DrillMediaURL.parse(urlString) {
            YouTubeEmbedView(videoId: id)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        } else {
            comingSoonPage(systemImage: "play.rectangle.fill",
                           message: chineseFirst("链接无效", "Link is no longer valid"))
        }
        #else
        comingSoonPage(systemImage: "play.rectangle.fill",
                       message: chineseFirst("YouTube 暂仅在 iOS 上播放", "YouTube playback is iOS-only"))
        #endif
    }

    @ViewBuilder
    private var imagePage: some View {
        #if os(iOS)
        if let path = media.localPath ?? media.thumbnailPath,
           let image = DrillMediaStorage.shared.loadImage(at: path) {
            ZoomableImageView(image: image, caption: media.caption)
        } else {
            comingSoonPage(systemImage: "photo",
                           message: chineseFirst("图片缺失", "Image missing"))
        }
        #else
        Color.black
        #endif
    }

    private func comingSoonPage(systemImage: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            if let url = media.remoteURL, let parsed = URL(string: url) {
                Link(destination: parsed) {
                    Text(chineseFirst("在浏览器中打开", "Open in browser"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.18), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chineseFirst(_ zh: String, _ en: String) -> String {
        LocalizationManager.shared.currentLanguage == .chinese ? zh : en
    }
}

#if os(iOS)
// MARK: - YouTubeEmbedView
/// WKWebView hosting the official IFrame Player API. Embeds give us proper
/// playback controls, scrubbing, fullscreen, and recover from the rare cases
/// where a deep link to the YouTube app isn't installed. Wrapped in a
/// UIViewRepresentable so it composes inside the SwiftUI paging viewer.
struct YouTubeEmbedView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the ID changes — otherwise we'd re-buffer every
        // layout pass.
        if webView.url?.absoluteString.contains(videoId) == true { return }

        // `playsinline=1` keeps the video in the embed instead of forcing
        // the fullscreen video controller; `rel=0` suppresses unrelated
        // suggested videos at the end.
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin:0; padding:0; background:#000; height:100%; }
          .wrap { position:fixed; inset:0; display:flex; align-items:center; justify-content:center; }
          iframe { width:100%; height:100%; border:0; }
        </style>
        </head><body><div class="wrap">
        <iframe src="https://www.youtube.com/embed/\(videoId)?playsinline=1&rel=0&modestbranding=1"
                allow="autoplay; encrypted-media; picture-in-picture"
                allowfullscreen></iframe>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}

// MARK: - ZoomableImageView
/// Pinch-to-zoom with a double-tap to toggle 1×/2×. Caption pinned along the
/// bottom edge when present.
private struct ZoomableImageView: View {
    let image: UIImage
    let caption: String?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1, min(lastScale * value.magnification, 5))
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 {
                                    withAnimation(.spring) { offset = .zero; lastOffset = .zero }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        if scale > 1 {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        } else {
                            scale = 2; lastScale = 2
                        }
                    }
                }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
