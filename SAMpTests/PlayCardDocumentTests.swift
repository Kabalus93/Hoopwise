import XCTest
import CoreGraphics
import PDFKit
@testable import Hoopwise

/// PLAY EDITOR v2, PHASE D — the printed play card.
///
/// The card replaces video export as the editor's shareable artifact, so what
/// these defend is that it is a REAL DOCUMENT: vector, not a bitmap wearing a
/// PDF extension; paginated by content rather than by hope; and carrying the
/// reads as their own sections instead of reprinting the shared entry once per
/// counter.
///
/// The vector check is not paranoia. The project's export rule exists because
/// `ImageRenderer` silently rasterises any view containing a material, a blur
/// or an image and hands back a valid PDF that is secretly a screenshot — you
/// find out at the printer.
final class PlayCardDocumentTests: XCTestCase {

    private let o1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let o2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
    private let o5 = UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!

    // MARK: - Fixtures

    /// A four-frame play with one read, in the shape the acceptance play has.
    private func diagram(withRead: Bool, extraFrames: Int = 0) -> PlayDiagram {
        var diagram = PlayDiagram(playId: UUID(),
                                  space: CourtSpace(standard: .fiba, mode: .half))
        diagram.entities = [
            DiagramEntity(id: o1, kind: .player(team: .offense, number: 1, role: nil),
                          label: "1", homePosition: CGPoint(x: 25, y: 28)),
            DiagramEntity(id: o2, kind: .player(team: .offense, number: 2, role: nil),
                          label: "2", homePosition: CGPoint(x: 43, y: 22)),
            DiagramEntity(id: o5, kind: .player(team: .defense, number: 5, role: nil),
                          label: "5", homePosition: CGPoint(x: 8, y: 10)),
            DiagramEntity(kind: .ball, homePosition: CGPoint(x: 27, y: 28))
        ]

        var root = ReadNode(id: diagram.rootNodeId, title: "Base")
        var sequence = FrameSequence(startFormation: diagram.homeFormation,
                                     pace: .default, rim: diagram.rimPoint)
        sequence.appendFrame(caption: "O1 enters right")
        sequence.addAction(PlayAction(kind: .dribble, actorId: o1,
                                      path: [CGPoint(x: 34, y: 27)]), toFrame: 0)
        sequence.appendFrame(caption: "O5 screens for O2")
        sequence.addAction(PlayAction(kind: .screen, actorId: o5,
                                      path: [CGPoint(x: 19, y: 19)],
                                      screenForId: o2), toFrame: 1)
        sequence.appendFrame(caption: "Swing to the curl")
        sequence.addAction(PlayAction(kind: .pass, actorId: o1,
                                      target: .player(o2)), toFrame: 2)
        sequence.appendFrame(caption: "Catch and shoot")
        sequence.addAction(PlayAction(kind: .shot, actorId: o2,
                                      target: .point(diagram.rimPoint)), toFrame: 3)
        for index in 0..<extraFrames {
            sequence.appendFrame(caption: "extra \(index + 1)")
        }
        root.frames = sequence.frames

        var nodes = [root]
        if withRead {
            var child = ReadNode(title: "Switch")
            child.frames = [PlayFrame(actions: [PlayAction(kind: .cut, actorId: o2,
                                                           path: [CGPoint(x: 25, y: 8)])],
                                      caption: "back door")]
            root.edges = [ReadEdge(targetId: child.id, kind: .branch,
                                   condition: "they switch the screen",
                                   afterFrameIndex: 1)]
            nodes = [root, child]
        }
        diagram.nodes = nodes
        diagram.pace = .default
        return diagram
    }

    private func render(_ diagram: PlayDiagram, name: String = "Triangle Offense") throws -> URL {
        let input = PlayCardDocument.makeInput(diagram: diagram, title: name,
                                               family: "Horns", coachName: "Luther")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
        return try PlayCardDocument.render(input, to: url)
    }

    // MARK: - The layer survives its own teardown

    /// A REGRESSION PIN, and it looks absurd until you know what it caught.
    /// `PDFDocumentRenderer` was implicitly main-actor isolated by the
    /// project's default isolation, which made its DEINIT isolated, and
    /// releasing one aborted in malloc — constructing a renderer and dropping
    /// it was enough to kill the test process. It is why the document layer had
    /// no tests at all until now.
    func testARendererCanBeCreatedAndReleased() {
        for _ in 0..<3 {
            let renderer = PDFDocumentRenderer()
            XCTAssertEqual(renderer.currentPage, 0)
        }
    }

    // MARK: - It is a document

