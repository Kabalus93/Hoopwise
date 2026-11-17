import SwiftUI
import SwiftData

// HOME SEARCH (16 November 2026, Luther: "a Spotlight-like search bar that
// only appears on the home screen upon dragging down the page … results like
// students, drills, plays, lexicon, private students, coaches, sessions,
// programs and teams"). Pulling Home down brings it in WITH the finger, like
// the iPhone's home screen (16 Nov 2026, Luther: the first version — pull far,
// "Release to search", open after the bounce — was "awkwardly slow"); letting
// go past `HomeSearch.commitDistance` opens it with the field focused. Results are grouped by
// kind, a few each, best first; a tap closes the search and opens the item
// where the app already opens it (Home routes the target).

/// What a result opens.
enum HomeSearchTarget {
    case athlete(Student)
    case privateClient(Contract)
    case session(SessionEvent)
    case program(Program)
    case team(UUID)
    case coach(StaffCoach)
    case play(JournalPlay)
    case drill(DrillItem)
    case lexicon(Lexicon.Located)
}

enum HomeSearch {
    /// The pull (points of overscroll) at which the search is fully in.
    static let revealDistance: CGFloat = 70
    /// Letting go past this pull opens the search.
    static let commitDistance: CGFloat = 28
    /// Results shown per kind.
    static let perGroup = 5

    enum Kind: CaseIterable {
        case athletes, privateClients, sessions, programs, teams, coaches, plays, drills, lexicon

        func title(_ isChinese: Bool) -> String {
            switch self {
            case .athletes: isChinese ? "学员" : "Athletes"
            case .privateClients: isChinese ? "私教学员" : "Private clients"
            case .sessions: isChinese ? "课程" : "Sessions"
            case .programs: isChinese ? "项目" : "Programs"
            case .teams: isChinese ? "球队" : "Teams"
            case .coaches: isChinese ? "教练" : "Coaches"
            case .plays: isChinese ? "战术" : "Plays"
            case .drills: isChinese ? "训练" : "Drills"
            case .lexicon: isChinese ? "术语" : "Lexicon"
            }
        }

        var symbol: String {
            switch self {
            case .athletes: "person.fill"
            case .privateClients: "person.crop.circle.badge.checkmark"
            case .sessions: "calendar"
            case .programs: "rectangle.stack.fill"
            case .teams: "tshirt.fill"
            case .coaches: "whistle.fill"
            case .plays: "point.topleft.down.to.point.bottomright.curvepath"
            case .drills: "figure.basketball"
            case .lexicon: "book.closed.fill"
            }
        }
    }

    struct Hit: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        var student: Student?
        let target: HomeSearchTarget
    }

    struct Group: Identifiable {
        let kind: Kind
        let hits: [Hit]
        /// Matches beyond the ones shown.
        let more: Int
        var id: Kind { kind }
    }

    /// Every word of the query somewhere in the fields, any case and accent.
    static func matches(_ query: String, _ fields: [String?]) -> Bool {
        DrillFinder.typedMatch(query, in: fields.compactMap { $0 })
    }

    /// A field that STARTS with the query ranks first.
    static func startsWith(_ query: String, _ field: String) -> Bool {
        field.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .hasPrefix(query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }
}

/// The pull as the finger moves — read by the overlay alone, so the drag
/// redraws the search field and its blur, not Home.
@Observable final class HomePull {
    var distance: CGFloat = 0
    var dragging = false
}

/// Home's search layer: follows the pull, then stays open.
struct HomeSearchOverlay: View {
    let pull: HomePull
    let showing: Bool
    let onClose: () -> Void
    let onOpen: (HomeSearchTarget) -> Void

    private var reveal: CGFloat {
        guard pull.dragging, !showing else { return 0 }
        return min(1, pull.distance / HomeSearch.revealDistance)
    }

    var body: some View {
        if showing || reveal > 0 {
            HomeSearchView(live: showing, reveal: showing ? 1 : reveal, onClose: onClose, onOpen: onOpen)
                .allowsHitTesting(showing)
                .transition(.opacity)
        }
    }
}

/// Everything searchable, folded once when the search opens: a keystroke
/// checks prepared lowercase text instead of re-folding every session, drill
/// and play.
struct HomeSearchIndex {
    struct Item<Value> {
        let value: Value
        /// Folded searchable text (every field).
        let text: String
        /// Folded name alone (ranking).
        let name: String
    }
    var sessions: [Item<SessionEvent>] = []
    var programs: [Item<Program>] = []
    var teams: [Item<Team>] = []
    var plays: [Item<JournalPlay>] = []
    var drills: [Item<DrillItem>] = []

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Every word of the query somewhere in `text`.
    static func matches(_ words: [String], _ text: String) -> Bool {
        words.allSatisfy { text.contains($0) }
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

struct HomeSearchView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.modelContext) private var modelContext
    /// Opened (false while it follows the finger in).
    var live = true
    /// How far it has come in, 0…1.
    var reveal: CGFloat = 1
    let onClose: () -> Void
    let onOpen: (HomeSearchTarget) -> Void

