import Foundation
import CloudKit
import CoreData
import CryptoKit
import Combine

struct CloudBackupItem: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let createdAt: Date
    let byteCount: Int
    let checksum: String
    let formatVersion: Int
}

protocol CloudBackupTransport {
    func accountIdentity() async throws -> String
    func list() async throws -> [CloudBackupItem]
    func upload(_ item: CloudBackupItem, file: URL) async throws
    func download(_ id: String) async throws -> Data
    func delete(_ id: String) async throws
}

enum CloudBackupError: LocalizedError {
    case unavailable, invalidData, tooLarge, busy, accountChanged
    var errorDescription: String? {
        switch self {
        case .unavailable: return "请在真机上登录 iCloud，并允许小西记账使用 iCloud。"
        case .invalidData: return "备份校验失败，当前数据没有修改。"
        case .tooLarge: return "此备份超过 100 MB，请使用文件导出备份。"
        case .busy: return "已有备份任务正在处理，请稍候。"
        case .accountChanged: return "iCloud 账户已变化，自动备份已暂停，请在确认当前账户后重新开启。"
        }
    }
}

/// Dedicated private zone: never writes into Core Data's mirroring zones or CKShare zones.
final class CloudKitBackupTransport: CloudBackupTransport {
    static let zoneID = CKRecordZone.ID(zoneName: "XXJZBackups_v1", ownerName: CKCurrentUserDefaultName)
    private lazy var container = CKContainer(identifier: Constants.ICloud.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }
    private let recordType = "XXJZBackupSnapshot"
    private let fields = ["name", "createdAt", "byteCount", "checksum", "formatVersion"]
    func accountIdentity() async throws -> String {
        guard PersistenceController.cloudRuntimeAvailable else { throw CloudBackupError.unavailable }
        guard try await container.accountStatus() == .available else { throw CloudBackupError.unavailable }
        let id = try await container.userRecordID()
        return PreferenceJournal.hash(Data(id.recordName.utf8))
    }
    private func ensureZone() async throws {
        do { _ = try await database.recordZone(for: Self.zoneID) }
        catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            _ = try await database.save(CKRecordZone(zoneID: Self.zoneID))
        }
    }
    private func configure(_ operation: CKOperation) {
        operation.configuration.timeoutIntervalForRequest = 30
        operation.configuration.timeoutIntervalForResource = 120
        operation.qualityOfService = .userInitiated
    }
    func list() async throws -> [CloudBackupItem] {
        try await ensureZone()
        return try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.desiredKeys = fields
            let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [Self.zoneID], configurationsByRecordZoneID: [Self.zoneID: config])
            operation.fetchAllChanges = true
            let lock = NSLock()
            var records: [String: CloudBackupItem] = [:]
            var recordError: Error?
            operation.recordChangedBlock = { record in
                guard record.recordType == self.recordType,
                      let name = record["name"] as? String,
                      let date = record.creationDate ?? record["createdAt"] as? Date,
                      let bytes = record["byteCount"] as? NSNumber,
                      let checksum = record["checksum"] as? String,
                      let version = record["formatVersion"] as? NSNumber else { return }
                let item = CloudBackupItem(id: record.recordID.recordName, name: name, createdAt: date,
                    byteCount: bytes.intValue, checksum: checksum, formatVersion: version.intValue)
                lock.lock(); records[item.id] = item; lock.unlock()
            }
            operation.recordWithIDWasDeletedBlock = { id, _ in lock.lock(); records[id.recordName] = nil; lock.unlock() }
            operation.recordZoneFetchCompletionBlock = { _, _, _, _, error in
                if let error { lock.lock(); recordError = error; lock.unlock() }
            }
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                lock.lock(); let failure = error ?? recordError; let result = Array(records.values); lock.unlock()
                if let failure { continuation.resume(throwing: failure) }
                else { continuation.resume(returning: result.sorted { $0.createdAt > $1.createdAt }) }
            }
            configure(operation); database.add(operation)
        }
    }
    func upload(_ item: CloudBackupItem, file: URL) async throws {
        try await ensureZone()
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: item.id, zoneID: Self.zoneID))
        record["name"] = item.name as CKRecordValue; record["createdAt"] = item.createdAt as CKRecordValue
        record["byteCount"] = item.byteCount as CKRecordValue; record["checksum"] = item.checksum as CKRecordValue
        record["formatVersion"] = item.formatVersion as CKRecordValue; record["payload"] = CKAsset(fileURL: file)
        try await modify(saving: [record], deleting: [])
    }
    func download(_ id: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [CKRecord.ID(recordName: id, zoneID: Self.zoneID)])
            operation.desiredKeys = ["payload"]
            operation.fetchRecordsCompletionBlock = { records, error in
                if let error { continuation.resume(throwing: error); return }
                do {
                    guard let asset = records?.values.first?["payload"] as? CKAsset, let url = asset.fileURL else { throw CloudBackupError.invalidData }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard bytes <= ICloudBackupService.maximumBytes else { throw CloudBackupError.tooLarge }
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch { continuation.resume(throwing: error) }
            }
            configure(operation); database.add(operation)
        }
    }
    func delete(_ id: String) async throws {
        try await modify(saving: [], deleting: [CKRecord.ID(recordName: id, zoneID: Self.zoneID)])
    }
    private func modify(saving: [CKRecord], deleting: [CKRecord.ID]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: saving, recordIDsToDelete: deleting)
            operation.savePolicy = .ifServerRecordUnchanged; operation.isAtomic = true
            operation.modifyRecordsCompletionBlock = { _, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            configure(operation); database.add(operation)
        }
    }
}

