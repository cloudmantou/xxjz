import XCTest
import CoreData
import CloudKit
@testable import AssetLife

private final class SharingMetadataContainer: NSPersistentCloudKitContainer {
    var ownerSharedIDs: Set<NSManagedObjectID> = []
    override func fetchShares(matching objectIDs: [NSManagedObjectID]) throws -> [NSManagedObjectID: CKShare] {
        Dictionary(uniqueKeysWithValues: objectIDs.filter { ownerSharedIDs.contains($0) }.map {
            ($0, CKShare(rootRecord: CKRecord(recordType: "Ledger")))
        })
    }
}

@MainActor
final class LedgerTests: XCTestCase {
    private func setup(twoStores: Bool = false) throws -> (NSPersistentCloudKitContainer, LedgerStore) {
        let container = SharingMetadataContainer(name: "test", managedObjectModel: PersistenceController.makeModel(enableUniqueConstraints: false))
        container.persistentStoreDescriptions = (twoStores ? ["Private", "Shared"] : ["Private"]).map { name in
            let d = NSPersistentStoreDescription(); d.type = NSInMemoryStoreType; d.configuration = name
            d.url = URL(fileURLWithPath: "/" + UUID().uuidString); return d
        }
        var failure: Error?; container.loadPersistentStores { _, error in if let error { failure = error } }
        if let failure { throw failure }
        let suite = "ledger-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let store = LedgerStore(defaults: defaults); store.start(container: container)
        return (container, store)
    }
    private func insert(_ amount: Double, ledger: Ledger, context: NSManagedObjectContext, store: LedgerStore) throws -> BookkeepingTransaction {
        let tx = BookkeepingTransaction(context: context, amount: amount, categoryKey: "food")
        try store.scope(for: ledger).attach(tx, in: context)
        try store.prepareSave(context); try context.save(); return tx
    }
    func test_oldRowsAssignedToPersonalLedgerWithoutChangingBusinessFields() throws {
        let (container, store) = try setup()
        let context = container.viewContext
        let tx = BookkeepingTransaction(context: context, amount: 23.4, categoryKey: "custom_old", note: "old")
        let id = tx.id; try context.save(); let uri = tx.objectID.uriRepresentation()
        store.refresh(); store.refresh()
        XCTAssertEqual(tx.id, id); XCTAssertEqual(tx.amount, 23.4); XCTAssertEqual(tx.note, "old")
        XCTAssertEqual(tx.objectID.uriRepresentation(), uri)
        XCTAssertEqual(tx.ledgerRaw?.id, Ledger.personalID)
        XCTAssertEqual(try context.count(for: Ledger.fetchRequest()), 1)
    }
    func test_scopesIsolateBillsBudgetsAndSoftDeletedRows() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let personal = try XCTUnwrap(store.selected)
        let family = try store.create(name: "家庭")
        _ = try insert(10, ledger: personal, context: context, store: store)
        let deleted = try insert(20, ledger: family, context: context, store: store)
        deleted.isTrashed = true; try store.prepareSave(context); try context.save()
        _ = try insert(30, ledger: family, context: context, store: store)
        let budget = BudgetEntry(context: context, categoryKey: "food", monthlyAmount: 200, month: Date())
        try store.scope(for: family).attach(budget, in: context); try context.save()
        let bills = BookkeepingTransaction.fetchRequest(); store.scope(for: personal).apply(bills)
        XCTAssertEqual(try context.fetch(bills).map(\.amount), [10])
        let familyBills = BookkeepingTransaction.fetchRequest(); store.scope(for: family).apply(familyBills)
        XCTAssertEqual(try context.fetch(familyBills).map(\.amount), [30])
        let budgets = BudgetEntry.fetchRequest(); store.scope(for: personal).apply(budgets)
        XCTAssertTrue(try context.fetch(budgets).isEmpty)
        XCTAssertEqual(try context.count(for: BookkeepingTransaction.fetchRequest()), 3)
    }
    func test_capturedImportScopeSurvivesSelectionChange() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let personal = try XCTUnwrap(store.selected); let captured = store.scope(in: context)
        _ = try store.create(name: "另一账本")
        let tx = BookkeepingTransaction(context: context, amount: 10, categoryKey: "food")
        try captured.attach(tx, in: context); try store.prepareSave(context); try context.save()
        XCTAssertEqual(tx.ledgerRaw, personal)
    }
    func test_duplicatePersonalRootsArePresentedAsOneWithoutDeletingTransactions() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let duplicate = Ledger(context: context); duplicate.id = Ledger.personalID; duplicate.name = "个人账本"; duplicate.emoji = "📒"
        duplicate.currencyCode = "CNY"; duplicate.createdAt = Date()
        let tx = BookkeepingTransaction(context: context, amount: 9, categoryKey: "food"); tx.ledgerRaw = duplicate
        try context.save(); store.refresh()
        XCTAssertEqual(store.ledgers.filter(\.isPersonalDefault).count, 1)
        XCTAssertEqual(try context.count(for: Ledger.fetchRequest()), 2)
        let request = BookkeepingTransaction.fetchRequest(); store.scope(in: context).apply(request)
        XCTAssertEqual(try context.fetch(request).count, 1)
    }
    func test_archivedLedgerRejectsWritesAndRetainsOriginalValueAfterRollback() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let ledger = try store.create(name: "旅行")
        let tx = try insert(10, ledger: ledger, context: context, store: store)
        try store.update(ledger, name: ledger.name, emoji: "✈️", targetCents: 0, targetDate: nil, archived: true)
        tx.amount = 20
        XCTAssertThrowsError(try store.prepareSave(context)); context.rollback()
        XCTAssertEqual(tx.amount, 10)
        try store.update(ledger, name: ledger.name, emoji: "✈️", targetCents: 0, targetDate: nil, archived: false)
        XCTAssertTrue(store.canEdit(ledger))
    }
    func test_historyPreservesBeforeAndAfterAndRestoresDeletedBill() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let ledger = try XCTUnwrap(store.selected)
        let tx = try insert(10, ledger: ledger, context: context, store: store)
        tx.amount = 20; try store.prepareSave(context); try context.save()
        tx.isTrashed = true; try store.prepareSave(context); try context.save()
        let history = try context.fetch(LedgerActivity.fetchRequest())
        XCTAssertEqual(history.count, 5)
        let original = try XCTUnwrap(history.first { $0.action == "新增" })
        try store.restoreRevision(original)
        XCTAssertEqual(tx.amount, 10); XCTAssertFalse(tx.isTrashed)
        XCTAssertEqual(try context.count(for: LedgerActivity.fetchRequest()), 7)
    }
    func test_sharedGraphCannotContainAssetsOrGlobalPreferences() throws {
        let model = PersistenceController.makeModel(enableUniqueConstraints: false)
        XCTAssertEqual(Set(model.entities(forConfigurationName: "Shared")!.compactMap(\.name)), ["Ledger", "LedgerActivity", "BookkeepingTransaction", "BudgetEntry"])
        let destinations = Set(model.entitiesByName["Ledger"]!.relationshipsByName.values.compactMap { $0.destinationEntity?.name })
        XCTAssertEqual(destinations, ["LedgerActivity", "BookkeepingTransaction", "BudgetEntry"])
    }
    func test_archiveRecoveryCreatesPrivateCopyWithNewIdentifiersAndHistory() throws {
        let (container, store) = try setup(twoStores: true); let context = container.viewContext
        let ledger = try store.create(name: "攒钱", targetCents: 100000)
        let original = try insert(100, ledger: ledger, context: context, store: store)
        let archive = try LedgerArchive.capture(ledger, in: context)
        let copy = try archive.restorePersonalCopy(in: context, store: XCTUnwrap(store.privateStore))
        XCTAssertNotEqual(copy.id, ledger.id); XCTAssertEqual(copy.targetCents, 100000)
        let request = BookkeepingTransaction.fetchRequest(); store.scope(for: copy).apply(request)
        let restored = try XCTUnwrap(context.fetch(request).first)
        XCTAssertNotEqual(restored.id, original.id); XCTAssertEqual(restored.amount, original.amount)
        XCTAssertEqual(restored.objectID.persistentStore, store.privateStore)
        let histories = (copy.activitiesRaw?.allObjects as? [LedgerActivity]) ?? []
        XCTAssertEqual(histories.first?.targetID, restored.id)
    }
    func test_fullBackupRestorePreservesJoinedSharedLedgerAndCreatesPersonalCopy() throws {
        let (container, store) = try setup(twoStores: true); let context = container.viewContext
        let shared = Ledger(context: context); context.assign(shared, to: try XCTUnwrap(store.sharedStore))
        shared.id = UUID(); shared.name = "共同账本"; shared.emoji = "🏡"; shared.currencyCode = "CNY"; shared.createdAt = Date()
        let tx = BookkeepingTransaction(context: context, amount: 80, categoryKey: "food")
        context.assign(tx, to: try XCTUnwrap(store.sharedStore)); tx.ledgerRaw = shared; try context.save()
        let originalURI = tx.objectID.uriRepresentation()
        let service = LocalBackupService(ledgerStore: store)
        let envelope = try service.decodeAndValidate(service.exportBackup(from: context))
        tx.amount = 90; try context.save()
        try service.restore(envelope, into: context)
        XCTAssertEqual(tx.amount, 90); XCTAssertEqual(tx.objectID.uriRepresentation(), originalURI)
        XCTAssertFalse(tx.isDeleted); XCTAssertEqual(tx.ledgerRaw, shared)
        let rows = try context.fetch(BookkeepingTransaction.fetchRequest())
        let copy = try XCTUnwrap(rows.first { $0.objectID.persistentStore === store.privateStore })
        XCTAssertEqual(copy.amount, 80); XCTAssertNotEqual(copy.id, tx.id); XCTAssertNotEqual(copy.ledgerRaw?.id, shared.id)
    }
    func test_incompleteSharedGraphRefusesBackupInsteadOfReassigningToPersonal() throws {
        let (container, store) = try setup(twoStores: true); let context = container.viewContext
        let tx = BookkeepingTransaction(context: context, amount: 80, categoryKey: "food")
        context.assign(tx, to: try XCTUnwrap(store.sharedStore)); try context.save()
        XCTAssertThrowsError(try LocalBackupService(ledgerStore: store).exportBackup(from: context))
        XCTAssertNil(tx.ledgerRaw)
    }
    func test_fullRestorePreservesOwnerSharedLedgerInPrivateStore() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let shared = try store.create(name: "家庭共享")
        let tx = try insert(100, ledger: shared, context: context, store: store)
        (container as! SharingMetadataContainer).ownerSharedIDs = [shared.objectID]
        let service = LocalBackupService(ledgerStore: store)
        let backup = try service.decodeAndValidate(service.exportBackup(from: context))
        tx.amount = 150; try context.save()
        try service.restore(backup, into: context)
        XCTAssertFalse(shared.isDeleted); XCTAssertEqual(tx.amount, 150)
        let copies = try context.fetch(Ledger.fetchRequest()).filter { !$0.isPersonalDefault && $0.id != shared.id }
        XCTAssertEqual(copies.count, 1)
        XCTAssertTrue(copies[0].name.contains("备份副本"))
    }
    func test_sharedRowWithoutWritePermissionIsRejectedBeforeSave() throws {
        let (container, store) = try setup(twoStores: true); let context = container.viewContext
        let ledger = Ledger(context: context); context.assign(ledger, to: try XCTUnwrap(store.sharedStore))
        ledger.id = UUID(); ledger.name = "只读"; ledger.emoji = "📒"; ledger.currencyCode = "CNY"; ledger.createdAt = Date()
        try context.save(); store.refresh()
        XCTAssertThrowsError(try store.requireWritable(store.scope(for: ledger), in: context))
        XCTAssertEqual(try context.count(for: BookkeepingTransaction.fetchRequest()), 0)
    }
    func test_billHistoryRestoresNoteCategoryAndIncomeTogether() throws {
        let (container, store) = try setup(); let context = container.viewContext
        let tx = try insert(10, ledger: XCTUnwrap(store.selected), context: context, store: store)
        let original = try XCTUnwrap(context.fetch(LedgerActivity.fetchRequest()).first)
        tx.amount = 50; tx.note = "编辑"; tx.categoryKey = "other_income"; tx.isIncome = true
        try store.prepareSave(context); try context.save()
        try store.restoreRevision(original)
        XCTAssertEqual(tx.amount, 10); XCTAssertNil(tx.note); XCTAssertEqual(tx.categoryKey, "food"); XCTAssertFalse(tx.isIncome)
    }
    func test_goalMoneyUsesExactCentsAndRejectsInvalidPrecision() throws {
        XCTAssertEqual(try LedgerMoney.cents("0.29"), 29)
        XCTAssertEqual(try LedgerMoney.cents("123456789012.99"), 12345678901299)
        for text in ["-1", "nan", "1.001", "1e6", "", "1,000", "999999999999999999999"] { XCTAssertThrowsError(try LedgerMoney.cents(text)) }
    }
    func test_v2OnDiskMigrationPreservesIdentityPreferencesAndBills() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AssetLife.sqlite")
        let legacy = PersistenceController.makeModel(enableUniqueConstraints: false, includeLedgers: false)
        let resource = try XCTUnwrap(Bundle.main.url(forResource: "AssetLifeLegacyV2", withExtension: "mom"))
        XCTAssertEqual(legacy.entityVersionHashesByName, NSManagedObjectModel(contentsOf: resource)?.entityVersionHashesByName)
        let old = NSPersistentContainer(name: "old", managedObjectModel: legacy)
        old.persistentStoreDescriptions = [PersistenceController.makeStoreDescription(storeURL: url, inMemory: false, cloudSyncEnabled: false)]
        var error: Error?; old.loadPersistentStores { _, e in error = e }; if let error { throw error }
        let row = NSEntityDescription.insertNewObject(forEntityName: "BookkeepingTransaction", into: old.viewContext)
        let id = UUID(); row.setValue(id, forKey: "id"); row.setValue(42.5, forKey: "amount"); row.setValue("custom_abc", forKey: "categoryKey")
        try old.viewContext.save()
        let originalStore = try XCTUnwrap(old.persistentStoreCoordinator.persistentStores.first); let identity = originalStore.identifier
        try old.persistentStoreCoordinator.remove(originalStore)
        let model = PersistenceController.makeModel(enableUniqueConstraints: false)
        try PersistenceController.backupBeforePreferenceMigration(storeURL: url, model: model)
        let migrated = NSPersistentCloudKitContainer(name: "new", managedObjectModel: model)
        migrated.persistentStoreDescriptions = PersistenceController.makeLedgerStoreDescriptions(storeURL: url, inMemory: false, cloudSyncEnabled: false)
        migrated.loadPersistentStores { _, e in if let e { error = e } }; if let error { throw error }
        defer { for s in migrated.persistentStoreCoordinator.persistentStores { try? migrated.persistentStoreCoordinator.remove(s) } }
        let store = LedgerStore(defaults: UserDefaults(suiteName: UUID().uuidString)!); store.start(container: migrated)
        let restored = try XCTUnwrap(migrated.viewContext.fetch(BookkeepingTransaction.fetchRequest()).first)
        XCTAssertEqual(restored.id, id); XCTAssertEqual(restored.amount, 42.5); XCTAssertEqual(restored.categoryKey, "custom_abc")
        XCTAssertEqual(restored.ledgerRaw?.id, Ledger.personalID); XCTAssertFalse(restored.isTrashed)
        XCTAssertEqual(store.privateStore?.identifier, identity)
        XCTAssertEqual(migrated.persistentStoreCoordinator.persistentStores.count, 2)
    }
}
