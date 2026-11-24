import SwiftUI

// DRAG THINGS WHERE THEY BELONG (25 Nov 2026, Luther's film-room brief). On
// the Mac a drill (Drills) or a play (Plays) can be dragged onto a class in
// the sidebar's clipboard: it joins that class's plan — the drill in Warm-up
// when the library files it as a routine, else in Skills; the play in the
// plan's plays. Plan items only: dropping an ATHLETE on a class would mark
// them present and charge a session, so athletes are not draggable.

enum FilmRoomDrag {
    private static let prefix = "hoopwise-drag:"

    enum Item: Equatable {
        case drill(UUID)
        case play(SessionPlayRef)
    }

    static func payload(_ item: Item) -> String {
        switch item {
        case .drill(let id): return prefix + "drill:" + id.uuidString
        case .play(let ref): return prefix + "play:" + ref.key + "\n" + ref.name
        }
    }

    static func parse(_ text: String) -> Item? {
        guard text.hasPrefix(prefix) else { return nil }
        let rest = String(text.dropFirst(prefix.count))
        if rest.hasPrefix("drill:") { return UUID(uuidString: String(rest.dropFirst(6))).map(Item.drill) }
        if rest.hasPrefix("play:") {
            let parts = String(rest.dropFirst(5)).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let key = parts.first, !key.isEmpty else { return nil }
            return .play(SessionPlayRef(key: key, name: parts.count > 1 ? parts[1] : ""))
        }
        return nil
    }

    /// What a drop did, in the coach's words.
    enum Outcome: Equatable {
        case addedToWarmup, addedToSkills, addedPlay, alreadyThere, notPossible

        func text(chinese: Bool) -> String {
            switch self {
            case .addedToWarmup: chinese ? "已加入热身" : "Added to Warm-up"
            case .addedToSkills: chinese ? "已加入技能" : "Added to Skills"
            case .addedPlay: chinese ? "已加入战术" : "Added to the plays"
            case .alreadyThere: chinese ? "计划里已经有了" : "Already in the plan"
            case .notPossible: chinese ? "这节课不能再改计划" : "This class's plan is closed"
            }
        }
        var added: Bool { self == .addedToWarmup || self == .addedToSkills || self == .addedPlay }
    }
}

extension SwiftDataManager {
    /// Put a dragged drill or play in a class's plan. Onto the STORED
    /// session; games, marks and results keep the store's values.
    @discardableResult
    func drop(_ item: FilmRoomDrag.Item, onSession sessionId: UUID) -> FilmRoomDrag.Outcome {
        guard var session = sessionEvents.first(where: { $0.id == sessionId }),
              !SessionLifecycle.didNotHappen(session), session.status != .completed else { return .notPossible }
        switch item {
        case .drill(let id):
            guard let drill = drills.first(where: { $0.id == id }), !drill.isSeries else { return .notPossible }
            if (session.curriculum.warmupDrillIds + session.curriculum.skillDrillIds).contains(id) { return .alreadyThere }
            let warmup = drill.libraryActivity?.block == .routine
            if warmup { session.curriculum.warmupDrillIds.append(id) } else { session.curriculum.skillDrillIds.append(id) }
            updateSessionEvent(session)
            return warmup ? .addedToWarmup : .addedToSkills
        case .play(let ref):
            if session.curriculum.plays.contains(where: { $0.key == ref.key }) { return .alreadyThere }
            session.curriculum.plays.append(ref)
            updateSessionEvent(session)
            return .addedPlay
        }
    }
}

private struct FilmRoomDraggable: ViewModifier {
    let item: FilmRoomDrag.Item
    let title: String
    let symbol: String

    func body(content: Content) -> some View {
        if FilmRoom.isOn {
            content.draggable(FilmRoomDrag.payload(item)) {
                // A small pane that follows the pointer (no data-bound views:
                // a drag preview is drawn outside the app's environment).
                Label(title, systemImage: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color(white: 0.18).opacity(0.95)))
            }
        } else {
            content
        }
    }
}

extension View {
    /// On the Mac this row can be dragged onto a class in the sidebar.
    func filmRoomDraggable(_ item: FilmRoomDrag.Item, title: String, symbol: String) -> some View {
        modifier(FilmRoomDraggable(item: item, title: title, symbol: symbol))
    }
}
