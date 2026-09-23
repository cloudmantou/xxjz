import Foundation

// MARK: - File Parser Protocol

protocol FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]])
}

// MARK: - CSV Parser

final class CsvParser: FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]]) {
        // Read file data first
        let fileData = try Data(contentsOf: url)

        // Try multiple encodings commonly used for Chinese text
        var content: String?

        // Use NSString for better encoding support on iOS
        // NSString can handle more encodings than String.Encoding directly
        let gb18030Encoding = CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)
        if gb18030Encoding != kCFStringEncodingInvalidId {
            if let nsString = NSString(data: fileData, encoding: UInt(gb18030Encoding)) {
                let str = nsString as String
                if !str.contains("\u{FFFD}") {
                    content = str
                }
            }
        }

        // Fallback: try UTF-8
        if content == nil {
            if let str = String(data: fileData, encoding: .utf8) {
                content = str
            }
        }

        // Fallback: try Windows-1252 / Latin-1
        if content == nil {
            if let str = String(data: fileData, encoding: .windowsCP1252) {
                if !str.contains("\u{FFFD}") {
                    content = str
                }
            }
        }

        guard let finalContent = content else {
            throw ImportError.parseError("无法识别文件编码，请将文件保存为 UTF-8 编码后重试")
        }

        let lines = finalContent.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return ([], []) }

        let delimiter = detectDelimiter(firstLine: lines[0])
        let columns = parseCSVLine(lines[0], delimiter: delimiter)

        let rows = lines.dropFirst().map { parseCSVLine($0, delimiter: delimiter) }
        return (columns, Array(rows))
    }

    private func detectDelimiter(firstLine: String) -> Character {
        let commaCount = firstLine.filter { $0 == "," }.count
        let tabCount = firstLine.filter { $0 == "\t" }.count
        let semicolonCount = firstLine.filter { $0 == ";" }.count

        if tabCount >= commaCount && tabCount >= semicolonCount { return "\t" }
        if semicolonCount > commaCount { return ";" }
        return ","
    }

    private func parseCSVLine(_ line: String, delimiter: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

// MARK: - XLSX Parser (Office Open XML - zip+xml)

final class XlsxParser: FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]]) {
        // xlsx is a zip file: read sharedStrings.xml + sheet1.xml
        let zipData = try Data(contentsOf: url)

        // Read shared strings (cell string values)
        let sharedStrings = try parseSharedStringsSimple(data: zipData)

        // Read the first sheet
        let (columns, rows) = try parseFirstSheetSimple(data: zipData, sharedStrings: sharedStrings)

