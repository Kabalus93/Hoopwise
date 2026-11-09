import Foundation

/// A drill's court drawing, made in the Plays editor (Luther, November 2026:
/// "the same editor that's in plays" in place of the Add Visual menu). It is
/// the editable file of a `.courtDiagram` DrillMedia — its `strokesPath`
/// holds this as JSON beside the rendered JPEG (`localPath`, `thumbnailPath`)
/// that the carousel, the viewer, bundles and older builds show. Telling it
/// from a legacy PencilKit `.pkdrawing` goes by CONTENT (`decode`), because
/// a bundle import writes every strokes file under the `.pkdrawing` name.
///
/// Like every drill visual it lives on this device's disk; it does not sync
/// through CloudKit (only the SDDrillMedia row does).
nonisolated struct DrillDrawing: Codable, Equatable, Sendable {
    struct Step: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        var diagram: JournalPlayDiagram
        var caption = ""
        var text = ""
    }

    var version = 1
    var court: JournalCourtKind
    var steps: [Step]

    /// A new drawing: one step, the five in the default alignment.
    static func new(court: JournalCourtKind = .half) -> DrillDrawing {
        DrillDrawing(court: court, steps: [Step(diagram: JournalPlayMath.defaultAlignment(court))])
    }

    var encoded: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    /// The drawing in `data`, or nil when it is something else (a PencilKit
    /// drawing, a missing file).
    static func decode(_ data: Data?) -> DrillDrawing? {
        guard let data, data.first == UInt8(ascii: "{"),
              let drawing = try? JSONDecoder().decode(DrillDrawing.self, from: data),
              !drawing.steps.isEmpty else { return nil }
        return drawing
    }
}
