import SwiftUI
import CoreData

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ExportViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isExporting {
                    exportingSection
                } else if let url = viewModel.exportedFileURL {
                    resultSection(fileURL: url)
                } else {
                    optionsSection
                }
            }
            .navigationTitle("导出账单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !viewModel.isExporting && viewModel.exportedFileURL == nil {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Options

    private var optionsSection: some View {
        List {
            Section(header: Text("日期范围")) {
                Toggle("全部时间", isOn: $viewModel.exportAllTime)

                if !viewModel.exportAllTime {
                    DatePicker("开始日期", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $viewModel.endDate, displayedComponents: .date)
                }
            }

            Section(header: Text("记录类型")) {
                Toggle("支出", isOn: $viewModel.includeExpense)
                Toggle("收入", isOn: $viewModel.includeIncome)
            }

            Section(header: Text("导出格式")) {
                Picker("格式", selection: $viewModel.exportFormat) {
                    Text("Excel (.xlsx)").tag(ExportFormat.xlsx)
                    Text("CSV").tag(ExportFormat.csv)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button(action: {
                    Task { await viewModel.exportTransactions() }
                }) {
                    HStack {
                        Spacer()
                        Label("导出", systemImage: "square.and.arrow.up")
                            .font(.headline)
                        Spacer()
                    }
                }
                .disabled(!viewModel.canExport)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Exporting

    private var exportingSection: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("正在导出...")
                .font(.headline)

            Text("共 \(viewModel.transactionCount) 条记录")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Result

    private func resultSection(fileURL: URL) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("导出成功")
                    .font(.title2.bold())

                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(action: { shareFile(url: fileURL) }) {
                    Label("分享文件", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.warmTeal)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                Button(action: { dismiss() }) {
                    Text("完成")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - ViewModel

enum ExportFormat {
    case xlsx
    case csv
}

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var exportAllTime = true
    @Published var startDate = Date().addingTimeInterval(-365 * 24 * 3600)
    @Published var endDate = Date()

    @Published var includeExpense = true
    @Published var includeIncome = true
    @Published var exportFormat: ExportFormat = .xlsx

    @Published var isExporting = false
    @Published var exportedFileURL: URL?
    @Published var errorMessage: String?
    @Published var transactionCount = 0

    private let importService = ImportExportService.shared
    private let context = PersistenceController.shared.container.viewContext

    var canExport: Bool {
        includeExpense || includeIncome
    }

    func exportTransactions() async {
        isExporting = true

        do {
            let options = ExportOptions(
                dateRange: exportAllTime ? nil : startDate...endDate,
                includeIncome: includeIncome,
                includeExpense: includeExpense,
                categoryFilter: nil
            )

            let transactions = try fetchTransactions(options: options)
            transactionCount = transactions.count

            guard !transactions.isEmpty else {
                errorMessage = "没有可导出的记录"
                isExporting = false
                return
            }

            let url: URL
            switch exportFormat {
            case .xlsx:
                url = try await importService.exportToXlsx(transactions: transactions, options: options)
            case .csv:
                url = try await exportToCsv(transactions: transactions)
            }

            exportedFileURL = url
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }

    private func fetchTransactions(options: ExportOptions) throws -> [BookkeepingTransaction] {
        let request: NSFetchRequest<BookkeepingTransaction> = BookkeepingTransaction.fetchRequest()

        var predicates: [NSPredicate] = []

        if let range = options.dateRange {
            let startDate = range.lowerBound as NSDate
            let endDate = range.upperBound as NSDate
            predicates.append(NSPredicate(format: "date >= %@ AND date <= %@", startDate, endDate))
        }

        if options.includeExpense && !options.includeIncome {
            predicates.append(NSPredicate(format: "isIncome == NO AND categoryKey != %@", "transfer"))
        } else if options.includeIncome && !options.includeExpense {
            predicates.append(NSPredicate(format: "isIncome == YES AND categoryKey != %@", "transfer"))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \BookkeepingTransaction.date, ascending: false)
        ]

        let result: [BookkeepingTransaction] = try context.fetch(request)
        return result
    }

    private func exportToCsv(transactions: [BookkeepingTransaction]) async throws -> URL {
        var csv = "日期,金额,类型,类别,子类别,备注,账户,商户,来源,创建时间\n"

        for tx in transactions {
            let dateStr = tx.date.formatted(as: "yyyy-MM-dd HH:mm")
            let amountStr = String(format: "%.2f", tx.amount)
            let typeStr: String
            switch tx.kind {
            case .income: typeStr = "收入"
            case .expense: typeStr = "支出"
            case .transfer: typeStr = "转账"
            }
            let categoryStr = tx.categoryName
            let subcategoryStr = tx.subcategoryName ?? ""
            let noteStr = tx.note ?? ""
            let accountStr: String
            if let key = tx.fundAccountKey {
                accountStr = FundAccount.find(key: key)?.name ?? ""
            } else {
                accountStr = ""
            }
            let merchantStr = tx.merchantName ?? ""
            let billSourceStr = tx.billSource ?? ""
            let createdAtStr = tx.createdAt.formatted(as: "yyyy-MM-dd HH:mm")

            let row = [
                dateStr,
                amountStr,
                typeStr,
                categoryStr,
                subcategoryStr,
                noteStr,
                accountStr,
                merchantStr,
                billSourceStr,
                createdAtStr
            ]
            .map { "\"\($0)\"" }
            .joined(separator: ",")

            csv += row + "\n"
        }

        let fileName = "账本导出_\(Date().formatted(as: "yyyyMMdd")).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csv.write(to: url, atomically: true, encoding: .utf8)

        return url
    }
}

#Preview {
    ExportView()
}