        return (columns, rows)
    }

    private func parseSharedStringsSimple(data: Data) throws -> [String] {
        // Simple approach: extract shared strings XML from zip and parse
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return []
        }

        // Find xl/sharedStrings.xml content between <sst> tags
        var strings: [String] = []
        let siPattern = #"<si>(.*?)</si>"#
        if let regex = try? NSRegularExpression(pattern: siPattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let range = Range(match.range(at: 1), in: content) {
                    let siContent = String(content[range])
                    // Extract text between <t> tags
                    let tPattern = #"<t[^>]*>([^<]*)</t>"#
                    if let tRegex = try? NSRegularExpression(pattern: tPattern),
                       let tMatch = tRegex.firstMatch(in: siContent, range: NSRange(siContent.startIndex..., in: siContent)),
                       let tRange = Range(tMatch.range(at: 1), in: siContent) {
                        strings.append(String(siContent[tRange]))
                    }
                }
            }
        }

        return strings
    }

    private func parseFirstSheetSimple(data: Data, sharedStrings: [String]) throws -> (columns: [String], rows: [[String]]) {
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ImportError.parseError("无法读取文件内容")
        }

        // Find sheet1.xml content - find the worksheet XML
        var rows: [[String]] = []

        // Match row elements: <row r="1"...>...</row>
        let rowPattern = #"<row[^>]*r="(\d+)"[^>]*>(.*?)</row>"#
        if let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) {
            let matches = rowRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))

            for match in matches {
                guard let rowContentRange = Range(match.range(at: 2), in: content) else { continue }

                let rowContent = String(content[rowContentRange])

                // Parse cells for this row
                let cells = parseRowCells(rowContent, sharedStrings: sharedStrings)
                rows.append(cells)
            }
        }

        let columns = rows.first ?? []
        let dataRows = rows.dropFirst()
        return (columns, Array(dataRows))
    }

    private func parseRowCells(_ rowContent: String, sharedStrings: [String]) -> [String] {
        var cells: [String] = []

        // Match cell elements: <c r="A1" ...><v>value</v></c> or <c r="A1" ...><is><t>text</t></is></c>
        let cellPattern = #"<c[^>]*r="([A-Z]+\d+)"[^>]*>(.*?)</c>"#
        if let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) {
            let matches = cellRegex.matches(in: rowContent, range: NSRange(rowContent.startIndex..., in: rowContent))

            for match in matches {
                guard let _ = Range(match.range(at: 1), in: rowContent),
                      let cellContentRange = Range(match.range(at: 2), in: rowContent) else { continue }

                let cellContent = String(rowContent[cellContentRange])

                // Check for shared string (t="s")
                if cellContent.contains(#"t="s""#) {
                    // Shared string reference
                    let vPattern = #"<v>(\d+)</v>"#
                    if let vRegex = try? NSRegularExpression(pattern: vPattern),
                       let vMatch = vRegex.firstMatch(in: cellContent, range: NSRange(cellContent.startIndex..., in: cellContent)),
                       let vRange = Range(vMatch.range(at: 1), in: cellContent) {
                        let index = Int(String(cellContent[vRange])) ?? 0
                        if index < sharedStrings.count {
                            cells.append(sharedStrings[index])
                            continue
                        }
                    }
                    cells.append("")
                } else if cellContent.contains("<is>") {
                    // Inline string
                    let tPattern = #"<t[^>]*>([^<]*)</t>"#
                    if let tRegex = try? NSRegularExpression(pattern: tPattern),
                       let tMatch = tRegex.firstMatch(in: cellContent, range: NSRange(cellContent.startIndex..., in: cellContent)),
                       let tRange = Range(tMatch.range(at: 1), in: cellContent) {
                        cells.append(String(cellContent[tRange]))
                    } else {
                        cells.append("")
                    }
                } else {
                    // Numeric or other value
                    let vPattern = #"<v>([^<]*)</v>"#
                    if let vRegex = try? NSRegularExpression(pattern: vPattern),
                       let vMatch = vRegex.firstMatch(in: cellContent, range: NSRange(cellContent.startIndex..., in: cellContent)),
                       let vRange = Range(vMatch.range(at: 1), in: cellContent) {
                        cells.append(String(cellContent[vRange]))
                    } else {
                        cells.append("")
                    }
                }
            }
        }

        return cells
    }
}

// MARK: - XLS Parser (Legacy Excel - not supported natively, recommend conversion)

final class XlsParser: FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]]) {
        // XLS is binary format (BIFF). For simplicity, we convert to CSV first via temporary file.
        // In production, use a library like https://github.com/59SEP/BillConverter

        // For now, throw an error suggesting .xlsx or .csv
        throw ImportError.parseError("暂不支持 .xls 格式，请另存为 .xlsx 或 .csv 格式后重试")
    }
}

// MARK: - Simple XML Parser (for xlsx parsing)

final class SimpleXMLParser {
    struct Element {
        let name: String
        let attributes: [String: String]
        var text: String?
        let isEndElement: Bool
    }

    let elements: [Element]

    init(data: Data) {
        var result: [Element] = []
        let content = String(data: data, encoding: .utf8) ?? ""

        // Simple regex-based parsing for xlsx XML
        // Match <tag attr="value"...>text</tag> and <tag ... />
        let tagPattern = #"<(\w+)([^>]*))(?::(\w+))?([^>]*)(?:/>|>)([^<]*)"#

        if let regex = try? NSRegularExpression(pattern: tagPattern, options: []) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

            for match in matches {
                if let fullRange = Range(match.range, in: content),
                   let nameRange = Range(match.range(at: 1), in: content) {
                    let name = String(content[nameRange])
                    let isEndElement = fullRange.lowerBound < content.endIndex && content[content.index(before: content.index(before: fullRange.upperBound))] == "/"
                    let textRange = match.range(at: 5)
                    let text = textRange.location != NSNotFound && textRange.location < content.count
                        ? String(content[Range(textRange, in: content)!])
                        : nil

                    // Parse attributes
                    var attrs: [String: String] = [:]
                    let attrPattern = #"(\w+)="([^"]*)""#
                    if let attrRegex = try? NSRegularExpression(pattern: attrPattern) {
                        let attrMatches = attrRegex.matches(in: content, range: NSRange(nameRange.upperBound..<fullRange.upperBound, in: content))
                        for attrMatch in attrMatches {
                            if let keyRange = Range(attrMatch.range(at: 1), in: content),
                               let valRange = Range(attrMatch.range(at: 2), in: content) {
                                attrs[String(content[keyRange])] = String(content[valRange])
                            }
                        }
                    }

                    result.append(Element(name: name, attributes: attrs, text: text?.trimmingCharacters(in: .whitespacesAndNewlines), isEndElement: isEndElement))
                }
            }
        }

