import Foundation
import CoreData
import Combine

/// Core Data is authoritative; UserDefaults/SQLite remain compatible read projections.
/// All production entry points and projections run on the main queue. CloudKit notifications
/// enqueue work there; projection writes never generate new cloud operations.
final class PreferenceSyncCoordinator: ObservableObject {
    static let shared = PreferenceSyncCoordinator()
    @Published private(set) var errorMessage: String?
    @Published private(set) var conflicts: [PreferenceResolution] = []
    @Published private(set) var deletedItems: [PreferenceResolution] = []
    @Published private(set) var isReady = false
    private(set) var isConfigured = false
    private var journal: PreferenceJournal?
    private var observers: [NSObjectProtocol] = []
    private var migrationKey = ""
    private let defaults: UserDefaults
    private let categories: CustomCategoryStore
    private let rules: KeywordRulesTable
    private let backupDirectory: URL
    private let didProjectRules: () -> Void

    init(defaults: UserDefaults = .standard, categories: CustomCategoryStore = .shared,
         rules: KeywordRulesTable = .shared, backupDirectory: URL? = nil,
         didProjectRules: @escaping () -> Void = { RuleUpdateService.shared.preferencesDidProject() }) {
        self.defaults = defaults; self.categories = categories; self.rules = rules
        self.backupDirectory = backupDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PreferenceMigrationBackups", isDirectory: true)
        self.didProjectRules = didProjectRules
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(container: NSPersistentContainer) {
        isConfigured = true
        guard container.persistentStoreCoordinator.persistentStores.count == 1,
              let store = container.persistentStoreCoordinator.persistentStores.first else {
            errorMessage = PreferenceSyncError.unavailable.localizedDescription; return
        }
        journal = PreferenceJournal(container: container)
        migrationKey = "preference-journal-migrated-v1-" + store.identifier
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator, queue: .main) { [weak self] _ in self?.refresh() }]
        refresh()
    }

    func refresh() {
        guard let journal else { return }
        defer { writeDiagnostics() }
        do {
            if !defaults.bool(forKey: migrationKey) {
                struct LegacySnapshot: Codable { let categories: [CustomCategory]; let rules: [KeywordRule] }
                let legacyCategories = try categories.backupSnapshot()
                let legacyRules = try rules.fetchAllRulesStrict().filter { $0.searchTexts?.first?.ruleKind == .local }
                let snapshot = LegacySnapshot(categories: legacyCategories, rules: legacyRules)
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                let bytes = try PreferenceJournal.encode(snapshot)
                let backup = backupDirectory.appendingPathComponent("legacy-" + PreferenceJournal.hash(bytes) + ".json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try bytes.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                var seeds = try legacyCategories.map { category in
                    PreferenceJournal.seed(kind: .category, id: category.id, payload: try PreferenceJournal.encode(category))
                }
                seeds += try legacyRules.map { rule in
                    let id = try PreferenceJournal.ruleIdentity(rule)
                    return PreferenceJournal.seed(kind: .rule, id: id, payload: try PreferenceJournal.encode(PreferenceJournal.canonicalRule(rule, id: id)))
                }
                try journal.append(seeds)
                // Commit journal before marker, marker before projection. Replaying after a
                // crash deduplicates deterministic seeds; old snapshots are never removed.
                defaults.set(true, forKey: migrationKey)
            }
            try project(journal.resolutions())
            isReady = true; errorMessage = nil
        } catch {
            isReady = false
            errorMessage = (error as? PreferenceSyncError)?.localizedDescription ?? PreferenceSyncError.unavailable.localizedDescription
        }
    }

    private func writeDiagnostics() {
        // Counts/status only: never include category names, rule text, IDs or ledger content.
        guard self === Self.shared,
              let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("PreferenceSyncDiagnostics.json") else { return }
        let snapshot: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "ready": isReady, "hasError": errorMessage != nil,
            "categoryCount": categories.categories.count,
            "localRuleCount": (try? rules.fetchAllRulesStrict().filter { $0.searchTexts?.first?.ruleKind == .local }.count) ?? -1,
            "operationCount": (try? journal?.operations().count) ?? -1,
            "conflictCount": conflicts.count, "deletedCount": deletedItems.count
        ]
        if let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func project(_ states: [PreferenceResolution]) throws {
        var liveCategories: [CustomCategory] = []
        var historicalCategories: [CustomCategory] = []
        var liveRules: [KeywordRule] = []
        for state in states {
            switch state.winner.kind {
            case .category:
                if let payload = state.winner.payload { liveCategories.append(try JSONDecoder().decode(CustomCategory.self, from: payload)) }
                if let payload = state.historicalPayload {
                    historicalCategories.append(try JSONDecoder().decode(CustomCategory.self, from: payload))
                }
            case .rule:
                if let payload = state.winner.payload { liveRules.append(try JSONDecoder().decode(KeywordRule.self, from: payload)) }
            }
        }
        let oldLocal = try rules.fetchAllRulesStrict().filter { $0.searchTexts?.first?.ruleKind == .local }
        func normalized(_ input: [KeywordRule]) throws -> Data {
            try PreferenceJournal.encode(input.map { PreferenceJournal.canonicalRule($0, id: $0.syncID ?? "") }
                .sorted { ($0.syncID ?? "") < ($1.syncID ?? "") })
        }
        if try normalized(oldLocal) != normalized(liveRules) {
            try rules.replaceLocalRules(liveRules)
            didProjectRules()
        }
        guard categories.applyProjection(liveCategories.sorted { $0.id < $1.id }, historical: historicalCategories) else {
            throw PreferenceSyncError.unavailable
        }
        conflicts = states.filter(\.hasConflict)
        deletedItems = states.filter { $0.winner.payload == nil }
    }

    private func commit(_ make: (PreferenceJournal) throws -> [PreferenceOperation]) -> Bool {
        refresh()
        guard isReady, let journal else { return false }
        do {
            try journal.append(make(journal))
            // A committed operation is durable even if rebuilding a read projection fails.
            refresh()
            return true
        } catch {
            errorMessage = (error as? PreferenceSyncError)?.localizedDescription ?? PreferenceSyncError.unavailable.localizedDescription
            return false
        }
    }
    func saveCategory(_ category: CustomCategory) -> Bool {
        commit { [try $0.change(kind: .category, id: category.id, payload: PreferenceJournal.encode(category))] }
    }
    func deleteCategory(_ category: CustomCategory) -> Bool {
        commit { [try $0.change(kind: .category, id: category.id, payload: nil)] }
    }
    func saveRule(_ rule: KeywordRule) -> Bool {
        commit { journal in
            let current = try rules.fetchAllRulesStrict().first { $0.ruleId == rule.ruleId && $0.searchTexts?.first?.ruleKind == .local }
            let id = rule.syncID ?? current?.syncID ?? UUID().uuidString
            return [try journal.change(kind: .rule, id: id, payload: PreferenceJournal.encode(PreferenceJournal.canonicalRule(rule, id: id)))]
        }
    }
    func deleteRule(_ rule: KeywordRule) -> Bool {
        commit { journal in
            let current = try rules.fetchAllRulesStrict().first { $0.ruleId == rule.ruleId && $0.searchTexts?.first?.ruleKind == .local }
            guard let id = rule.syncID ?? current?.syncID else { throw PreferenceSyncError.unavailable }
            return [try journal.change(kind: .rule, id: id, payload: nil)]
        }
    }
    func resolve(_ state: PreferenceResolution, choosing version: PreferenceOperation) -> Bool {
        commit { journal in
            // Only acknowledge the versions the user actually reviewed. A newer unseen edit
            // remains concurrent and visible in conflicts instead of being silently overwritten.
            guard state.history.contains(version), version.key == state.id else { throw PreferenceSyncError.invalidData }
            return [PreferenceOperation(id: UUID().uuidString, kind: version.kind, entityID: version.entityID,
                                        parents: state.heads.map(\.id), payload: version.payload, isSeed: false, date: Date())]
        }
    }

    func owns(_ context: NSManagedObjectContext) -> Bool {
        journal?.container.persistentStoreCoordinator === context.persistentStoreCoordinator
    }
    func backupHistory(in context: NSManagedObjectContext) throws -> [PreferenceOperation]? {
        guard owns(context), let journal else { return nil }
        let history = try journal.operations(in: context)
        _ = try PreferenceJournal.resolve(history)
        return history.sorted { $0.id < $1.id }
    }
    /// Called inside the same context transaction as ledger replacement, before its save.
    /// No cache changes or cloud writes occur unless that transaction commits.
    func stageRestore(categories replacements: [CustomCategory], rules restored: [KeywordRule], history: [PreferenceOperation] = [], in context: NSManagedObjectContext) throws {
        guard isReady, let journal, owns(context) else { throw PreferenceSyncError.unavailable }
        try journal.append(history, in: context)
        let states = try PreferenceJournal.resolve(journal.operations(in: context))
        var desired: [String: (PreferenceOperation.Kind, String, Data)] = [:]
        for category in replacements {
            desired["category:" + category.id] = (.category, category.id, try PreferenceJournal.encode(category))
        }
        for rule in restored where rule.searchTexts?.first?.ruleKind == .local {
            let id = try PreferenceJournal.ruleIdentity(rule)
            desired["rule:" + id] = (.rule, id, try PreferenceJournal.encode(PreferenceJournal.canonicalRule(rule, id: id)))
        }
        var operations: [PreferenceOperation] = []
        for state in states where desired[state.id] == nil && state.winner.payload != nil {
            operations.append(try journal.change(kind: state.winner.kind, id: state.winner.entityID, payload: nil, in: context))
        }
        for (_, value) in desired {
            operations.append(try journal.change(kind: value.0, id: value.1, payload: value.2, allowRestore: true, in: context))
        }
        try journal.append(operations, in: context)
    }
}
