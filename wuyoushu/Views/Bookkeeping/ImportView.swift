import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ImportViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                switch viewModel.step {
                case .selectFile:
                    fileSelectSection
                case .preview:
                    previewSection
                case .matching:
                    matchingSection
                case .confirm:
                    confirmSection
                case .importing:
                    importingSection
                case .result:
                    resultSection
                }
            }
            .navigationTitle(viewModel.step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.step != .importing {
                        Button("取消") { dismiss() }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.step == .preview || viewModel.step == .matching {
                        Button("下一步") {
                            viewModel.nextStep()
                        }
                        .font(.body.weight(.semibold))
                        .disabled(!viewModel.canProceed)
                    }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showFilePicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(filenameExtension: "xls") ?? .data,
                    UTType(filenameExtension: "csv") ?? .commaSeparatedText,
                    .commaSeparatedText,
                    .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.handleFileSelected(url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("错误", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - File Select

    private var fileSelectSection: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(Color.warmTeal)

            VStack(spacing: 8) {
                Text("导入账单")
                    .font(.title2.bold())

                Text("支持 .xlsx、.xls、.csv 格式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: { viewModel.showFilePicker = true }) {
                    Label("选择文件", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.warmTeal)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                Text("支持微信、支付宝、银行等账单导出格式")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        VStack(spacing: 0) {
            // File info
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(viewModel.fileModel?.fileName ?? "")
                    .font(.subheadline)
                Spacer()
                Text("\(viewModel.fileModel?.rowCount ?? 0) 条")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.appPageBackground)

            // Column mapping
            VStack(alignment: .leading, spacing: 12) {
                Text("请指定每列对应的字段")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView {
                    VStack(spacing: 16) {
                        columnMappingRow(title: "日期 *", selection: $viewModel.dateColumnIndex, examples: viewModel.firstRow)
                        columnMappingRow(title: "金额 *", selection: $viewModel.amountColumnIndex, examples: viewModel.firstRow)
                        columnMappingRow(title: "类别 *", selection: $viewModel.categoryColumnIndex, examples: viewModel.firstRow)
                        columnMappingRow(title: "收支类型", selection: $viewModel.typeColumnIndex, examples: viewModel.firstRow, isOptional: true)
                        columnMappingRow(title: "子类别", selection: $viewModel.subcategoryColumnIndex, examples: viewModel.firstRow, isOptional: true)
                        columnMappingRow(title: "备注", selection: $viewModel.noteColumnIndex, examples: viewModel.firstRow, isOptional: true)
                        columnMappingRow(title: "账户", selection: $viewModel.fundAccountColumnIndex, examples: viewModel.firstRow, isOptional: true)
                        columnMappingRow(title: "商户", selection: $viewModel.merchantColumnIndex, examples: viewModel.firstRow, isOptional: true)
                    }
                    .padding()
                }
            }

            // Preview table
            Text("预览 (前5行)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                ForEach(Array(viewModel.previewRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            if colIndex == viewModel.dateColumnIndex ||
                               colIndex == viewModel.amountColumnIndex ||
                               colIndex == viewModel.categoryColumnIndex {
                                Text(cell)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: 200)
        }
    }

    private func columnMappingRow(title: String, selection: Binding<Int?>, examples: [String], isOptional: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .frame(width: 90, alignment: .leading)

            Picker("", selection: selection) {
                Text("未选择").tag(nil as Int?)
                ForEach(Array(examples.enumerated()), id: \.offset) { index, cell in
                    Text(cell.isEmpty ? "(空)" : String(cell.prefix(20)))
                        .tag(index as Int?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Matching

    private var matchingSection: some View {
        VStack(spacing: 0) {
            // Summary
            HStack {
                Label("\(viewModel.matchedCount) 已匹配", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
                Spacer()
                Label("\(viewModel.unmatchedCount) 待处理", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.appPageBackground)

            if !viewModel.unmatchedCategories.isEmpty {
                List {
                    Section(header: Text("以下类别将自动创建（也可手动指定）")) {
                        ForEach(viewModel.unmatchedCategories) { unmatched in
                            unmatchedCategoryRow(unmatched)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            if !viewModel.autoMatchedResults.isEmpty {
                List {
                    Section(header: Text("自动匹配结果")) {
                        ForEach(viewModel.autoMatchedResults.prefix(10), id: \.originalName) { result in
                            HStack {
                                Text(result.originalName)
                                    .font(.subheadline)
                                Spacer()
                                if let cat = result.matchedCategory {
                                    Text("\(cat.emoji) \(cat.localizedName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("未匹配")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func unmatchedCategoryRow(_ unmatched: UnmatchedCategoryDisplay) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(unmatched.originalName)
                    .font(.subheadline)
                Text("\(unmatched.occurrenceCount) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                ForEach(BookkeepingCategory.expenseCategories + BookkeepingCategory.incomeCategories) { cat in
                    Button("\(cat.emoji) \(cat.localizedName)") {
                        viewModel.setMapping(for: unmatched.originalName, categoryKey: cat.key)
                    }
                }
            } label: {
                HStack {
                    if let key = unmatched.matchedKey {
                        if let cat = BookkeepingCategory.find(key: key) {
                            Text("\(cat.emoji) \(cat.localizedName)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("选择类别")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
        }
    }

    // MARK: - Confirm

    private var confirmSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.warmTeal)

            VStack(spacing: 8) {
                Text("确认导入")
                    .font(.title2.bold())

                Text("将导入 \(viewModel.importableCount) 条账单记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if viewModel.invalidDateCount > 0 {
                    Text("另有 \(viewModel.invalidDateCount) 条日期无法识别，确认后会跳过。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text("类别已匹配")
                    Spacer()
                    Text("\(viewModel.matchedCount) 条")
                        .foregroundStyle(.green)
                }
                HStack {
                    Text("类别未匹配")
                    Spacer()
                    Text("\(viewModel.unmatchedCount) 条")
                        .foregroundStyle(viewModel.unmatchedCount > 0 ? .orange : .secondary)
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal, 32)

            Button(action: {
                Task {
                    await viewModel.executeImport()
                }
            }) {
                Text("确认导入")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.warmTeal)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Importing

    private var importingSection: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("正在导入...")
                .font(.headline)

            Text("请勿关闭应用")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(spacing: 20) {
            Spacer()

            if viewModel.importSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("导入完成")
                        .font(.title2.bold())

                    Text("成功导入 \(viewModel.importedCount) 条")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.duplicateCount > 0 {
                        Text("跳过重复记录 \(viewModel.duplicateCount) 条")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if viewModel.invalidDateCount > 0 {
                        Text("跳过日期无效记录 \(viewModel.invalidDateCount) 条")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if viewModel.failedCount > 0 {
                        Text("失败 \(viewModel.failedCount) 条（类别无法匹配）")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    if viewModel.autoCreatedCategoryCount > 0 {
                        Text("已自动创建 \(viewModel.autoCreatedCategoryCount) 个新分类")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text("导入失败")
                        .font(.title2.bold())

                    Text(viewModel.errorMessage ?? "未知错误")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.invalidDateCount > 0 {
                        Text("另有 \(viewModel.invalidDateCount) 条记录因日期无法识别而跳过。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Button(action: { dismiss() }) {
                Text("完成")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.warmTeal)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ImportViewModel: ObservableObject {
    enum Step: String {
        case selectFile = "导入账单"
        case preview = "预览数据"
        case matching = "类目匹配"
        case confirm = "确认导入"
        case importing = "导入中"
        case result = "导入结果"

        var title: String { rawValue }
    }

    @Published var step: Step = .selectFile
    @Published var showFilePicker = false
    @Published var errorMessage: String?

    @Published var fileModel: ImportFileModel?
    @Published var allRows: [[String]] = []
    @Published var firstRow: [String] = []
    @Published var previewRows: [[String]] = []

    // Column mapping
    @Published var dateColumnIndex: Int?
    @Published var amountColumnIndex: Int?
    @Published var typeColumnIndex: Int?          // 收支类型列（支出/收入）
    @Published var categoryColumnIndex: Int?
    @Published var subcategoryColumnIndex: Int?
    @Published var noteColumnIndex: Int?
    @Published var fundAccountColumnIndex: Int?
    @Published var merchantColumnIndex: Int?

    // Matching
    @Published var autoMatchedResults: [CategoryMatchResult] = []
    @Published var unmatchedCategories: [UnmatchedCategoryDisplay] = []
    @Published var userMappings: [String: String] = [:]  // originalName -> categoryKey

    // Result
    @Published var importSuccess = false
    @Published var importedCount = 0
    @Published var duplicateCount = 0
    @Published var failedCount = 0
    @Published var invalidDateCount = 0
    @Published var autoCreatedCategoryCount = 0  // 自动创建的新分类数量

    private let importService = ImportExportService.shared
    private var importRecords: [ImportBillRecord] = []

    var canProceed: Bool {
        switch step {
        case .preview:
            return dateColumnIndex != nil && amountColumnIndex != nil && categoryColumnIndex != nil
        case .matching:
            return true  // 未匹配的分类会在导入时自动创建，无需手动选择
        default:
            return true
        }
    }

    var matchedCount: Int {
        importRecords.filter { $0.matchedCategoryKey != nil }.count
    }

    var unmatchedCount: Int {
        importRecords.filter { $0.matchedCategoryKey == nil }.count
    }

    var importableCount: Int {
        matchedCount
    }

    func handleFileSelected(_ url: URL) {
        Task {
            do {
                // Try security-scoped access first (for sandboxed apps)
                var accessedSecurityScope = false
                if url.startAccessingSecurityScopedResource() {
                    accessedSecurityScope = true
                }

                defer {
                    if accessedSecurityScope {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                // Copy to temp file to ensure we can read it
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileName = url.lastPathComponent
                let tempUrl = tempDir.appendingPathComponent(tempFileName)

                // Remove existing temp file if present
                try? FileManager.default.removeItem(at: tempUrl)
                try FileManager.default.copyItem(at: url, to: tempUrl)

                let fileModel = try await importService.parseFile(at: tempUrl)
                self.fileModel = fileModel

                // Load file content
                let parser: FileParser = switch fileModel.detectedFormat {
                case .xlsx: XlsxParser()
                case .xls: XlsParser()
                case .csv: CsvParser()
                }

                let (columns, rows) = try await parser.parse(url: tempUrl)
                self.allRows = rows
                self.firstRow = columns
                self.previewRows = Array(rows.prefix(5))

                // Auto-detect columns
                autoDetectColumns(columns: columns, firstRow: rows.first ?? [])

                step = .preview
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func nextStep() {
        switch step {
        case .preview:
            prepareMatching()
            step = .matching
        case .matching:
            step = .confirm
        default:
            break
        }
    }

    func executeImport() async {
        step = .importing
        let originalCategoryIDs = Set(CustomCategoryStore.shared.categories.map(\.id))
        var newlyCreatedCategories: [CustomCategory] = []

        do {
            let mapping = ColumnMapping(
                dateColumn: dateColumnIndex!,
                amountColumn: amountColumnIndex!,
                typeColumn: typeColumnIndex,
                categoryColumn: categoryColumnIndex!,
                subcategoryColumn: subcategoryColumnIndex,
                noteColumn: noteColumnIndex,
                fundAccountColumn: fundAccountColumnIndex,
                merchantColumn: merchantColumnIndex
            )

            var records = importService.convertToBillRecords(rows: allRows, columnMapping: mapping)
            invalidDateCount = importService.invalidDateRowCount
            if records.isEmpty {
                let amountHeader: String = {
                    guard let idx = amountColumnIndex, idx >= 0, idx < firstRow.count else { return "未知列" }
                    return firstRow[idx]
                }()
                errorMessage = "未检测到可导入记录。当前金额列为「\(amountHeader)」，请确认选择的是实际“金额”而非“已退款金额”等辅助列。"
                importSuccess = false
                step = .result
                return
            }

            // Apply mappings
            for i in records.indices {
                if let mapping = userMappings[records[i].categoryName] {
                    records[i].matchedCategoryKey = mapping
                }
            }

            // Auto-match remaining
            let results = importService.autoMatchCategories(records: records)

            // Collect unmatched category names (separate by income/expense)
            var unmatchedExpenseNames: [String] = []
            var unmatchedIncomeNames: [String] = []
            for (i, result) in results.enumerated() {
                if records[i].matchedCategoryKey == nil {
                    if let key = result.matchedCategory?.key {
                        records[i].matchedCategoryKey = key
                        records[i].matchedSubcategoryKey = result.matchedSubcategory?.key
                    } else {
                        // 收集未匹配的分类名，按收支类型分组
                        if !records[i].categoryName.isEmpty {
                            if records[i].isIncome {
                                unmatchedIncomeNames.append(records[i].categoryName)
                            } else {
                                unmatchedExpenseNames.append(records[i].categoryName)
                            }
                        }
                    }
                }
            }

            // 自动为未匹配的分类创建自定义分类
            var createdMappings: [String: String] = [:]
            if !unmatchedExpenseNames.isEmpty {
                let uniqueNames = Array(Set(unmatchedExpenseNames))
                let mappings = importService.autoCreateCategoriesForUnmatched(
                    unmatchedNames: uniqueNames,
                    isIncome: false
                )
                createdMappings.merge(mappings) { _, new in new }
            }
            if !unmatchedIncomeNames.isEmpty {
                let uniqueNames = Array(Set(unmatchedIncomeNames))
                let mappings = importService.autoCreateCategoriesForUnmatched(
                    unmatchedNames: uniqueNames,
                    isIncome: true
                )
                createdMappings.merge(mappings) { _, new in new }
            }

            // 跟踪自动创建的分类数量
            autoCreatedCategoryCount = createdMappings.count
            newlyCreatedCategories = CustomCategoryStore.shared.categories.filter { !originalCategoryIDs.contains($0.id) }

            // 将新创建的分类映射到记录
            for (i, record) in records.enumerated() {
                if record.matchedCategoryKey == nil,
                   let newKey = createdMappings[record.categoryName] {
                    records[i].matchedCategoryKey = newKey
                }
            }

            let batch = try await importService.executeImport(
                records: records,
                invalidDateCount: invalidDateCount
            )

            importedCount = batch.importedCount
            duplicateCount = batch.duplicateCount
            failedCount = batch.failedCount
            importSuccess = true
            step = .result
        } catch {
            for category in newlyCreatedCategories {
                CustomCategoryStore.shared.delete(category)
            }
            errorMessage = error.localizedDescription
            importSuccess = false
            step = .result
        }
    }

    private func autoDetectColumns(columns: [String], firstRow: [String]) {
        for (index, header) in columns.enumerated() {
            let lower = normalizedHeader(header)

            if typeColumnIndex == nil && (lower == "类型" || lower.contains("收支类型") || lower == "type") {
                typeColumnIndex = index
            } else if dateColumnIndex == nil && (lower.contains("日期") || lower.contains("date") || lower.contains("时间")) {
                dateColumnIndex = index
            } else if amountColumnIndex == nil && (
                lower == "金额" ||
                lower == "amount" ||
                ((lower.contains("金额") || lower.contains("amount") || lower.contains("钱") || lower.contains("数目")) &&
                    !lower.contains("退款") &&
                    !lower.contains("已退"))
            ) {
                amountColumnIndex = index
            } else if categoryColumnIndex == nil && (
                lower == "分类" ||
                lower == "类别" ||
                (lower.contains("category") && !lower.contains("sub"))
            ) {
                categoryColumnIndex = index
            } else if subcategoryColumnIndex == nil && (lower.contains("子类别") || lower.contains("子分类") || lower.contains("sub")) {
                subcategoryColumnIndex = index
            } else if noteColumnIndex == nil && (lower.contains("备注") || lower.contains("note") || lower.contains("描述")) {
                noteColumnIndex = index
            } else if fundAccountColumnIndex == nil && (lower.contains("账户") || lower.contains("account") || lower.contains("钱包")) {
                fundAccountColumnIndex = index
            } else if merchantColumnIndex == nil && (lower.contains("商户") || lower.contains("merchant") || lower.contains("商家")) {
                merchantColumnIndex = index
            }
        }
    }

    private func normalizedHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func prepareMatching() {
        let mapping = ColumnMapping(
            dateColumn: dateColumnIndex!,
            amountColumn: amountColumnIndex!,
            typeColumn: typeColumnIndex,
            categoryColumn: categoryColumnIndex!,
            subcategoryColumn: subcategoryColumnIndex,
            noteColumn: noteColumnIndex,
            fundAccountColumn: fundAccountColumnIndex,
            merchantColumn: merchantColumnIndex
        )

        importRecords = importService.convertToBillRecords(rows: allRows, columnMapping: mapping)
        invalidDateCount = importService.invalidDateRowCount
        autoMatchedResults = importService.autoMatchCategories(records: importRecords)

        // 将自动匹配结果写回 importRecords，避免已匹配的项出现在待处理列表
        for (i, result) in autoMatchedResults.enumerated() {
            if let key = result.matchedCategory?.key {
                importRecords[i].matchedCategoryKey = key
                importRecords[i].matchedSubcategoryKey = result.matchedSubcategory?.key
            }
        }

        // Build unmatched list（仅包含真正未匹配的）
        let unmatched = importService.collectUnmatchedCategories(records: importRecords)
        unmatchedCategories = unmatched.map { um in
            UnmatchedCategoryDisplay(
                originalName: um.originalName,
                occurrenceCount: um.occurrenceCount,
                matchedKey: nil
            )
        }
    }

    func setMapping(for originalName: String, categoryKey: String) {
        if let index = unmatchedCategories.firstIndex(where: { $0.originalName == originalName }) {
            unmatchedCategories[index].matchedKey = categoryKey
            userMappings[originalName] = categoryKey
        }
    }
}

struct UnmatchedCategoryDisplay: Identifiable {
    let originalName: String
    let occurrenceCount: Int
    var matchedKey: String?
    var id: String { originalName }
}

#Preview {
    ImportView()
}
