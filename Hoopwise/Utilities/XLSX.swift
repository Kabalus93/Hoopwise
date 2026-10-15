import Foundation
import Compression

// MARK: - XLSX codec
//
// A dependency-free reader/writer for Office Open XML spreadsheets, Foundation
// and Compression only, so it compiles unchanged on iOS and macOS.
//
// NONISOLATED, DELIBERATELY — same reasoning as PDFDocumentRenderer. The
// project compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; parsing a
// spreadsheet is not UI work and must be callable from a background task and
// from tests without hopping to the main actor.
//
// READER scope: what real Excel / WPS / Numbers output contains — ZIP with
// stored or deflated entries (sizes taken from the central directory, so
// data-descriptor entries work), the workbook → rels → worksheet mapping,
// shared strings including rich-text runs (phonetic <rPh> runs excluded),
// cell types s / inlineStr / str / b / e / d / numbers, missing `r` attributes.
// Dates come back as their serial NUMBER — number formats are not interpreted.
// ZIP64 archives are rejected as corrupt.
//
// WRITER scope: stored (uncompressed) ZIP, inline strings, numbers, optional
// column widths, one minimal stylesheet. No formulas, no styles per cell.

nonisolated enum XLSXCell: Equatable {
    case text(String)
    case number(Double)
    case empty
}

nonisolated struct XLSXSheet: Equatable {
    var name: String
    var rows: [[XLSXCell]]
    var columnWidths: [Double] = []
}

nonisolated enum XLSXError: Error, LocalizedError {
    case notAZip
    case missingPart(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "The file is not a valid .xlsx (ZIP) archive."
        case .missingPart(let part): return "The spreadsheet is missing a required part: \(part)."
        case .corrupt(let detail): return "The spreadsheet is damaged: \(detail)."
        }
    }
}

nonisolated extension XLSXCell {
    /// `.text` → the string; `.number` → integer text when whole ("36", not
    /// "36.0"); `.empty` → "".
    var stringValue: String {
        switch self {
        case .text(let s): return s
        case .empty: return ""
        case .number(let n): return XLSX.formatNumber(n)
        }
    }
}

