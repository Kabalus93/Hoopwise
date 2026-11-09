import Foundation

/// A drill's court drawing, made in the Plays editor (Luther, November 2026:
/// "the same editor that's in plays" in place of the Add Visual menu). It is
/// the editable file of a `.courtDiagram` DrillMedia — its `strokesPath`
/// holds this as JSON beside the rendered JPEG (`localPath`, `thumbnailPath`)
/// that the carousel, the viewer, bundles and older builds show. Telling it
/// from a legacy PencilKit `.pkdrawing` goes by CONTENT (`decode`), because
/// a bundle import writes every strokes file under the `.pkdrawing` name.
///
/// IT SYNCS (Luther, November 2026: a drawing made on the Mac must show on
/// the phone). Drill media files live on one device's disk and never reach
/// CloudKit, so the drawing also rides IN the synced SDDrillMedia row, as
/// `syncPayload` in its `remoteURL` column (unused by a court diagram; no
/// schema change). Readers prefer the payload; a device that receives one
/// writes the files back (`DrillDrawingMedia.restoreFiles`).
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

    /// The `remoteURL` value that carries this drawing through CloudKit:
    /// "hoopwise-drawing:" + the JSON in base64. Nil past `syncLimit` — a
    /// CloudKit record holds 1 MB in all, and a drawing is a few KB a step.
    var syncPayload: String? {
        guard let data = encoded else { return nil }
        let payload = Self.syncPrefix + data.base64EncodedString()
        return payload.utf8.count <= Self.syncLimit ? payload : nil
    }

    static let syncPrefix = "hoopwise-drawing:"
    static let syncLimit = 400_000

    /// The drawing a `remoteURL` carries, or nil for a link or nothing.
    static func decode(syncPayload: String?) -> DrillDrawing? {
        guard let syncPayload, syncPayload.hasPrefix(syncPrefix),
              let data = Data(base64Encoded: String(syncPayload.dropFirst(syncPrefix.count))) else { return nil }
        return decode(data)
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
