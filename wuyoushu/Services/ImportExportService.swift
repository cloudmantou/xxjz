import Foundation
import CoreData
import UniformTypeIdentifiers

// MARK: - Import Models

/// 从xlsx/csv解析出的单条账单记录
struct ImportBillRecord: Identifiable {
    let id = UUID()
    var date: Date
    var amount: Double
    var isIncome: Bool
    var categoryName: String       // 原始类别名（待匹配）
    var subcategoryName: String?  // 原始子类别名
    var note: String?
    var fundAccountName: String?
    var merchantName: String?
    var importRowIndex: Int        // 在文件中的行号（用于错误定位）

    /// 匹配后的类别key（匹配成功后才填充）
    var matchedCategoryKey: String?
    var matchedSubcategoryKey: String?
}

/// 导入文件元数据
struct ImportFileModel {
    let url: URL
    let fileName: String
    let fileSize: Int64
    let rowCount: Int
    let columns: [String]           // 第一行（表头）
    let detectedFormat: ImportFileFormat
}

enum ImportFileFormat: String {
    case xlsx = "xlsx"
    case xls = "xls"
    case csv = "csv"
}

/// 导入批次追踪
struct ImportBatch {
    let id: UUID
    let fileName: String
    let importedAt: Date
    let recordCount: Int
    let importedCount: Int
    let duplicateCount: Int
    let failedCount: Int
    let invalidDateCount: Int
    let autoCreatedCategoryCount: Int  // 自动创建的新分类数量
}

private struct ImportDeduplicationKey: Hashable, Sendable {
    let minute: Int64
    let amountInCents: Int64
    let isIncome: Bool
    let categoryKey: String
    let subcategoryKey: String
    let fundAccountKey: String
    let note: String
    let merchant: String
}

// MARK: - Category Matching

/// 类目匹配结果
struct CategoryMatchResult {
    let originalName: String
    let matchedCategory: BookkeepingCategory?
    let matchedSubcategory: BookkeepingSubcategory?
    let confidence: Float             // 0.0~1.0
    let suggestion: String?         // "是否匹配到: 餐饮 > 午餐"
}

/// 未匹配的类目（需要用户手动映射）
struct UnmatchedCategory {
    let originalName: String
    let occurrenceCount: Int
    var userMappingKey: String?     // 用户选择的类别key
    var userMappingSubkey: String?  // 用户选择的子类别key
}

// MARK: - Import Service

@MainActor
final class ImportExportService: ObservableObject {
    static let shared = ImportExportService()

