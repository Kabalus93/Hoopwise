import Foundation
import PDFKit
import Testing
import UIKit
@testable import Hoopwise

/// Plays shared from a team (23 Nov 2026): a player's job worded from the
/// drawing, the cast's bubbles keeping photos to consented athletes, and the
/// A4 sheets.
struct PlaySheetTests {
    private typealias P = JournalCourtPoint

    /// 1 at the top dribbles to the right wing and passes to 2 in the
    /// corner; 4 screens for 2 at the right elbow first; 3 does nothing.
    private var diagram: JournalPlayDiagram {
        var d = JournalPlayDiagram(offense: [
            .init(number: 1, at: P(7.5, 8.5)),
            .init(number: 2, at: P(13.8, 6.0)),
            .init(number: 3, at: P(1.0, 1.0)),
            .init(number: 4, at: P(7.5, 5.8)),
        ], ball: 1)
        d.actions = [
            .init(kind: .screen, player: 4, path: [P(7.5, 5.8), P(10.2, 5.6)]),
            .init(kind: .cut, player: 2, path: [P(13.8, 6.0), P(10.6, 5.2), P(13.9, 1.0)]),
            .init(kind: .dribble, player: 1, path: [P(7.5, 8.5), P(12.4, 6.2)]),
            .init(kind: .pass, player: 1, path: [P(12.4, 6.2), P(13.9, 1.0)], receiver: 2),
        ]
        return d
    }

    private func names(_ n: Int) -> String { ["", "Maya", "Leo", "Sofia", "Amir"][n] }

    @Test func spotsOnTheFloorHaveACoachsName() {
        #expect(PlayRoleJob.spotName(P(7.5, 1.6), court: .half, chinese: false) == "the rim")
        #expect(PlayRoleJob.spotName(P(13.9, 1.0), court: .half, chinese: false) == "the right corner")
        #expect(PlayRoleJob.spotName(P(1.1, 1.0), court: .half, chinese: false) == "the left corner")
        #expect(PlayRoleJob.spotName(P(7.5, 9.0), court: .half, chinese: false) == "the top")
        #expect(PlayRoleJob.spotName(P(12.4, 6.2), court: .half, chinese: false) == "the right wing")
        #expect(PlayRoleJob.spotName(P(9.95, 5.8), court: .half, chinese: false) == "the right elbow")
        #expect(PlayRoleJob.spotName(P(7.5, 12.5), court: .half, chinese: false) == "half court")
        #expect(PlayRoleJob.spotName(P(13.9, 1.0), court: .half, chinese: true) == "右底角")
        // The full court is read at the attacked end: rim (26.425, 7.5).
        #expect(PlayRoleJob.spotName(P(26.4, 7.5), court: .full, chinese: false) == "the rim")
        #expect(PlayRoleJob.spotName(P(5, 7.5), court: .full, chinese: false) == "the backcourt")
    }