nonisolated enum XLSX {

    // MARK: Public API

    /// All sheets, in workbook order. Rows are dense: row index i == spreadsheet
    /// row i+1, cells padded with .empty so column index j == column letter j
    /// (A=0). Trailing empty rows trimmed (and trailing empty cells per row).
    static func read(_ data: Data) throws -> [XLSXSheet] {
        let zip = try XLSXZipReader(data: data)

        // Locate the workbook through the package rels; fall back to the
        // conventional path.
        var workbookPath = "xl/workbook.xml"
        if let rootRels = zip.entry(named: "_rels/.rels") {
            let rels = try RelationshipsParser.parse(try zip.contents(of: rootRels))
            if let office = rels.first(where: { $0.type.hasSuffix("/officeDocument") }) {
                workbookPath = resolve(target: office.target, relativeTo: "")
            }
        }
        guard let workbookEntry = zip.entry(named: workbookPath) else {
            throw XLSXError.missingPart(workbookPath)
        }
        let workbookDir = directory(of: workbookPath)
        let sheetRefs = try WorkbookParser.parse(try zip.contents(of: workbookEntry))

        let relsPath = workbookDir + "_rels/" + fileName(of: workbookPath) + ".rels"
        var relsById: [String: Relationship] = [:]
        var sharedStringsPath = workbookDir + "sharedStrings.xml"
        if let relsEntry = zip.entry(named: relsPath) {
            let rels = try RelationshipsParser.parse(try zip.contents(of: relsEntry))
            for rel in rels { relsById[rel.id] = rel }
            if let ss = rels.first(where: { $0.type.hasSuffix("/sharedStrings") }) {
                sharedStringsPath = resolve(target: ss.target, relativeTo: workbookDir)
            }
        }

        var sharedStrings: [String] = []
        if let ssEntry = zip.entry(named: sharedStringsPath) {
            sharedStrings = try SharedStringsParser.parse(try zip.contents(of: ssEntry))
        }

        var sheets: [XLSXSheet] = []
        for (index, ref) in sheetRefs.enumerated() {
            let path: String
            if let rid = ref.relationshipId, let rel = relsById[rid] {
                path = resolve(target: rel.target, relativeTo: workbookDir)
            } else {
                path = workbookDir + "worksheets/sheet\(index + 1).xml"
            }
            // Chartsheets / dialog sheets have no cell grid; skip non-worksheets.
            if let rid = ref.relationshipId, let rel = relsById[rid],
               !rel.type.hasSuffix("/worksheet") {
                continue
            }
            guard let entry = zip.entry(named: path) else {
                throw XLSXError.missingPart(path)
            }
            let rows = try WorksheetParser.parse(try zip.contents(of: entry),
                                                 sharedStrings: sharedStrings)
            sheets.append(XLSXSheet(name: ref.name, rows: rows.rows,
                                    columnWidths: rows.columnWidths))
        }
        return sheets
    }

    /// A valid .xlsx that Excel, WPS Office and Apple Numbers open.
    static func write(_ sheets: [XLSXSheet]) throws -> Data {
        guard !sheets.isEmpty else {
            throw XLSXError.corrupt("a workbook needs at least one sheet")
        }
        let names = sanitizedSheetNames(sheets.map(\.name))

        var parts: [(String, Data)] = []
        parts.append(("[Content_Types].xml", Data(contentTypesXML(sheetCount: sheets.count).utf8)))
        parts.append(("_rels/.rels", Data(rootRelsXML.utf8)))
        parts.append(("xl/workbook.xml", Data(workbookXML(names: names).utf8)))
        parts.append(("xl/_rels/workbook.xml.rels", Data(workbookRelsXML(sheetCount: sheets.count).utf8)))
        parts.append(("xl/styles.xml", Data(stylesXML.utf8)))
        for (i, sheet) in sheets.enumerated() {
            let xml = try worksheetXML(sheet)
            parts.append(("xl/worksheets/sheet\(i + 1).xml", Data(xml.utf8)))
        }
        return XLSXZipWriter.storedArchive(parts)
    }

    // MARK: Helpers shared with tests

    /// Integer text when whole and exactly representable; otherwise Swift's
    /// shortest round-tripping representation.
    static func formatNumber(_ n: Double) -> String {
        if n.isFinite, n == n.rounded(), abs(n) < 1e15 {
            return String(Int64(n))
        }
        return "\(n)"
    }

    /// 0 → "A", 25 → "Z", 26 → "AA".
    static func columnLetters(_ index: Int) -> String {
        var n = index + 1
        var scalars: [Character] = []
        while n > 0 {
            let rem = (n - 1) % 26
            scalars.append(Character(UnicodeScalar(UInt8(65 + rem))))
            n = (n - 1) / 26
        }
        return String(scalars.reversed())
    }

    /// "A" → 0, "AA" → 26. Nil when there are no letters.
    static func columnIndex(_ letters: Substring) -> Int? {
        var value = 0
        var any = false
        for ch in letters.uppercased().unicodeScalars {
            guard ch.value >= 65, ch.value <= 90 else { return nil }
            value = value * 26 + Int(ch.value - 64)
            any = true
        }
        return any ? value - 1 : nil
    }

    /// Splits "AB12" into (column 27, row 12). Row is 1-based.
    static func parseCellReference(_ ref: String) -> (column: Int, row: Int?)? {
        let letters = ref.prefix(while: { $0.isLetter })
        guard let col = columnIndex(letters) else { return nil }
        let digits = ref.dropFirst(letters.count).filter { $0 != "$" }
        return (col, Int(digits))
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for byte in buf {
                crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    /// Excel's sheet-name rules: ≤ 31 UTF-16 units, none of []:*?/\, not
    /// starting/ending with an apostrophe, not blank, not "History", unique
    /// case-insensitively.
    static func sanitizedSheetNames(_ raw: [String]) -> [String] {
        let forbidden: Set<Character> = ["[", "]", ":", "*", "?", "/", "\\"]
        var used: Set<String> = []
        var result: [String] = []
        for (i, original) in raw.enumerated() {
            var name = String(original.map { forbidden.contains($0) ? "_" : $0 })
            name = String(name.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
                .map(Character.init))
            name = name.trimmingCharacters(in: .whitespaces)
            while name.hasPrefix("'") { name.removeFirst() }
            while name.hasSuffix("'") { name.removeLast() }
            if name.isEmpty { name = "Sheet\(i + 1)" }
            if name.lowercased() == "history" { name += "_" }
            name = truncatedUTF16(name, max: 31)

            var candidate = name
            var n = 2
            while used.contains(candidate.lowercased()) {
                let suffix = " (\(n))"
                candidate = truncatedUTF16(name, max: 31 - suffix.utf16.count) + suffix
                n += 1
            }
            used.insert(candidate.lowercased())
            result.append(candidate)
        }
        return result
    }

    private static func truncatedUTF16(_ s: String, max: Int) -> String {
        var out = ""
        var count = 0
        for ch in s {
            let w = String(ch).utf16.count
            if count + w > max { break }
            out.append(ch)
            count += w
        }
        return out
    }

    // MARK: Path resolution

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    private static func fileName(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Resolves a relationship target against the source part's directory.
    /// Absolute targets ("/xl/worksheets/sheet1.xml") are package-rooted.
    static func resolve(target: String, relativeTo baseDir: String) -> String {
        let t = target.replacingOccurrences(of: "\\", with: "/")
        let joined = t.hasPrefix("/") ? String(t.dropFirst()) : baseDir + t
        var stack: [Substring] = []
        for comp in joined.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !stack.isEmpty { stack.removeLast() }; continue }
            stack.append(comp)
        }
        return stack.joined(separator: "/")
    }

    // MARK: Writer parts

    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static func contentTypesXML(sheetCount: Int) -> String {
        var s = xmlHeader
        s += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        s += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        s += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        s += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for i in 1...sheetCount {
            s += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        s += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        s += "</Types>"
        return s
    }

    private static let rootRelsXML: String = xmlHeader
        + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>"
        + "</Relationships>"

    private static func workbookXML(names: [String]) -> String {
        var s = xmlHeader
        s += "<workbook xmlns=\"\(mainNS)\" xmlns:r=\"\(relNS)\">"
        s += "<bookViews><workbookView/></bookViews><sheets>"
        for (i, name) in names.enumerated() {
            s += "<sheet name=\"\(escape(name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        s += "</sheets></workbook>"
        return s
    }

    private static func workbookRelsXML(sheetCount: Int) -> String {
        var s = xmlHeader
        s += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1...sheetCount {
            s += "<Relationship Id=\"rId\(i)\" Type=\"\(relNS)/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        s += "<Relationship Id=\"rId\(sheetCount + 1)\" Type=\"\(relNS)/styles\" Target=\"styles.xml\"/>"
        s += "</Relationships>"
        return s
    }

    private static let stylesXML: String = xmlHeader
        + "<styleSheet xmlns=\"\(mainNS)\">"
        + "<fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/><family val=\"2\"/></font></fonts>"
        + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
        + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
        + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        + "<cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs>"
        + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        + "</styleSheet>"

    private static func worksheetXML(_ sheet: XLSXSheet) throws -> String {
        var s = xmlHeader
        s += "<worksheet xmlns=\"\(mainNS)\" xmlns:r=\"\(relNS)\">"
        let widths = sheet.columnWidths.enumerated().filter { $0.element.isFinite && $0.element > 0 }
        if !widths.isEmpty {
            s += "<cols>"
            for (i, w) in widths {
                s += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(formatNumber(min(w, 255)))\" customWidth=\"1\"/>"
            }
            s += "</cols>"
        }
        s += "<sheetData>"
        for (r, row) in sheet.rows.enumerated() {
            let cells = row.enumerated().filter { $0.element != .empty }
            if cells.isEmpty { continue }
            s += "<row r=\"\(r + 1)\">"
            for (c, cell) in cells {
                let ref = columnLetters(c) + String(r + 1)
                switch cell {
                case .text(let text):
                    guard text.utf16.count <= 32767 else {
                        throw XLSXError.corrupt("cell \(ref) exceeds Excel's 32,767-character limit")
                    }
                    s += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(text))</t></is></c>"
                case .number(let n):
                    guard n.isFinite else {
                        throw XLSXError.corrupt("cell \(ref) holds a non-finite number")
                    }
                    s += "<c r=\"\(ref)\"><v>\(formatNumber(n))</v></c>"
                case .empty:
                    break
                }
            }
            s += "</row>"
        }
        s += "</sheetData></worksheet>"
        return s
    }

    /// XML 1.0 escaping. Characters XML 1.0 cannot carry at all (C0 controls
    /// other than tab/LF/CR, U+FFFE/U+FFFF) are dropped — a single one makes
    /// Excel refuse the whole file.
    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                let v = scalar.value
                if v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D { continue }
                if v == 0xFFFE || v == 0xFFFF { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

// MARK: - ZIP reading

nonisolated struct XLSXZipReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
        let crc: UInt32
    }

    private let bytes: [UInt8]
    private(set) var entries: [Entry] = []
    private var byName: [String: Int] = [:]
    private var byLowerName: [String: Int] = [:]

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw XLSXError.notAZip }

        // End of central directory: scan backwards (comment ≤ 65535 bytes).
        var eocd = -1
        let lowest = max(0, bytes.count - 22 - 65535)
        var i = bytes.count - 22
        while i >= lowest {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw XLSXError.notAZip }

        let count = Int(u16(eocd + 10))
        let cdSize = Int(u32(eocd + 12))
        let cdOffset = Int(u32(eocd + 16))
        if count == 0xFFFF || cdOffset == 0xFFFF_FFFF {
            throw XLSXError.corrupt("ZIP64 archives are not supported")
        }
        guard cdOffset + cdSize <= bytes.count else {
            throw XLSXError.corrupt("central directory out of range")
        }

        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else {
                throw XLSXError.corrupt("bad central directory record")
            }
            let method = u16(p + 10)
            let crc = u32(p + 16)
            let comp = Int(u32(p + 20))
            let uncomp = Int(u32(p + 24))
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let localOffset = Int(u32(p + 42))
            guard p + 46 + nameLen <= bytes.count else {
                throw XLSXError.corrupt("bad entry name")
            }
            let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLen)])
            let rawName = String(decoding: nameBytes, as: UTF8.self)
            let name = rawName.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let entry = Entry(name: name, method: method, compressedSize: comp,
                              uncompressedSize: uncomp, localHeaderOffset: localOffset, crc: crc)
            byName[name] = entries.count
            byLowerName[name.lowercased()] = entries.count
            entries.append(entry)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func entry(named name: String) -> Entry? {
        if let i = byName[name] { return entries[i] }
        if let i = byLowerName[name.lowercased()] { return entries[i] }
        return nil
    }

    func contents(of entry: Entry) throws -> Data {
        let h = entry.localHeaderOffset
        guard h + 30 <= bytes.count, u32(h) == 0x0403_4B50 else {
            throw XLSXError.corrupt("bad local header for \(entry.name)")
        }
        // Local name/extra lengths can differ from the central record's.
        let start = h + 30 + Int(u16(h + 26)) + Int(u16(h + 28))
        let end = start + entry.compressedSize
        guard end <= bytes.count else {
            throw XLSXError.corrupt("\(entry.name) runs past the end of the file")
        }
        let raw = bytes[start..<end]

        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return try inflate(Array(raw), expected: entry.uncompressedSize, name: entry.name)
        default:
            throw XLSXError.corrupt("\(entry.name) uses unsupported compression method \(entry.method)")
        }
    }

    /// Raw deflate (Apple's COMPRESSION_ZLIB is headerless RFC 1951).
    private func inflate(_ src: [UInt8], expected: Int, name: String) throws -> Data {
        if expected == 0 { return Data() }
        // +1 so a short decode is distinguishable from a decode that filled
        // the buffer exactly.
        let capacity = expected + 1
        var dst = [UInt8](repeating: 0, count: capacity)
        let written = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, capacity,
                                          s.baseAddress!, s.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expected else {
            throw XLSXError.corrupt("\(name) did not inflate to its recorded size")
        }
        return Data(dst[0..<written])
    }

    private func u16(_ o: Int) -> UInt16 {
        UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8)
    }

    private func u32(_ o: Int) -> UInt32 {
        UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8)
            | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
    }
}

