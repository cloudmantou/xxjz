import SwiftUI
import UniformTypeIdentifiers
import CoreData

struct LocalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct LocalBackupView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var document: LocalBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingRestore: LocalBackupEnvelope?
    @State private var showsRestoreConfirmation = false
    @State private var alertTitle = ""
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section("完整本地备份") {
                Text("备份文件包含账单、预算、资产及维护和出售记录、心愿单及价格历史、自定义分类和规则。文件保存在你选择的位置，不依赖服务器。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    exportBackup()
                } label: {
                    Label("导出完整备份", systemImage: "square.and.arrow.up")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("选择备份并预览", systemImage: "square.and.arrow.down")
                }
            }

            if let pendingRestore {
                Section("备份预览") {
                    previewRow("导出时间", pendingRestore.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    previewRow("账单", "\(pendingRestore.transactionCount)")
                    previewRow("预算", "\(pendingRestore.budgetCount)")
                    previewRow("资产 / 维护 / 出售", "\(pendingRestore.assetCount) / \(pendingRestore.payload.assets.reduce(0) { $0 + $1.extraCosts.count }) / \(pendingRestore.payload.assets.reduce(0) { $0 + $1.saleRecords.count })")
                    previewRow("心愿 / 价格记录", "\(pendingRestore.wishlistCount) / \(pendingRestore.wishHistoryCount)")
                    previewRow("自定义分类 / 规则", "\(pendingRestore.customCategoryCount) / \(pendingRestore.customRuleCount)")
                    previewRow("SHA-256", String(pendingRestore.payloadSHA256.prefix(16)) + "…")
                        .font(.caption.monospaced())

                    Button("恢复此备份", role: .destructive) {
                        showsRestoreConfirmation = true
                    }
                }
            }

            Section {
                Text("恢复会完整替换当前设备中的账单、预算、资产、心愿单、自定义分类和规则。请先导出当前数据作为回退备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("完整数据备份")
        .fileExporter(
            isPresented: $isExporting,
            document: document,
            contentType: .json,
            defaultFilename: "小西记账完整备份-\(Date().formatted(as: "yyyyMMdd-HHmmss"))"
        ) { result in
            switch result {
            case .success:
                showAlert(title: "备份已导出", message: "完整本地备份文件已保存。")
            case .failure(let error):
                showAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .confirmationDialog(
            "用此备份覆盖当前全部本地数据？",
            isPresented: $showsRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("覆盖并恢复", role: .destructive) {
                restoreBackup()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复后，当前账单、预算、资产、心愿单、自定义分类和规则将被备份内容替换。")
        }
        .alert(alertTitle, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }

    private func exportBackup() {
        do {
            let data = try LocalBackupService.shared.exportBackup(from: context)
            document = LocalBackupDocument(data: data)
            isExporting = true
        } catch {
            showAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let data = try Data(contentsOf: url)
            pendingRestore = try LocalBackupService.shared.decodeAndValidate(data)
        } catch {
            showAlert(title: "无法读取备份", message: error.localizedDescription)
        }
    }

    private func restoreBackup() {
        guard let pendingRestore else { return }
        do {
            try LocalBackupService.shared.restore(pendingRestore, into: context)
            self.pendingRestore = nil
            showAlert(title: "恢复完成", message: "本地数据已从备份恢复。")
        } catch {
            showAlert(title: "恢复失败", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
    }
}
