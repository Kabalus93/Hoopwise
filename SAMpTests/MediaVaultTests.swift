import XCTest
@testable import Hoopwise

/// The media vault (26 Nov 2026): the index of an athlete's photos in Photos,
/// kept by its own writer, and the numbers a post puts on a photo.
@MainActor
final class MediaVaultTests: XCTestCase {
    private let team = UUID()

    private func game(_ who: UUID, pts: Int, reb: Int, ast: Int) -> SessionGame {
        let id = UUID()
        return SessionGame(sessionId: UUID(), gameType: .twoTeam,
                           playerStats: [SessionPlayerStats(playerId: who, gameId: id, teamId: team,
                                                            points: pts, rebounds: reb, assists: ast)],
                           basketValue: 2, status: .completed)
    }

    private func session(_ date: Date, _ games: [SessionGame]) -> SessionEvent {
        var s = SessionEvent(programId: nil, title: "U10", date: date, startTime: date,
                             endTime: date.addingTimeInterval(3600), status: .completed, attendeeIds: [])
        s.games = games
        return s
    }

    // MARK: The vault

    func testTheVaultHasItsOwnWriterAndNeverDoubles() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let kid = Student(name: "Maya Chen")
        let other = Student(name: "Leo Martin")
        dm.addStudent(kid); dm.addStudent(other)
        let a = VaultPhoto(localId: "A/L0", cloudId: "cloud-a", addedAt: .now, takenAt: .now)
        let b = VaultPhoto(localId: "B/L0", cloudId: nil, addedAt: .now, takenAt: .now.addingTimeInterval(-60))

        dm.addToVaults([a, b], studentIds: [kid.id, other.id])
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.mediaAssets.vault.count, 2)
        XCTAssertEqual(dm.students.first { $0.id == other.id }?.mediaAssets.vault.count, 2, "one photo, several athletes")

        // The same photo again — by local id, or by the cloud id another device found.
        var sameElsewhere = a; sameElsewhere.localId = "A-on-the-iPad"
        dm.addToVaults([a, sameElsewhere], studentIds: [kid.id])
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.mediaAssets.vault.count, 2, "never doubled")

        // A whole-athlete save from an older copy keeps the stored vault.
        var stale = kid
        stale.name = "Maya C."
        stale.mediaAssets.vault = []
        dm.updateStudent(stale)
        let stored = dm.students.first { $0.id == kid.id }!
        XCTAssertEqual(stored.name, "Maya C.")
        XCTAssertEqual(stored.mediaAssets.vault.count, 2, "only setVault writes the vault")

        dm.setVault(studentId: kid.id) { $0.removeAll { $0.localId == "B/L0" } }
        XCTAssertEqual(dm.students.first { $0.id == kid.id }?.mediaAssets.vault.map(\.localId), ["A/L0"])
        XCTAssertEqual(VaultPhoto.ordered([b, a]).first?.localId, "A/L0", "newest shot first")
    }

    func testAnOlderVaultlessRecordStillDecodes() throws {
        let old = #"{"photoReady":true,"videoHighlightPending":false,"photoUrls":[],"videoUrls":[]}"#
        let decoded = try JSONDecoder().decode(MediaAssetStatus.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.vault.isEmpty)
        XCTAssertTrue(decoded.photoReady)
    }

    // MARK: What a post says

    func testTheLastGameHeadlinesItsBestNumbersAndNoZeros() {
        let kid = Student(name: "Maya Chen")
        let day = Date().addingTimeInterval(-2 * 86_400)
        let s = session(day, [game(kid.id, pts: 4, reb: 1, ast: 0), game(kid.id, pts: 12, reb: 6, ast: 0)])
        let f = AthletePostFacts.make(student: kid, jersey: 7, colorHex: "#2A78D6", academy: "Academy",
                                      sessions: [s], source: .lastGame, chinese: false)
        XCTAssertEqual(f.firstName, "Maya"); XCTAssertEqual(f.lastName, "Chen")
        XCTAssertEqual(f.games, 1)
        XCTAssertEqual(f.stats.first { $0.key == "pts" }?.text, "12", "the better game of the class")
        XCTAssertEqual(f.headline.map(\.key), ["pts", "reb"], "zeros are never headlined")
        XCTAssertEqual(f.big?.key, "pts")
        XCTAssertTrue(f.eyebrow.hasPrefix("GAME · "))
    }

    func testMonthAveragesOnlyThisMonth() {
        let kid = Student(name: "Leo")
        let now = Date()
        let lastYear = now.addingTimeInterval(-400 * 86_400)
        let sessions = [session(lastYear, [game(kid.id, pts: 30, reb: 0, ast: 0)]),
                        session(now.addingTimeInterval(-60), [game(kid.id, pts: 6, reb: 2, ast: 1), game(kid.id, pts: 9, reb: 0, ast: 2)])]
        let month = AthletePostFacts.make(student: kid, jersey: nil, colorHex: "#000", academy: "",
                                          sessions: sessions, source: .month, chinese: false, now: now)
        XCTAssertEqual(month.games, 2)
        XCTAssertEqual(month.stats.first { $0.key == "pts" }?.text, "7.5")
        XCTAssertEqual(month.stats.last?.key, "gp")
        XCTAssertEqual(month.lastName, "Leo"); XCTAssertEqual(month.firstName, "")
        let all = AthletePostFacts.make(student: kid, jersey: nil, colorHex: "#000", academy: "",
                                        sessions: sessions, source: .allTime, chinese: false, now: now)
        XCTAssertEqual(all.stats.first { $0.key == "pts" }?.text, "15.0")
        let none = AthletePostFacts.make(student: Student(name: "New Kid"), jersey: nil, colorHex: "#000", academy: "",
                                         sessions: sessions, source: .lastGame, chinese: false)
        XCTAssertFalse(none.hasStats, "no games: nothing invented")
    }
}
