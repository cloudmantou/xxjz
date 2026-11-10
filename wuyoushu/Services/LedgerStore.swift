import Foundation
import CoreData
import CloudKit
import Combine
import WidgetKit

/// UI-owned selection. Background imports capture LedgerScope before entering their queue.
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()
    @Published private(set) var ledgers: [Ledger] = []
    @Published private(set) var selected: Ledger?
    @Published private(set) var selectionToken = "personal"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReady = false
    private(set) var container: NSPersistentCloudKitContainer?
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var isRefreshing = false
    var memberName: String {
        let value = defaults.string(forKey: "ledger.memberName")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "记账成员" : String(value.prefix(30))
    }
    var selectedName: String { selected?.name ?? "个人账本" }
    var privateStore: NSPersistentStore? { container?.persistentStoreCoordinator.persistentStores.first { $0.configurationName != "Shared" } }
    var sharedStore: NSPersistentStore? { container?.persistentStoreCoordinator.persistentStores.first { $0.configurationName == "Shared" } }
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(container: NSPersistentCloudKitContainer) {
        self.container = container
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in self?.refresh() },
            NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave,
                object: container.viewContext, queue: .main) { [weak self] _ in self?.updateWidget() }]
        refresh()
    }

    func refresh() {
        guard !isRefreshing, let container, let privateStore else { return }
        isRefreshing = true; defer { isRefreshing = false }
        let context = container.viewContext
        do {
            try migrateUnassigned(in: context, privateStore: privateStore)
            let request = Ledger.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let rows = try context.fetch(request)
            // Every offline device may seed the personal root. Keep all objects and relationships;
            // present them as one logical personal ledger, without destructive deduplication.
            let personal = rows.first { $0.isPersonalDefault && $0.objectID.persistentStore === privateStore }
            ledgers = (personal.map { [$0] } ?? []) + rows.filter { !$0.isPersonalDefault }
            let saved = defaults.string(forKey: "ledger.selectedURI")
            if let old = selected, !old.isDeleted, ledgers.contains(where: { $0.objectID == old.objectID }) {
                selected = old
            } else {
                selected = ledgers.first { $0.objectID.uriRepresentation().absoluteString == saved } ?? personal
            }
            selectionToken = selected?.objectID.uriRepresentation().absoluteString ?? "personal"
            isReady = true; errorMessage = nil
            updateWidget()
        } catch {
            // Roll back migration changes only; startup/remote refresh never owns UI edits.
            if context.transactionAuthor == "LedgerMigration" { context.rollback() }
            isReady = false; errorMessage = "账本加载失败，原有数据已保留。请重新打开 App 后重试。"
        }
    }

    private func migrateUnassigned(in context: NSManagedObjectContext, privateStore: NSPersistentStore) throws {
        guard !context.hasChanges else { return }
        let previousAuthor = context.transactionAuthor
        context.transactionAuthor = "LedgerMigration"
        defer { context.transactionAuthor = previousAuthor }
        do {
            let request = Ledger.fetchRequest()
            request.affectedStores = [privateStore]
            request.predicate = NSPredicate(format: "id == %@", Ledger.personalID as NSUUID)
            let personal: Ledger
            if let existing = try context.fetch(request).first { personal = existing }
            else {
                personal = Ledger(context: context)
                context.assign(personal, to: privateStore)
                personal.id = Ledger.personalID; personal.name = "个人账本"; personal.emoji = "📒"
                personal.currencyCode = "CNY"; personal.createdAt = Date(timeIntervalSince1970: 0)
            }
            for entity in ["BookkeepingTransaction", "BudgetEntry"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                request.affectedStores = [privateStore]
                request.predicate = NSPredicate(format: "ledgerRaw == nil")
                for object in try context.fetch(request) { object.setValue(personal, forKey: "ledgerRaw") }
            }
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
    }

    func owns(_ context: NSManagedObjectContext) -> Bool {
        container?.persistentStoreCoordinator === context.persistentStoreCoordinator
    }
    func scope(in context: NSManagedObjectContext) -> LedgerScope {
        guard owns(context), let selected, !selected.isDeleted else {
            return LedgerScope(objectID: nil, store: nil,
                               isPersonal: true, name: "个人账本")
        }
        return scope(for: selected)
    }
    func scope(for ledger: Ledger) -> LedgerScope {
        LedgerScope(objectID: ledger.objectID, store: ledger.objectID.persistentStore,
                    isPersonal: ledger.isPersonalDefault && ledger.objectID.persistentStore === privateStore, name: ledger.name)
    }
    func transactionRequest(predicate: NSPredicate? = nil,
                            sortDescriptors: [NSSortDescriptor] = []) -> NSFetchRequest<BookkeepingTransaction> {
        let request = BookkeepingTransaction.fetchRequest()
        request.predicate = predicate; request.sortDescriptors = sortDescriptors
        if let context = container?.viewContext { scope(in: context).apply(request) }
        else { request.predicate = LedgerScope(objectID: nil, store: nil, isPersonal: true, name: "个人账本").predicate(predicate) }
        return request
    }

    func updateWidget() {
        guard self === Self.shared, let context = container?.viewContext, let selected, !selected.isDeleted,
              let defaults = UserDefaults(suiteName: Constants.Bookkeeping.widgetSuiteName) else { return }
        let today = Date(), start = Date().startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let request = transactionRequest(predicate: NSPredicate(format: "date >= %@ AND date < %@ AND isIncome == NO AND categoryKey != %@", start as NSDate, end as NSDate, "transfer"))
        do {
            let rows = try context.fetch(request)
            let summary = TodaySummary(totalExpense: rows.reduce(0) { $0 + $1.normalizedAmount },
                transactionCount: rows.count, dateString: today.shortDateString, ledgerName: selected.name)
            defaults.set(try JSONEncoder().encode(summary), forKey: Constants.Bookkeeping.widgetTodaySummaryKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "BookkeepingWidget")
        } catch { defaults.removeObject(forKey: Constants.Bookkeeping.widgetTodaySummaryKey) }
    }

    func select(_ ledger: Ledger) {
        guard !ledger.isDeleted else { return }
        selected = ledger; selectionToken = ledger.objectID.uriRepresentation().absoluteString
        defaults.set(selectionToken, forKey: "ledger.selectedURI")
        updateWidget()
    }
    @discardableResult
    func create(name: String, emoji: String = "📚", targetCents: Int64 = 0, targetDate: Date? = nil) throws -> Ledger {
        guard let context = container?.viewContext, let privateStore, isReady, !context.hasChanges else { throw LedgerError.unavailable }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw LedgerError.invalidName }
        let ledger = Ledger(context: context)
        context.assign(ledger, to: privateStore)
        ledger.id = UUID(); ledger.name = trimmed; ledger.emoji = emoji; ledger.currencyCode = "CNY"
        ledger.createdAt = Date(); ledger.targetCents = max(0, targetCents); ledger.targetDate = targetDate
        do { try context.save(); refresh(); select(ledger); return ledger }
        catch { context.rollback(); throw error }
    }
    func update(_ ledger: Ledger, name: String, emoji: String, targetCents: Int64, targetDate: Date?, archived: Bool) throws {
        guard let context = container?.viewContext, !context.hasChanges else { throw LedgerError.unavailable }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw LedgerError.invalidName }
        // Owners and read-write members can unarchive; read-only members cannot.
        guard hasWritePermission(for: ledger) else { throw LedgerError.readOnly }
        guard !ledger.isPersonalDefault || !archived else { throw LedgerError.unavailable }
        ledger.name = trimmed; ledger.emoji = String(emoji.prefix(4)); ledger.targetCents = max(0, targetCents)
        ledger.targetDate = targetDate; ledger.archived = archived
        do { try context.save(); refresh() } catch { context.rollback(); throw error }
    }

    func restoreRevision(_ activity: LedgerActivity) throws {
        guard let context = container?.viewContext, !context.hasChanges, let ledger = activity.ledgerRaw,
              let data = activity.snapshot else { throw LedgerError.unavailable }
        try requireWritable(scope(for: ledger), in: context)
        let revision = try JSONDecoder().decode(LedgerRevision.self, from: data)
        guard revision.id == activity.targetID, revision.amount.isFinite, revision.amount >= 0 else { throw LedgerError.invalidAmount }
        let request = BookkeepingTransaction.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", revision.id as NSUUID)
        scope(for: ledger).apply(request, includesDeleted: true)
        guard let tx = try context.fetch(request).first else { throw LedgerError.unavailable }
        do {
            revision.apply(to: tx)
            try LedgerRevision.record(tx, author: memberName, in: context)
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func canEdit(_ ledger: Ledger) -> Bool {
        guard !ledger.isDeleted, !ledger.archived else { return false }
        return hasWritePermission(for: ledger)
    }
    func hasWritePermission(for ledger: Ledger) -> Bool {
        guard !ledger.isDeleted else { return false }
        if ledger.objectID.persistentStore === privateStore { return true }
        // Missing/not-yet-imported share metadata is not proof of permission. In a local
        // fallback container canUpdateRecord alone may return true for an unmirrored row.
        guard let share = try? share(for: ledger), let participant = share.currentUserParticipant,
              participant.acceptanceStatus == .accepted, participant.permission == .readWrite else { return false }
        return container?.canUpdateRecord(forManagedObjectWith: ledger.objectID) ?? false
    }
    func requireWritable(_ scope: LedgerScope, in context: NSManagedObjectContext) throws {
        guard owns(context) else { return }
        guard isReady, let id = scope.objectID, let ledger = try context.existingObject(with: id) as? Ledger,
              !ledger.isDeleted else { throw LedgerError.unavailable }
        if ledger.archived { throw LedgerError.archived }
        guard canEdit(ledger) else { throw LedgerError.readOnly }
    }
    func share(for ledger: Ledger) throws -> CKShare? {
        guard let container else { return nil }
        return try container.fetchShares(matching: [ledger.objectID])[ledger.objectID]
    }
    func isShared(_ ledger: Ledger) -> Bool {
        ledger.objectID.persistentStore === sharedStore || (try? share(for: ledger)) != nil
    }

    func protectedLedgers(in context: NSManagedObjectContext) throws -> [Ledger] {
        let all = try context.fetch(Ledger.fetchRequest())
        let joined = all.filter { $0.objectID.persistentStore?.configurationName == "Shared" }
        guard owns(context), let container else { return joined }
        let candidates = all.filter { !$0.isPersonalDefault && $0.objectID.persistentStore?.configurationName != "Shared" }
        guard !candidates.isEmpty else { return joined }
        // Fail closed: an error reading share metadata must not turn a shared ledger into
        // an apparently personal ledger that a full backup restore may delete.
        let shares = try container.fetchShares(matching: candidates.map(\.objectID))
        return joined + candidates.filter { shares[$0.objectID] != nil }
    }

    /// Called before every UI save so denied writes are rolled back with their activities.
    func prepareSave(_ context: NSManagedObjectContext) throws {
        guard owns(context) else { return }
        let target = scope(in: context)
        let changes = context.insertedObjects.union(context.updatedObjects)
        for object in changes where object is BookkeepingTransaction || object is BudgetEntry {
            if object.isInserted, object.value(forKey: "ledgerRaw") == nil { try target.attach(object, in: context) }
            guard let ledger = object.value(forKey: "ledgerRaw") as? Ledger else { throw LedgerError.unavailable }
            try requireWritable(scope(for: ledger), in: context)
            if let transaction = object as? BookkeepingTransaction {
                if transaction.isInserted { transaction.creatorName = memberName }
                transaction.categoryNameSnapshot = BookkeepingCategory.find(key: transaction.categoryKey)?.localizedName ?? transaction.categoryNameSnapshot
                transaction.categoryEmojiSnapshot = BookkeepingCategory.find(key: transaction.categoryKey)?.emoji ?? transaction.categoryEmojiSnapshot
                try LedgerRevision.record(transaction, author: memberName, in: context)
            }
        }
        for object in context.deletedObjects where object is BookkeepingTransaction || object is BudgetEntry {
            // Bulk restore has its own protected path. Interactive deletions must be reversible.
            throw LedgerError.unavailable
        }
    }
}

struct LedgerRevision: Codable {
    var id: UUID
    var amount: Double
    var categoryKey: String
    var subcategoryKey: String?
    var note: String?
    var date: Date
    var isIncome: Bool
    var createdAt: Date
    var fundAccountKey: String?
    var notInBudget: Bool
    var billSource: String?
    var merchantName: String?
    var importFingerprint: String?
    var creatorName: String
    var categoryNameSnapshot: String?
    var categoryEmojiSnapshot: String?
    var isTrashed: Bool

    init(_ tx: BookkeepingTransaction, committed: Bool = false) {
        let old = committed ? tx.committedValues(forKeys: nil) : [:]
        func value<T>(_ key: String, _ fallback: T) -> T { old[key] as? T ?? fallback }
        func optional<T>(_ key: String, _ fallback: T?) -> T? { old.keys.contains(key) ? old[key] as? T : fallback }
        id = value("id", tx.id); amount = value("amount", tx.amount)
        categoryKey = value("categoryKey", tx.categoryKey); subcategoryKey = optional("subcategoryKey", tx.subcategoryKey)
        note = optional("note", tx.note); date = value("date", tx.date); isIncome = value("isIncome", tx.isIncome)
        createdAt = value("createdAt", tx.createdAt); fundAccountKey = optional("fundAccountKey", tx.fundAccountKey)
        notInBudget = value("notInBudget", tx.notInBudget); billSource = optional("billSource", tx.billSource)
        merchantName = optional("merchantName", tx.merchantName); importFingerprint = optional("importFingerprint", tx.importFingerprint)
        creatorName = value("creatorName", tx.creatorName); isTrashed = value("isTrashed", tx.isTrashed)
        categoryNameSnapshot = optional("categoryNameSnapshot", tx.categoryNameSnapshot)
        categoryEmojiSnapshot = optional("categoryEmojiSnapshot", tx.categoryEmojiSnapshot)
    }
    func apply(to tx: BookkeepingTransaction) {
        tx.id = id; tx.amount = amount; tx.categoryKey = categoryKey; tx.subcategoryKey = subcategoryKey
        tx.note = note; tx.date = date; tx.isIncome = isIncome; tx.createdAt = createdAt
        tx.fundAccountKey = fundAccountKey; tx.notInBudget = notInBudget; tx.billSource = billSource
        tx.merchantName = merchantName; tx.importFingerprint = importFingerprint; tx.creatorName = creatorName
        tx.categoryNameSnapshot = categoryNameSnapshot; tx.categoryEmojiSnapshot = categoryEmojiSnapshot
        tx.isTrashed = isTrashed
    }
    static func record(_ transaction: BookkeepingTransaction, author: String, in context: NSManagedObjectContext) throws {
        guard let ledger = transaction.ledgerRaw else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func add(_ snapshot: LedgerRevision, action: String) throws {
            let activity = LedgerActivity(context: context)
            if let store = ledger.objectID.persistentStore { context.assign(activity, to: store) }
            activity.id = UUID(); activity.targetID = transaction.id; activity.date = Date()
            activity.author = author; activity.action = action; activity.ledgerRaw = ledger
            activity.snapshot = try encoder.encode(snapshot)
        }
        if !transaction.isInserted { try add(LedgerRevision(transaction, committed: true), action: "修改前") }
        try add(LedgerRevision(transaction), action: transaction.isTrashed ? "删除" : transaction.isInserted ? "新增" : "修改")
    }
}