// MARK: - ZIP writing (stored entries)

nonisolated enum XLSXZipWriter {
    /// A ZIP of uncompressed entries. DOS date fixed at 1980-01-01 so equal
    /// inputs give byte-identical archives.
    static func storedArchive(_ parts: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0x0021  // 1980-01-01
        let flags: UInt16 = 0x0800    // names are UTF-8

        for (name, content) in parts {
            let nameData = Data(name.utf8)
            let crc = XLSX.crc32(content)
            let offset = UInt32(out.count)
            let size = UInt32(content.count)

            out.appendLE(UInt32(0x0403_4B50))
            out.appendLE(UInt16(20))
            out.appendLE(flags)
            out.appendLE(UInt16(0))
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(crc)
            out.appendLE(size)
            out.appendLE(size)
            out.appendLE(UInt16(nameData.count))
            out.appendLE(UInt16(0))
            out.append(nameData)
            out.append(content)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(flags)
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(size)
            central.appendLE(size)
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))   // extra
            central.appendLE(UInt16(0))   // comment
            central.appendLE(UInt16(0))   // disk
            central.appendLE(UInt16(0))   // internal attrs
            central.appendLE(UInt32(0))   // external attrs
            central.appendLE(offset)
            central.append(nameData)
        }

        let cdOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(UInt32(0x0605_4B50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(parts.count))
        out.appendLE(UInt16(parts.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(cdOffset)
        out.appendLE(UInt16(0))
        return out
    }
}

nonisolated fileprivate extension Data {
    mutating func appendLE(_ v: UInt16) {
        append(UInt8(v & 0xFF)); append(UInt8(v >> 8))
    }
    mutating func appendLE(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8(v >> 24))
    }
}

