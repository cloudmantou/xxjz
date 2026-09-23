import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct AssetImportExportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = AssetImportExportViewModel()

    init(initialTab: Int = 0) {
        _viewModel = StateObject(wrappedValue: AssetImportExportViewModel(initialTab: initialTab))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("功能", selection: $viewModel.selectedTab) {
                    Text("导入").tag(0)
                    Text("导出").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if viewModel.selectedTab == 0 {
                    importContent
                } else {
                    exportContent
                }

                Spacer()
            }
            .navigationTitle("资产导入导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $viewModel.showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await viewModel.handleFileSelected(url) }
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .alert("错误", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("确定") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("导入结果", isPresented: $viewModel.showImportResult) {
                Button("确定") { }
            } message: {
                Text(viewModel.importResultMessage)
            }
            .sheet(item: $viewModel.exportFileURL) { urlItem in
                ShareSheet(activityItems: [urlItem.url])
            }
        }
    }

    // MARK: - Import Content

    private var importContent: some View {
        VStack(spacing: 24) {
            // Template Download
            VStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.warmTeal)

                Text("下载模板，填写后导入")
                    .font(.headline)

                Text("模板包含示例数据，可直接修改使用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if let url = AssetImportExportService.templateURL {
                        viewModel.shareTemplate(url: url)
                    }
                } label: {
                    Label("下载 CSV 模板", systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.warmTeal)
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Import Button
            VStack(spacing: 12) {
                Button {
                    viewModel.showingFilePicker = true
                } label: {
                    Label("选择 CSV 文件导入", systemImage: "square.and.arrow.down.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.warmTeal)
                .disabled(viewModel.isImporting)

                if viewModel.isImporting {
                    ProgressView()
                    Text("正在导入...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Import History
            if !viewModel.importHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近导入")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(viewModel.importHistory, id: \.id) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.name)
                                    .font(.callout)
                                Text(record.date.mediumDateString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(record.count) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - Export Content

    private var exportContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.warmTeal)

                Text("导出全部资产为 CSV")
                    .font(.headline)

                Text("导出文件可在 Excel 或 Numbers 中打开")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.exportAssets()
                } label: {
                    if viewModel.isExporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Label("导出 CSV", systemImage: "square.and.arrow.up.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.warmTeal)
                .disabled(viewModel.isExporting || viewModel.assetCount == 0)

                if viewModel.assetCount == 0 {
                    Text("暂无资产数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("共 \(viewModel.assetCount) 条资产")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class AssetImportExportViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var showingFilePicker = false
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var errorMessage: String?
    @Published var showImportResult = false
    @Published var importResultMessage = ""
    @Published var exportFileURL: IdentifiableURL?
    @Published var importHistory: [ImportHistoryRecord] = []

    private let service = AssetImportExportService.shared

    init(initialTab: Int = 0) {
        selectedTab = initialTab
    }

    var assetCount: Int {
        service.assetCount
    }

    func handleFileSelected(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "无法访问文件"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        isImporting = true
        defer { isImporting = false }

        do {
            let records = try service.parseCSV(at: url)
            guard !records.isEmpty else {
                errorMessage = "文件中没有找到有效数据"
                return
            }

            let result = service.importRecords(records)
            importResultMessage = "成功导入 \(result.successCount) 条，失败 \(result.failedCount) 条"
            if !result.errors.isEmpty {
                importResultMessage += "\n" + result.errors.prefix(3).joined(separator: "\n")
                if result.errors.count > 3 {
                    importResultMessage += "\n...等 \(result.errors.count) 条错误"
                }
            }
            showImportResult = true

            // Save to history
            let historyRecord = ImportHistoryRecord(
                id: UUID(),
                name: url.lastPathComponent,
                date: Date(),
                count: result.successCount
            )
            importHistory.insert(historyRecord, at: 0)
            if importHistory.count > 10 { importHistory.removeLast() }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportAssets() {
        isExporting = true
        defer { isExporting = false }

        if let url = service.exportAllAssetsCSV() {
            exportFileURL = IdentifiableURL(url: url)
        } else {
            errorMessage = "导出失败，请稍后重试"
        }
    }

    func shareTemplate(url: URL) {
        exportFileURL = IdentifiableURL(url: url)
    }
}

struct ImportHistoryRecord: Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let count: Int
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    AssetImportExportView()
}
