import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct PersistentStoreRecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.package] }

    private let fileContents: [String: Data]
    private let preferredFilename: String

    init(storeURL: URL) throws {
        var fileContents: [String: Data] = [:]
        var manifest: [String: String] = [:]

        for suffix in ["", "-wal", "-shm", "-journal"] {
            let sourceURL = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            let name = sourceURL.lastPathComponent
            fileContents[name] = data
            manifest[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        guard fileContents[storeURL.lastPathComponent] != nil else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let manifestData = try JSONSerialization.data(
            withJSONObject: ["formatVersion": 1, "sha256": manifest],
            options: [.prettyPrinted, .sortedKeys]
        )
        fileContents["manifest.json"] = manifestData
        self.fileContents = fileContents
        preferredFilename = "小西记账存储恢复包.xijzrecovery"
    }

    init(configuration: ReadConfiguration) throws {
        guard let wrappers = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }
        fileContents = wrappers.compactMapValues(\.regularFileContents)
        preferredFilename = configuration.file.preferredFilename ?? "小西记账存储恢复包.xijzrecovery"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let wrappers = fileContents.mapValues { FileWrapper(regularFileWithContents: $0) }
        let root = FileWrapper(directoryWithFileWrappers: wrappers)
        root.preferredFilename = preferredFilename
        return root
    }
}

struct PersistenceRecoveryView: View {
    @ObservedObject var controller: PersistenceController
    @State private var recoveryDocument: PersistentStoreRecoveryDocument?
    @State private var isExporting = false
    @State private var recoveryMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(.orange)

            Text("本地数据暂时无法打开")
                .font(.title2.bold())

            Text(controller.loadFailure ?? "请重试，或先导出原始存储文件以保留恢复线索。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            Button("重试加载") {
                controller.retryStoreLoad()
            }
            .buttonStyle(.borderedProminent)

            Button("导出原始存储恢复包") {
                do {
                    guard let storeURL = controller.storeURL else {
                        throw CocoaError(.fileReadNoSuchFile)
                    }
                    recoveryDocument = try PersistentStoreRecoveryDocument(storeURL: storeURL)
                    isExporting = true
                } catch {
                    recoveryMessage = error.localizedDescription
                }
            }
            .buttonStyle(.bordered)

            Text("恢复包保留现有 SQLite、WAL 与 SHM 文件，不会删除或重建原数据库。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appPageBackground.ignoresSafeArea())
        .fileExporter(
            isPresented: $isExporting,
            document: recoveryDocument,
            contentType: .package,
            defaultFilename: "小西记账存储恢复包"
        ) { result in
            if case .failure(let error) = result {
                recoveryMessage = error.localizedDescription
            }
        }
        .alert("恢复包导出", isPresented: Binding(
            get: { recoveryMessage != nil },
            set: { if !$0 { recoveryMessage = nil } }
        )) {
            Button("好", role: .cancel) { recoveryMessage = nil }
        } message: {
            Text(recoveryMessage ?? "")
        }
    }
}