// MARK: - XML parsing

nonisolated private func localName(_ qualified: String) -> String {
    guard let colon = qualified.lastIndex(of: ":") else { return qualified }
    return String(qualified[qualified.index(after: colon)...])
}

nonisolated private func runParser(_ data: Data, delegate: XMLParserDelegate, part: String) throws {
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    if !parser.parse() {
        let reason = parser.parserError?.localizedDescription ?? "unknown error"
        throw XLSXError.corrupt("\(part) is not well-formed XML (\(reason))")
    }
}

nonisolated private struct Relationship {
    let id: String
    let type: String
    let target: String
}

nonisolated private final class RelationshipsParser: NSObject, XMLParserDelegate {
    var rels: [Relationship] = []

    static func parse(_ data: Data) throws -> [Relationship] {
        let p = RelationshipsParser()
        try runParser(data, delegate: p, part: "relationships")
        return p.rels
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard localName(elementName) == "Relationship" else { return }
        guard let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        if attributeDict["TargetMode"] == "External" { return }
        rels.append(Relationship(id: id, type: attributeDict["Type"] ?? "", target: target))
    }
}

nonisolated private struct SheetRef {
    let name: String
    let relationshipId: String?
}

nonisolated private final class WorkbookParser: NSObject, XMLParserDelegate {
    var sheets: [SheetRef] = []

    static func parse(_ data: Data) throws -> [SheetRef] {
        let p = WorkbookParser()
        try runParser(data, delegate: p, part: "workbook.xml")
        return p.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard localName(elementName) == "sheet" else { return }
        // r:id — the prefix varies between writers, so match any "<prefix>:id".
        let rid = attributeDict.first(where: { $0.key.hasSuffix(":id") })?.value
        sheets.append(SheetRef(name: attributeDict["name"] ?? "Sheet\(sheets.count + 1)",
                               relationshipId: rid))
    }
}

