import SwiftUI
import UIKit

// PLAYS WITH THE TEAM'S FACES (23 Nov 2026, Luther: "when I'm using a play in
// a team practice or team option in the hub, let me have the choice of having
// either numbers or bubble pictures on the play … share a play to the team …
// share a play to a player: this highlights what that player does").
//
// A play's numbered players are the team's ROLES (PlayBreakdown): who plays
// role 3 is written on the breakdown. `PlayBubble`s carry that person onto the
// court — photo (or initials) with the role number as a small badge — and
// `playFocus` dims everyone but one player. Both ride the environment so the
// step player, the play page, playback and the printed sheets draw them with
// the one JournalPlayDiagramView.

/// One numbered player shown as a person.
struct PlayBubble: Equatable {
    var number: Int
    var personId: UUID?
    var name: String
    var initials: String
    var image: UIImage?
    /// Painted behind a cut-out photo (the skill-level colour).
    var backdrop: Color?

    static func == (a: PlayBubble, b: PlayBubble) -> Bool {
        a.number == b.number && a.personId == b.personId && a.name == b.name
            && a.initials == b.initials && (a.image === b.image) && a.backdrop == b.backdrop
    }

    /// Initials for a bubble without a photo: the last two characters of a
    /// Chinese name (the given name), else the first letters of two words.
    static func initials(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            let chars = trimmed.filter { !$0.isWhitespace }
            return String(chars.suffix(chars.count >= 3 ? 2 : chars.count))
        }
        let words = trimmed.split(separator: " ").prefix(2)
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

extension EnvironmentValues {
    /// Number → person; empty draws numbers, as always.
    @Entry var playBubbles: [Int: PlayBubble] = [:]
    /// The one player to follow: their lines bold and in colour, the rest grey.
    @Entry var playFocus: Int? = nil
    /// Leave the defenders off (a printed sheet when the coach says so).
    @Entry var playHidesDefense: Bool = false
}

/// The colour that marks the followed player — orange, apart from the
/// offense blue and the shot red.
enum PlayFocusStyle {
    static let color = Color(red: 0.95, green: 0.50, blue: 0.08)
}

// MARK: - The team's cast for one play

/// Who plays each numbered role of a play on a team (from its breakdown),
/// and which of several is on the floor (`lineup`, remembered per team and
/// play on the device).
struct TeamPlayCast: Equatable {
    struct Person: Identifiable, Equatable {
        let id: UUID
        var name: String
        var secondName: String?
        var imageData: Data?
        var backdropHex: String?
        var isCoach: Bool
        /// Media consent for publication (`mayPublishMedia`); coaches count as
        /// consenting (adults on their own staff).
        var mayPublish: Bool
    }
    struct Seat: Identifiable, Equatable {
        let number: Int
        var people: [Person]
        var standard: String
        var drillNames: [String]
        var id: Int { number }
    }

    var teamId: UUID
    var playKey: String
    var seats: [Seat]
    /// role number → chosen person when the role has several.
    var lineup: [Int: UUID]

    /// The person shown for a role.
    func person(for number: Int) -> Person? {
        guard let seat = seats.first(where: { $0.number == number }) else { return nil }
        if let chosen = lineup[number], let p = seat.people.first(where: { $0.id == chosen }) { return p }
        return seat.people.first
    }

    var hasPeople: Bool { seats.contains { !$0.people.isEmpty } }

    /// Bubbles for the court. `photos` false = initials only; `onlyConsented`
    /// keeps photos to people with publication consent (exports).
    func bubbles(photos: Bool = true, onlyConsented: Bool = false) -> [Int: PlayBubble] {
        var out: [Int: PlayBubble] = [:]
        for seat in seats {
            guard let p = person(for: seat.number) else { continue }
            let showPhoto = photos && (!onlyConsented || p.mayPublish)
            let image = showPhoto ? p.imageData.flatMap { decodedProfileImage($0) } : nil
            out[seat.number] = PlayBubble(number: seat.number, personId: p.id, name: p.name,
                                          initials: PlayBubble.initials(of: p.name), image: image,
                                          backdrop: p.backdropHex.map { Color(hex: $0) })
        }
        return out
    }

    // Device-local lineup.
    private static func lineupKey(team: UUID, play: String) -> String { "team.play.lineup.\(team.uuidString).\(play)" }

    static func storedLineup(team: UUID, play: String) -> [Int: UUID] {
        guard let raw = UserDefaults.standard.dictionary(forKey: lineupKey(team: team, play: play)) as? [String: String] else { return [:] }
        var out: [Int: UUID] = [:]
        for (k, v) in raw { if let n = Int(k), let id = UUID(uuidString: v) { out[n] = id } }
        return out
    }

    static func storeLineup(_ lineup: [Int: UUID], team: UUID, play: String) {
        let raw = Dictionary(uniqueKeysWithValues: lineup.map { (String($0.key), $0.value.uuidString) })
        UserDefaults.standard.set(raw, forKey: lineupKey(team: team, play: play))
    }

    /// Numbers or photos on this team's plays (device-local, per team).
    static func showsPeople(team: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: "team.play.people.\(team.uuidString)")
    }

    static func setShowsPeople(_ on: Bool, team: UUID) {
        UserDefaults.standard.set(on, forKey: "team.play.people.\(team.uuidString)")
    }
}

extension DataManager {
    /// The cast of `ref` on team `teamId`, nil when the play is not broken
    /// down there.
    func teamPlayCast(teamId: UUID, ref: SessionPlayRef, chinese: Bool? = nil) -> TeamPlayCast? {
        guard let team = teams.first(where: { $0.id == teamId }),
              let breakdown = team.playbook.breakdowns[ref.key] else { return nil }
        let zh = chinese ?? (LocalizationManager.shared.currentLanguage == .chinese)
        let seats = breakdown.roles.sorted { $0.number < $1.number }.map { role -> TeamPlayCast.Seat in
            let people = role.playerIds.compactMap { id -> TeamPlayCast.Person? in
                if let s = students.first(where: { $0.id == id }) {
                    let second = s.secondaryName(chinese: zh)
                    return .init(id: id, name: s.primaryName(chinese: zh), secondName: second,
                                 imageData: s.thumbnailImageData ?? s.profileImageData,
                                 backdropHex: photoBackdropHex(for: id),
                                 isCoach: false, mayPublish: mayPublishMedia(for: id))
                }
                if let c = staffCoaches.first(where: { $0.id == id }) {
                    let g = c.asGuestPlayer(dataManager: self)
                    return .init(id: id, name: g.primaryName(chinese: zh), secondName: g.secondaryName(chinese: zh),
                                 imageData: g.thumbnailImageData, backdropHex: nil, isCoach: true, mayPublish: true)
                }
                return nil
            }
            let drills = role.drillIds.compactMap { id in drills.first { $0.id == id }?.localizedName }
            return .init(number: role.number, people: people, standard: role.standard, drillNames: drills)
        }
        return TeamPlayCast(teamId: teamId, playKey: ref.key, seats: seats,
                            lineup: TeamPlayCast.storedLineup(team: teamId, play: ref.key))
    }
}