        self.elements = result
    }

    func allText() -> String {
        elements.compactMap { $0.text }.joined()
    }
}

// MARK: - ZIP Support (minimal implementation for xlsx)

struct ZIPEntry {
    let fileName: String
    let dataOffset: Int
    let uncompressedSize: Int
}

final class ZIPHandle {
    let data: Data

    init(data: Data) throws {
        self.data = data
        // Validate zip header
        guard data.count >= 4 else { throw ImportError.invalidFormat }
        let signature = data.prefix(4)
        guard signature == Data([0x50, 0x4B, 0x03, 0x04]) else {
            throw ImportError.invalidFormat
        }
    }

    func close() throws {
        // No-op for Data-based handle
    }
}

final class ZIPArchive: Sequence {
    typealias Element = ZIPEntry

    private let data: Data
    private var entries: [ZIPEntry] = []

    init?(url: ZIPHandle) {
        self.data = url.data
        parseEndOfCentralDirectory()
    }

    func makeIterator() -> IndexingIterator<[ZIPEntry]> {
        entries.makeIterator()
    }

    func first(where predicate: (ZIPEntry) -> Bool) -> ZIPEntry? {
        entries.first(where: predicate)
    }

    var first: ZIPEntry? { entries.first }

    private func parseEndOfCentralDirectory() {
        guard data.count >= 22 else { return }

        // Find end of central directory signature (0x06054b50)
        var offset = data.count - 22
        while offset > 0 {
            if data[offset] == 0x50 && data[offset+1] == 0x4B &&
               data[offset+2] == 0x05 && data[offset+3] == 0x06 {
                // Found EOCD
                let centralDirOffset = Int(data[offset+16...offset+19].withUnsafeBytes { $0.load(as: UInt32.self) })
                parseCentralDirectory(startOffset: centralDirOffset)
                return
            }
            offset -= 1
        }
    }

    private func parseCentralDirectory(startOffset: Int) {
        var off = startOffset
        while off < data.count - 4 {
            guard data[off] == 0x50 && data[off+1] == 0x4B &&
                  data[off+2] == 0x01 && data[off+3] == 0x02 else { break }

            let fileNameLength = Int(data[off+28...off+29].withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraLength = Int(data[off+30...off+31].withUnsafeBytes { $0.load(as: UInt16.self) })
            let commentLength = Int(data[off+32...off+33].withUnsafeBytes { $0.load(as: UInt16.self) })

            let nameData = data[off+46..<off+46+fileNameLength]
            let fileName = String(data: nameData, encoding: .utf8) ?? ""

            let localHeaderOffset = Int(data[off+42...off+45].withUnsafeBytes { $0.load(as: UInt32.self) })

            entries.append(ZIPEntry(fileName: fileName, dataOffset: localHeaderOffset + 30, uncompressedSize: 0))

            off += 46 + fileNameLength + extraLength + commentLength
        }
    }
}

// MARK: - XLSX Generator (Office Open XML)

final class XlsxGenerator {
    func generate(headers: [String], rows: [[String]], fileName: String) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).xlsx")

        // Create zip in-memory (simplified)
        // xl/sharedStrings.xml
        let sharedStrings = Array(Set(headers + rows.flatMap { $0 })).filter { $0.contains("<") || $0.contains(">") || $0.contains("&") }
        let sharedStringsXML = buildSharedStringsXML(strings: sharedStrings)

        // xl/worksheets/sheet1.xml
        let sheetXML = buildSheetXML(headers: headers, rows: rows, sharedStrings: sharedStrings)

        // [Content_Types].xml
        let contentTypesXML = buildContentTypesXML()

        // xl/workbook.xml
        let workbookXML = buildWorkbookXML()

        // xl/_rels/workbook.xml.rels
        let workbookRelsXML = buildWorkbookRelsXML()

        // _rels/.rels
        let rootRelsXML = buildRootRelsXML()

        // Write to file (xlsx is a zip)
        let zip = try createZipData(
            files: [
                "[Content_Types].xml": contentTypesXML,
                "_rels/.rels": rootRelsXML,
                "xl/workbook.xml": workbookXML,
                "xl/workbook.xml.rels": workbookRelsXML,
                "xl/sharedStrings.xml": sharedStringsXML,
                "xl/worksheets/sheet1.xml": sheetXML
            ]
        )

