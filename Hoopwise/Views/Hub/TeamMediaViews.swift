import SwiftUI
import PhotosUI
import Photos

// THE TEAM'S MEDIA (28 Nov 2026, Luther: "for teams, add a vault too. here
// goes the picture of the team. exporting would be for the final score, Game
// day … and other team related stats"). Photos stay in the coach's library;
// the team keeps the index (TeamPlaybook.media, setTeamVault). A post is made
// from a photo — or from none (the team colour) — as a final score, a game-day
// poster or the season so far (TeamPostFacts, TeamPostTemplates).

struct TeamMediaBlock: View {
    let team: Team
    @EnvironmentObject var dataManager: DataManager
    @State private var picked: [PhotosPickerItem] = []
    @State private var opened: VaultPhoto?
    @State private var access = PhotoVault.hasAccess
    @State private var composing = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var entries: [VaultPhoto] {
        VaultPhoto.ordered(dataManager.teams.first { $0.id == team.id }?.playbook.media ?? [])
    }

    var body: some View {
        let shown = access ? PhotoVault.assets(for: Array(entries.prefix(12))) : []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text((isChinese ? "照片" : "Media").uppercased()).font(.caption2.weight(.bold)).monospaced()
                } icon: {
                    Image(systemName: "photo.stack").font(.caption)
                }
                .foregroundStyle(.pink)
                if !entries.isEmpty {
                    Text("· \(entries.count)").font(.caption2.weight(.bold)).monospaced().foregroundStyle(.pink)
                }
                Spacer()
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "plus").font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityIdentifier("team.media.add")
            }
            if entries.isEmpty {
                Text(isChinese ? "球队的照片：合影、比赛照片。用 + 添加，再做比分、比赛日和赛季海报。"
                               : "The team's photos — the team picture, game shots. Add them with +, then make final-score, game-day and season posts.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !access {
                Button { Task { access = await PhotoVault.requestAccess() } } label: {
                    Label(isChinese ? "允许访问照片以查看" : "Allow access to Photos to see them", systemImage: "lock").font(.subheadline)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shown, id: \.entry.id) { item in
                            Button { opened = item.entry } label: {
                                VaultThumbnail(asset: item.asset)
                                    .frame(width: 120, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("team.media.photo")
                        }
                    }
                }
            }
            Button { composing = true } label: {
                Label(isChinese ? "制作球队海报" : "Make a team post", systemImage: "wand.and.stars")
                    .font(.body.weight(.semibold))
            }
            .accessibilityIdentifier("team.media.makePost")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .filmGlass(.regular, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("team.media")
        .onChange(of: picked) { _, items in add(items) }
        .sheet(item: $opened) { entry in
            NavigationStack { TeamPhotoView(team: team, entry: entry) }
                .environmentObject(dataManager)
        }
        .fullScreenCover(isPresented: $composing) {
            TeamPostLoader(team: team, entry: entries.first).environmentObject(dataManager)
        }
        .task { if !entries.isEmpty && !access { access = await PhotoVault.requestAccess() } }
    }

    private func add(_ items: [PhotosPickerItem]) {
        let ids = items.compactMap(\.itemIdentifier)
        picked = []
        guard !ids.isEmpty else { return }
        Task {
            access = await PhotoVault.requestAccess()
            let new = PhotoVault.entries(localIds: ids)
            dataManager.setTeamVault(teamId: team.id) { list in
                for p in new where !list.contains(where: { $0.sameAsset(as: p) }) { list.append(p) }
            }
            PhotoVault.file(localIds: ids, inAlbumFor: team.name)
        }
    }
}

/// One team photo: make a post with it, share it, take it out of the media.
struct TeamPhotoView: View {
    let team: Team
    let entry: VaultPhoto
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var composing = false
    @State private var confirmingRemove = false

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { composing = true } label: {
                Label(isChinese ? "用这张照片制作海报" : "Make a post with this photo", systemImage: "wand.and.stars")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(image == nil)
            .accessibilityIdentifier("team.media.photo.makePost")
        }
        .padding()
        .navigationTitle(team.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let image { ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) }
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label(isChinese ? "从球队照片中移出（照片保留）" : "Remove from the team (stays in Photos)", systemImage: "minus.circle")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog(isChinese ? "从球队照片中移出？" : "Remove from the team's media?",
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(isChinese ? "移出" : "Remove", role: .destructive) {
                dataManager.setTeamVault(teamId: team.id) { $0.removeAll { $0.id == entry.id } }
                dismiss()
            }
        } message: {
            Text(isChinese ? "照片仍保留在“照片”App 中。" : "The photo stays in your Photos library.")
        }
        .task {
            if let asset = PhotoVault.assets(for: [entry]).first?.asset { image = await PhotoVault.fullImage(asset) }
        }
        .fullScreenCover(isPresented: $composing) {
            if let image {
                TeamPostComposer(team: team, photo: image, more: []).environmentObject(dataManager)
            }
        }
    }
}

/// Loads the newest team photo (and two more for the collage), then composes.
struct TeamPostLoader: View {
    let team: Team
    let entry: VaultPhoto?
    @EnvironmentObject var dataManager: DataManager
    @State private var photo: UIImage?
    @State private var more: [UIImage] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if loaded {
                TeamPostComposer(team: team, photo: photo, more: more)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            let media = VaultPhoto.ordered((dataManager.teams.first { $0.id == team.id } ?? team).playbook.media)
            let assets = PhotoVault.assets(for: Array(media.prefix(3))).map(\.asset).filter { $0.mediaType == .image }
            if let first = assets.first { photo = await PhotoVault.fullImage(first) }
            for a in assets.dropFirst() { if let i = await PhotoVault.fullImage(a, side: 1400) { more.append(i) } }
            loaded = true
        }
    }
}

