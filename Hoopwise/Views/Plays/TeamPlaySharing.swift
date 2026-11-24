import SwiftUI
import UIKit

// A team's play, on screen and on paper (23 Nov 2026, Luther). Where a play is
// opened from a team — its breakdown page, its play page from the team, a team
// practice's plan — `TeamPlayCastBar` sits over the court: Numbers | Players
// (remembered per team), and a chip per role to FOLLOW that player (their
// lines bold orange, the rest grey). Share opens `PlaySheetShareSheet`: a team
// sheet, one player's sheet or sheets for everyone, as an A4 PDF, printed, or
// one long image for WeChat.

/// The state a team play page keeps: the cast, numbers or players, who is followed.
struct TeamPlayViewState: Equatable {
    var cast: TeamPlayCast?
    var showsPeople = false
    var focus: Int?

    var bubbles: [Int: PlayBubble] { showsPeople ? (cast?.bubbles() ?? [:]) : [:] }
}

struct TeamPlayCastBar: View {
    @Binding var state: TeamPlayViewState
    var onShare: () -> Void
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let cast = state.cast, cast.hasPeople {
                    Picker(isChinese ? "球场上显示" : "On the court", selection: Binding(
                        get: { state.showsPeople },
                        set: { on in
                            state.showsPeople = on
                            TeamPlayCast.setShowsPeople(on, team: cast.teamId)
                        })) {
                        Text(isChinese ? "号码" : "Numbers").tag(false)
                        Text(isChinese ? "球员" : "Players").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .accessibilityIdentifier("teamPlay.marks")
                }
                Spacer(minLength: 0)
                Button(action: onShare) {
                    Label(isChinese ? "分享" : "Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("teamPlay.share")
            }
            if let cast = state.cast, cast.hasPeople {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(selected: state.focus == nil, identifier: "teamPlay.follow.all") {
                            Image(systemName: "person.3.fill").font(.caption)
                            Text(isChinese ? "全队" : "Everyone").font(.subheadline.weight(.medium))
                        } action: { state.focus = nil }
                        ForEach(cast.seats) { seat in seatChip(seat, cast: cast) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func seatChip(_ seat: TeamPlayCast.Seat, cast: TeamPlayCast) -> some View {
        let person = cast.person(for: seat.number)
        let content = HStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let person, let data = person.imageData, let image = decodedProfileImage(data) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 26, height: 26)
                        .background(Color(hex: person.backdropHex ?? "#E0E0E0"))
                        .clipShape(Circle())
                } else {
                    Circle().fill(Color(.tertiarySystemFill)).frame(width: 26, height: 26)
                        .overlay(Text(person.map { PlayBubble.initials(of: $0.name) } ?? "\(seat.number)")
                            .font(.system(size: 10, weight: .bold, design: .rounded)))
                }
                Text("\(seat.number)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(state.focus == seat.number ? PlayFocusStyle.color : JPalette.play, in: Circle())
                    .offset(x: 4, y: 3)
            }
            Text(person?.name ?? (isChinese ? "未分配" : "Open"))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if seat.people.count > 1 {
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        if seat.people.count > 1 {
            // Several on one role: tap follows, the menu picks who is on.
            Menu {
                Picker(isChinese ? "谁在场上" : "Who's on", selection: Binding(
                    get: { cast.person(for: seat.number)?.id },
                    set: { id in
                        guard var c = state.cast, let id else { return }
                        c.lineup[seat.number] = id
                        TeamPlayCast.storeLineup(c.lineup, team: c.teamId, play: c.playKey)
                        state.cast = c
                    })) {
                    ForEach(seat.people) { Text($0.name).tag(Optional($0.id)) }
                }
            } label: {
                chipLabel(selected: state.focus == seat.number) { content }
            } primaryAction: {
                toggle(seat.number)
            }
            .accessibilityIdentifier("teamPlay.follow.\(seat.number)")
        } else {
            chip(selected: state.focus == seat.number, identifier: "teamPlay.follow.\(seat.number)") {
                content
            } action: { toggle(seat.number) }
        }
    }

    private func toggle(_ number: Int) {
        withAnimation(.snappy) { state.focus = state.focus == number ? nil : number }
    }

    private func chip<C: View>(selected: Bool, identifier: String, @ViewBuilder content: () -> C,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(selected: selected, content: content) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipLabel<C: View>(selected: Bool, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 6) { content() }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
            .background(Capsule().fill(selected ? PlayFocusStyle.color.opacity(0.18) : Color(.secondarySystemFill)))
            .overlay(Capsule().strokeBorder(selected ? PlayFocusStyle.color : .clear, lineWidth: 1.5))
            .contentShape(Capsule())
    }
}

extension View {
    /// Draws the team's state on every court below.
    func teamPlayState(_ state: TeamPlayViewState) -> some View {
        environment(\.playBubbles, state.bubbles)
            .environment(\.playFocus, state.focus)
    }
}

// MARK: - Share

struct PlaySheetShareSheet: View {
    let play: JournalPlay
    let teamId: UUID?
    /// The player followed on screen: the sheet starts on theirs.
    var initialFocus: Int?

    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) private var dismiss

    enum Kind: Hashable { case team, player(Int), everyone }
    @State private var kind: Kind = .team
    /// Asked every time (Luther): nil until the coach answers.
    @State private var defenders: Bool?
    @State private var people = true
    @State private var photos = true
    @State private var preview: UIImage?
    @State private var pdf: Data?
    @State private var sharing: [Any]?
    @State private var cast: TeamPlayCast?

    private var chinese: Bool { AreaLanguage.isChinese(.exports) }
    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
    private var team: Team? { teamId.flatMap { id in dataManager.teams.first { $0.id == id } } }
    private var hasDefense: Bool {
        play.sortedParts.contains { $0.sortedSteps.contains { !$0.diagram.defense.isEmpty } }
    }
    /// PHOTOS ON THE SHEET (23 Nov 2026, Luther, markup on Players: "with
    /// photos" — it printed initials for a team with no consent recorded).
    /// A play sheet goes to the team itself, so "Players" means their photos;
    /// the switch stays to leave them off, and the footer says who has no
    /// media consent on record (a reminder before posting it anywhere public).
    private var hasPhotos: Bool { cast?.seats.contains { $0.people.contains { $0.imageData != nil } } ?? false }
    private var withoutConsent: Int {
        cast.map { c in c.seats.compactMap { c.person(for: $0.number) }.filter { $0.imageData != nil && !$0.mayPublish }.count } ?? 0
    }
    private var ready: Bool { !hasDefense || defenders != nil }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            // The sheet as it will be sent, always in view above the options.
            previewView
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .filmRoomPage()
            Form {
                if let cast, cast.hasPeople {
                    Section(isChinese ? "战术单" : "Sheet") {
                        Picker(isChinese ? "给谁" : "For", selection: $kind) {
                            Text(isChinese ? "全队" : "The team").tag(Kind.team)
                            ForEach(cast.seats.filter { !$0.people.isEmpty }) { seat in
                                Text("\(seat.number) · \(cast.person(for: seat.number)?.name ?? "")").tag(Kind.player(seat.number))
                            }
                            Text(isChinese ? "每人一份" : "Sheets for everyone").tag(Kind.everyone)
                        }
                        .accessibilityIdentifier("playSheet.kind")
                    }
                    Section {
                        Picker(isChinese ? "球场上" : "On the court", selection: $people) {
                            Text(isChinese ? "号码" : "Numbers").tag(false)
                            Text(isChinese ? "球员" : "Players").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if people && hasPhotos {
                            Toggle(isChinese ? "包含照片" : "Include photos", isOn: $photos)
                                .accessibilityIdentifier("playSheet.photos")
                        }
                    } footer: {
                        if people {
                            if !hasPhotos {
                                Text(isChinese ? "球员以姓名缩写显示，号位旁写上姓名。" : "Players show as initials, with their names beside the role numbers.")
                            } else if photos && withoutConsent > 0 {
                                Text(isChinese ? "其中 \(withoutConsent) 名学员没有记录肖像发布同意：这份战术单发给本队即可，不要公开发布。"
                                               : "\(withoutConsent) of these athletes have no media consent on record — fine for the team itself, not for a public post.")
                            } else {
                                Text(isChinese ? "球员显示照片，号位旁写上姓名。" : "Players show with their photos, names beside the role numbers.")
                            }
                        }
                    }
                }
                if hasDefense {
                    Section {
                        Picker(isChinese ? "防守球员" : "Defenders", selection: $defenders) {
                            Text(isChinese ? "显示" : "Show").tag(Optional(true))
                            Text(isChinese ? "隐藏" : "Hide").tag(Optional(false))
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("playSheet.defenders")
                    } header: {
                        Text(isChinese ? "防守球员" : "Defenders")
                    } footer: {
                        if defenders == nil {
                            Text(isChinese ? "每次都要选：这张单子要画防守吗？" : "Choose each time: should this sheet show the defense?")
                        }
                    }
                }
            }
          }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(isChinese ? "分享战术" : "Share Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChinese ? "完成" : "Done") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                if let sharing { ShareSheet(items: sharing) }
            }
        }
        .presentationSizing(.page)
        .onAppear {
            cast = teamId.flatMap { dataManager.teamPlayCast(teamId: $0, ref: play.planRef, chinese: chinese) }
            if let cast {
                people = cast.hasPeople
                if let initialFocus, cast.person(for: initialFocus) != nil { kind = .player(initialFocus) }
            }
            render()
            #if DEBUG
            debugExport()
            #endif
        }
        .onChange(of: kind) { render() }
        .onChange(of: defenders) { render() }
        .onChange(of: people) { render() }
        .onChange(of: photos) { render() }
    }

    /// Always in reach under the options.
    private var actions: some View {
        HStack(spacing: 10) {
            Button { share(pdfFile: true) } label: {
                Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("playSheet.sharePDF")
            Button(action: print) {
                Label(isChinese ? "打印" : "Print", systemImage: "printer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("playSheet.print")
            Button { share(pdfFile: false) } label: {
                Label(isChinese ? "长图" : "Image", systemImage: "photo").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("playSheet.shareImage")
        }
        .controlSize(.large)
        .disabled(!ready || pdf == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var previewView: some View {
        if let preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .accessibilityIdentifier("playSheet.preview")
        } else {
            ProgressView().frame(height: 280)
        }
    }

    // MARK: - Making the sheets

    private func sheets() -> [PlaySheet] {
        let zh = chinese
        let bubbles = people ? (cast?.bubbles(photos: photos, onlyConsented: false) ?? [:]) : [:]
        let roles: [PlaySheet.Role] = {
            let numbers = play.conceptPart?.sortedSteps.first?.diagram.offense.map(\.number).sorted() ?? []
            let all = Set(numbers + (cast?.seats.map(\.number) ?? [])).sorted()
            return all.map { PlaySheet.Role(number: $0, name: people ? cast?.person(for: $0)?.name : nil) }
        }()
        let base = PlaySheet(
            playName: play.name, category: play.category, court: play.court,
            situation: play.situation, idea: play.concept, parts: PlaySheet.parts(of: play),
            teamName: team?.name, teamColor: UIColor(Color(hex: team?.colorHex ?? "#2A78D6")),
            academy: ProgramGuideStore.academyName, roles: roles, bubbles: bubbles,
            showsDefense: defenders ?? true, chinese: zh)
        func forPlayer(_ n: Int) -> PlaySheet {
            var s = base
            s.focus = n
            let seat = cast?.seats.first { $0.number == n }
            s.focusName = cast?.person(for: n)?.name
            s.focusStandard = seat?.standard ?? ""
            s.focusDrills = seat?.drillNames ?? []
            return s
        }
        switch kind {
        case .team: return [base]
        case .player(let n): return [forPlayer(n)]
        case .everyone:
            let numbers = cast?.seats.filter { !$0.people.isEmpty }.map(\.number) ?? []
            return numbers.isEmpty ? [base] : numbers.map(forPlayer)
        }
    }

    #if DEBUG
    /// HOOPWISE_PLAYSHEET_EXPORT=team|player|everyone (gallery shot playSheet).
    private func debugExport() {
        guard let which = ProcessInfo.processInfo.environment["HOOPWISE_PLAYSHEET_EXPORT"],
              let caches = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.OKTO.SAMp")?
                .appendingPathComponent("Library/Caches") else { return }
        defenders = ProcessInfo.processInfo.environment["HOOPWISE_PLAYSHEET_DEFENSE"] != "0"
        photos = true
        switch which {
        case "player": kind = cast?.seats.first(where: { !$0.people.isEmpty }).map { .player($0.number) } ?? .team
        case "everyone": kind = .everyone
        default: kind = .team
        }
        let data = PlaySheetDocument.pdf(sheets())
        try? data.write(to: caches.appendingPathComponent("playsheet.pdf"))
        try? PlaySheetDocument.longImage(pdf: data)?.write(to: caches.appendingPathComponent("playsheet.jpg"))
    }
    #endif

    private func render() {
        let data = PlaySheetDocument.pdf(sheets())
        pdf = data
        preview = PlaySheetDocument.preview(pdf: data, width: 900)
    }

    private var fileStem: String {
        var parts = [play.name]
        if let team = team?.name { parts.append(team) }
        if case .player(let n) = kind, let name = cast?.person(for: n)?.name { parts.append(name) }
        let raw = parts.joined(separator: "_")
        return raw.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
    }

    private func share(pdfFile: Bool) {
        guard let pdf else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlaySheets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if pdfFile {
            let url = dir.appendingPathComponent("Play_\(fileStem).pdf")
            try? pdf.write(to: url)
            sharing = [url]
        } else if let jpeg = PlaySheetDocument.longImage(pdf: pdf) {
            let url = dir.appendingPathComponent("Play_\(fileStem).jpg")
            try? jpeg.write(to: url)
            sharing = [url]
        }
    }

    private func print() {
        guard let pdf else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = play.name
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true)
    }
}
