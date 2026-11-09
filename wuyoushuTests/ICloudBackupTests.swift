import XCTest
import CoreData
@testable import AssetLife

private final class FakeBackupTransport: CloudBackupTransport {
    var account = "account-A"
    var items: [CloudBackupItem] = []
    var files: [String: Data] = [:]
    var uploads = 0, downloads = 0, deletes = 0
    var uploadFails = false
    var afterUpload: (() -> Void)?
    func accountIdentity() async throws -> String { account }
    func list() async throws -> [CloudBackupItem] { items }
    func upload(_ item: CloudBackupItem, file: URL) async throws {
        uploads += 1
        if uploadFails { throw CloudBackupError.unavailable }
        files[item.id] = try Data(contentsOf: file); items.append(item); afterUpload?()
    }
    func download(_ id: String) async throws -> Data { downloads += 1; return files[id] ?? Data() }
    func delete(_ id: String) async throws { deletes += 1; items.removeAll { $0.id == id }; files[id] = nil }
}

@MainActor
final class ICloudBackupTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "cloud-backup-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }; return defaults
    }
    private func context() throws -> NSManagedObjectContext {
        let c = NSPersistentContainer(name: "test", managedObjectModel: PersistenceController.makeModel(enableUniqueConstraints: false))
        let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType; c.persistentStoreDescriptions = [d]
        var failure: Error?; c.loadPersistentStores { _, e in failure = e }; if let failure { throw failure }
        // Retain container until teardown; context's coordinator survives independently too.
        addTeardownBlock { _ = c }; return c.viewContext
    }
    func test_successfulUploadCanBeValidatedAndDeletedWithoutTouchingSource() async throws {
        let context = try context(); let transport = FakeBackupTransport()
        let service = ICloudBackupService(transport: transport, defaults: try defaults())
        let data = try LocalBackupService.shared.exportBackup(from: context)
        let item = try await service.createBackup(data: data)
        let result = try await service.preview(item)
        XCTAssertEqual(result.formatVersion, 2); XCTAssertEqual(transport.uploads, 1)
        XCTAssertNotNil(service.lastBackupAt); XCTAssertEqual(service.backups.count, 1)
        try await service.delete(item); XCTAssertTrue(service.backups.isEmpty); XCTAssertFalse(context.hasChanges)
    }
    func test_failedUploadDoesNotAdvanceLastSuccess() async throws {
        let transport = FakeBackupTransport(); transport.uploadFails = true
        let service = ICloudBackupService(transport: transport, defaults: try defaults())
        do { try await service.createBackup(data: LocalBackupService.shared.exportBackup(from: context())); XCTFail("Expected failure") } catch {}
        XCTAssertNil(service.lastBackupAt); XCTAssertTrue(service.backups.isEmpty); XCTAssertFalse(service.isBusy)
    }
    func test_corruptedAssetIsRejectedBeforeRestore() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        let item = try await service.createBackup(data: LocalBackupService.shared.exportBackup(from: context()))
        transport.files[item.id] = Data("corrupt".utf8)
        do { _ = try await service.preview(item); XCTFail("Expected checksum failure") } catch {}
    }
    func test_accountSwitchRefusesStalePreviewAndDeletionBeforeSendingRequests() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        let item = try await service.createBackup(data: LocalBackupService.shared.exportBackup(from: context()))
        transport.account = "account-B"
        do { _ = try await service.preview(item); XCTFail("Expected account rejection") } catch {}
        do { try await service.delete(item); XCTFail("Expected stale item rejection") } catch {}
        XCTAssertEqual(transport.downloads, 0); XCTAssertEqual(transport.deletes, 0)
    }
    func test_accountSwitchAfterPreviewRejectsRestoreAndPreservesCurrentData() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        let context = try context()
        let tx = BookkeepingTransaction(context: context, amount: 40, categoryKey: "food"); try context.save()
        let item = try await service.createBackup(data: LocalBackupService.shared.exportBackup(from: context))
        let envelope = try await service.preview(item)
        tx.amount = 50; try context.save(); transport.account = "B"
        do { try await service.restorePreview(envelope, into: context); XCTFail("Expected account rejection") } catch {}
        XCTAssertEqual(tx.amount, 50); XCTAssertFalse(tx.isDeleted)
    }
    func test_accountSwitchDuringUploadDoesNotClaimSuccess() async throws {
        let transport = FakeBackupTransport(); transport.afterUpload = { transport.account = "B" }
        let service = ICloudBackupService(transport: transport, defaults: try defaults())
        do { try await service.createBackup(data: LocalBackupService.shared.exportBackup(from: context())); XCTFail("Expected account rejection") } catch {}
        XCTAssertNil(service.lastBackupAt); XCTAssertTrue(service.backups.isEmpty)
        transport.afterUpload = nil
    }
    func test_automaticBackupIsOptInAndOnceDaily() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        let context = try context(); let now = Date()
        await service.automaticBackupIfNeeded(from: context, now: now)
        XCTAssertEqual(transport.uploads, 0)
        await service.setAutomatic(true)
        await service.automaticBackupIfNeeded(from: context, now: now)
        await service.automaticBackupIfNeeded(from: context, now: now.addingTimeInterval(3600))
        XCTAssertEqual(transport.uploads, 1)
        await service.automaticBackupIfNeeded(from: context, now: now.addingTimeInterval(86401))
        XCTAssertEqual(transport.uploads, 2)
    }
    func test_automaticBackupPausesOnAccountSwitch() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        await service.setAutomatic(true); transport.account = "B"
        await service.automaticBackupIfNeeded(from: try context())
        XCTAssertFalse(service.automaticEnabled); XCTAssertEqual(transport.uploads, 0); XCTAssertNotNil(service.errorMessage)
    }
    func test_retentionLimitNeverAutomaticallyDeletesOldBackups() async throws {
        let transport = FakeBackupTransport(); let service = ICloudBackupService(transport: transport, defaults: try defaults())
        transport.items = (0..<20).map { CloudBackupItem(id: "\($0)", name: "backup", createdAt: Date(), byteCount: 0, checksum: "", formatVersion: 2) }
        await service.setAutomatic(true); await service.automaticBackupIfNeeded(from: try context())
        XCTAssertEqual(transport.uploads, 0); XCTAssertEqual(transport.deletes, 0); XCTAssertNotNil(service.errorMessage)
    }
    func test_otherStoreSuccessCannotClearSharedStoreFailure() {
        var state = CloudSyncState(); let now = Date()
        let failure = CloudSyncState.Failure(domain: "test", code: 1, message: "shared failed")
        state.receive(id: UUID(), phase: .upload, start: now, end: now, succeeded: false, failure: failure, storeIdentifier: "Shared")
        state.receive(id: UUID(), phase: .upload, start: now.addingTimeInterval(1), end: now, succeeded: true, failure: nil, storeIdentifier: "Private")
        XCTAssertEqual(state.failures, [failure])
        state.receive(id: UUID(), phase: .upload, start: now.addingTimeInterval(2), end: now, succeeded: true, failure: nil, storeIdentifier: "Shared")
        XCTAssertTrue(state.failures.isEmpty)
    }
}