    @Test func aPlayersJobIsWhatTheDrawingGivesThem() {
        let d = diagram
        #expect(PlayRoleJob.sentence(for: 1, in: d, court: .half, name: names, chinese: false)
                == "Dribble to the right wing, then pass to Leo.")
        #expect(PlayRoleJob.sentence(for: 2, in: d, court: .half, name: names, chinese: false)
                == "Cut to the right corner, then catch from Maya.")
        #expect(PlayRoleJob.sentence(for: 4, in: d, court: .half, name: names, chinese: false)
                == "Screen for Leo at the right elbow.")
        #expect(PlayRoleJob.sentence(for: 3, in: d, court: .half, name: names, chinese: false)
                == "Stay at the left corner.")
        #expect(PlayRoleJob.sentence(for: 1, in: d, court: .half, name: names, chinese: true)
                == "运球到右侧翼，然后传球给Leo。")
        #expect(PlayRoleJob.lines(for: 9, in: d, court: .half, name: names, chinese: false).isEmpty,
                "nobody numbered 9 on the floor")
    }

    @Test func initialsReadNaturally() {
        #expect(PlayBubble.initials(of: "Maya Chen") == "MC")
        #expect(PlayBubble.initials(of: "Leo") == "L")
        #expect(PlayBubble.initials(of: "王小明") == "小明")
        #expect(PlayBubble.initials(of: "李华") == "李华")
    }

    @Test func photosOnPaperOnlyWithConsent() {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.pngData()
        let yes = TeamPlayCast.Person(id: UUID(), name: "Maya Chen", imageData: photo, isCoach: false, mayPublish: true)
        let no = TeamPlayCast.Person(id: UUID(), name: "Leo Martin", imageData: photo, isCoach: false, mayPublish: false)
        let spare = TeamPlayCast.Person(id: UUID(), name: "Noah Davis", imageData: nil, isCoach: false, mayPublish: true)
        var cast = TeamPlayCast(teamId: UUID(), playKey: "k", seats: [
            .init(number: 1, people: [yes], standard: "", drillNames: []),
            .init(number: 2, people: [no, spare], standard: "", drillNames: []),
            .init(number: 3, people: [], standard: "", drillNames: []),
        ], lineup: [:])
        let screen = cast.bubbles()
        #expect(screen[1]?.image != nil && screen[2]?.image != nil, "the coach's own screen shows every photo")
        #expect(screen[3] == nil, "an open role stays a number")
        let paper = cast.bubbles(photos: true, onlyConsented: true)
        #expect(paper[1]?.image != nil)
        #expect(paper[2]?.image == nil && paper[2]?.initials == "LM", "no consent: initials on paper")
        // The lineup picks who is on for a role with two.
        cast.lineup[2] = spare.id
        #expect(cast.person(for: 2)?.name == "Noah Davis")
        #expect(cast.bubbles()[2]?.initials == "ND")
    }

    @MainActor
    @Test func sheetsAreA4AndAWrinkleStartsAPage() throws {
        let step = PlaySheet.Step(diagram: diagram, caption: "Entry", text: "1 pushes to the wing.")
        var sheet = PlaySheet(
            playName: "Wing Entry", category: .halfCourt, court: .half, situation: "Against man", idea: "Get 2 a corner three.",
            parts: [.init(kind: .concept, name: "Wing Entry", notes: "", steps: [step, step]),
                    .init(kind: .wrinkle, name: "Back door", notes: "If 2 is denied.", steps: [step])],
            teamName: "Hawks", teamColor: .systemBlue, academy: "Academy",
            roles: [1, 2, 3, 4].map { PlaySheet.Role(number: $0, name: names($0)) },
            bubbles: [:], showsDefense: true, chinese: false)
        let team = try #require(PDFDocument(data: PlaySheetDocument.pdf([sheet])))
        #expect(team.pageCount == 2, "the concept on page 1, the wrinkle on its own")
        let bounds = try #require(team.page(at: 0)).bounds(for: .mediaBox)
        #expect(abs(bounds.width - 595.28) < 0.5 && abs(bounds.height - 841.89) < 0.5)
        let text = team.page(at: 0)?.string ?? ""
        #expect(text.contains("Wing Entry") && text.contains("Step 1") && text.contains("Leo"),
                "text is real text — the sheet is vector, not a picture")
        #expect(team.page(at: 1)?.string?.contains("Back door") == true)

        sheet.focus = 2
        sheet.focusName = "Leo"
        sheet.focusStandard = "Sprint to the corner"
        let player = try #require(PDFDocument(data: PlaySheetDocument.pdf([sheet])))
        let page = player.page(at: 0)?.string ?? ""
        #expect(page.contains("Your job") && page.contains("Cut to the right corner"))
        #expect(page.contains("Sprint to the corner"))

        let everyone = try #require(PDFDocument(data: PlaySheetDocument.pdf([sheet, sheet, sheet])))
        #expect(everyone.pageCount == 6, "a page set per player")
        #expect(PlaySheetDocument.longImage(pdf: PlaySheetDocument.pdf([sheet])) != nil)
    }
}