    func testItWritesAReadablePDF() throws {
        let url = try render(diagram(withRead: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
    }

    /// VECTOR, NOT A BITMAP. A card that is secretly a screenshot prints soft
    /// and cannot be scaled — and it looks fine on screen right up until it
    /// comes out of the gym's printer.
    func testTheCardIsVectorWithNoRasterImages() throws {
        let url = try render(diagram(withRead: true))
        let data = try Data(contentsOf: url)
        let bytes = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(bytes.contains("/Subtype /Image"),
                       "the card must contain no raster images at all")
        XCTAssertFalse(bytes.contains("/Subtype/Image"))
    }

    /// The text is real text — searchable, selectable, and sharp at any size.
    func testTheCaptionsAreSelectableText() throws {
        let url = try render(diagram(withRead: false))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("Triangle Offense"), "the play names itself")
        XCTAssertTrue(text.contains("O1 enters right"), "captions print under their frame")
        XCTAssertTrue(text.contains("Catch and shoot"))
        // THE HEADER BAND. A 9pt line in a 13pt box renders as NOTHING —
        // CTFrame drops a line that does not fully fit — so the wordmark and
        // the whole meta line disappeared without any error at all.
        XCTAssertTrue(text.contains("Play Card"), "the document names its kind")
        XCTAssertTrue(text.contains("frames"), "the meta line survives its box")
    }

    // MARK: - Structure

    /// A read is its OWN section, headed by its condition and carrying only its
    /// own frames. Printing whole runs would reprint the shared entry once per
    /// counter — three pages of the same two frames to show two options.
    func testAReadPrintsAsItsOwnSectionNotAWholeRun() throws {
        let input = PlayCardDocument.makeInput(diagram: diagram(withRead: true),
                                               title: "Triangle Offense")
        XCTAssertEqual(input.sections.count, 2)
        XCTAssertNil(input.sections[0].condition, "the play needs no condition to happen")
        XCTAssertEqual(input.sections[0].sequence.frames.count, 4)
        XCTAssertEqual(input.sections[1].condition, "they switch the screen")
        XCTAssertEqual(input.sections[1].sequence.frames.count, 1,
                       "only the read's own frames — the entry is not reprinted")

        // NUMBERING CONTINUES across sections, so a coach saying "frame five"
        // has one thing to point at.
        XCTAssertEqual(input.sections[0].firstFrameNumber, 1)
        XCTAssertEqual(input.sections[1].firstFrameNumber, 5)
    }

    /// The read opens where its parent left off — the same continuity the
    /// canvas and playback have, now on paper.
    func testAReadsFramesOpenOnTheInheritedFormation() throws {
        let input = PlayCardDocument.makeInput(diagram: diagram(withRead: true),
                                               title: "Triangle Offense")
        let read = input.sections[1]
        let opening = read.sequence.formation(enteringFrame: 0)
        // O1 dribbled to (34,27) in the base play's frame 1; the read inherits
        // him there rather than at his home position.
        XCTAssertEqual(opening[o1]?.x ?? 0, 34, accuracy: 0.01)
        XCTAssertEqual(opening[o1]?.y ?? 0, 27, accuracy: 0.01)
    }

    /// Pagination is driven by CONTENT. Four frames fit a page; twelve do not.
    func testItPaginatesByContent() throws {
        let short = try PDFDocument(url: try render(diagram(withRead: false)))
        let long = try PDFDocument(url: try render(diagram(withRead: false, extraFrames: 8),
                                                   name: "Long Play"))
        let shortPages = try XCTUnwrap(short?.pageCount)
        let longPages = try XCTUnwrap(long?.pageCount)
        XCTAssertGreaterThan(longPages, shortPages,
                             "a longer play takes more pages — nothing is silently dropped")
    }

    /// The card is WRITTEN OUT so it can be looked at, not just asserted about.
    /// A document's real acceptance is somebody reading it.
    func testItWritesAnInspectableCopy() throws {
        let url = try render(diagram(withRead: true), name: "Triangle Offense")
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("play-card-evidence.pdf")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        print("PLAYCARD_EVIDENCE \(destination.path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    /// A4, because the coach operates in China where US Letter is not the paper.
    func testItIsA4() throws {
        let url = try render(diagram(withRead: false))
        let document = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 595.276, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 841.890, accuracy: 0.5)
    }

    // MARK: - The thumbnail agrees with the card

    /// The thumbnail is DRAWN, not blank. It shares `FrameCardRenderer` with the
    /// printed card, so what this really pins is that the bitmap path — its own
    /// context, its own line scale — produces the same picture rather than a
    /// white square nobody notices until the playbook is full of them.
    func testTheThumbnailIsActuallyDrawn() throws {
        let image = try XCTUnwrap(FrameThumbnailRenderer.render(diagram: diagram(withRead: false)))
        XCTAssertEqual(image.width, Int(FrameThumbnailRenderer.size.width))

        // Count non-white pixels. A court, five pucks and a dribble line cover a
        // real fraction of the card; a blank one covers none.
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        var inked = 0
        let bytesPerPixel = 4
        var index = 0
        while index + 2 < data.count {
            if data[index] < 240 || data[index + 1] < 240 || data[index + 2] < 240 { inked += 1 }
            index += bytesPerPixel * 7   // sample, rather than walk 211k pixels
        }
        XCTAssertGreaterThan(inked, 200, "the thumbnail draws a court and a play, not a white square")
    }

    /// FRAME 1, not the midpoint: a play is recognised by its SET-UP. The
    /// keyframe editor rendered the play's middle instant, which is the moment
    /// every play looks alike.
    func testTheThumbnailFrameIsTheSetUp() {
        let play = diagram(withRead: false)
        guard let root = play.rootNode else { return XCTFail("no root") }
        var sequence = play.frameSequence(for: root.id, startingFrom: play.homeFormation)
        sequence.reresolve()
        let opening = sequence.formation(enteringFrame: 0)
        XCTAssertEqual(opening[o1]?.x ?? 0, 25, accuracy: 0.01,
                       "frame 1 opens on the home formation, before anyone has moved")
    }
}
