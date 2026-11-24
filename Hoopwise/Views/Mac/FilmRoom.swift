import SwiftUI

// THE MAC IS A FILM ROOM (25 Nov 2026, Luther: "HoopWise on the Mac (not
// iPad, not iOS) should feel like a quiet, well-lit film room rather than a
// dashboard. You open it and the court is already there, a deep blue wash
// with faint lines running behind everything, and the controls float over it
// on thin panes of frosted glass … The sidebar sits on the left like a
// clipboard you never put down … Nothing shouts: colour appears only where a
// team, a status or a decision needs it … rows that light up under the
// cursor … a second window when you want the board beside the plan.")
//
// Mac Catalyst only. iPhone and iPad keep the tab bar and their pages exactly
// as they are; `FilmRoom.isOn` is the one switch (DEBUG: HOOPWISE_FILM_ROOM=1
// shows the Mac shell on an iPad simulator, which is how it is looked at —
// the Mac itself cannot be screenshotted from here).

enum FilmRoom {
    static let isOn: Bool = {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif DEBUG
        return ProcessInfo.processInfo.environment["HOOPWISE_FILM_ROOM"] == "1"
        #else
        return false
        #endif
    }()

    static let sidebarWidth: CGFloat = 236
    static let boardWindowId = "coachBoard"
}

extension Notification.Name {
    /// ⇧⌘B on the Mac: the Coach board in its own window (the shell opens it).
    static let hoopwiseOpenBoardWindow = Notification.Name("hoopwiseOpenBoardWindow")
}

private struct FilmRoomWindowKey: EnvironmentKey { static let defaultValue: CGSize = .zero }
extension EnvironmentValues {
    /// The Mac window's size, so every page draws the court in the same place.
    var filmRoomWindow: CGSize {
        get { self[FilmRoomWindowKey.self] }
        set { self[FilmRoomWindowKey.self] = newValue }
    }
}

// MARK: - The court behind everything

/// What sits between the window's glass and the app. On the Mac: a faint
/// cool tint, nothing else (the court artwork is gone — Luther: "how about
/// nothing? just a frosted glass?"). On the iPad simulator's DEBUG preview
/// there is no window glass, so a plain deep blue stands in.
struct FilmRoomBackdrop: View {
    var body: some View {
        #if targetEnvironment(macCatalyst)
        Color(red: 0.05, green: 0.09, blue: 0.18).opacity(0.22)
        #else
        // A stand-in for the frosted window: a blurred desktop, roughly.
        LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24), Color(red: 0.09, green: 0.10, blue: 0.14)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        #endif
    }
}

/// A PAGE's background. Off the Mac: the system's grouped background, as
/// before. On the Mac: nothing — the window's glass is the background of
/// every page.
struct FilmRoomPageBackground: View {
    var body: some View {
        if FilmRoom.isOn {
            Color.clear
        } else {
            Color(.systemGroupedBackground)
        }
    }
}

extension Color {
    /// A CARD's fill. Off the Mac: the system's secondary grouped background,
    /// as before. On the Mac: a thin pane of glass over the window's.
    static var filmCard: Color {
        FilmRoom.isOn ? Color.white.opacity(0.075) : Color(.secondarySystemGroupedBackground)
    }
}

// MARK: - Rows that answer the pointer

private struct FilmRoomHover: ViewModifier {
    let radius: CGFloat
    @State private var over = false
    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            content
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(over ? 0.075 : 0))
                    .padding(-4))
                .onHover { over = $0 }
                .animation(.easeOut(duration: 0.12), value: over)
        } else {
            content
        }
    }
}

extension View {
    /// A List row: on the Mac a thin pane over the court; elsewhere the
    /// system's own row background (nil leaves it alone).
    func filmRoomListRow() -> some View {
        listRowBackground(FilmRoom.isOn ? Color.filmCard : nil)
    }

    /// On the Mac the row lights up under the pointer; nothing elsewhere.
    func filmRoomHover(cornerRadius: CGFloat = 12) -> some View { modifier(FilmRoomHover(radius: cornerRadius)) }
}

// MARK: - The shell: sidebar + the work

