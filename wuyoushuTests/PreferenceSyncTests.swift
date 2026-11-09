import XCTest
import CoreData
@testable import AssetLife

final class PreferenceSyncTests: XCTestCase {
    @MainActor
    func test_legacyStoreLightweightMigration_preservesRowsHistoryAndStoreIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("AssetLife.sqlite")
        let legacy = PersistenceController.makeModel(enableUniqueConstraints: false, includeSyncedPreferences: false)
        let bundledURL = try XCTUnwrap(Bundle.main.url(forResource: "AssetLifeLegacyV1", withExtension: "mom"))
        let bundled = try XCTUnwrap(NSManagedObjectModel(contentsOf: bundledURL))
        XCTAssertEqual(legacy.entityVersionHashesByName, bundled.entityVersionHashesByName)
        func open(_ model: NSManagedObjectModel) throws -> NSPersistentContainer {
            let container = NSPersistentContainer(name: "AssetLife", managedObjectModel: model)
            container.persistentStoreDescriptions = [PersistenceController.makeStoreDescription(storeURL: url, inMemory: false, cloudSyncEnabled: false)]
            var failure: Error?
            container.loadPersistentStores { _, error in failure = error }
            if let failure { throw failure }
            return container
        }
        let original = try open(legacy)
        let object = NSEntityDescription.insertNewObject(forEntityName: "BookkeepingTransaction", into: original.viewContext)
        object.setValue(UUID(), forKey: "id")
        object.setValue(12.3, forKey: "amount")
        object.setValue("custom_legacy-reference", forKey: "categoryKey")
        try original.viewContext.save()
        let originalStore = try XCTUnwrap(original.persistentStoreCoordinator.persistentStores.first)
        let identifier = originalStore.identifier
        try original.persistentStoreCoordinator.remove(originalStore)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url)
        XCTAssertNotNil(NSManagedObjectModel.mergedModel(from: [Bundle.main], forStoreMetadata: metadata))
        try PersistenceController.backupBeforePreferenceMigration(storeURL: url, model: PersistenceController.makeModel(enableUniqueConstraints: false))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("BeforePreferenceSync-") }
        XCTAssertEqual(backups.count, 1)
        let backupURL = try XCTUnwrap(backups.first).appendingPathComponent("AssetLife.sqlite")
        let backupMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: backupURL)
        XCTAssertTrue(legacy.isConfiguration(withName: nil, compatibleWithStoreMetadata: backupMetadata))
        let migrated = try open(PersistenceController.makeModel(enableUniqueConstraints: false))
        defer { for store in migrated.persistentStoreCoordinator.persistentStores { try? migrated.persistentStoreCoordinator.remove(store) } }
        XCTAssertEqual(migrated.persistentStoreCoordinator.persistentStores.first?.identifier, identifier)
        let rows = try migrated.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "BookkeepingTransaction"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.value(forKey: "amount") as? Double, 12.3)
        XCTAssertEqual(rows.first?.value(forKey: "categoryKey") as? String, "custom_legacy-reference")
        let history = try XCTUnwrap(try migrated.viewContext.execute(NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)) as? NSPersistentHistoryResult)
        XCTAssertFalse((history.result as? [NSPersistentHistoryTransaction] ?? []).isEmpty)
        XCTAssertEqual(try migrated.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "SyncedPreferenceOperation")), 0)
    }
}