nonisolated private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inSI = false
    private var inT = false
    private var phoneticDepth = 0

    static func parse(_ data: Data) throws -> [String] {
        let p = SharedStringsParser()
        try runParser(data, delegate: p, part: "sharedStrings.xml")
        return p.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "si": inSI = true; current = ""
        case "rPh": phoneticDepth += 1
        case "t": inT = inSI && phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch localName(elementName) {
        case "si": strings.append(current); inSI = false; current = ""
        case "rPh": phoneticDepth = max(0, phoneticDepth - 1)
        case "t": inT = false
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }
}

nonisolated private final class WorksheetParser: NSObject, XMLParserDelegate {
    struct Result {
        let rows: [[XLSXCell]]
        let columnWidths: [Double]
    }

    let sharedStrings: [String]
    private var cells: [Int: [Int: XLSXCell]] = [:]
    private var widths: [Int: Double] = [:]

    private var currentRow = 0          // 1-based
    private var nextColumn = 0          // 0-based, for cells without `r`
    private var cellColumn = 0
    private var cellType = "n"
    private var inCell = false
    private var inV = false
    private var inIS = false
    private var inT = false
    private var phoneticDepth = 0
    private var valueText = ""
    private var inlineText = ""
    private var sawInline = false
    var failure: XLSXError?

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    static func parse(_ data: Data, sharedStrings: [String]) throws -> Result {
        let p = WorksheetParser(sharedStrings: sharedStrings)
        try runParser(data, delegate: p, part: "worksheet")
        if let f = p.failure { throw f }
        return p.result()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch localName(elementName) {
        case "row":
            if let r = attributeDict["r"].flatMap(Int.init), r > 0 {
                currentRow = r
            } else {
                currentRow += 1
            }
            nextColumn = 0
        case "c":
            inCell = true
            cellType = attributeDict["t"] ?? "n"
            valueText = ""; inlineText = ""; sawInline = false
            if let ref = attributeDict["r"], let parsed = XLSX.parseCellReference(ref) {
                cellColumn = parsed.column
                if let r = parsed.row, r > 0, r != currentRow {
                    currentRow = r
                }
            } else {
                cellColumn = nextColumn
            }
            if currentRow == 0 { currentRow = 1 }
        case "v": if inCell { inV = true }
        case "is": if inCell { inIS = true; sawInline = true }
        case "rPh": phoneticDepth += 1
        case "t": inT = inIS && phoneticDepth == 0
        case "col":
            if let lo = attributeDict["min"].flatMap(Int.init),
               let hi = attributeDict["max"].flatMap(Int.init),
               let w = attributeDict["width"].flatMap(Double.init),
               lo >= 1, hi >= lo, hi - lo < 1024 {
                for c in lo...hi { widths[c - 1] = w }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch localName(elementName) {
        case "v": inV = false
        case "is": inIS = false
        case "t": inT = false
        case "rPh": phoneticDepth = max(0, phoneticDepth - 1)
        case "c":
            inCell = false
            let cell = makeCell()
            if cell != .empty {
                cells[currentRow, default: [:]][cellColumn] = cell
            }
            nextColumn = cellColumn + 1
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV { valueText += string }
        else if inT { inlineText += string }
    }

    private func makeCell() -> XLSXCell {
        switch cellType {
        case "s":
            let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let idx = Int(trimmed) else { return .empty }
            guard idx >= 0, idx < sharedStrings.count else {
                failure = XLSXError.corrupt("shared string index \(idx) out of range")
                return .empty
            }
            let s = sharedStrings[idx]
            return s.isEmpty ? .empty : .text(s)
        case "inlineStr":
            let s = sawInline ? inlineText : valueText
            return s.isEmpty ? .empty : .text(s)
        case "b":
            let v = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { return .empty }
            return .text(v == "1" || v.lowercased() == "true" ? "TRUE" : "FALSE")
        case "str", "e", "d":
            return valueText.isEmpty ? .empty : .text(valueText)
        default:
            let v = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty { return .empty }
            if let d = Double(v) { return .number(d) }
            return .text(v)
        }
    }

    func result() -> Result {
        let maxRow = cells.keys.max() ?? 0
        var rows: [[XLSXCell]] = []
        rows.reserveCapacity(maxRow)
        if maxRow > 0 {
            for r in 1...maxRow {
                guard let rowCells = cells[r], let maxCol = rowCells.keys.max() else {
                    rows.append([])
                    continue
                }
                var row = [XLSXCell](repeating: .empty, count: maxCol + 1)
                for (c, v) in rowCells { row[c] = v }
                rows.append(row)
            }
        }
        var colWidths: [Double] = []
        if let maxCol = widths.keys.max() {
            colWidths = (0...maxCol).map { widths[$0] ?? 0 }
        }
        return Result(rows: rows, columnWidths: colWidths)
    }
}