struct TeamPostComposer: View {
    let team: Team
    let photo: UIImage?
    let more: [UIImage]
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TeamPostFacts.Kind = .final
    @State private var template: TeamPostTemplate = .scoreBar
    @State private var gameId: UUID?
    @State private var aspect: AthletePostAspect = .portrait
    @State private var cutout: UIImage?
    @State private var cutoutTried = false
    @State private var sharing: [Any]?

    private var isChinese: Bool { AreaLanguage.isChinese(.playerCard) }
    private var scored: [SessionEvent] { TeamPostFacts.scored(of: team, in: dataManager.sessionEvents) }
    private var upcoming: [SessionEvent] { TeamPostFacts.upcoming(of: team, in: dataManager.sessionEvents) }
    private var games: [SessionEvent] { kind == .final ? scored : (kind == .gameDay ? upcoming : []) }
    private var game: SessionEvent? { games.first { $0.id == gameId } ?? games.first }

    private var facts: TeamPostFacts {
        TeamPostFacts.make(kind: kind, team: team, game: game, sessions: dataManager.sessionEvents,
                           academy: ProgramGuideStore.academyName, chinese: isChinese)
    }

    var body: some View {
        let f = facts
        let templates = TeamPostTemplate.of(kind)
        NavigationStack {
            VStack(spacing: 14) {
                Picker("", selection: $kind) {
                    ForEach(TeamPostFacts.Kind.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("teamPost.kind")
                if games.count > 1 {
                    Picker(isChinese ? "比赛" : "Game", selection: Binding(get: { game?.id }, set: { gameId = $0 })) {
                        ForEach(games) { g in
                            let plan = g.curriculum.gamePlan ?? GamePlan()
                            Text((plan.isHome ? "vs " : "@ ") + plan.opponentName(chinese: isChinese) + " · "
                                 + g.startTime.formatted(.dateTime.day().month(.abbreviated)))
                                .tag(Optional(g.id))
                        }
                    }
                    .accessibilityIdentifier("teamPost.game")
                }
                if f.hasData {
                    ScaledPost(size: aspect.size) {
                        TeamPostCanvas(template: template, facts: f, photo: photo, more: more, cutout: cutout, aspect: aspect)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .accessibilityIdentifier("teamPost.preview")
                    .contentShape(.rect)
                    .modifier(PostSwipe(count: templates.count, index: Binding(
                        get: { templates.firstIndex(of: template) ?? 0 },
                        set: { template = templates[$0] })))
                    PostTemplateBar(items: templates, selection: $template,
                                    title: { $0.title(chinese: isChinese) }, symbol: { $0.symbol },
                                    thumbnail: { t in
                                        ScaledPost(size: aspect.size) {
                                            TeamPostCanvas(template: t, facts: f, photo: photo, more: more, cutout: cutout, aspect: aspect)
                                        }
                                    },
                                    thumbnailAspect: aspect.size.width / aspect.size.height)
                } else {
                    ContentUnavailableView {
                        Label(empty.title, systemImage: "sportscourt")
                    } description: {
                        Text(empty.detail)
                    }
                    .frame(maxHeight: .infinity)
                }
                HStack {
                    Picker("", selection: $aspect) {
                        ForEach(AthletePostAspect.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 120)
                    Spacer()
                    Button(action: share) {
                        Label(isChinese ? "分享图片" : "Share image", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(minWidth: 180, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!f.hasData)
                    .accessibilityIdentifier("teamPost.share")
                }
            }
            .padding()
            .navigationTitle(isChinese ? "球队海报" : "Team post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: sharing) }
            }
            .onAppear {
                // Open on what there is: a result, else the next game, else the season.
                if scored.isEmpty { kind = upcoming.isEmpty ? .season : .gameDay }
                template = TeamPostTemplate.of(kind).first ?? .scoreBar
            }
            .onChange(of: kind) { _, k in
                gameId = nil
                if template.kind != k { template = TeamPostTemplate.of(k).first ?? template }
            }
            .onChange(of: template) { _, t in if t.liftsSubject { lift() } }
        }
    }

    private var empty: (title: String, detail: String) {
        switch kind {
        case .final: (isChinese ? "还没有比分" : "No score yet",
                      isChinese ? "在比赛日记录一场比赛的比分后，这里就能做比分海报。" : "Score a game from Game day and its final score can be posted here.")
        case .gameDay: (isChinese ? "没有即将到来的比赛" : "No game coming up",
                        isChinese ? "在球队页的“比赛日”里安排一场比赛。" : "Schedule a game from the team page's Game day.")
        case .season: (isChinese ? "还没有打完的比赛" : "No finished games yet",
                       isChinese ? "打完的比赛会算进赛季战绩。" : "Finished games make up the season record.")
        }
    }

    /// The players lifted out of the photo, every one of them (Vision, on the device).
    private func lift() {
        guard !cutoutTried, let cg = photo?.uprightCGImage else { return }
        cutoutTried = true
        Task {
            let t = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let c = ProfileBackgroundRemoval.cutOutAll(cg), let full = ProfileBackgroundRemoval.transparent(c) else { return nil }
                return PostLift.trimmed(full)
            }.value
            if let t { cutout = UIImage(cgImage: t) }
        }
    }

    private func share() {
        let renderer = ImageRenderer(content: TeamPostCanvas(template: template, facts: facts, photo: photo, more: more,
                                                             cutout: cutout, aspect: aspect))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.92) else { return }
        let name = team.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) \(template.rawValue).jpg")
        try? data.write(to: url)
        sharing = [url]
    }
}
