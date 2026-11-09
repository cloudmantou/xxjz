import Foundation
import CoreData
import CloudKit
import SwiftUI
import UIKit

struct LedgerArchive: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var ledger: LocalBackupLedger
    var transactions: [LedgerRevision]
    var budgets: [LocalBackupBudget]
    var activities: [LocalBackupLedgerActivity]

    static func capture(_ ledger: Ledger, in context: NSManagedObjectContext) throws -> LedgerArchive {
        let scope = LedgerStore.shared.scope(for: ledger)
        let txRequest = BookkeepingTransaction.fetchRequest(); scope.apply(txRequest, includesDeleted: true)
        let budgetRequest = BudgetEntry.fetchRequest(); scope.apply(budgetRequest, includesDeleted: true)
        let activityRequest = LedgerActivity.fetchRequest()
        activityRequest.predicate = NSPredicate(format: "ledgerRaw == %@", ledger)
        let info = LocalBackupLedger(id: ledger.id, name: ledger.name, emoji: ledger.emoji, currencyCode: ledger.currencyCode,
            createdAt: ledger.createdAt, archived: ledger.archived, targetCents: ledger.targetCents, targetDate: ledger.targetDate, wasShared: true)
        return LedgerArchive(id: UUID(), createdAt: Date(), ledger: info,
            transactions: try context.fetch(txRequest).map { LedgerRevision($0) },
            budgets: try context.fetch(budgetRequest).map { LocalBackupBudget(id: $0.id, categoryKey: $0.categoryKey,
                monthlyAmount: $0.monthlyAmount, month: $0.month, createdAt: $0.createdAt, ledgerID: ledger.id, isTrashed: $0.isTrashed) },
            activities: try context.fetch(activityRequest).map { LocalBackupLedgerActivity(id: $0.id, ledgerID: ledger.id,
                targetID: $0.targetID, date: $0.date, author: $0.author, action: $0.action, snapshot: $0.snapshot) })
    }

    /// Shared permissions are never restored from a file; a copy is always private with new IDs.
    @discardableResult
    func restorePersonalCopy(in context: NSManagedObjectContext, store: NSPersistentStore) throws -> Ledger {
        guard !context.hasChanges else { throw LedgerError.unavailable }
        do {
            let copy = Ledger(context: context); context.assign(copy, to: store)
            copy.id = UUID(); copy.name = String(ledger.name.prefix(30)) + "（个人副本）"
            copy.emoji = ledger.emoji; copy.currencyCode = ledger.currencyCode; copy.createdAt = Date()
            copy.targetCents = ledger.targetCents; copy.targetDate = ledger.targetDate; copy.archived = false
            var idMap: [UUID: UUID] = [:]
            for var snapshot in transactions {
                let originalID = snapshot.id; snapshot.id = UUID(); idMap[originalID] = snapshot.id
                let tx = BookkeepingTransaction(context: context, amount: snapshot.amount, categoryKey: snapshot.categoryKey)
                context.assign(tx, to: store); snapshot.apply(to: tx); tx.ledgerRaw = copy
            }
            for snapshot in budgets {
                let budget = BudgetEntry(context: context, categoryKey: snapshot.categoryKey, monthlyAmount: snapshot.monthlyAmount,
                    month: snapshot.month, createdAt: snapshot.createdAt)
                context.assign(budget, to: store); budget.ledgerRaw = copy; budget.isTrashed = snapshot.isTrashed ?? false
            }
            for snapshot in activities {
                let activity = LedgerActivity(context: context); context.assign(activity, to: store)
                activity.id = UUID(); activity.ledgerRaw = copy; activity.targetID = idMap[snapshot.targetID] ?? snapshot.targetID
                activity.author = snapshot.author; activity.date = snapshot.date; activity.action = snapshot.action
                if let data = snapshot.snapshot, var revision = try? JSONDecoder().decode(LedgerRevision.self, from: data) {
                    revision.id = idMap[revision.id] ?? revision.id
                    activity.snapshot = try JSONEncoder().encode(revision)
                } else { activity.snapshot = snapshot.snapshot }
            }
            try context.save()
            return copy
        } catch { context.rollback(); throw error }
    }
}

struct LedgerSharingSession: Identifiable {
    let id = UUID()
    let ledgerID: NSManagedObjectID
    let share: CKShare
    let cloudContainer: CKContainer
    let store: NSPersistentStore
    let archive: LedgerArchive
}

