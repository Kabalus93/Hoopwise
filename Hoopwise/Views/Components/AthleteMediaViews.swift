import SwiftUI
import PhotosUI
import Photos

// THE MEDIA VAULT ON SCREEN (26 Nov 2026). The athlete's photos — on the
// profile and in the Quick Peep — the whole vault, one photo, the post composer,
// and a class's "Photos from this class". Photos stay in Photos; the vault is
// the index (Models/AthleteVault.swift, Services/PhotoVault.swift).

private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

// MARK: - A thumbnail

struct VaultThumbnail: View {
    let asset: PHAsset
    var side: CGFloat = 220
    @State private var image: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text(VideoTime.text(asset.duration)).font(.caption2.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(5)
                }
            }
            .task(id: asset.localIdentifier) { image = await PhotoVault.image(asset, side: side) }
    }
}

// MARK: - The card on the profile / Quick Peep

struct AthleteMediaCard: View {
    let studentId: UUID
    @EnvironmentObject var dataManager: DataManager
    @State private var picked: [PhotosPickerItem] = []
    @State private var showingVault = false
    @State private var opened: VaultPhoto?
    @State private var access = PhotoVault.hasAccess
    @State private var tick = 0

    private var student: Student? { dataManager.students.first { $0.id == studentId } }
    private var entries: [VaultPhoto] { VaultPhoto.ordered(student?.mediaAssets.vault ?? []) }

    var body: some View {
        let shown = access ? PhotoVault.assets(for: Array(entries.prefix(12))) : []
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isChinese ? "照片" : "Media", systemImage: "photo.stack").font(.headline)
                if !entries.isEmpty {
                    Text("\(entries.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if !entries.isEmpty {
                    Button(isChinese ? "全部" : "See all") { showingVault = true }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("media.all")
                }
                PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                    Image(systemName: "plus").font(.subheadline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityIdentifier("media.add")
            }
            if !access && !entries.isEmpty {
                Button {
                    Task { access = await PhotoVault.requestAccess() }
                } label: {
                    Label(isChinese ? "允许访问照片以查看" : "Allow access to Photos to see them", systemImage: "lock")
                        .font(.subheadline)
                }
            } else if entries.isEmpty {
                Text(isChinese ? "你给这位学员拍的照片和视频：用 + 添加，或在课程的 ⋯ → 把课堂照片加给学员 里选。"
                               : "Photos and videos you shot of this athlete. Add them with +, or from a class's ⋯ → Add Class Photos to Athletes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shown, id: \.entry.id) { item in
                            Button { opened = item.entry } label: {
                                VaultThumbnail(asset: item.asset)
                                    .frame(width: 96, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("media.photo")
                        }
                    }
                }
                if shown.count < min(entries.count, 12) {
                    Text(isChinese ? "有些照片还在同步或已从照片中删除。" : "Some photos are still syncing or were deleted from Photos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("athlete.media")
        .onChange(of: picked) { _, items in add(items) }
        .sheet(isPresented: $showingVault) {
            NavigationStack { AthleteMediaVaultView(studentId: studentId) }
                .environmentObject(dataManager)
        }
        .sheet(item: $opened) { entry in
            NavigationStack { VaultPhotoView(studentId: studentId, entry: entry) }
                .environmentObject(dataManager)
        }
        .task { if !entries.isEmpty && !access { access = await PhotoVault.requestAccess() } }
        // The face index: each photo is looked at once, in the background, so
        // a poster already knows which photo holds the best close-up.
        .task(id: entries.filter { $0.facesChecked != true }.count) {
            guard access else { return }
            try? await Task.sleep(for: .seconds(1.5))
            await FaceIndex.index(studentId: studentId, vault: entries, dataManager: dataManager)
        }
    }

    private func add(_ items: [PhotosPickerItem]) {
        let ids = items.compactMap(\.itemIdentifier)
        picked = []
        guard !ids.isEmpty else { return }
        Task {
            access = await PhotoVault.requestAccess()
            let entries = PhotoVault.entries(localIds: ids)
            dataManager.addToVaults(entries, studentIds: [studentId])
            if let name = student?.primaryDisplayName { PhotoVault.file(localIds: ids, inAlbumFor: name) }
        }
    }
}

// MARK: - The whole vault

struct AthleteMediaVaultView: View {
    let studentId: UUID
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var opened: VaultPhoto?

    private var student: Student? { dataManager.students.first { $0.id == studentId } }

    var body: some View {
        let items = PhotoVault.assets(for: VaultPhoto.ordered(student?.mediaAssets.vault ?? []))
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 4)], spacing: 4) {
                ForEach(items, id: \.entry.id) { item in
                    Button { opened = item.entry } label: {
                        VaultThumbnail(asset: item.asset, side: 300)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("media.vault.photo")
                }
            }
            .padding(4)
        }
        .navigationTitle(student.map { (isChinese ? "照片 · " : "Media · ") + $0.primaryDisplayName } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
        }
        .navigationDestination(item: $opened) { entry in
            VaultPhotoView(studentId: studentId, entry: entry, pushed: true)
        }
    }
}