extension PreferenceSyncTests {
    private func category(_ name: String = "餐饮", id: String = "category-1") -> CustomCategory {
        CustomCategory(id: id, name: name, emoji: "🍜")
    }
    private func rule(_ keyword: String = "咖啡", id: Int = 123, syncID: String? = nil) -> KeywordRule {
        KeywordRule(ruleId: id, keyWord: keyword, searchTexts: [AutoBillSearchText(ruleId: id, ruleKind: .local)], syncID: syncID)
    }
    private func seed() throws -> PreferenceOperation {
        PreferenceJournal.seed(kind: .category, id: "category-1", payload: try PreferenceJournal.encode(category()))
    }
    private func edit(_ seed: PreferenceOperation, name: String, id: String, delete: Bool = false) throws -> PreferenceOperation {
        PreferenceOperation(id: id, kind: .category, entityID: seed.entityID, parents: [seed.id],
                            payload: delete ? nil : try PreferenceJournal.encode(category(name)), isSeed: false, date: Date(timeIntervalSince1970: 100))
    }
    private func container() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "test", managedObjectModel: PersistenceController.makeModel(enableUniqueConstraints: false))
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        return container
    }

    func test_concurrentEdits_convergeRegardlessOfArrivalOrderAndPreserveBothVersions() throws {
        let initial = try seed()
        let a = try edit(initial, name: "午饭", id: "A")
        var b = try edit(initial, name: "晚饭", id: "B")
        b.date = .distantFuture // A bad device clock must not affect the winner.
        let first = try XCTUnwrap(PreferenceJournal.resolve([initial, a, b]).first)
        let reverse = try XCTUnwrap(PreferenceJournal.resolve([b, a, initial]).first)
        XCTAssertEqual(first.winner.id, reverse.winner.id)
        XCTAssertTrue(first.hasConflict)
        XCTAssertEqual(Set(first.heads.map(\.label)), ["午饭", "晚饭"])
    }
    func test_concurrentDelete_winsOverOfflineEdit_andLateLegacySeed() throws {
        let initial = try seed()
        let deletion = try edit(initial, name: "", id: "Z", delete: true)
        let edit = try edit(initial, name: "离线编辑", id: "A")
        let late = PreferenceJournal.seed(kind: .category, id: initial.entityID, payload: try PreferenceJournal.encode(category("旧设备")))
        let state = try XCTUnwrap(PreferenceJournal.resolve([initial, deletion, edit, late]).first)
        XCTAssertNil(state.winner.payload)
        XCTAssertTrue(state.hasConflict)
        XCTAssertEqual(state.history.count, 4)
    }
    func test_explicitResolution_supersedesAllReviewedHeads() throws {
        let initial = try seed()
        let a = try edit(initial, name: "午饭", id: "A")
        let b = try edit(initial, name: "晚饭", id: "B", delete: true)
        var restore = a
        restore.id = "restore"; restore.parents = [a.id, b.id]
        let state = try XCTUnwrap(PreferenceJournal.resolve([initial, a, b, restore]).first)
        XCTAssertEqual(state.winner.label, "午饭")
        XCTAssertFalse(state.hasConflict)
        XCTAssertEqual(state.history.count, 4)
    }
    func test_unknownParentAndFutureSchema_doNotProduceAnEmptyProjection() throws {
        let initial = try seed()
        let orphan = try edit(initial, name: "孤立版本", id: "orphan")
        XCTAssertThrowsError(try PreferenceJournal.resolve([orphan]))
        var future = initial; future.version = 2
        XCTAssertThrowsError(try PreferenceJournal.resolve([future]))
    }
    func test_cyclesAndCrossEntityParents_areRejected() throws {
        let initial = try seed()
        var a = try edit(initial, name: "a", id: "A")
        var b = try edit(initial, name: "b", id: "B")
        a.parents = [b.id]; b.parents = [a.id]
        XCTAssertThrowsError(try PreferenceJournal.resolve([a, b]))
        a.parents = [initial.id]; a.entityID = "another"
        a.payload = try PreferenceJournal.encode(category("a", id: "another"))
        XCTAssertThrowsError(try PreferenceJournal.resolve([initial, a]))
    }
    func test_duplicateCloudRows_areIdempotentButConflictingIDsAreRejected() throws {
        let initial = try seed()
        XCTAssertEqual(try PreferenceJournal.resolve([initial, initial]).first?.history.count, 1)
        var corrupt = initial; corrupt.date = .distantFuture
        XCTAssertThrowsError(try PreferenceJournal.resolve([initial, corrupt]))
    }
    func test_legacyRulesWithSameIntegerID_getDifferentGlobalIdentities() throws {
        XCTAssertNotEqual(try PreferenceJournal.ruleIdentity(rule("A")), try PreferenceJournal.ruleIdentity(rule("B")))
        XCTAssertEqual(try PreferenceJournal.ruleIdentity(rule("A")), try PreferenceJournal.ruleIdentity(rule("A")))
    }
    func test_oldRuleJSON_decodesWithoutSyncID_andKeepsBackupChecksumEncoding() throws {
        let data = try PreferenceJournal.encode(rule())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("syncID"))
        XCTAssertNil(try JSONDecoder().decode(KeywordRule.self, from: data).syncID)
        XCTAssertEqual(try PreferenceJournal.encode(JSONDecoder().decode(KeywordRule.self, from: data)), data)
    }
    func test_twoIndependentStores_convergeAfterOfflineEditsAndResolution() throws {
        let a = PreferenceJournal(container: try container())
        let b = PreferenceJournal(container: try container())
        let initial = try seed()
        try a.append([initial]); try b.append([initial])
        try a.append([a.change(kind: .category, id: initial.entityID, payload: PreferenceJournal.encode(category("甲")))])
        try b.append([b.change(kind: .category, id: initial.entityID, payload: nil)])
        let aOffline = try a.operations(), bOffline = try b.operations()
        try a.append(bOffline); try b.append(aOffline)
        XCTAssertEqual(try a.resolutions().first?.winner, try b.resolutions().first?.winner)
        XCTAssertNil(try a.resolutions().first?.winner.payload)
        XCTAssertThrowsError(try a.change(kind: .category, id: initial.entityID, payload: PreferenceJournal.encode(category())))
        let restore = try a.change(kind: .category, id: initial.entityID, payload: PreferenceJournal.encode(category("恢复")), allowRestore: true)
        try a.append([restore]); try b.append([restore])
        XCTAssertEqual(try b.resolutions().first?.winner.label, "恢复")
        XCTAssertFalse(try a.resolutions().first!.hasConflict)
    }
    func test_stagedRestoreRollback_doesNotPublishAnyOperation() throws {
        let container = try container()
        let journal = PreferenceJournal(container: container)
        try journal.append([seed()])
        let staged = try journal.change(kind: .category, id: "category-1", payload: nil, in: container.viewContext)
        try journal.append([staged], in: container.viewContext)
        XCTAssertEqual(try journal.operations().count, 1)
        container.viewContext.rollback()
        XCTAssertEqual(try journal.operations().count, 1)
        XCTAssertNotNil(try journal.resolutions().first?.winner.payload)
    }
    func test_sqliteProjection_preservesPackageAndRemapsCollidingIDs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try KeywordRulesTable(databaseURL: url)
        var package = rule("内置"); package.searchTexts?[0].ruleKind = .auto
        XCTAssertTrue(table.upsertRules([package]))
        try table.replaceLocalRules([rule("甲", syncID: "a"), rule("乙", syncID: "b")])
        let rows = try table.fetchAllRulesStrict()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.ruleId)).count, 3)
        XCTAssertEqual(rows.first(where: { $0.ruleId == 123 })?.keyWord, "内置")
        XCTAssertEqual(Set(rows.compactMap(\.syncID)), ["a", "b"])
        try table.replaceLocalRules([])
        XCTAssertEqual(try table.fetchAllRulesStrict().map(\.keyWord), ["内置"])
    }
    func test_packageUpdate_cannotOverwriteExistingLocalRuleWithSameIntegerID() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let table = try KeywordRulesTable(databaseURL: url)
        XCTAssertTrue(table.upsertRule(rule("用户", syncID: "user")))
        var package = rule("新规则包"); package.searchTexts?[0].ruleKind = .common
        XCTAssertTrue(table.upsertRules([package]))
        let rows = try table.fetchAllRulesStrict()
        XCTAssertEqual(rows.count, 2)
        let local = try XCTUnwrap(rows.first { $0.syncID == "user" })
        XCTAssertNotEqual(local.ruleId, 123)
        XCTAssertEqual(local.searchTexts?.first?.ruleId, local.ruleId)
        XCTAssertEqual(local.keyWord, "用户")
    }

    @MainActor
    func test_migration_isRepeatableKeepsLegacyBackupAndProjectsRemoteEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        // Use a separate suite so tests never alter the app's preferences or rule database.
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let categories = CustomCategoryStore(defaults: isolated, usesSync: false)
        XCTAssertTrue(categories.add(category()))
        let table = try KeywordRulesTable(databaseURL: directory.appendingPathComponent("rules.sqlite"))
        XCTAssertTrue(table.upsertRule(rule()))
        let container = try container()
        var refreshCount = 0
        let coordinator = PreferenceSyncCoordinator(defaults: isolated, categories: categories, rules: table,
            backupDirectory: directory.appendingPathComponent("backup"), didProjectRules: { refreshCount += 1 })
        coordinator.start(container: container)
        XCTAssertTrue(coordinator.isReady, coordinator.errorMessage ?? "")
        let journal = PreferenceJournal(container: container)
        XCTAssertEqual(try journal.operations().count, 2)
        XCTAssertEqual(categories.categories.first?.id, "category-1")
        XCTAssertNotNil(try table.fetchAllRulesStrict().first?.syncID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("backup").path).count, 1)
        // Simulate a crash after journal save but before the migration marker is durable.
        isolated.removeObject(forKey: "preference-journal-migrated-v1-" + container.persistentStoreCoordinator.persistentStores[0].identifier)
        coordinator.refresh()
        XCTAssertEqual(try journal.operations().count, 2)
        let remote = try journal.change(kind: .category, id: "category-1", payload: PreferenceJournal.encode(category("云端编辑")))
        try journal.append([remote]); coordinator.refresh()
        XCTAssertEqual(categories.categories.first?.name, "云端编辑")
        XCTAssertTrue(coordinator.deleteCategory(category()))
        XCTAssertTrue(categories.categories.isEmpty)
        XCTAssertNotNil(categories.find(key: "custom_category-1")) // Existing ledger references keep a label.
        XCTAssertEqual(coordinator.deletedItems.count, 1)
        XCTAssertGreaterThan(refreshCount, 0)
    }
    @MainActor
    func test_migrationBackupFailure_preservesLegacyDataAndBlocksMutation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let categories = CustomCategoryStore(defaults: isolated, usesSync: false)
        XCTAssertTrue(categories.add(category()))
        let table = try KeywordRulesTable(databaseURL: directory.appendingPathComponent("rules.sqlite"))
        XCTAssertTrue(table.upsertRule(rule()))
        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let container = try container()
        let coordinator = PreferenceSyncCoordinator(defaults: isolated, categories: categories, rules: table, backupDirectory: file, didProjectRules: {})
        coordinator.start(container: container)
        XCTAssertFalse(coordinator.isReady)
        XCTAssertFalse(coordinator.deleteCategory(category()))
        XCTAssertEqual(categories.categories.count, 1)
        XCTAssertEqual(try table.fetchAllRulesStrict().count, 1)
        XCTAssertTrue(try PreferenceJournal(container: container).operations().isEmpty)
    }
}