        try zip.write(to: fileURL)
        return fileURL
    }

    private func buildSharedStringsXML(strings: [String]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\#(strings.count)" uniqueCount="\#(strings.count)">"#
        for str in strings {
            xml += "<si><t>\(escapeXML(str))</t></si>"
        }
        xml += "</sst>"
        return xml
    }

    private func buildSheetXML(headers: [String], rows: [[String]], sharedStrings: [String]) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        xml += "<sheetData>"

        // Header row
        xml += "<row r=\"1\">"
        for (col, header) in headers.enumerated() {
            let cellRef = columnIndexToLetter(col) + "1"
            xml += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(header))</t></is></c>"
        }
        xml += "</row>"

        // Data rows
        for (rowIndex, row) in rows.enumerated() {
            xml += "<row r=\"\(rowIndex + 2)\">"
            for (colIndex, cell) in row.enumerated() {
                let cellRef = columnIndexToLetter(colIndex) + "\(rowIndex + 2)"
                xml += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapeXML(cell))</t></is></c>"
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    private func buildContentTypesXML() -> String {
        return #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# +
        #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"# +
        #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"# +
        #"<Default Extension="xml" ContentType="application/xml"/>"# +
        #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"# +
        #"<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"# +
        #"<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>"# +
        #"</Types>"#
    }

    private func buildWorkbookXML() -> String {
        return #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# +
        #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"# +
        #"<sheets><sheet name="账本" sheetId="1" r:id="rId1"/></sheets>"# +
        #"</workbook>"#
    }

    private func buildWorkbookRelsXML() -> String {
        return #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# +
        #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"# +
        #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>"# +
        #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>"# +
        #"</Relationships>"#
    }

    private func buildRootRelsXML() -> String {
        return #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# +
        #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"# +
        #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"# +
        #"</Relationships>"#
    }

    private func createZipData(files: [String: String]) throws -> Data {
        var data = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [Int] = []

        for (fileName, content) in files.sorted(by: { $0.key < $1.key }) {
            let fileData = content.data(using: .utf8) ?? Data()
            let offset = data.count

            // Local file header
            data.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])  // signature
            data.append(contentsOf: [0x14, 0x00])                // version needed
            data.append(contentsOf: [0x00, 0x00])                // flags
            data.append(contentsOf: [0x00, 0x00])                // compression (stored)
            data.append(contentsOf: [0x00, 0x00])                // mod time
            data.append(contentsOf: [0x00, 0x00])                // mod date
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // crc (placeholder)
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // compressed size
            data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // uncompressed size
            let nameData = fileName.data(using: .utf8) ?? Data()
            data.append(UInt8(nameData.count & 0xFF))
            data.append(UInt8((nameData.count >> 8) & 0xFF))
            data.append(contentsOf: [0x00, 0x00])                // extra field length
            data.append(nameData)
            data.append(fileData)

            localHeaderOffsets.append(offset)

            // Central directory entry
            centralDirectory.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])  // signature
            centralDirectory.append(contentsOf: [0x14, 0x00])                // version made by
            centralDirectory.append(contentsOf: [0x14, 0x00])                // version needed
            centralDirectory.append(contentsOf: [0x00, 0x00])                // flags
            centralDirectory.append(contentsOf: [0x00, 0x00])                // compression
            centralDirectory.append(contentsOf: [0x00, 0x00])                // mod time
            centralDirectory.append(contentsOf: [0x00, 0x00])                // mod date
            centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // crc
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(fileData.count).littleEndian) { Array($0) })
            centralDirectory.append(UInt8(nameData.count & 0xFF))
            centralDirectory.append(UInt8((nameData.count >> 8) & 0xFF))
            centralDirectory.append(contentsOf: [0x00, 0x00])                // extra field length
            centralDirectory.append(contentsOf: [0x00, 0x00])                // file comment length
            centralDirectory.append(contentsOf: [0x00, 0x00])                // disk number
            centralDirectory.append(contentsOf: [0x00, 0x00])                // internal attrs
            centralDirectory.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // external attrs
            centralDirectory.append(contentsOf: withUnsafeBytes(of: UInt32(offset).littleEndian) { Array($0) })
            centralDirectory.append(nameData)
        }

        // End of central directory
        let cdOffset = data.count
        data.append(centralDirectory)
        data.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        data.append(contentsOf: [0x00, 0x00])                    // disk number
        data.append(contentsOf: [0x00, 0x00])                    // cd disk number
        data.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(files.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(centralDirectory.count).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(cdOffset).littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00])                    // comment length

        return data
    }

    private func columnIndexToLetter(_ index: Int) -> String {
        var result = ""
        var idx = index
        while idx >= 0 {
            result = String(Character(UnicodeScalar(65 + idx % 26)!)) + result
            idx = idx / 26 - 1
        }
        return result
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
