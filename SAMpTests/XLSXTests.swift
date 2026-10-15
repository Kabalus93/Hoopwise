import XCTest
import Compression
@testable import Hoopwise

/// The dependency-free XLSX codec. The writer must produce files Excel / WPS /
/// Numbers open; the reader must survive what those apps actually emit —
/// deflated entries, data descriptors, shared strings with rich-text runs, and
/// cells without `r` attributes. Fixtures are synthetic: no roster data here.
final class XLSXTests: XCTestCase {

    // MARK: Round trip

    func testRoundTripPreservesTextNumbersGapsAndSheets() throws {
        let roster = XLSXSheet(
            name: "上课名单",
            rows: [
                [.text("课程"), .text("姓名"), .text("课时")],
                [.text("U10 周日"), .text("张三"), .number(36)],
                [],                                                   // gap row
                [.empty, .text("李四 & <王五> \"引号\" 'apos'"), .number(2.5)],
                [.number(-7), .empty, .empty, .text("  leading/trailing spaces  ")],
            ],
            columnWidths: [12, 20, 8])
        let second = XLSXSheet(
            name: "Totals",
            rows: [[.text("Line1\nLine2"), .number(1e-5), .number(123456789012)]])

        let data = try XLSX.write([roster, second])
        let back = try XLSX.read(data)

        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0], roster)
        XCTAssertEqual(back[1].name, "Totals")
        XCTAssertEqual(back[1].rows, second.rows)
        XCTAssertEqual(back[0].rows[1][2].stringValue, "36")
        XCTAssertEqual(back[0].rows[3][2].stringValue, "2.5")
    }

    func testTrailingEmptyRowsAndCellsAreTrimmed() throws {
        let sheet = XLSXSheet(name: "S", rows: [[.text("a"), .empty], [.empty], []])
        let back = try XLSX.read(XLSX.write([sheet]))
        XCTAssertEqual(back[0].rows, [[.text("a")]])
    }

    func testColumnsBeyondZ() throws {
        var row = [XLSXCell](repeating: .empty, count: 28)
        row[27] = .text("AB")
        let back = try XLSX.read(XLSX.write([XLSXSheet(name: "Wide", rows: [row])]))
        XCTAssertEqual(back[0].rows[0].count, 28)
        XCTAssertEqual(back[0].rows[0][27], .text("AB"))
        XCTAssertEqual(XLSX.columnLetters(0), "A")
        XCTAssertEqual(XLSX.columnLetters(25), "Z")
        XCTAssertEqual(XLSX.columnLetters(26), "AA")
        XCTAssertEqual(XLSX.columnLetters(701), "ZZ")
        XCTAssertEqual(XLSX.columnLetters(702), "AAA")
        XCTAssertEqual(XLSX.columnIndex("AAA"), 702)
    }

    func testStringValue() {
        XCTAssertEqual(XLSXCell.number(36).stringValue, "36")
        XCTAssertEqual(XLSXCell.number(-3).stringValue, "-3")
        XCTAssertEqual(XLSXCell.number(1.5).stringValue, "1.5")
        XCTAssertEqual(XLSXCell.text("x").stringValue, "x")
        XCTAssertEqual(XLSXCell.empty.stringValue, "")
    }

    func testSheetNamesAreSanitized() throws {
        let names = XLSX.sanitizedSheetNames([
            "a/b:c*d?e[f]g\\h", "", "History", String(repeating: "x", count: 40),
            "dup", "DUP", "'quoted'",
        ])
        XCTAssertEqual(names[0], "a_b_c_d_e_f_g_h")
        XCTAssertEqual(names[1], "Sheet2")
        XCTAssertNotEqual(names[2].lowercased(), "history")
        XCTAssertEqual(names[3].utf16.count, 31)
        XCTAssertEqual(names[4], "dup")
        XCTAssertEqual(names[5], "DUP (2)")
        XCTAssertEqual(names[6], "quoted")

        let back = try XLSX.read(XLSX.write([XLSXSheet(name: "Q1/Q2", rows: [])]))
        XCTAssertEqual(back[0].name, "Q1_Q2")
    }

    func testWriterRejectsUnrepresentableInput() {
        XCTAssertThrowsError(try XLSX.write([]))
        XCTAssertThrowsError(try XLSX.write([XLSXSheet(name: "S", rows: [[.number(.nan)]])]))
    }

    func testControlCharactersAreDroppedSoTheFileStaysValid() throws {
        let back = try XLSX.read(XLSX.write([XLSXSheet(name: "S", rows: [[.text("a\u{0B}b\u{01}c")]])]))
        XCTAssertEqual(back[0].rows[0][0], .text("abc"))
    }

    // MARK: ZIP

    func testCRC32KnownVectors() {
        XCTAssertEqual(XLSX.crc32(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(XLSX.crc32(Data()), 0)
        XCTAssertEqual(XLSX.crc32(Data("The quick brown fox jumps over the lazy dog".utf8)), 0x414F_A339)
    }

    func testNotAZip() {
        XCTAssertThrowsError(try XLSX.read(Data("hello".utf8))) { error in
            guard case XLSXError.notAZip = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: Reading Excel-shaped input

    /// A deflated, data-descriptor archive shaped like real Excel/WPS output:
    /// shared strings with a rich-text run and a phonetic run, t="str",
    /// t="b", t="inlineStr", a cell with no `r`, a row with no `r`, a prefixed
    /// namespace, an absolute rels target and a gap.
    func testReadsDeflatedExcelStyleWorkbook() throws {
        let ss = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">
        <si><t>课程</t></si>
        <si><r><rPr><b/></rPr><t>张</t></r><r><t xml:space="preserve"> 彦俊 </t></r><rPh sb="0" eb="1"><t>ZHANG</t></rPh></si>
        <si><t>A &amp; B</t></si>
        </sst>
        """
        let sheet1 = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <x:cols><x:col min="1" max="2" width="15.5" customWidth="1"/></x:cols>
        <x:sheetData>
        <x:row r="1"><x:c r="A1" t="s" s="1"><x:v>0</x:v></x:c><x:c r="D1" s="2"/></x:row>
        <x:row r="3"><x:c r="C3" t="s"><x:v>1</x:v></x:c><x:c r="D3"><x:v>36</x:v></x:c></x:row>
        <x:row><x:c t="str"><x:f>A1</x:f><x:v>8</x:v></x:c><x:c t="b"><x:v>1</x:v></x:c><x:c t="inlineStr"><x:is><x:t>行内</x:t></x:is></x:c></x:row>
        <x:row r="30"><x:c r="AA30" t="s"><x:v>2</x:v></x:c></x:row>
        <x:row r="40"><x:c r="A40" s="3"/></x:row>
        </x:sheetData>
        </x:worksheet>
        """
        let sheet2 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="上课名单" sheetId="1" r:id="rId7"/><sheet name="空" sheetId="2" r:id="rId2"/></sheets>
        </workbook>
        """
        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/other.xml"/>
        <Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/first.xml"/>
        <Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
        </Relationships>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let zip = try Self.deflatedZip([
            ("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"/>"),
            ("_rels/.rels", rootRels),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", wbRels),
            ("xl/sharedStrings.xml", ss),
            ("xl/worksheets/first.xml", sheet1),
            ("xl/worksheets/other.xml", sheet2),
        ])

        let sheets = try XLSX.read(zip)
        XCTAssertEqual(sheets.map(\.name), ["上课名单", "空"])
        let s = sheets[0]
        XCTAssertEqual(s.rows.count, 30, "styled-but-empty row 40 is trimmed")
        XCTAssertEqual(s.rows[0], [.text("课程")])
        XCTAssertEqual(s.rows[1], [])
        XCTAssertEqual(s.rows[2][2], .text("张 彦俊 "), "runs concatenated, phonetic run excluded")
        XCTAssertEqual(s.rows[2][3], .number(36))
        XCTAssertEqual(s.rows[2][3].stringValue, "36")
        XCTAssertEqual(s.rows[3], [.text("8"), .text("TRUE"), .text("行内")], "row and cells without r are sequential")
        XCTAssertEqual(s.rows[29].count, 27)
        XCTAssertEqual(s.rows[29][26], .text("A & B"))
        XCTAssertEqual(s.columnWidths, [15.5, 15.5])
        XCTAssertEqual(sheets[1].rows, [])
    }

    // MARK: Fixture builder

    /// Raw-deflate entries (Compression's ZLIB is headerless RFC 1951) with
    /// general-purpose bit 3 set: the local header carries zero CRC/sizes and
    /// the real values follow the data in a descriptor, as streaming writers
    /// do. The reader must take sizes from the central directory.
    private static func deflatedZip(_ parts: [(String, String)]) throws -> Data {
        var out = Data()
        var central = Data()
        for (name, text) in parts {
            let content = Data(text.utf8)
            let compressed = try deflate(content)
            let crc = XLSX.crc32(content)
            let nameData = Data(name.utf8)
            let offset = UInt32(out.count)

            out.le32(0x0403_4B50); out.le16(20); out.le16(0x0808); out.le16(8)
            out.le16(0); out.le16(0x0021)
            out.le32(0); out.le32(0); out.le32(0)
            out.le16(UInt16(nameData.count)); out.le16(0)
            out.append(nameData)
            out.append(compressed)
            out.le32(0x0807_4B50); out.le32(crc)
            out.le32(UInt32(compressed.count)); out.le32(UInt32(content.count))

            central.le32(0x0201_4B50); central.le16(20); central.le16(20)
            central.le16(0x0808); central.le16(8); central.le16(0); central.le16(0x0021)
            central.le32(crc); central.le32(UInt32(compressed.count)); central.le32(UInt32(content.count))
            central.le16(UInt16(nameData.count)); central.le16(0); central.le16(0)
            central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x0605_4B50); out.le16(0); out.le16(0)
        out.le16(UInt16(parts.count)); out.le16(UInt16(parts.count))
        out.le32(UInt32(central.count)); out.le32(cdOffset); out.le16(0)
        return out
    }

    private static func deflate(_ data: Data) throws -> Data {
        let src = [UInt8](data)
        var dst = [UInt8](repeating: 0, count: src.count + 1024)
        let n = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, d.count, s.baseAddress!, s.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { throw XLSXError.corrupt("test deflate failed") }
        return Data(dst[0..<n])
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) {
        append(UInt8(v & 0xFF)); append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF)); append(UInt8(v >> 24))
    }
}