@MainActor
final class ICloudBackupService: ObservableObject {
    static let shared = ICloudBackupService()
    nonisolated static let maximumBytes = 100 * 1024 * 1024
    @Published private(set) var backups: [CloudBackupItem] = []
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?
    @Published private(set) var automaticEnabled: Bool
    @Published private(set) var lastBackupAt: Date?
    private let transport: CloudBackupTransport
    private let defaults: UserDefaults
    private var visibleAccount: String?
    private var automaticInProgress = false
    private var previewIdentity: (account: String, envelopeID: String)?
    init(transport: CloudBackupTransport = CloudKitBackupTransport(), defaults: UserDefaults = .standard) {
        self.transport = transport; self.defaults = defaults
        automaticEnabled = defaults.bool(forKey: "cloudBackup.automatic")
        lastBackupAt = defaults.object(forKey: "cloudBackup.lastSuccess") as? Date
    }
    private func checkAccount() async throws -> String {
        let identity = try await transport.accountIdentity()
        if visibleAccount != identity {
            backups = []; visibleAccount = identity; previewIdentity = nil
            lastBackupAt = defaults.string(forKey: "cloudBackup.lastSuccessAccount") == identity
                ? defaults.object(forKey: "cloudBackup.lastSuccess") as? Date : nil
        }
        return identity
    }
    func refresh() async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let account = try await checkAccount()
            let result = try await transport.list()
            guard try await checkAccount() == account else { throw CloudBackupError.accountChanged }
            backups = result; errorMessage = nil
        }
        catch { report(error) }
    }
    @discardableResult
    func createBackup(data: Data, now: Date = Date()) async throws -> CloudBackupItem {
        guard !isBusy else { throw CloudBackupError.busy }
        guard data.count <= Self.maximumBytes else { throw CloudBackupError.tooLarge }
        let envelope = try LocalBackupService.shared.decodeAndValidate(data)
        isBusy = true; defer { isBusy = false }
        let account = try await checkAccount()
        let item = CloudBackupItem(id: UUID().uuidString, name: "小西记账完整备份", createdAt: now,
            byteCount: data.count, checksum: PreferenceJournal.hash(data), formatVersion: envelope.formatVersion)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        defer { try? FileManager.default.removeItem(at: file) }
        try await transport.upload(item, file: file)
        guard try await checkAccount() == account else { throw CloudBackupError.accountChanged }
        // Set success only after the server accepted the asset. Refresh failure must not
        // falsely label a successful upload as lost or cause duplicate auto uploads.
        lastBackupAt = now; defaults.set(now, forKey: "cloudBackup.lastSuccess")
        defaults.set(account, forKey: "cloudBackup.lastSuccessAccount")
        backups.insert(item, at: 0); errorMessage = nil
        return item
    }
    func preview(_ item: CloudBackupItem) async throws -> LocalBackupEnvelope {
        guard !isBusy else { throw CloudBackupError.busy }
        guard item.byteCount >= 0, item.byteCount <= Self.maximumBytes else { throw CloudBackupError.tooLarge }
        isBusy = true; defer { isBusy = false }
        let expectedAccount = visibleAccount
        let account = try await checkAccount()
        guard account == expectedAccount, backups.contains(where: { $0.id == item.id }) else { throw CloudBackupError.accountChanged }
        let data = try await transport.download(item.id)
        guard try await checkAccount() == account else { throw CloudBackupError.accountChanged }
        guard data.count == item.byteCount, PreferenceJournal.hash(data) == item.checksum else { throw CloudBackupError.invalidData }
        let envelope = try LocalBackupService.shared.decodeAndValidate(data)
        previewIdentity = (account, envelope.id)
        return envelope
    }
    func restorePreview(_ envelope: LocalBackupEnvelope, into context: NSManagedObjectContext) async throws {
        guard !isBusy else { throw CloudBackupError.busy }
        isBusy = true; defer { isBusy = false }
        let expected = previewIdentity
        let account = try await checkAccount()
        guard let expected, expected.account == account, expected.envelopeID == envelope.id else { throw CloudBackupError.accountChanged }
        try LocalBackupService.shared.restore(envelope, into: context)
        previewIdentity = nil
    }
    func delete(_ item: CloudBackupItem) async throws {
        guard !isBusy else { throw CloudBackupError.busy }
        isBusy = true; defer { isBusy = false }
        let expectedAccount = visibleAccount
        let account = try await checkAccount()
        guard account == expectedAccount, backups.contains(where: { $0.id == item.id }) else { throw CloudBackupError.accountChanged }
        try await transport.delete(item.id)
        guard try await checkAccount() == account else { throw CloudBackupError.accountChanged }
        backups.removeAll { $0.id == item.id }
    }
    func setAutomatic(_ enabled: Bool) async {
        if enabled {
            do { defaults.set(try await checkAccount(), forKey: "cloudBackup.automaticAccount") }
            catch { report(error); return }
        }
        automaticEnabled = enabled; defaults.set(enabled, forKey: "cloudBackup.automatic")
    }
    func automaticBackupIfNeeded(from context: NSManagedObjectContext, now: Date = Date()) async {
        guard automaticEnabled, !automaticInProgress, !isBusy, !context.hasChanges,
              now.timeIntervalSince(lastBackupAt ?? .distantPast) >= 86400,
              now.timeIntervalSince(defaults.object(forKey: "cloudBackup.lastAttempt") as? Date ?? .distantPast) >= 600 else { return }
        automaticInProgress = true; defer { automaticInProgress = false }
        defaults.set(now, forKey: "cloudBackup.lastAttempt")
        do {
            guard try await checkAccount() == defaults.string(forKey: "cloudBackup.automaticAccount") else {
                await setAutomatic(false); throw CloudBackupError.accountChanged
            }
            let existing = try await transport.list()
            guard existing.count < 20 else { errorMessage = "已保留 20 个云端备份。请手动管理旧版本后继续自动备份。"; return }
            guard !context.hasChanges else { return }
            let data = try LocalBackupService.shared.exportBackup(from: context)
            try await createBackup(data: data, now: now)
        } catch { report(error) }
    }
    func report(_ error: Error) {
        if let known = error as? CloudBackupError { errorMessage = known.localizedDescription }
        else if let known = error as? LocalBackupError { errorMessage = known.localizedDescription }
        else { errorMessage = CloudSyncState.Failure.from(error).message }
    }
}