/// Where the sidebar takes you. The raw values are the tab numbers the app
/// already uses (⌘1–⌘4), carried on for the pages that were inside the Hub.
enum FilmRoomPlace: Int, CaseIterable, Identifiable {
    case home = 0, sessions, athletes, hub, plays, drills, lexicon, teams, organization
    var id: Int { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .home: chinese ? "首页" : "Home"
        case .sessions: chinese ? "课程" : "Sessions"
        case .athletes: chinese ? "学员" : "Athletes"
        case .hub: chinese ? "中心" : "Hub"
        case .plays: chinese ? "战术" : "Plays"
        case .drills: chinese ? "训练" : "Drills"
        case .lexicon: chinese ? "术语" : "Lexicon"
        case .teams: chinese ? "球队" : "Teams"
        case .organization: chinese ? "机构" : "Organization"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .sessions: "calendar"
        case .athletes: "person.2"
        case .hub: "square.grid.2x2"
        case .plays: "sportscourt"
        case .drills: "cone"
        case .lexicon: "book"
        case .teams: "tshirt"
        case .organization: "building.2"
        }
    }

    static let work: [FilmRoomPlace] = [.home, .sessions, .athletes, .hub]
    static let library: [FilmRoomPlace] = [.plays, .drills, .lexicon]
    static let people: [FilmRoomPlace] = [.teams, .organization]
}

struct FilmRoomShell<Main: View>: View {
    @EnvironmentObject private var dataManager: DataManager
    @Environment(\.openWindow) private var openWindow
    @Binding var selection: Int
    /// The four pages the tab bar holds on the iPhone and iPad.
    @ViewBuilder let main: (FilmRoomPlace) -> Main

    /// Pages opened so far stay alive behind the one on screen, so coming
    /// back finds them where they were left.
    @State private var visited: Set<FilmRoomPlace> = []

    private var place: FilmRoomPlace { FilmRoomPlace(rawValue: selection) ?? .home }