    @State private var query = ""
    @State private var index: HomeSearchIndex?
    /// Groups opened past their first few ("+N more").
    @State private var expanded: Set<HomeSearch.Kind> = []
    @FocusState private var focused: Bool

    private var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .offset(y: -70 * (1 - reveal))
            ScrollView {
                VStack(spacing: 16) {
                    let trimmed = query.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        hint
                    } else {
                        let groups = results(for: trimmed)
                        if groups.isEmpty {
                            noResults(trimmed)
                        } else {
                            ForEach(groups) { group($0) }
                        }
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 140)
            }
            .scrollDismissesKeyboard(.interactively)
            .opacity(reveal)
        }
        .background(.ultraThinMaterial.opacity(reveal))
        .background(Color(.systemGroupedBackground).opacity(0.55 * reveal))
        .onAppear {
            if live { DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: live) { _, isLive in
            if isLive { focused = true }
        }
        // The index is built once it is OPEN, after the field has come in —
        // never during the drag (a fetch there was a hitch).
        .task(id: live) {
            guard live, index == nil else { return }
            await Task.yield()
            index = buildIndex()
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(isChinese ? "搜索" : "Search", text: $query)
                    .onChange(of: query) { expanded = [] }
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(openTopHit)
                    .accessibilityIdentifier("home.search.field")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isChinese ? "清除" : "Clear")
                }
            }
            .font(.title3)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)

            Button(isChinese ? "取消" : "Cancel", action: onClose)
                .font(.body.weight(.semibold))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("home.search.cancel")
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hint: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isChinese ? "搜索学员、私教学员、课程、项目、球队、教练、战术、训练和术语"
                           : "Athletes, private clients, sessions, programs, teams, coaches, plays, drills and terms")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    private func noResults(_ query: String) -> some View {
        Text(isChinese ? "没有找到“\(query)”" : "Nothing found for “\(query)”")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 60)
    }

    private func group(_ group: HomeSearch.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.kind.title(isChinese).uppercased())
                    .font(.caption2.weight(.bold))
                    .monospaced()
                    .foregroundStyle(.secondary)
                Spacer()
                if group.more > 0 {
                    Button(isChinese ? "还有 \(group.more) 个" : "+\(group.more) more") {
                        withAnimation(.snappy) { _ = expanded.insert(group.kind) }
                    }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.leading, 6)
            VStack(spacing: 0) {
                ForEach(group.hits) { hit in
                    row(hit, kind: group.kind)
                    if hit.id != group.hits.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(_ hit: HomeSearch.Hit, kind: HomeSearch.Kind) -> some View {
        Button {
            onOpen(hit.target)
        } label: {
            HStack(spacing: 12) {
                if let student = hit.student {
                    StudentAvatarView(student: student, size: 36)
                } else {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !hit.subtitle.isEmpty {
                        Text(hit.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.search.result")
    }

    private func openTopHit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let first = results(for: trimmed).first?.hits.first else { return }
        onOpen(first.target)
    }

    // MARK: - Results

    /// Fold everything once (on open).
    private func buildIndex() -> HomeSearchIndex {
        let fold = HomeSearchIndex.fold
        let programNames = Dictionary(dataManager.programs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var index = HomeSearchIndex()
        index.sessions = dataManager.cachedSessionEvents.map { session in
            let program = session.programId.flatMap { programNames[$0] } ?? ""
            return .init(value: session, text: fold([session.title, program, session.location ?? ""].joined(separator: " ")),
                         name: fold(session.title))
        }
        index.programs = dataManager.programs.map { .init(value: $0, text: fold($0.name), name: fold($0.name)) }
        index.teams = dataManager.teams.map { team in
            .init(value: team, text: fold([team.name, team.shortName].joined(separator: " ")), name: fold(team.name))
        }
        let plays = (try? modelContext.fetch(FetchDescriptor<JournalPlay>(sortBy: [SortDescriptor(\.name)]))) ?? []
        index.plays = plays.map { play in
            .init(value: play, text: fold([play.name, play.concept, play.situation].joined(separator: " ")), name: fold(play.name))
        }
        index.drills = dataManager.drills.map { drill in
            let name = fold([drill.name, drill.localizedName].joined(separator: " "))
            return .init(value: drill, text: name + " " + fold(drill.description), name: name)
        }
        return index
    }

    private func results(for q: String) -> [HomeSearch.Group] {
        var groups: [HomeSearch.Group] = []
        func add(_ kind: HomeSearch.Kind, _ hits: [HomeSearch.Hit]) {
            guard !hits.isEmpty else { return }
            let shown = expanded.contains(kind) ? min(hits.count, 60) : HomeSearch.perGroup
            groups.append(HomeSearch.Group(kind: kind, hits: Array(hits.prefix(shown)),
                                           more: max(0, hits.count - shown)))
        }
        let lower = q.lowercased()
        let programName: (UUID?) -> String? = { id in
            id.flatMap { pid in dataManager.programs.first { $0.id == pid }?.name }
        }

        // Athletes: name, Chinese name, pinyin, initials.
        let athletes = dataManager.students
            .filter { NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(lower) }
            .sorted { $0.primaryDisplayName < $1.primaryDisplayName }
        add(.athletes, athletes.map { student in
            HomeSearch.Hit(id: "a\(student.id)", title: student.primaryDisplayName,
                           subtitle: [student.secondaryNameLine, programName(student.programId)]
                               .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                           student: student, target: .athlete(student))
        })

        // Private clients: an active private contract whose athlete matches.
        let matched = Set(athletes.map(\.id))
        let privateContracts = dataManager.contracts
            .filter { ($0.kind == .privateBundle || $0.kind == .privatePayPerSession) && $0.status == .active }
            .filter { matched.contains($0.studentId) }
        add(.privateClients, privateContracts.compactMap { contract in
            guard let student = dataManager.students.first(where: { $0.id == contract.studentId }) else { return nil }
            let detail: String
            if contract.kind == .privateBundle {
                let left = contract.bundleRedemptionsRemaining ?? 0
                detail = isChinese ? "课时包 · 剩 \(left) 节" : "Bundle · \(left) left"
            } else {
                detail = isChinese ? "按次付费" : "Pay per session"
            }
            return HomeSearch.Hit(id: "c\(contract.id)", title: student.primaryDisplayName, subtitle: detail,
                                  student: student, target: .privateClient(contract))
        })

        let words = HomeSearchIndex.words(q)
        let folded = HomeSearchIndex.fold(q)
        let idx = index ?? HomeSearchIndex()

        // Sessions: name, program, venue — upcoming soonest first, then the
        // most recent.
        let now = Date()
        let sessions = idx.sessions.filter { HomeSearchIndex.matches(words, $0.text) }.map(\.value)
            .sorted { a, b in
                let au = a.startTime >= now, bu = b.startTime >= now
                if au != bu { return au }
                return au ? a.startTime < b.startTime : a.startTime > b.startTime
            }
        add(.sessions, sessions.map { session in
            let when = session.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            return HomeSearch.Hit(id: "s\(session.id)", title: session.title,
                                  subtitle: [when, session.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                  target: .session(session))
        })

        add(.programs, idx.programs
            .filter { HomeSearchIndex.matches(words, $0.text) }
            .sorted { ($0.name.hasPrefix(folded) ? 0 : 1, $0.name) < ($1.name.hasPrefix(folded) ? 0 : 1, $1.name) }
            .map(\.value)
            .map { program in
                let count = program.enrolledStudentIds.count
                return HomeSearch.Hit(id: "p\(program.id)", title: program.name,
                                      subtitle: isChinese ? "\(count) 名学员" : "\(count) athlete\(count == 1 ? "" : "s")",
                                      target: .program(program))
            })

        add(.teams, idx.teams
            .filter { HomeSearchIndex.matches(words, $0.text) }
            .map(\.value)
            .map { team in
                HomeSearch.Hit(id: "t\(team.id)", title: team.name,
                               subtitle: isChinese ? "\(team.playerIds.count) 名球员" : "\(team.playerIds.count) players",
                               target: .team(team.id))
            })

        add(.coaches, dataManager.staffCoaches
            .filter { NameIndex.cached(name: $0.name, secondary: $0.chineseName).matches(lower) }
            .map { coach in
                let name = isChinese ? (coach.chineseName?.isEmpty == false ? coach.chineseName! : coach.name) : coach.name
                return HomeSearch.Hit(id: "k\(coach.id)", title: name, subtitle: coach.role.localizedName,
                                      target: .coach(coach))
            })

        add(.plays, idx.plays
            .filter { HomeSearchIndex.matches(words, $0.text) }
            .sorted { ($0.name.hasPrefix(folded) ? 0 : 1) < ($1.name.hasPrefix(folded) ? 0 : 1) }
            .map(\.value)
            .map { play in
                HomeSearch.Hit(id: "y\(play.persistentModelID.hashValue)", title: play.name,
                               subtitle: jp(play.category.label), target: .play(play))
            })

        // Drills: name matches first.
        let drills = idx.drills
            .filter { HomeSearchIndex.matches(words, $0.text) }
            .map { ($0, HomeSearchIndex.matches(words, $0.name)) }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 }
                return a.0.value.localizedName < b.0.value.localizedName
            }
            .map(\.0.value)
        add(.drills, drills.map { drill in
            HomeSearch.Hit(id: "d\(drill.id)", title: drill.localizedName,
                           subtitle: drill.description.replacingOccurrences(of: "\n", with: " "),
                           target: .drill(drill))
        })

        add(.lexicon, Lexicon.shared.search(q).map { item in
            HomeSearch.Hit(id: "l\(item.id)", title: item.entry.term, subtitle: item.entry.definition,
                           target: .lexicon(item))
        })
        return groups
    }
}
