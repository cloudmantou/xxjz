import Foundation
import CoreFoundation

// MARK: - File Parser Protocol

protocol FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]])
}

enum CSVCodec {
    static func escapeField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

// MARK: - CSV Parser

final class CsvParser: FileParser {
    func parse(url: URL) async throws -> (columns: [String], rows: [[String]]) {
        let fileData = try Data(contentsOf: url)

        let utf8BOM = Data([0xEF, 0xBB, 0xBF])
        let hasUTF8BOM = fileData.starts(with: utf8BOM)
        let dataWithoutBOM = hasUTF8BOM ? Data(fileData.dropFirst(utf8BOM.count)) : fileData
        var content = String(data: dataWithoutBOM, encoding: .utf8)

        if content == nil && !hasUTF8BOM {
            let gb18030CFEncoding = CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)
            let gb18030NSStringEncoding = CFStringConvertEncodingToNSStringEncoding(gb18030CFEncoding)
            if gb18030CFEncoding != kCFStringEncodingInvalidId,
               gb18030NSStringEncoding != kCFStringEncodingInvalidId,
               let nsString = NSString(data: fileData, encoding: gb18030NSStringEncoding) {
                let decoded = nsString as String
                if !decoded.contains("\u{FFFD}") {
                    content = decoded
                }
            }

            if content == nil,
               let decoded = String(data: fileData, encoding: .windowsCP1252),
               !decoded.contains("\u{FFFD}") {
                content = decoded
            }
        }

        guard let finalContent = content else {
            throw ImportError.parseError("无法识别文件编码，请将文件保存为 UTF-8 编码后重试")
        }

        let records = try Self.parseCSVText(finalContent)
        guard let columns = records.first else { return ([], []) }
        return (columns, Array(records.dropFirst()))
    }

    static func parseCSVText(_ content: String) throws -> [[String]] {
        let normalizedContent = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        let characters = Array(normalizedContent)
        let delimiter = detectDelimiter(in: characters)

        var rows: [[String]] = []
        var row: [String] = []
        var current = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let char = characters[index]
            if char == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                row.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                row.append(current.trimmingCharacters(in: .whitespaces))
                if row.contains(where: { !$0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                current = ""
                if char == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            } else {
                current.append(char)
            }
            index += 1
        }

        guard !inQuotes else {
            throw ImportError.parseError("CSV 引号不完整，请检查文件内容后重试")
        }
        row.append(current.trimmingCharacters(in: .whitespaces))
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    private static func detectDelimiter(in characters: [Character]) -> Character {
        var counts: [Character: Int] = [",": 0, "\t": 0, ";": 0]
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let char = characters[index]
            if char == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    index += 2
                    continue
                }
                inQuotes.toggle()
            } else if (char == "\n" || char == "\r") && !inQuotes {
                break
            } else if !inQuotes, counts[char] != nil {
                counts[char, default: 0] += 1
            }
            index += 1
        }

        return counts.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key != "," && rhs.key == "," }
            return lhs.value < rhs.value
        }?.key ?? ","
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