    private let viewContext: NSManagedObjectContext
    private(set) var invalidDateRowCount = 0
    private lazy var dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM-dd-yyyy",
            "yyyy年MM月dd日 HH:mm:ss",
            "yyyy年M月d日 HH:mm:ss",
            "yyyy年MM月dd日 HH:mm",
            "yyyy年M月d日 HH:mm"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter
        }
    }()
    private lazy var isoDateFormatter = ISO8601DateFormatter()
    private lazy var fractionalISODateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
    }

    // MARK: - File Parsing

    /// 解析文件（xlsx/xls/csv）返回行数据
    func parseFile(at url: URL) async throws -> ImportFileModel {
        let fileName = url.lastPathComponent
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0

        let format = detectFormat(fileName: fileName)
        let parser: FileParser = switch format {
        case .xlsx: XlsxParser()
        case .xls: XlsParser()
        case .csv: CsvParser()
        }

        let (columns, rows) = try await parser.parse(url: url)

        guard !rows.isEmpty else {
            throw ImportError.emptyFile
        }

        return ImportFileModel(
            url: url,
            fileName: fileName,
            fileSize: fileSize,
            rowCount: rows.count,
            columns: columns,
            detectedFormat: format
        )
    }

    /// 将行数据转换为 ImportBillRecord
    func convertToBillRecords(
        rows: [[String]],
        columnMapping: ColumnMapping,
        startRowIndex: Int = 0
    ) -> [ImportBillRecord] {
        var records: [ImportBillRecord] = []
        invalidDateRowCount = 0

        for (index, row) in rows.enumerated() where index >= startRowIndex {
            guard let amount = parseAmount(row[safe: columnMapping.amountColumn]), amount > 0 else {
                continue
            }
            guard let date = parseDate(row[safe: columnMapping.dateColumn]) else {
                invalidDateRowCount += 1
                continue
            }

            let record = ImportBillRecord(
                date: date,
                amount: amount,
                isIncome: columnMapping.typeColumn.flatMap { row[safe: $0] }.map { val in
                    let t = val.trimmingCharacters(in: .whitespaces)
                    return t == "收入" || t.lowercased() == "income" || t.contains("收入")
                } ?? false,
                categoryName: row[safe: columnMapping.categoryColumn] ?? "",
                subcategoryName: row[safe: columnMapping.subcategoryColumn],
                note: row[safe: columnMapping.noteColumn],
                fundAccountName: row[safe: columnMapping.fundAccountColumn],
                merchantName: row[safe: columnMapping.merchantColumn],
                importRowIndex: index
            )
            records.append(record)
        }

        return records
    }

    // MARK: - Category Matching

    /// 自动匹配类目（包括自定义分类）
    func autoMatchCategories(records: [ImportBillRecord]) -> [CategoryMatchResult] {
        // 内置分类
        let builtInCategories = BookkeepingCategory.expenseCategories + BookkeepingCategory.incomeCategories
        // 自定义分类
        let customCategories = CustomCategoryStore.shared.categories.map { $0.toBookkeepingCategory() }
        let allCategories = builtInCategories + customCategories

        return records.map { record in
            let result = findBestMatch(
                originalName: record.categoryName,
                categories: allCategories
            )
            return CategoryMatchResult(
                originalName: record.categoryName,
                matchedCategory: result.category,
                matchedSubcategory: result.subcategory,
                confidence: result.confidence,
                suggestion: result.category.map { cat in
                    if let sub = result.subcategory {
                        return "\(cat.localizedName) > \(sub.localizedName)"
                    }
                    return cat.localizedName
                }
            )
        }
    }

    /// 为未匹配的分类自动创建自定义分类
    func autoCreateCategoriesForUnmatched(unmatchedNames: [String], isIncome: Bool) -> [String: String] {
        // key: originalName, value: new category key
        var createdMappings: [String: String] = [:]

        for name in unmatchedNames {
            guard !name.isEmpty else { continue }

            // 检查是否已存在（包括内置和自定义）
            let allCategories = (BookkeepingCategory.expenseCategories + BookkeepingCategory.incomeCategories)
                .map { $0.key } + CustomCategoryStore.shared.categories.map { $0.categoryKey }

            let normalizedName = name.trimmingCharacters(in: .whitespaces)
            // 检查是否已存在同名分类，若存在直接复用其 key
            if let existingKey = allCategories.first(where: { catKey in
                BookkeepingCategory.find(key: catKey)?.localizedName.lowercased() == normalizedName.lowercased()
            }) {
                createdMappings[name] = existingKey
                continue
            }

            // 创建新的自定义分类
            let emoji = guessEmoji(for: normalizedName)
            let customCategory = CustomCategory(
                name: normalizedName,
                emoji: emoji,
                colorHex: isIncome ? "FFF8E1" : "F5F5F5",
                isIncome: isIncome
            )
            CustomCategoryStore.shared.add(customCategory)
            createdMappings[name] = customCategory.categoryKey
        }

        return createdMappings
    }

    /// 根据名称猜测合适的 emoji
    private func guessEmoji(for name: String) -> String {
        let lowercased = name.lowercased()

        // 常见关键词匹配
        let emojiMap: [(keywords: [String], emoji: String)] = [
            (["餐饮", "吃饭", "食物", "餐厅", "饭店", "食堂"], "🍽️"),
            (["交通", "出行", "公交", "地铁", "打车", " taxi", "开车"], "🚗"),
            (["购物", "商场", "超市", "网购", "衣服", "鞋子"], "🛍️"),
            (["娱乐", "电影", "游戏", "KTV", "唱歌", "音乐"], "🎮"),
            (["居住", "房租", "水电", "物业", "住房"], "🏠"),
            (["医疗", "医院", "买药", "看病", "健康"], "🏥"),
            (["教育", "学习", "课程", "培训", "书籍", "书"], "📚"),
            (["人情", "红包", "送礼", "礼物", "请客"], "🎁"),
            (["转账", "微信", "支付宝", "银行"], "💸"),
            (["工资", "薪水", "收入", "赚钱"], "💰"),
            (["兼职", "副业", "外快"], "💼"),
            (["理财", "投资", "股票", "基金"], "📈"),
            (["退款", "退款"], "🔄"),
            (["旅行", "旅游", "度假"], "✈️"),
            (["咖啡", "奶茶", "饮品", "饮料"], "☕"),
            (["水果", "零食", "甜点"], "🍰"),
            (["美容", "美发", "化妆", "护肤"], "💄"),
            (["健身", "运动", "跑步", "游泳"], "🏃"),
            (["宠物", "猫", "狗", "动物"], "🐶"),
            (["通讯", "手机", "话费", "流量"], "📱"),
            (["办公", "文具", "打印"], "📎"),
            (["快递", "物流", "邮寄"], "📦"),
            (["烟酒", "烟草", "酒"], "🍺"),
            (["彩票", "赌博"], "🎰"),
            (["装修", "家具", "家电"], "🛋️")
        ]

        for (keywords, emoji) in emojiMap {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return emoji
                }
            }
        }

        // 默认 emoji
        return "📋"
    }

    /// 收集未匹配的类目
    func collectUnmatchedCategories(records: [ImportBillRecord]) -> [UnmatchedCategory] {
        var categoryCount: [String: Int] = [:]

        for record in records {
            guard record.matchedCategoryKey == nil else { continue }
            categoryCount[record.categoryName, default: 0] += 1
        }

        return categoryCount
            .map { UnmatchedCategory(originalName: $0.key, occurrenceCount: $0.value) }
            .sorted { $0.occurrenceCount > $1.occurrenceCount }
    }

    /// 执行导入（批量插入 CoreData）
    func executeImport(
        records: [ImportBillRecord],
        invalidDateCount: Int = 0,
        batchId: UUID = UUID()
    ) async throws -> ImportBatch {
        var importedCount = 0
        var duplicateCount = 0
        var failedCount = 0

        var seenKeys = Set<ImportDeduplicationKey>()
        try viewContext.performAndWait {
            let existingTransactions = try viewContext.fetch(BookkeepingTransaction.fetchRequest())
            seenKeys = Set(existingTransactions.map { Self.transactionKey(for: $0) })
        }

        guard let coordinator = viewContext.persistentStoreCoordinator else {
            throw ImportError.persistenceUnavailable
        }
        let importContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        importContext.persistentStoreCoordinator = coordinator
        importContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        var importedObjectIDs: [NSManagedObjectID] = []
        let fundAccountKeys = Dictionary(uniqueKeysWithValues: records.map { ($0.id, matchFundAccount($0.fundAccountName)) })

        do {
            try importContext.performAndWait {
                let committedTransactions = try importContext.fetch(BookkeepingTransaction.fetchRequest())
                seenKeys.formUnion(committedTransactions.map { Self.transactionKey(for: $0) })

                for record in records {
                    guard let categoryKey = record.matchedCategoryKey else {
                        failedCount += 1
                        continue
                    }

                    let fundAccountKey = fundAccountKeys[record.id] ?? nil
                    let key = Self.transactionKey(for: record, categoryKey: categoryKey, fundAccountKey: fundAccountKey)
                    guard seenKeys.insert(key).inserted else {
                        duplicateCount += 1
                        continue
                    }

                    let tx = BookkeepingTransaction(
                        context: importContext,
                        amount: record.amount,
                        categoryKey: categoryKey,
                        subcategoryKey: record.matchedSubcategoryKey,
                        note: record.note,
                        date: record.date,
                        isIncome: record.isIncome,
                        fundAccountKey: fundAccountKey,
                        notInBudget: false,
                        billSource: "import:\(batchId.uuidString)",
                        merchantName: record.merchantName
                    )
                    importedObjectIDs.append(tx.objectID)
                    importedCount += 1
                }

                if importContext.hasChanges {
                    try importContext.save()
                }
            }
        } catch {
            importContext.performAndWait { importContext.rollback() }
            throw error
        }

        if !importedObjectIDs.isEmpty {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSInsertedObjectsKey: importedObjectIDs],
                into: [viewContext]
            )
        }

        return ImportBatch(
            id: batchId,
            fileName: "import_\(Date().formatted(as: "yyyyMMdd_HHmmss"))",
            importedAt: Date(),
            recordCount: records.count,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            failedCount: failedCount,
            invalidDateCount: invalidDateCount,
            autoCreatedCategoryCount: 0  // 由 ViewModel 单独跟踪
        )
    }

    nonisolated private static func transactionKey(for transaction: BookkeepingTransaction) -> ImportDeduplicationKey {
        Self.transactionKey(
            date: transaction.date,
            amount: transaction.normalizedAmount,
            isIncome: transaction.isIncome,
            categoryKey: transaction.categoryKey,
            subcategoryKey: transaction.subcategoryKey,
            fundAccountKey: transaction.fundAccountKey,
            note: transaction.note,
            merchant: transaction.merchantName
        )
    }

    nonisolated private static func transactionKey(
        for record: ImportBillRecord,
        categoryKey: String,
        fundAccountKey: String?
    ) -> ImportDeduplicationKey {
        Self.transactionKey(
            date: record.date,
            amount: record.amount,
            isIncome: record.isIncome,
            categoryKey: categoryKey,
            subcategoryKey: record.matchedSubcategoryKey,
            fundAccountKey: fundAccountKey,
            note: record.note,
            merchant: record.merchantName
        )
    }

    nonisolated private static func transactionKey(
        date: Date,
        amount: Double,
        isIncome: Bool,
        categoryKey: String,
        subcategoryKey: String?,
        fundAccountKey: String?,
        note: String?,
        merchant: String?
    ) -> ImportDeduplicationKey {
        func normalized(_ value: String?) -> String {
            (value ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
                .lowercased()
        }
        return ImportDeduplicationKey(
            minute: Int64(date.timeIntervalSince1970 / 60),
            amountInCents: {
                let scaled = (abs(amount) * 100).rounded()
                return scaled >= Double(Int64.max) ? Int64.max : Int64(scaled)
            }(),
            isIncome: isIncome,
            categoryKey: normalized(categoryKey),
            subcategoryKey: normalized(subcategoryKey),
            fundAccountKey: normalized(fundAccountKey),
            note: normalized(note),
            merchant: normalized(merchant)
        )
    }

    // MARK: - Export

    /// 导出为 xlsx
    func exportToXlsx(
        transactions: [BookkeepingTransaction],
        options: ExportOptions
    ) async throws -> URL {
        let generator = XlsxGenerator()

        let rows: [[String]] = transactions.map { tx in
            [
                tx.date.formatted(as: "yyyy-MM-dd HH:mm"),
                String(format: "%.2f", tx.amount),
                tx.isIncome ? "收入" : "支出",
                tx.categoryName,
                tx.subcategoryName ?? "",
                tx.note ?? "",
                tx.fundAccountKey.map { FundAccount.find(key: $0)?.name ?? "" } ?? "",
                tx.merchantName ?? "",
                tx.billSource ?? "",
                tx.createdAt.formatted(as: "yyyy-MM-dd HH:mm")
            ]
        }

        let headers = ["日期", "金额", "类型", "类别", "子类别", "备注", "账户", "商户", "来源", "创建时间"]

        return try await generator.generate(
            headers: headers,
            rows: rows,
            fileName: "账本导出_\(Date().formatted(as: "yyyyMMdd"))"
        )
    }

    // MARK: - Helpers

    private func detectFormat(fileName: String) -> ImportFileFormat {
        if fileName.lowercased().hasSuffix(".xlsx") { return .xlsx }
        if fileName.lowercased().hasSuffix(".xls") { return .xls }
        return .csv
    }

    private func findBestMatch(
        originalName: String,
        categories: [BookkeepingCategory]
    ) -> (category: BookkeepingCategory?, subcategory: BookkeepingSubcategory?, confidence: Float) {
        let lowercased = originalName.trimmingCharacters(in: .whitespaces).lowercased()

        // 精确匹配 category key
        for cat in categories {
            if cat.key.lowercased() == lowercased {
                return (cat, nil, 1.0)
            }
            if cat.localizedName.lowercased() == lowercased {
                return (cat, nil, 1.0)
            }
            // 模糊匹配
            if cat.localizedName.lowercased().contains(lowercased) || lowercased.contains(cat.localizedName.lowercased()) {
                return (cat, nil, 0.8)
            }
        }

        // 子类别匹配
        for cat in categories {
            for sub in cat.subcategories {
                if sub.key.lowercased() == lowercased { return (cat, sub, 1.0) }
                if sub.localizedName.lowercased() == lowercased { return (cat, sub, 1.0) }
            }
        }

        return (nil, nil, 0.0)
    }

    nonisolated private func matchFundAccount(_ name: String?) -> String? {
        guard let name = name else { return nil }
        let lowercased = name.lowercased()
        return FundAccount.all.first { $0.name.lowercased().contains(lowercased) }?.key
    }

    private func parseAmount(_ string: String?) -> Double? {
        guard var string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }

        string = string
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "−", with: "-")

        // Some exports represent negatives as "(123.45)".
        if string.hasPrefix("("), string.hasSuffix(")") {
            string = "-" + String(string.dropFirst().dropLast())
        }

        guard let amount = Double(string), amount.isFinite else { return nil }
        return amount
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        if let isoDate = isoDateFormatter.date(from: string) {
            return isoDate
        }
        return fractionalISODateFormatter.date(from: string)
    }
}

// MARK: - Column Mapping

struct ColumnMapping {
    var dateColumn: Int = 0
    var amountColumn: Int = 1
    var typeColumn: Int? = nil          // 可选：区分收入/支出
    var categoryColumn: Int = 2
    var subcategoryColumn: Int? = nil
    var noteColumn: Int? = nil
    var fundAccountColumn: Int? = nil
    var merchantColumn: Int? = nil
}

// MARK: - Export Options

struct ExportOptions {
    var dateRange: ClosedRange<Date>?
    var includeIncome: Bool = true
    var includeExpense: Bool = true
    var categoryFilter: Set<String>?
}

// MARK: - Import Error

enum ImportError: LocalizedError {
    case emptyFile
    case invalidFormat
    case persistenceUnavailable
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "文件为空"
        case .invalidFormat: return "不支持的文件格式"
        case .persistenceUnavailable: return "本地数据库当前不可用，账单没有导入。"
        case .parseError(let msg): return "解析错误: \(msg)"
        }
    }
}

// MARK: - Array Safe Access

private extension Array {
    subscript(safe index: Int?) -> Element? {
        guard let index = index, index >= 0, index < count else { return nil }
        return self[index]
    }
}
