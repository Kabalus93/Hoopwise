import Foundation

// MARK: - DrillMediaURL
/// Parses pasted URLs into a recognized remote media kind. Covers the URL
/// shapes coaches actually paste (mobile share sheet, browser address bar,
/// shortened links). Anything we don't recognize falls through to `.unsupported`
/// so the picker can surface a clear "we can't read this link" message.
enum DrillMediaURL: Equatable {
    case youtube(videoId: String, original: URL)
    case instagram(shortcode: String, original: URL)
    case unsupported

    /// The corresponding `DrillMediaKind` for parsed cases, or nil for
    /// `.unsupported`.
    var kind: DrillMediaKind? {
        switch self {
        case .youtube: return .youtube
        case .instagram: return .instagram
        case .unsupported: return nil
        }
    }

    /// The original URL string (suitable for storing on `DrillMedia.remoteURL`).
    var canonicalString: String? {
        switch self {
        case .youtube(_, let url), .instagram(_, let url):
            return url.absoluteString
        case .unsupported:
            return nil
        }
    }

    /// Returns a remote URL we can download a poster thumbnail from. YouTube
    /// exposes a hot-linkable JPEG at `img.youtube.com`. Instagram does not
    /// (the platform blocks anonymous thumbnail access), so callers should
    /// fall back to a placeholder for `.instagram`.
    var thumbnailURL: URL? {
        switch self {
        case .youtube(let id, _):
            // `hqdefault` is 480x360, always available, returns 200 even when
            // higher resolutions don't exist.
            return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
        case .instagram, .unsupported:
            return nil
        }
    }

    /// Best-effort parser. Tolerates whitespace, missing scheme, and the most
    /// common URL shapes.
    static func parse(_ raw: String) -> DrillMediaURL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unsupported }

        // Prepend a scheme if the user pasted "youtu.be/abc" with no https://.
        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }
        guard let url = URL(string: withScheme), let host = url.host?.lowercased() else {
            return .unsupported
        }

        if let id = youtubeVideoId(from: url, host: host) {
            return .youtube(videoId: id, original: url)
        }
        if let code = instagramShortcode(from: url, host: host) {
            return .instagram(shortcode: code, original: url)
        }
        return .unsupported
    }

    // MARK: - YouTube extraction
    /// Pulls a video ID out of any of the canonical YouTube URL shapes:
    ///   - `youtube.com/watch?v=ID`
    ///   - `m.youtube.com/watch?v=ID`
    ///   - `youtu.be/ID`
    ///   - `youtube.com/embed/ID`
    ///   - `youtube.com/shorts/ID`
    private static func youtubeVideoId(from url: URL, host: String) -> String? {
        guard host.contains("youtube.com") || host.contains("youtu.be") else { return nil }

        if host == "youtu.be" {
            let path = url.pathComponents.filter { $0 != "/" }
            return path.first.flatMap(sanitizedYouTubeId)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // /watch?v=...
        if url.path == "/watch",
           let item = components?.queryItems?.first(where: { $0.name == "v" })?.value {
            return sanitizedYouTubeId(item)
        }
        // /embed/<id>, /shorts/<id>, /live/<id>
        let parts = url.pathComponents.filter { $0 != "/" }
        if let first = parts.first,
           ["embed", "shorts", "live", "v"].contains(first),
           parts.count >= 2 {
            return sanitizedYouTubeId(parts[1])
        }
        return nil
    }

    /// YouTube IDs are 11 characters of `[A-Za-z0-9_-]`. Reject anything that
    /// doesn't fit so we don't end up embedding garbage. `nonisolated` because
    /// it's a pure function — the call site `youtubeVideoId(from:)` is
    /// nonisolated when invoked from the main-actor-default `parse(_:)`.
    nonisolated private static func sanitizedYouTubeId(_ candidate: String) -> String? {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        )
        let stripped = candidate.unicodeScalars.prefix { allowed.contains($0) }
        let id = String(String.UnicodeScalarView(stripped))
        return id.count == 11 ? id : nil
    }

    // MARK: - Instagram extraction
    /// Instagram shortcodes live at `/p/<code>/`, `/reel/<code>/`, or
    /// `/tv/<code>/`. Shortcodes are alphanumeric + `_` / `-`.
    private static func instagramShortcode(from url: URL, host: String) -> String? {
        guard host.contains("instagram.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2,
              ["p", "reel", "reels", "tv"].contains(parts[0]) else { return nil }
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
        )
        let candidate = parts[1]
        let stripped = candidate.unicodeScalars.prefix { allowed.contains($0) }
        let code = String(String.UnicodeScalarView(stripped))
        return code.isEmpty ? nil : code
    }
}
