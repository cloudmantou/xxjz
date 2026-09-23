import Foundation
import CoreData

// MARK: - Asset Import Record

struct AssetImportRecord: Identifiable {
    let id = UUID()
    var name: String
    var category: String
    var purchaseDate: Date
    var purchasePrice: Double
    var currentValue: Double?
    var status: AssetStatus = .active
    var notes: String?
    var importRowIndex: Int

    var matchedCategory: String?
}

// MARK: - Import Result

struct AssetImportResult {
    let totalCount: Int
    let successCount: Int
    let failedCount: Int
    let errors: [String]
}

// MARK: - Service

@MainActor
final class AssetImportExportService: ObservableObject {
    static let shared = AssetImportExportService()

    private let viewContext: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }

    // MARK: - CSV Template

    static let csvTemplate = """
资产名称,分类,购买日期,购买价格,当前价值,状态,备注
iPhone 15 Pro,电子产品,2024-01-15,7999,7000,使用中,256GB
MacBook Air,电子产品,2024-02-20,8999,8500,使用中,13英寸
AirPods Pro,数码配件,2024-03-10,1899,1500,使用中,第二代
"""

    static var templateURL: URL? {
        let fileName = "资产导入模板.csv"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try csvTemplate.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Import

    func parseCSV(at url: URL) throws -> [AssetImportRecord] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = try CsvParser.parseCSVText(content)
        guard let header = rows.first, rows.count > 1 else { return [] }
        let headers = header.map { $0.lowercased() }

        let nameIdx = headers.firstIndex { $0.contains("资产名称") || $0.contains("名称") || $0 == "name" }
        let catIdx = headers.firstIndex { $0.contains("分类") || $0 == "category" }
        let dateIdx = headers.firstIndex { $0.contains("购买日期") || $0.contains("日期") || $0 == "date" }
        let priceIdx = headers.firstIndex { $0.contains("购买价格") || $0.contains("价格") || $0 == "price" }
        let valueIdx = headers.firstIndex { $0.contains("当前价值") || $0.contains("价值") || $0 == "value" }
        let statusIdx = headers.firstIndex { $0.contains("状态") || $0 == "status" }
        let notesIdx = headers.firstIndex { $0.contains("备注") || $0 == "notes" }

        guard let nameIndex = nameIdx, let catIndex = catIdx,
              let dateIndex = dateIdx, let priceIndex = priceIdx else {
            throw NSError(domain: "AssetImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV缺少必要列：资产名称、分类、购买日期、购买价格"])
        }

        var records: [AssetImportRecord] = []
        for (index, columns) in rows.dropFirst().enumerated() {
            guard columns.count > max(nameIndex, catIndex, dateIndex, priceIndex) else {
                throw NSError(
                    domain: "AssetImport",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行缺少必要字段"]
                )
            }

            let name = columns[nameIndex].trimmingCharacters(in: .whitespaces)
            let category = columns[catIndex].trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty else {
                throw NSError(
                    domain: "AssetImport",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行资产名称为空"]
                )
            }
            guard !category.isEmpty else {
                throw NSError(
                    domain: "AssetImport",
                    code: 8,
                    userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行资产分类为空"]
                )
            }

            let dateStr = columns[dateIndex].trimmingCharacters(in: .whitespaces)
            guard let purchaseDate = parsePurchaseDate(dateStr) else {
                throw NSError(
                    domain: "AssetImport",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行购买日期无法识别：\(dateStr)"]
                )
            }

            let priceStr = columns[priceIndex].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            guard let purchasePrice = parseCSVAmount(priceStr), purchasePrice >= 0 else {
                throw NSError(
                    domain: "AssetImport",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行购买价格无效：\(priceStr)"]
                )
            }

            var currentValue: Double?
            if let valueIndex = valueIdx, columns.count > valueIndex {
                let valueStr = columns[valueIndex].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
                if !valueStr.isEmpty {
                    guard let parsedValue = parseCSVAmount(valueStr), parsedValue >= 0 else {
                        throw NSError(
                            domain: "AssetImport",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行当前价值无效：\(valueStr)"]
                        )
                    }
                    currentValue = parsedValue
                }
            }

            var status: AssetStatus = .active
            if let statusIndex = statusIdx, columns.count > statusIndex {
                let statusStr = columns[statusIndex].trimmingCharacters(in: .whitespaces)
                if !statusStr.isEmpty {
                    guard let parsedStatus = AssetStatus(rawValue: statusStr) else {
                        throw NSError(
                            domain: "AssetImport",
                            code: 5,
                            userInfo: [NSLocalizedDescriptionKey: "第\(index + 2)行资产状态无法识别：\(statusStr)"]
                        )
                    }
                    status = parsedStatus
                }
            }

            var notes: String?
            if let notesIndex = notesIdx, columns.count > notesIndex {
                notes = columns[notesIndex].trimmingCharacters(in: .whitespaces)
                if notes?.isEmpty == true { notes = nil }
            }

            var record = AssetImportRecord(
                name: name,
                category: category,
                purchaseDate: purchaseDate,
                purchasePrice: purchasePrice,
                notes: notes,
                importRowIndex: index + 2
            )
            record.currentValue = currentValue
            record.status = status
            records.append(record)
        }

        return records
    }

    func importRecords(_ records: [AssetImportRecord]) -> AssetImportResult {
        var successCount = 0
        var failedCount = 0
        var errors: [String] = []

        for record in records {
            do {
                _ = AssetItem(
                    context: viewContext,
                    name: record.name,
                    category: record.category,
                    purchaseDate: record.purchaseDate,
                    purchasePrice: record.purchasePrice,
                    currentValue: record.currentValue ?? record.purchasePrice,
                    status: record.status,
                    notes: record.notes
                )
                try viewContext.save()
                successCount += 1
            } catch {
                failedCount += 1
                errors.append("第\(record.importRowIndex)行「\(record.name)」导入失败：\(error.localizedDescription)")
            }
        }

        return AssetImportResult(
            totalCount: records.count,
            successCount: successCount,
            failedCount: failedCount,
            errors: errors
        )
    }

    // MARK: - Export

    func exportAllAssetsCSV() -> URL? {
        let fetchRequest: NSFetchRequest<AssetItem> = AssetItem.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AssetItem.updatedAt, ascending: false)]

        guard let assets = try? viewContext.fetch(fetchRequest), !assets.isEmpty else {
            return nil
        }

        var csvContent = "资产名称,分类,购买日期,购买价格,当前价值,状态,备注\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for asset in assets {
            let name = escapeCSV(asset.name)
            let category = escapeCSV(asset.category)
            let dateStr = dateFormatter.string(from: asset.purchaseDate)
            let priceStr = String(format: "%.2f", asset.purchasePrice)
            let valueStr = String(format: "%.2f", asset.currentValue)
            let statusStr = asset.status.rawValue
            let notesStr = escapeCSV(asset.notes ?? "")

            csvContent += "\(name),\(category),\(dateStr),\(priceStr),\(valueStr),\(statusStr),\(notesStr)\n"
        }

        let fileName = "资产导出_\(DateFormatter.yyyyMMdd.string(from: Date())).csv"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func parseCSVAmount(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(normalized), amount.isFinite else { return nil }
        return amount
    }

    private func parsePurchaseDate(_ value: String) -> Date? {
        let formats = [
            "yyyy-MM-dd", "yyyy-M-d",
            "yyyy/MM/dd", "yyyy/M/d",
            "yyyy.MM.dd", "yyyy.M.d",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
            "yyyy年MM月dd日", "yyyy年M月d日",
            "yyyy年MM月dd日 HH:mm:ss", "yyyy年M月d日 HH:mm:ss",
            "yyyy年MM月dd日 HH:mm", "yyyy年M月d日 HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.isLenient = false
            formatter.dateFormat = format
            if let date = formatter.date(from: value), formatter.string(from: date) == value {
                return date
            }
        }
        return nil
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