    var body: some View {
        GeometryReader { window in
            ZStack(alignment: .topLeading) {
                FilmRoomBackdrop().ignoresSafeArea()
                // The work: right of the sidebar, clipped to its own area (a
                // split view inside a page otherwise takes the sidebar's clicks).
                ZStack {
                    ForEach(FilmRoomPlace.allCases) { p in
                        if visited.contains(p) || p == place {
                            page(p)
                                .opacity(p == place ? 1 : 0)
                                .allowsHitTesting(p == place)
                                .disabled(p != place)
                                .accessibilityHidden(p != place)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .padding(.leading, FilmRoom.sidebarWidth + 10)

                // The clipboard, above everything.
                FilmRoomSidebar(selection: $selection) { openWindow(id: FilmRoom.boardWindowId) }
                    .frame(width: FilmRoom.sidebarWidth)
                    .padding(.leading, 10).padding(.vertical, 10)
                    .zIndex(2)
            }
            .environment(\.filmRoomWindow, window.size)
        }
        .ignoresSafeArea()
        .onAppear { visited.insert(place) }
        .onChange(of: selection) { _, _ in visited.insert(place) }
        .onReceive(NotificationCenter.default.publisher(for: .hoopwiseOpenBoardWindow)) { _ in
            openWindow(id: FilmRoom.boardWindowId)
        }
    }

    @ViewBuilder
    private func page(_ p: FilmRoomPlace) -> some View {
        switch p {
        case .home, .sessions, .athletes, .hub: main(p)
        case .plays: NavigationStack { JournalPlaysScreen() }
        case .drills: NavigationStack { DrillsLibraryView() }
        case .lexicon: NavigationStack { LexiconScreen() }
        case .teams: NavigationStack { TeamsScreen() }
        case .organization: NavigationStack { OrganizationView() }
        }
    }
}

/// The clipboard: where you are, what is on today, the board.
struct FilmRoomSidebar: View {
    @EnvironmentObject private var dataManager: DataManager
    @ObservedObject private var localization = LocalizationManager.shared
    @Binding var selection: Int
    let openBoard: () -> Void

    private var zh: Bool { localization.currentLanguage == .chinese }

    /// The next classes — today's first — that can still be planned.
    private var upcoming: [SessionEvent] {
        let now = Date()
        return dataManager.sessionEvents
            .filter { !SessionLifecycle.didNotHappen($0) && $0.status != .completed && $0.endTime > now }
            .sorted { $0.startTime < $1.startTime }
            .prefix(6).map { $0 }
    }

    /// The class a drop just landed on, and what it did (shown for a moment).
    @State private var dropNote: (session: UUID, outcome: FilmRoomDrag.Outcome)?
    @State private var dropTarget: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's close / minimise / zoom buttons sit here.
            Color.clear.frame(height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("HOOPWISE").font(.system(size: 10, weight: .heavy)).kerning(2).foregroundStyle(.white.opacity(0.45))
                Text(ProgramGuideStore.academyName).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(FilmRoomPlace.work) { row($0) }
                    header(zh ? "资料库" : "LIBRARY")
                    ForEach(FilmRoomPlace.library) { row($0) }
                    header(zh ? "人员" : "PEOPLE")
                    ForEach(FilmRoomPlace.people) { row($0) }
                    header(zh ? "工具" : "TOOLS")
                    SidebarButton(symbol: "rectangle.on.rectangle", title: zh ? "战术板（新窗口）" : "Coach board",
                                  hint: "⇧⌘B", selected: false, action: openBoard)
                        .accessibilityIdentifier("filmRoom.board")

                    if !upcoming.isEmpty {
                        header(zh ? "接下来的课" : "UP NEXT")
                        ForEach(upcoming) { session in todayRow(session) }
                        Text(zh ? "把训练或战术拖到课上" : "Drag a drill or a play onto a class")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.32))
                            .padding(.horizontal, 10).padding(.top, 4)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)
                .locale(Locale(identifier: zh ? "zh_CN" : "en_US"))))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        // The pane catches a little light along its top and leading edges.
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.06), .white.opacity(0.02)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filmRoom.sidebar")
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).kerning(1.2).foregroundStyle(.white.opacity(0.38))
            .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 5)
    }

    private func row(_ place: FilmRoomPlace) -> some View {
        SidebarButton(symbol: place.symbol, title: place.title(chinese: zh), hint: "⌘\(place.rawValue + 1)",
                      selected: selection == place.rawValue) {
            selection = place.rawValue
        }
        .accessibilityIdentifier("filmRoom.place.\(place.rawValue)")
    }

    /// One of the next classes: when, its name, a dot only when it is live.
    /// A drill or a play dropped here joins its plan.
    private func todayRow(_ session: SessionEvent) -> some View {
        let live = session.status == .inProgress
        let isToday = Calendar.current.isDateInToday(session.startTime)
        let time = session.startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()
            .locale(Locale(identifier: "en_GB")))
        let day = session.startTime.formatted(.dateTime.weekday(.abbreviated)
            .locale(Locale(identifier: zh ? "zh_CN" : "en_US")))
        let note = dropNote?.session == session.id ? dropNote?.outcome : nil
        let targeted = dropTarget == session.id
        return Button {
            NotificationCenter.default.post(name: .hoopwiseOpenSessionRequest, object: session.id)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    if !isToday { Text(day).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4)) }
                    Text(time).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                }
                .frame(width: 38, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.title).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                    if let note {
                        Text(note.text(chinese: zh)).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(note.added ? Color.green : Color.orange)
                            .accessibilityIdentifier("filmRoom.dropNote")
                    }
                }
                Spacer(minLength: 0)
                if live { Circle().fill(Color.green).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 10).frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(targeted ? 0.18 : 0))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(targeted ? 0.5 : 0), lineWidth: 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .filmRoomHover(cornerRadius: 9)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.compactMap(FilmRoomDrag.parse).first else { return false }
            let outcome = dataManager.drop(item, onSession: session.id)
            withAnimation(.snappy) { dropNote = (session.id, outcome) }
            let id = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if dropNote?.session == id { withAnimation(.easeOut) { dropNote = nil } }
            }
            return outcome.added
        } isTargeted: { over in
            dropTarget = over ? session.id : (dropTarget == session.id ? nil : dropTarget)
        }
        .accessibilityIdentifier("filmRoom.today")
    }
}

private struct SidebarButton: View {
    let symbol: String
    let title: String
    let hint: String
    let selected: Bool
    let action: () -> Void
    @State private var over = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                    .symbolVariant(selected ? .fill : .none)
                    .frame(width: 22)
                Text(title).font(.system(size: 13.5, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                // The key, only while the pointer is here.
                Text(hint).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .opacity(over ? 1 : 0)
            }
            .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.16 : (over ? 0.07 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over = $0 }
        .animation(.easeOut(duration: 0.12), value: over)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Coach board in a window of its own (beside the plan).
struct CoachBoardWindow: View {
    @EnvironmentObject private var dataManager: DataManager
    var body: some View {
        CoachBoardScreen()
            .environmentObject(dataManager)
            .preferredColorScheme(.dark)
            .onAppear {
                #if targetEnvironment(macCatalyst)
                MacWindow.configure()
                #endif
            }
    }
}