extension PreferenceSyncTests {
    func test_journalSaveFailure_rollsBackAndKeepsPreviouslyCommittedVersion() throws {
        final class RejectingContext: NSManagedObjectContext {
            override func save() throws { throw NSError(domain: "InjectedSaveFailure", code: 1) }
        }
        let container = try container()
        let committed = PreferenceJournal(container: container)
        try committed.append([seed()])
        let rejecting = RejectingContext(concurrencyType: .privateQueueConcurrencyType)
        rejecting.persistentStoreCoordinator = container.persistentStoreCoordinator
        let journal = PreferenceJournal(container: container, context: rejecting)
        XCTAssertThrowsError(try journal.append([edit(seed(), name: "保存失败", id: "failed")]))
        XCTAssertFalse(rejecting.performAndWait { rejecting.hasChanges })
        XCTAssertEqual(try committed.operations().count, 1)
        XCTAssertEqual(try committed.resolutions().first?.winner.label, "餐饮")
    }

    @MainActor
    func test_restoreStagesCategoryAndRuleChangesWithLedgerAndCanRollBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let categories = CustomCategoryStore(defaults: isolated, usesSync: false)
        XCTAssertTrue(categories.add(category()))
        let table = try KeywordRulesTable(databaseURL: directory.appendingPathComponent("rules.sqlite"))
        XCTAssertTrue(table.upsertRule(rule()))
        let container = try container(), context = container.viewContext
        let coordinator = PreferenceSyncCoordinator(defaults: isolated, categories: categories, rules: table,
            backupDirectory: directory.appendingPathComponent("backup"), didProjectRules: {})
        coordinator.start(container: container)
        let journal = PreferenceJournal(container: container)
        let originalCount = try journal.operations().count
        try coordinator.stageRestore(categories: [], rules: [], in: context)
        let transaction = NSEntityDescription.insertNewObject(forEntityName: "BookkeepingTransaction", into: context)
        transaction.setValue(9.9, forKey: "amount")
        context.rollback()
        XCTAssertEqual(try journal.operations().count, originalCount)
        coordinator.refresh()
        XCTAssertEqual(categories.categories.count, 1)
        XCTAssertEqual(try table.fetchAllRulesStrict().count, 1)
        try coordinator.stageRestore(categories: [category("恢复后的分类")], rules: [], in: context)
        try context.save()
        coordinator.refresh()
        XCTAssertEqual(categories.categories.first?.name, "恢复后的分类")
        XCTAssertTrue(try table.fetchAllRulesStrict().isEmpty)
        XCTAssertEqual(try journal.resolutions().filter { $0.winner.kind == .rule }.first?.winner.payload, nil)
    }

    @MainActor
    func test_partialRemoteDownload_keepsExistingCachesUntilParentsArrive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let categories = CustomCategoryStore(defaults: isolated, usesSync: false)
        XCTAssertTrue(categories.add(category()))
        let table = try KeywordRulesTable(databaseURL: directory.appendingPathComponent("rules.sqlite"))
        let container = try container()
        let coordinator = PreferenceSyncCoordinator(defaults: isolated, categories: categories, rules: table,
            backupDirectory: directory.appendingPathComponent("backup"), didProjectRules: {})
        coordinator.start(container: container)
        let initial = try seed(), parent = try edit(seed(), name: "中间版本", id: "parent")
        var child = try edit(initial, name: "最新版本", id: "child"); child.parents = [parent.id]
        func importRow(_ op: PreferenceOperation) throws {
            let object = NSEntityDescription.insertNewObject(forEntityName: PreferenceJournal.entityName, into: container.viewContext)
            object.setValue(op.id, forKey: "operationID")
            object.setValue(try PreferenceJournal.encode(op), forKey: "encodedOperation")
            try container.viewContext.save()
        }
        try importRow(child); coordinator.refresh()
        XCTAssertFalse(coordinator.isReady)
        XCTAssertEqual(categories.categories.first?.name, "餐饮")
        try importRow(parent); coordinator.refresh()
        XCTAssertTrue(coordinator.isReady)
        XCTAssertEqual(categories.categories.first?.name, "最新版本")
    }
    func test_backupWithoutPreferenceHistory_staysBackwardCompatible() throws {
        let old = LocalBackupPayload(transactions: [], budgets: [], assets: [], wishItems: [], customCategories: [category()], keywordRules: [rule()])
        let encoded = try PreferenceJournal.encode(old)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("preferenceOperations"))
        let decoded = try JSONDecoder().decode(LocalBackupPayload.self, from: encoded)
        XCTAssertNil(decoded.preferenceOperations)
        XCTAssertEqual(try PreferenceJournal.encode(decoded), encoded)
        var current = decoded; current.preferenceOperations = [try seed()]
        XCTAssertEqual(try JSONDecoder().decode(LocalBackupPayload.self, from: PreferenceJournal.encode(current)).preferenceOperations?.count, 1)
    }
}