@MainActor
final class LedgerSharingService: ObservableObject {
    static let shared = LedgerSharingService()
    @Published var message: String?
    @Published private(set) var isAccepting = false
    private var preparingLedgers: Set<NSManagedObjectID> = []
    private var pendingShares: Set<CKRecord.ID> = []
    private var stoppedSessions: Set<UUID> = []
    static var archiveDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SharedLedgerSafetyCopies", isDirectory: true)
    }

    func prepare(_ ledger: Ledger) async throws -> LedgerSharingSession {
        guard preparingLedgers.insert(ledger.objectID).inserted else { throw LedgerError.unavailable }
        defer { preparingLedgers.remove(ledger.objectID) }
        let persistence = PersistenceController.shared
        guard persistence.bookkeepingCloudSyncEnabled, PersistenceController.cloudRuntimeAvailable,
              let store = ledger.objectID.persistentStore else { throw LedgerError.cloudUnavailable }
        guard !ledger.isPersonalDefault else { throw LedgerError.defaultNotShareable }
        guard !ledger.isDeleted, !ledger.archived, !persistence.container.viewContext.hasChanges else { throw LedgerError.unavailable }
        let archive = try LedgerArchive.capture(ledger, in: persistence.container.viewContext)
        try saveSafetyCopy(archive)
        let cloud = CKContainer(identifier: Constants.ICloud.containerIdentifier)
        if let existing = try persistence.container.fetchShares(matching: [ledger.objectID])[ledger.objectID] {
            return LedgerSharingSession(ledgerID: ledger.objectID, share: existing, cloudContainer: cloud, store: store, archive: archive)
        }
        let share: CKShare = try await withCheckedThrowingContinuation { continuation in
            let completion = LedgerCloudCompletion<CKShare>(continuation)
            persistence.container.share([ledger], to: nil) { _, share, _, error in
                if let error { completion.finish(.failure(error)) }
                else if let share { completion.finish(.success(share)) }
                else { completion.finish(.failure(LedgerError.unavailable)) }
            }
        }
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.title] = ledger.name as CKRecordValue
        try await persist(share, in: store)
        return LedgerSharingSession(ledgerID: ledger.objectID, share: share, cloudContainer: cloud, store: store, archive: archive)
    }

    func accept(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == Constants.ICloud.containerIdentifier else { return }
        guard !pendingShares.contains(metadata.share.recordID) else { return }
        let persistence = PersistenceController.shared
        guard persistence.bookkeepingCloudSyncEnabled, let store = LedgerStore.shared.sharedStore else {
            message = "请开启 iCloud 同步并重启 App，再次打开邀请链接。"; return
        }
        pendingShares.insert(metadata.share.recordID); isAccepting = true
        persistence.container.acceptShareInvitations(from: [metadata], into: store) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.pendingShares.remove(metadata.share.recordID); self.isAccepting = !self.pendingShares.isEmpty
                if let error { self.message = CloudSyncState.Failure.from(error).message }
                else {
                    LedgerStore.shared.refresh()
                    self.message = "已接受邀请。系统下载完成后，共享账本会出现在账本列表中。"
                }
            }
        }
    }

    func persist(_ share: CKShare, in store: NSPersistentStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = LedgerCloudCompletion<Void>(continuation)
            PersistenceController.shared.container.persistUpdatedShare(share, in: store) { _, error in
                completion.finish(error.map { .failure($0) } ?? .success(()))
            }
        }
        LedgerStore.shared.refresh()
    }

    func stopped(_ session: LedgerSharingSession) {
        guard stoppedSessions.insert(session.id).inserted else { return }
        let store = LedgerStore.shared
        guard let privateStore = store.privateStore, let context = store.container?.viewContext else { return }
        do {
            // Prefer all data visible at stop time; retain the durable pre-management snapshot
            // when the framework has already removed the shared graph.
            let archive: LedgerArchive
            if let ledger = try? context.existingObject(with: session.ledgerID) as? Ledger, !ledger.isDeleted {
                archive = try LedgerArchive.capture(ledger, in: context)
                try saveSafetyCopy(archive)
            } else { archive = session.archive }
            _ = try archive.restorePersonalCopy(in: context, store: privateStore)
            PersistenceController.shared.container.purgeObjectsAndRecordsInZone(with: session.share.recordID.zoneID,
                in: session.store) { _, error in
                Task { @MainActor in
                    store.refresh()
                    self.message = error == nil ? "已停止共享，并保留个人副本。" : "个人副本已保留。共享状态仍在更新，请稍后检查。"
                }
            }
        } catch {
            message = "共享安全副本已保留，请在账本管理中的「共享安全副本」恢复。"
        }
    }
    private func saveSafetyCopy(_ archive: LedgerArchive) throws {
        try FileManager.default.createDirectory(at: Self.archiveDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(archive).write(to: Self.archiveDirectory.appendingPathComponent(archive.id.uuidString + ".json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func safetyCopies() throws -> [LedgerArchive] {
        guard FileManager.default.fileExists(atPath: Self.archiveDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: Self.archiveDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(LedgerArchive.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct LedgerCloudSharingView: UIViewControllerRepresentable {
    let session: LedgerSharingSession
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: session.share, container: session.cloudContainer)
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let session: LedgerSharingSession
        init(_ session: LedgerSharingSession) { self.session = session }
        func itemTitle(for csc: UICloudSharingController) -> String? { session.archive.ledger.name }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            LedgerSharingService.shared.message = CloudSyncState.Failure.from(error).message
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            Task { @MainActor in
                do { try await LedgerSharingService.shared.persist(share, in: session.store) }
                catch { LedgerSharingService.shared.message = CloudSyncState.Failure.from(error).message }
            }
        }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { LedgerSharingService.shared.stopped(session) }
    }
}

/// A timeout releases the UI; late framework callbacks cannot resume a continuation twice.
private final class LedgerCloudCompletion<Value> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { self.finish(.failure(LedgerError.cloudTimedOut)) }
    }
    func finish(_ result: Result<Value, Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
    }
}
