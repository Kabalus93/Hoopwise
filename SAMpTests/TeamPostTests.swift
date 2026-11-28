import XCTest
import SwiftUI
@testable import Hoopwise

/// Team posts (28 Nov 2026): the facts' wording and every template renders.
@MainActor
final class TeamPostTests: XCTestCase {
    private func facts(_ kind: TeamPostFacts.Kind) -> TeamPostFacts {
        var f = TeamPostFacts(kind: kind, teamName: "Riverside Hawks", shortName: "RH", colorHex: "#C8102E",
                              academy: "Riverside Basketball Academy", chinese: false)
        f.opponent = "Lakeside Eagles"; f.isHome = false; f.venue = "Lakeside Gym"
        f.date = Date(timeIntervalSince1970: 1_795_000_000)
        f.ours = 34; f.theirs = 28; f.isFinal = true
        f.wins = 6; f.losses = 2; f.games = 8; f.pointsFor = 31.4; f.pointsAgainst = 24.9
        f.recent = ["W", "W", "L", "W", "W"]
        f.firstDate = Date(timeIntervalSince1970: 1_790_000_000); f.lastDate = f.date
        return f
    }

    func testWordsAndInitials() {
        XCTAssertEqual(TeamPostFacts.initials("Lakeside Eagles"), "LE")
        XCTAssertEqual(TeamPostFacts.initials("Hawks"), "HAW")
        XCTAssertEqual(TeamPostFacts.initials("东城猛虎"), "东城")
        var f = facts(.season)
        XCTAssertEqual(f.record, "6–2")
        f.ties = 1
        XCTAssertEqual(f.record, "6–2–1")
        XCTAssertEqual(facts(.gameDay).versusWord, "AT")
        XCTAssertTrue(facts(.final).hasData)
        var none = facts(.season); none.games = 0
        XCTAssertFalse(none.hasData, "no finished games: nothing to post")
    }

    func testEveryTemplateRenders() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200)).image { ctx in
            UIColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            UIColor(red: 0.85, green: 0.65, blue: 0.5, alpha: 1).setFill()
            for i in 0..<5 { ctx.cgContext.fillEllipse(in: CGRect(x: 160 + i * 270, y: 300, width: 180, height: 220)) }
            UIColor.white.setFill()
            for i in 0..<5 { ctx.cgContext.fill(CGRect(x: 130 + i * 270, y: 540, width: 240, height: 600)) }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("teamposts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for aspect in AthletePostAspect.allCases {
            for t in TeamPostTemplate.allCases {
                let r = ImageRenderer(content: TeamPostCanvas(template: t, facts: facts(t.kind), photo: photo, more: [photo],
                                                              cutout: nil, aspect: aspect))
                r.scale = 1
                let image = try XCTUnwrap(r.uiImage, "\(t) renders")
                XCTAssertEqual(image.size, aspect.size)
                try image.jpegData(compressionQuality: 0.8)?.write(to: dir.appendingPathComponent("\(t.rawValue)-\(aspect.rawValue).jpg"))
            }
        }
        print("TEAMPOSTS \(dir.path)")
    }
}

@MainActor
final class TeamMediaTests: XCTestCase {
    func testTheTeamsMediaHasItsOwnWriterAndSurvivesAnOlderCopy() {
        let dm = SwiftDataManager.inMemoryForTesting()
        let team = Team(name: "Hawks", shortName: "HK", colorHex: "#C8102E")
        dm.addTeam(team)
        let stale = dm.teams.first { $0.id == team.id }!
        dm.setTeamVault(teamId: team.id) { $0.append(VaultPhoto(localId: "photo-1", addedAt: .now)) }
        XCTAssertEqual(dm.teams.first { $0.id == team.id }?.playbook.media.count, 1)
        // A page holding the team from before the photo saves its playbook.
        var edited = stale
        var book = edited.playbook
        book.focus = ["starter:horns"]
        edited.playbook = book
        dm.updateTeam(edited)
        let now = dm.teams.first { $0.id == team.id }!.playbook
        XCTAssertEqual(now.media.count, 1, "an older copy does not drop the team's photos")
        XCTAssertEqual(now.focus, ["starter:horns"])
    }

    func testAnOlderPlaybookWithoutMediaDecodes() throws {
        let json = #"{"sections":{},"identity":"","objectives":[],"breakdowns":{},"focus":[]}"#
        let book = try JSONDecoder().decode(TeamPlaybook.self, from: Data(json.utf8))
        XCTAssertTrue(book.media.isEmpty)
        let out = String(decoding: try JSONEncoder().encode(book), as: UTF8.self)
        XCTAssertFalse(out.contains("media"), "an empty media list is not written")
    }
}