// MARK: - One photo

struct VaultPhotoView: View {
    let studentId: UUID
    let entry: VaultPhoto
    var pushed = false
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var composing = false
    @State private var confirmingRemove = false
    /// Every face on this photo (the face index looks at it on the device).
    @State private var faces: [VaultFace] = []

    private var asset: PHAsset? { PhotoVault.assets(for: [entry]).first?.asset }
    /// The stored entry (it changes when a face is chosen).
    private var stored: VaultPhoto {
        dataManager.students.first { $0.id == studentId }?.mediaAssets.vault.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        if let asset, asset.mediaType == .video {
            VaultVideoView(studentId: studentId, entry: entry, asset: asset, pushed: pushed)
        } else {
            photoBody
        }
    }

    private var photoBody: some View {
        VStack(spacing: 16) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .overlay { faceMarks(image: image) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let date = entry.takenAt {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            if faces.count > 1 {
                Text(isChinese ? "点一下学员的脸——制作图片时会用它。" : "Tap the athlete's face — posters use it.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("media.face.hint")
            }
            Button { composing = true } label: {
                Label(isChinese ? "加上数据制作图片" : "Make a post with their stats", systemImage: "wand.and.stars")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(image == nil)
            .accessibilityIdentifier("media.makePost")
        }
        .padding()
        .navigationTitle(isChinese ? "照片" : "Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !pushed {
                ToolbarItem(placement: .confirmationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    if let image { ShareLink(item: Image(uiImage: image), preview: SharePreview("Photo", image: Image(uiImage: image))) }
                    Button(role: .destructive) { confirmingRemove = true } label: {
                        Label(isChinese ? "从照片库中移出（照片保留）" : "Remove from vault (stays in Photos)", systemImage: "minus.circle")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityIdentifier("media.photo.more")
            }
        }
        .confirmationDialog(isChinese ? "从这位学员的照片中移出？" : "Remove from this athlete's media?",
                            isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button(isChinese ? "移出" : "Remove", role: .destructive) {
                dataManager.setVault(studentId: studentId) { $0.removeAll { $0.id == entry.id } }
                dismiss()
            }
        } message: {
            Text(isChinese ? "照片仍保留在“照片”App 中。" : "The photo stays in your Photos library.")
        }
        .task {
            if let asset { image = await PhotoVault.fullImage(asset) }
            if let cg = image?.uprightCGImage {
                faces = await Task.detached(priority: .userInitiated) { FaceIndex.faces(in: cg) }.value
            }
        }
        .fullScreenCover(isPresented: $composing) {
            if let image, let student = dataManager.students.first(where: { $0.id == studentId }) {
                AthletePostComposer(student: student, photo: image).environmentObject(dataManager)
            }
        }
    }
}

extension VaultPhotoView {
    /// The faces on the photo: the one used for posters ringed in the accent
    /// colour with the athlete's name; a tap on another makes it theirs (the
    /// face index otherwise takes the largest).
    @ViewBuilder
    func faceMarks(image: UIImage) -> some View {
        if faces.count > 1 {
            GeometryReader { geo in
                let chosen = stored.face?.rect ?? faces.first?.rect
                ForEach(faces.indices, id: \.self) { i in
                    let f = faces[i]
                    let r = CGRect(x: f.rect.minX * geo.size.width, y: f.rect.minY * geo.size.height,
                                   width: f.rect.width * geo.size.width, height: f.rect.height * geo.size.height)
                    let on = chosen.map { overlap($0, f.rect) > 0.5 } ?? false
                    Button { chooseFace(f, image: image) } label: {
                        RoundedRectangle(cornerRadius: r.width * 0.2)
                            .strokeBorder(on ? Color.accentColor : .white.opacity(0.85),
                                          style: StrokeStyle(lineWidth: on ? 3 : 1.5, dash: on ? [] : [5, 4]))
                            .background(Color.white.opacity(0.001))
                            .overlay(alignment: .bottom) {
                                if on, let name = dataManager.students.first(where: { $0.id == studentId })?.primaryDisplayName {
                                    Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.accentColor))
                                        .fixedSize().offset(y: 22)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: r.width, height: r.height)
                    .position(x: r.midX, y: r.midY)
                    .accessibilityIdentifier(on ? "media.face.chosen" : "media.face")
                }
            }
        }
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull, a.width * a.height > 0 else { return 0 }
        return (i.width * i.height) / min(a.width * a.height, b.width * b.height)
    }

    private func chooseFace(_ face: VaultFace, image: UIImage) {
        var mine = face
        mine.byCoach = true
        // Pixels at the photo's own size.
        if let asset { mine.pixels = face.rect.height * Double(asset.pixelHeight) }
        dataManager.setVault(studentId: studentId) { list in
            guard let i = list.firstIndex(where: { $0.id == entry.id }) else { return }
            list[i].face = mine
            list[i].facesChecked = true
        }
    }
}

// MARK: - The post composer

struct AthletePostComposer: View {
    let student: Student
    let photo: UIImage
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var template: AthletePostTemplate = .gameLine
    @State private var source: AthletePostFacts.Source = .lastGame
    @State private var aspect: AthletePostAspect = .portrait
    @State private var cutout: UIImage?
    @State private var cutoutTried = false
    /// The athlete alone, cropped to them (Torn paper stands them up large).
    @State private var figure: UIImage?
    @State private var figureStands = true
    /// The best close-up of their face in the vault (Torn paper's half face).
    @State private var portrait: PostPortrait?
    @State private var sharing: [Any]?

    private var chinese: Bool { AreaLanguage.isChinese(.playerCard) }

    private var facts: AthletePostFacts {
        let program = dataManager.programs.first { $0.id == student.programId }
        return AthletePostFacts.make(student: student, jersey: dataManager.player(for: student.id)?.jerseyNumber,
                                     colorHex: program?.colorHex ?? "#2A78D6",
                                     academy: ProgramGuideStore.academyName,
                                     sessions: dataManager.sessionEvents, source: source, chinese: chinese)
    }

    var body: some View {
        let f = facts
        NavigationStack {
            VStack(spacing: 14) {
                GeometryReader { geo in
                    let size = aspect.size
                    let scale = min(geo.size.width / size.width, geo.size.height / size.height)
                    AthletePostCanvas(template: template, facts: f, photo: photo, cutout: cutout, aspect: aspect,
                                      figure: figure, figureStands: figureStands, portrait: portrait)
                        .scaleEffect(scale)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityIdentifier("post.preview")
                if !f.hasStats {
                    Text(isChinese ? "这段时间没有比赛数据 — 换一个范围，或先记录比赛。"
                                   : "No game stats for this — try another range, or score a game first.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                // Thirteen templates: a strip of chips (26 Nov 2026).
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AthletePostTemplate.allCases) { t in
                                let on = template == t
                                Button { withAnimation(.snappy) { template = t } } label: {
                                    Label(t.title(chinese: isChinese), systemImage: t.symbol)
                                        .font(.subheadline.weight(on ? .semibold : .regular))
                                        .padding(.horizontal, 14).frame(minHeight: 38)
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemFill)))
                                }
                                .buttonStyle(.plain)
                                .id(t)
                                .accessibilityIdentifier("post.template.\(t.rawValue)")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    .onChange(of: template) { _, t in withAnimation { proxy.scrollTo(t, anchor: .center) } }
                }
                HStack {
                    Picker(isChinese ? "数据" : "Stats", selection: $source) {
                        ForEach(AthletePostFacts.Source.allCases) { Text($0.title(chinese: isChinese)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("post.source")
                    Picker("", selection: $aspect) {
                        ForEach(AthletePostAspect.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
                consentLine
                Button(action: share) {
                    Label(isChinese ? "分享图片" : "Share image", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("post.share")
            }
            .padding()
            .navigationTitle(isChinese ? "制作图片" : "Make a post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: sharing) }
            }
            .onChange(of: template) { _, t in if t.liftsSubject { liftSubject() } }
            .onAppear { if template.liftsSubject { liftSubject() } }
        }
    }

    /// Who may see it: anyone they choose for the family; publicly only with
    /// publication consent recorded on their contract.
    private var consentLine: some View {
        let mayPost = dataManager.mayPublishMedia(for: student.id)
        return Label(mayPost ? (isChinese ? "已记录肖像发布同意，可以公开发布。" : "Publication consent on record — fine to post publicly.")
                             : (isChinese ? "没有记录肖像发布同意：只发给家长，不要公开发布。" : "No publication consent on record — share with the family, don't post publicly."),
                     systemImage: mayPost ? "checkmark.seal" : "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(mayPost ? Color.green : Color.orange)
            .accessibilityIdentifier("post.consent")
    }

    /// The poster lifts the athlete out of the photo (Vision, on the device):
    /// the person with the largest face, a teammate leaning in left out. Then
    /// the half face: the sharpest close-up in their vault (the face index),
    /// else this photo, else their profile picture.
    private func liftSubject() {
        guard !cutoutTried, let cg = photo.uprightCGImage else { return }
        cutoutTried = true
        let vault = student.mediaAssets.vault
        let studentId = student.id
        let profile = student.profileImageData
        Task {
            let face = await Task.detached(priority: .userInitiated) { FaceIndex.athleteFace(in: cg) }.value
            let lifted = await Task.detached(priority: .userInitiated) { PostLift.lift(cg, face: face) }.value
            if let lifted {
                cutout = UIImage(cgImage: lifted)
                if let t = PostLift.trimmedFigure(lifted) { figure = UIImage(cgImage: t.image); figureStands = !t.cutAtBottom }
            }
            portrait = await makePortrait(mainFace: face, mainLifted: lifted, main: cg,
                                          vault: vault, studentId: studentId, profile: profile)
        }
    }

    private func makePortrait(mainFace: VaultFace?, mainLifted: CGImage?, main: CGImage,
                              vault: [VaultPhoto], studentId: UUID, profile: Data?) async -> PostPortrait? {
        await FaceIndex.index(studentId: studentId, vault: vault, dataManager: dataManager)
        let indexed = dataManager.students.first { $0.id == studentId }?.mediaAssets.vault ?? vault
        // This photo at its own resolution vs the best in the vault.
        let mainScore = mainFace.map { var f = $0; f.pixels = $0.height * Double(main.height); return f.score } ?? 0
        if let best = FaceIndex.bestFace(in: indexed), let face = best.face, face.score > mainScore,
           let asset = PhotoVault.assets(for: [best]).first?.asset,
           let image = await PhotoVault.fullImage(asset), let cg = image.uprightCGImage {
            // Find it again on this copy (a coach's pick keeps its rectangle).
            let here = face.byCoach == true ? face : (await Task.detached { FaceIndex.athleteFace(in: cg) }.value ?? face)
            let lifted = await Task.detached(priority: .userInitiated) { PostLift.lift(cg, face: here) }.value
            return PostPortrait(image: UIImage(cgImage: lifted ?? cg), face: here.rect, lifted: lifted != nil)
        }
        if let mainFace, mainScore > 0 {
            return PostPortrait(image: UIImage(cgImage: mainLifted ?? main), face: mainFace.rect, lifted: mainLifted != nil)
        }
        if let profile, let image = UIImage(data: profile), let cg = image.uprightCGImage,
           let face = await Task.detached(priority: .userInitiated, operation: { FaceIndex.athleteFace(in: cg) }).value {
            return PostPortrait(image: UIImage(cgImage: cg), face: face.rect,
                                lifted: ProfilePhotoEncoding.isTransparent(cg))
        }
        return nil
    }

    private func share() {
        let renderer = ImageRenderer(content: AthletePostCanvas(template: template, facts: facts, photo: photo,
                                                                cutout: cutout, aspect: aspect,
                                                                figure: figure, figureStands: figureStands, portrait: portrait))
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.92) else { return }
        let name = student.primaryDisplayName.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) \(template.rawValue).jpg")
        try? data.write(to: url)
        sharing = [url]
    }
}

// MARK: - Photos from a class

/// The photos shot during a class: pick some, then who is in them. Only the
/// class's athletes are offered — present ones once roll call started.
struct SessionPhotosSheet: View {
    let session: SessionEvent
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss
    @State private var access = PhotoVault.hasAccess
    @State private var assets: [PHAsset] = []
    @State private var loaded = false
    @State private var picked: Set<String> = []
    @State private var who: Set<UUID> = []
    @State private var filed: String?
    /// Photos picked from the whole library (27 Nov 2026, Luther: "how do I
    /// add pictures here?" — only photos shot during the class showed, and
    /// none meant a dead end).
    @State private var libraryPick: [PhotosPickerItem] = []

    private var athletes: [Student] {
        let present = Set(session.actualAttendeeIds)
        let ids = present.isEmpty ? AttendanceMath.expectedIds(of: session, programs: dataManager.programs) : Array(present)
        return dataManager.students.filter { ids.contains($0.id) }.sorted { $0.primaryDisplayName < $1.primaryDisplayName }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !access {
                    ContentUnavailableView {
                        Label(isChinese ? "需要访问照片" : "Photos access needed", systemImage: "photo.on.rectangle")
                    } description: {
                        Text(isChinese ? "Hoopwise 读取这节课期间拍的照片，照片本身留在“照片”App 中。"
                                       : "Hoopwise reads the photos shot during this class; they stay in your Photos library.")
                    } actions: {
                        Button(isChinese ? "允许访问" : "Allow access") { Task { await load(asking: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if loaded && assets.isEmpty {
                    ContentUnavailableView {
                        Label(isChinese ? "这节课期间没有照片" : "No photos from this class", systemImage: "photo")
                    } description: {
                        Text(isChinese ? "开始前 30 分钟到结束后 1 小时内用这台设备拍的照片和视频会自动出现在这里。也可以从照片图库里选。"
                                       : "Photos and videos shot on this device from 30 minutes before to an hour after the class appear here by themselves. You can also choose any from your library.")
                    } actions: {
                        libraryButton.buttonStyle(.borderedProminent)
                    }
                } else {
                    content
                }
            }
            .navigationTitle(isChinese ? "把课堂照片加给学员" : "Add Class Photos to Athletes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(isChinese ? "完成" : "Done") { dismiss() } }
                if access && !(loaded && assets.isEmpty) {
                    ToolbarItem(placement: .primaryAction) { libraryButton }
                }
            }
            .task { await load(asking: false) }
            .onChange(of: libraryPick) { _, items in
                let ids = items.compactMap(\.itemIdentifier)
                guard !ids.isEmpty else { return }
                let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var extra: [PHAsset] = []
                fetched.enumerateObjects { a, _, _ in extra.append(a) }
                let known = Set(assets.map(\.localIdentifier))
                assets = extra.filter { !known.contains($0.localIdentifier) } + assets
                picked.formUnion(ids)
                libraryPick = []
            }
        }
    }

    private var libraryButton: some View {
        PhotosPicker(selection: $libraryPick, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
            Label(isChinese ? "从图库选择" : "Choose from Library", systemImage: "photo.badge.plus")
        }
        .accessibilityIdentifier("classPhotos.library")
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text(isChinese ? "选出照片，再选照片里的学员——它们会出现在学员资料的“媒体”里。照片本身留在“照片”App 中。"
                           : "Pick the photos, then who is in them — they appear in each athlete's Media. The photos stay in your Photos library.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.vertical, 10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        let on = picked.contains(asset.localIdentifier)
                        Button {
                            if on { picked.remove(asset.localIdentifier) } else { picked.insert(asset.localIdentifier) }
                        } label: {
                            VaultThumbnail(asset: asset, side: 260)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(on ? Color.accentColor : .white)
                                        .shadow(radius: 2).padding(6)
                                }
                                .opacity(on ? 1 : 0.85)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("classPhotos.photo")
                    }
                }
                .padding(4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(isChinese ? "照片里有谁？" : "Who's in them?").font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(athletes) { s in
                            let on = who.contains(s.id)
                            Button {
                                if on { who.remove(s.id) } else { who.insert(s.id) }
                            } label: {
                                VStack(spacing: 4) {
                                    StudentAvatarView(student: s, size: 46)
                                        .overlay(Circle().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 3).padding(-3))
                                    Text(s.primaryDisplayName).font(.caption2).lineLimit(1).frame(width: 64)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("classPhotos.athlete")
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let filed {
                    Label(filed, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.green)
                }
                Button(action: file) {
                    Text(isChinese ? "把 \(picked.count) 张照片加入 \(who.count) 位学员" : "Add \(picked.count) photo\(picked.count == 1 ? "" : "s") to \(who.count) athlete\(who.count == 1 ? "" : "s")")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty || who.isEmpty)
                .accessibilityIdentifier("classPhotos.add")
            }
            .padding()
            .background(.bar)
        }
    }

    private func load(asking: Bool) async {
        if asking || PhotoVault.hasAccess { access = await PhotoVault.requestAccess() }
        guard access else { return }
        assets = PhotoVault.photos(during: session)
        loaded = true
    }

    private func file() {
        let ids = assets.map(\.localIdentifier).filter { picked.contains($0) }
        let entries = PhotoVault.entries(localIds: ids, sessionId: session.id)
        dataManager.addToVaults(entries, studentIds: Array(who))
        for s in athletes where who.contains(s.id) { PhotoVault.file(localIds: ids, inAlbumFor: s.primaryDisplayName) }
        filed = isChinese ? "已加入 \(who.count) 位学员的照片" : "Added to \(who.count) athlete\(who.count == 1 ? "" : "s")"
        picked = []
        who = []
    }
}
