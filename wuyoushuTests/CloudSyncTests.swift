import XCTest
import CoreData
import CloudKit
@testable import AssetLife

final class CloudSyncTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let networkError = CloudSyncState.Failure(domain: CKErrorDomain, code: CKError.networkFailure.rawValue, message: "网络不可用")

    func test_setupSuccessIsNotTransferSuccess() {
        var state = CloudSyncState()
        state.receive(id: UUID(), phase: .setup, start: start, end: start.addingTimeInterval(1), succeeded: true, failure: nil)
        XCTAssertFalse(state.hasCompletedTransfer)
    }

    func test_downloadSuccessCannotHideUploadFailure() {
        var state = CloudSyncState()
        state.receive(id: UUID(), phase: .upload, start: start, end: start.addingTimeInterval(1), succeeded: false, failure: networkError)
        state.receive(id: UUID(), phase: .download, start: start, end: start.addingTimeInterval(2), succeeded: true, failure: nil)
        XCTAssertEqual(state.failures, [networkError])
        XCTAssertNil(state.activities[.upload]?.lastSuccess)
        let retry = UUID()
        state.receive(id: retry, phase: .upload, start: start.addingTimeInterval(3), end: nil, succeeded: false, failure: nil)
        XCTAssertEqual(state.failures, [networkError], "A retry starting is not recovery")
        state.receive(id: retry, phase: .upload, start: start.addingTimeInterval(3), end: start.addingTimeInterval(4), succeeded: true, failure: nil)
        XCTAssertTrue(state.failures.isEmpty)
        XCTAssertNotNil(state.activities[.upload]?.lastSuccess)
    }

    func test_overlappingOperationsStayActiveUntilBothFinish() {
        var state = CloudSyncState()
        let first = UUID(), second = UUID()
        state.receive(id: first, phase: .upload, start: start, end: nil, succeeded: false, failure: nil)
        state.receive(id: second, phase: .upload, start: start.addingTimeInterval(1), end: nil, succeeded: false, failure: nil)
        state.receive(id: first, phase: .upload, start: start, end: start.addingTimeInterval(2), succeeded: true, failure: nil)
        XCTAssertTrue(state.isActive)
        state.receive(id: second, phase: .upload, start: start.addingTimeInterval(1), end: start.addingTimeInterval(3), succeeded: true, failure: nil)
        XCTAssertFalse(state.isActive)
    }

    func test_lateOlderSuccessDoesNotClearNewerFailure() {
        var state = CloudSyncState()
        state.receive(id: UUID(), phase: .upload, start: start.addingTimeInterval(1), end: start.addingTimeInterval(2), succeeded: false, failure: networkError)
        state.receive(id: UUID(), phase: .upload, start: start, end: start.addingTimeInterval(3), succeeded: true, failure: nil)
        XCTAssertEqual(state.failures, [networkError])
    }

    func test_failedCompletionWithoutErrorIsStillFailure() {
        var state = CloudSyncState()
        state.receive(id: UUID(), phase: .download, start: start, end: start, succeeded: false, failure: nil)
        XCTAssertEqual(state.failures.count, 1)
        XCTAssertFalse(state.hasCompletedTransfer)
    }

    @MainActor
    func test_localFallbackRemainsVisibleAndNeverQueriesCloud() {
        var calls = 0
        let monitor = CloudSyncMonitor(runtimeAvailable: true, accountProvider: { _ in calls += 1 })
        monitor.configure(requested: true, enabled: false, storeError: NSError(domain: NSCocoaErrorDomain, code: 134060))
        monitor.refreshAccountStatus()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(monitor.statusText(preference: true).contains("退回本地"))
        XCTAssertEqual(monitor.storeFailure?.code, 134060)
    }

    @MainActor
    func test_disabledTestRuntimeNeverInstantiatesCloudAccountProvider() {
        var calls = 0
        let monitor = CloudSyncMonitor(runtimeAvailable: false, accountProvider: { _ in calls += 1 })
        monitor.configure(requested: true, enabled: true, storeError: nil)
        monitor.refreshAccountStatus()
        XCTAssertFalse(monitor.isEnabled)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(monitor.statusText(preference: true).contains("此运行环境"))
    }

    @MainActor
    func test_preferenceChangeReportsPendingRestartInsteadOfSuccess() {
        let monitor = CloudSyncMonitor(runtimeAvailable: true, accountProvider: { _ in })
        monitor.configure(requested: false, enabled: false, storeError: nil)
        XCTAssertTrue(monitor.statusText(preference: true).contains("开启待重启"))
        monitor.configure(requested: true, enabled: true, storeError: nil)
        XCTAssertTrue(monitor.statusText(preference: false).contains("关闭待重启"))
    }

    @MainActor
    func test_availableAccountDoesNotClaimSyncedAndNoAccountIsActionable() async {
        var completion: ((CKAccountStatus, Error?) -> Void)?
        let monitor = CloudSyncMonitor(runtimeAvailable: true, accountProvider: { completion = $0 })
        monitor.configure(requested: true, enabled: true, storeError: nil)
        monitor.refreshAccountStatus()
        completion?(.available, nil)
        await drainMainQueue()
        XCTAssertTrue(monitor.statusText(preference: true).contains("尚无上传或下载成功记录"))
        monitor.refreshAccountStatus()
        completion?(.noAccount, nil)
        await drainMainQueue()
        XCTAssertEqual(monitor.statusText(preference: true), "未登录 iCloud")
    }

    @MainActor
    func test_accountChangeInvalidatesInFlightAccountCheck() async {
        let center = NotificationCenter()
        var callbacks: [(CKAccountStatus, Error?) -> Void] = []
        let monitor = CloudSyncMonitor(runtimeAvailable: true, center: center, accountProvider: { callbacks.append($0) })
        monitor.configure(requested: true, enabled: true, storeError: nil)
        monitor.refreshAccountStatus()
        center.post(name: .CKAccountChanged, object: nil)
        XCTAssertEqual(callbacks.count, 2)
        callbacks[1](.noAccount, nil)
        callbacks[0](.available, nil)
        await drainMainQueue()
        XCTAssertEqual(monitor.accountStatus, .noAccount)
    }

    func test_wrappedCloudErrorReportsSafeActionWithoutRecordDetails() {
        let inner = NSError(domain: CKErrorDomain, code: CKError.quotaExceeded.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "PRIVATE RECORD AND ACCOUNT"])
        let outer = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSUnderlyingErrorKey: inner])
        let failure = CloudSyncState.Failure.from(outer)
        XCTAssertEqual(failure.code, CKError.quotaExceeded.rawValue)
        XCTAssertTrue(failure.message.contains("空间不足"))
        XCTAssertFalse(failure.message.contains("PRIVATE"))
    }

    @MainActor
    func test_diagnosticsExcludeAccountAndRecordContents() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let monitor = CloudSyncMonitor(runtimeAvailable: true, diagnosticsURL: url, accountProvider: { _ in })
        monitor.configure(requested: true, enabled: false,
                          storeError: NSError(domain: CKErrorDomain, code: CKError.permissionFailure.rawValue,
                                              userInfo: [NSLocalizedDescriptionKey: "PRIVATE RECORD AND ACCOUNT"]))
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("PRIVATE"))
        XCTAssertTrue(text.contains("enabled"))
        XCTAssertTrue(text.contains(CKErrorDomain))
    }

    func test_historyTrackingRemainsEnabledWhenCloudIsOff() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("unused.sqlite")
        for enabled in [false, true] {
            let description = PersistenceController.makeStoreDescription(storeURL: url, inMemory: false, cloudSyncEnabled: enabled)
            XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
            XCTAssertEqual(description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
            XCTAssertEqual(description.cloudKitContainerOptions != nil, enabled)
        }
    }

    @MainActor
    func test_offlineStoreReopenPreservesTransactionsAndExportHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Ledger.sqlite")
        let model = PersistenceController(inMemory: true).container.managedObjectModel
        func open() throws -> NSPersistentContainer {
            let container = NSPersistentContainer(name: "AssetLife", managedObjectModel: model)
            container.persistentStoreDescriptions = [PersistenceController.makeStoreDescription(storeURL: url, inMemory: false, cloudSyncEnabled: false)]
            var failure: Error?
            container.loadPersistentStores { _, error in failure = error }
            if let failure { throw failure }
            return container
        }
        let first = try open()
        let transaction = NSEntityDescription.insertNewObject(forEntityName: "BookkeepingTransaction", into: first.viewContext)
        transaction.setValue(12.0, forKey: "amount")
        transaction.setValue("dining", forKey: "categoryKey")
        transaction.setValue(UUID(), forKey: "id")
        try first.viewContext.save()
        for store in first.persistentStoreCoordinator.persistentStores { try first.persistentStoreCoordinator.remove(store) }
        let second = try open()
        defer { for store in second.persistentStoreCoordinator.persistentStores { try? second.persistentStoreCoordinator.remove(store) } }
        XCTAssertEqual(try second.viewContext.count(for: BookkeepingTransaction.fetchRequest()), 1)
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
        let result = try XCTUnwrap(try second.viewContext.execute(request) as? NSPersistentHistoryResult)
        let history = try XCTUnwrap(result.result as? [NSPersistentHistoryTransaction])
        XCTAssertFalse(history.isEmpty)
        XCTAssertTrue(history.contains { ($0.changes?.count ?? 0) > 0 })
    }

    @MainActor
    func test_accountCheckTimeoutAllowsRetryAndIgnoresLateCallback() async throws {
        var callback: ((CKAccountStatus, Error?) -> Void)?
        let monitor = CloudSyncMonitor(runtimeAvailable: true, accountTimeout: 0.01, accountProvider: { callback = $0 })
        monitor.configure(requested: true, enabled: true, storeError: nil)
        monitor.refreshAccountStatus()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(monitor.isCheckingAccount)
        XCTAssertEqual(monitor.accountFailure?.code, -2)
        callback?(.available, nil)
        await drainMainQueue()
        XCTAssertNil(monitor.accountStatus)
        monitor.refreshAccountStatus()
        callback?(.available, nil)
        await drainMainQueue()
        XCTAssertEqual(monitor.accountStatus, .available)
        XCTAssertNil(monitor.accountFailure)
    }

    func test_appBundleEnablesBackgroundCloudNotifications() {
        XCTAssertTrue((Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String])?.contains("remote-notification") == true)
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
