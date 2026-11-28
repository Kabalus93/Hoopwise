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

    // MARK: Faces (28 Nov 2026)

    func testAFaceRidesInTheVaultAndOlderEntriesDecode() throws {
        let old = #"{"id":"6F1C1E4A-0C3B-4C55-9D6E-2F3A4B5C6D7E","localId":"x","addedAt":0}"#
        let entry = try JSONDecoder().decode(VaultPhoto.self, from: Data(old.utf8))
        XCTAssertNil(entry.face)
        XCTAssertNil(entry.facesChecked)
        var e = entry
        e.face = VaultFace(rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25), pixels: 600, quality: 0.8)
        e.facesChecked = true
        let back = try JSONDecoder().decode(VaultPhoto.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back.face, e.face)
        XCTAssertEqual(back.face?.rect.minY ?? 0, 0.2, accuracy: 0.0001)
    }

    func testTheBestFaceIsTheCoachsPickThenTheSharpest() {
        func photo(_ px: Double, coach: Bool = false) -> VaultPhoto {
            var p = VaultPhoto(localId: UUID().uuidString, addedAt: .now)
            p.face = VaultFace(rect: CGRect(x: 0, y: 0, width: 0.2, height: 0.2), pixels: px, byCoach: coach ? true : nil)
            return p
        }
        let small = photo(60), big = photo(700), mid = photo(300), picked = photo(200, coach: true)
        XCTAssertEqual(FaceIndex.bestFace(in: [small, mid, big])?.id, big.id)
        XCTAssertEqual(FaceIndex.bestFace(in: [small, big, picked])?.id, picked.id)
        XCTAssertNil(FaceIndex.bestFace(in: [small]), "a face under 80 px is too small for a close-up")
    }

    func testPinyinOfAChineseNameRunsFamilyNameFirst() {
        var kid = Student(name: "Liú Chén Lín")
        kid.chineseName = "刘晨林"
        let parts = AthletePostFacts.nameParts(kid, chinese: false)
        XCTAssertEqual(parts.last, "Liú")
        XCTAssertEqual(parts.first, "Chén Lín")
        let western = AthletePostFacts.nameParts(Student(name: "Sofia Reyes"), chinese: false)
        XCTAssertEqual(western.last, "Reyes")
    }

    func testAFigureIsTrimmedToTheAthlete() throws {
        // 100 × 200 transparent, a solid block at x 30…69, y 50…199 (runs off the bottom).
        let w = 100, h = 200
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 50..<200 { for x in 30..<70 { let i = (y * w + x) * 4; px[i] = 255; px[i + 3] = 255 } }
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let t = try XCTUnwrap(PostLift.trimmedFigure(image))
        XCTAssertEqual(Double(t.image.width), 40, accuracy: 4)
        XCTAssertEqual(Double(t.image.height), 150, accuracy: 4)
        XCTAssertTrue(t.cutAtBottom)
    }
}
