import Foundation
import CoreData
import CryptoKit

/// Immutable operations travel in the same private CloudKit store as the ledger.
/// Causality, rather than device clocks, determines which edits supersede others.
struct PreferenceOperation: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case category, rule }
    var version = 1
    var id: String
    var kind: Kind
    var entityID: String
    var parents: [String]
    var payload: Data?
    var isSeed: Bool
    var date: Date

    var key: String { kind.rawValue + ":" + entityID }
    var label: String {
        guard let payload else { return "保留删除" }
        switch kind {
        case .category: return (try? JSONDecoder().decode(CustomCategory.self, from: payload).name) ?? "分类"
        case .rule: return (try? JSONDecoder().decode(KeywordRule.self, from: payload).keyWord) ?? "识别规则"
        }
    }
}

struct PreferenceResolution: Identifiable {
    var id: String { winner.key }
    let winner: PreferenceOperation
    let heads: [PreferenceOperation]
    let history: [PreferenceOperation]
    var hasConflict: Bool { Set(heads.map(\.payload)).count > 1 }
}

enum PreferenceSyncError: LocalizedError {
    case invalidData, incomplete, unavailable, deleted
    var errorDescription: String? {
        switch self {
        case .invalidData: return "分类或规则记录无法读取，请保留本机数据并更新 App 后重试。"
        case .incomplete: return "分类或规则仍在下载，请稍后重试。本机数据已保留。"
        case .unavailable: return "分类与规则暂时无法保存，请重试。本机原有数据已保留。"
        case .deleted: return "此项已被删除。如需恢复，请在 iCloud 分类与规则页面选择保留的版本。"
        }
    }
}

final class PreferenceJournal {
    static let entityName = "SyncedPreferenceOperation"
    let container: NSPersistentContainer
    let context: NSManagedObjectContext
    init(container: NSPersistentContainer, context: NSManagedObjectContext? = nil) {
        self.container = container
        self.context = context ?? container.newBackgroundContext()
        self.context.transactionAuthor = "PreferenceJournal"
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func ruleIdentity(_ rule: KeywordRule) throws -> String {
        if let id = rule.syncID, !id.isEmpty { return id }
        // Preserve different legacy rules even when different devices assigned the same integer ID.
        return "legacy-" + hash(try encode(rule))
    }
    static func canonicalRule(_ rule: KeywordRule, id: String) -> KeywordRule {
        var result = rule
        result.syncID = id
        result.ruleId = 0 // This is a device-local SQLite key, not a cloud identity.
        result.searchTexts = result.searchTexts?.map { text in
            var text = text; text.ruleId = 0; text.ruleKind = .local; return text
        }
        return result
    }
    static func seed(kind: PreferenceOperation.Kind, id: String, payload: Data) -> PreferenceOperation {
        let key = kind.rawValue + ":" + id
        return PreferenceOperation(id: "seed-" + hash(Data(key.utf8) + payload), kind: kind,
                                   entityID: id, parents: [], payload: payload, isSeed: true,
                                   date: Date(timeIntervalSince1970: 0))
    }

    static func resolve(_ input: [PreferenceOperation]) throws -> [PreferenceResolution] {
        var byID: [String: PreferenceOperation] = [:]
        for operation in input {
            guard operation.version == 1, !operation.id.isEmpty, !operation.entityID.isEmpty,
                  !operation.parents.contains(operation.id), !(operation.isSeed && (!operation.parents.isEmpty || operation.payload == nil))
            else { throw PreferenceSyncError.invalidData }
            if let old = byID[operation.id], old != operation { throw PreferenceSyncError.invalidData }
            if let payload = operation.payload {
                switch operation.kind {
                case .category:
                    guard try JSONDecoder().decode(CustomCategory.self, from: payload).id == operation.entityID else { throw PreferenceSyncError.invalidData }
                case .rule:
                    let rule = try JSONDecoder().decode(KeywordRule.self, from: payload)
                    guard rule.syncID == operation.entityID, rule.searchTexts?.first?.ruleKind == .local else { throw PreferenceSyncError.invalidData }
                }
            }
            byID[operation.id] = operation
        }
        // Partial CloudKit batches may contain children before their parents. Preserve the
        // projection until the whole graph is available; never infer deletions from missing rows.
        for op in byID.values {
            for parent in op.parents {
                guard let ancestor = byID[parent] else { throw PreferenceSyncError.incomplete }
                guard ancestor.key == op.key else { throw PreferenceSyncError.invalidData }
            }
        }
        // Kahn's algorithm also rejects cycles without recursion on long-lived histories.
        var remaining = byID.mapValues { Set($0.parents).count }
        var children: [String: [String]] = [:]
        for op in byID.values { for parent in Set(op.parents) { children[parent, default: []].append(op.id) } }
        var queue = remaining.filter { $0.value == 0 }.map(\.key)
        var cursor = 0
        while cursor < queue.count {
            let id = queue[cursor]; cursor += 1
            for child in children[id] ?? [] {
                remaining[child, default: 0] -= 1
                if remaining[child] == 0 { queue.append(child) }
            }
        }
        guard queue.count == byID.count else { throw PreferenceSyncError.invalidData }
        return Dictionary(grouping: byID.values, by: \.key).values.map { history in
            let superseded = Set(history.flatMap(\.parents))
            var heads = history.filter { !superseded.contains($0.id) }
            // A legacy cache arriving late must not resurrect a deleted or edited item.
            if heads.contains(where: { !$0.isSeed }) { heads.removeAll(where: \.isSeed) }
            heads.sort { $0.id < $1.id }
            let winner = heads.first(where: { $0.payload == nil }) ?? heads[0]
            return PreferenceResolution(winner: winner, heads: heads, history: history.sorted { $0.id < $1.id })
        }.sorted { $0.id < $1.id }
    }

    func operations(in suppliedContext: NSManagedObjectContext? = nil) throws -> [PreferenceOperation] {
        let target = suppliedContext ?? context
        return try target.performAndWait {
            try target.fetch(NSFetchRequest<NSManagedObject>(entityName: Self.entityName)).map {
                guard let data = $0.value(forKey: "encodedOperation") as? Data else { throw PreferenceSyncError.invalidData }
                let op = try JSONDecoder().decode(PreferenceOperation.self, from: data)
                guard op.id == $0.value(forKey: "operationID") as? String else { throw PreferenceSyncError.invalidData }
                return op
            }
        }
    }
    func resolutions() throws -> [PreferenceResolution] { try Self.resolve(operations()) }

    /// Can stage operations in a ledger restore transaction; the caller then owns save/rollback.
    func append(_ operations: [PreferenceOperation], in suppliedContext: NSManagedObjectContext? = nil) throws {
        let target = suppliedContext ?? context
        try target.performAndWait {
            do {
                let existing = try self.operations(in: target)
                _ = try Self.resolve(existing + operations)
                var ids = Set(existing.map(\.id))
                for operation in operations where ids.insert(operation.id).inserted {
                    let row = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: target)
                    row.setValue(operation.id, forKey: "operationID")
                    row.setValue(try Self.encode(operation), forKey: "encodedOperation")
                }
                if suppliedContext == nil, target.hasChanges { try target.save() }
            } catch {
                if suppliedContext == nil { target.rollback() }
                throw error
            }
        }
    }

    func change(kind: PreferenceOperation.Kind, id: String, payload: Data?, allowRestore: Bool = false,
                in target: NSManagedObjectContext? = nil) throws -> PreferenceOperation {
        let state = try Self.resolve(operations(in: target)).first { $0.winner.kind == kind && $0.winner.entityID == id }
        if payload != nil, state?.winner.payload == nil, state != nil, !allowRestore { throw PreferenceSyncError.deleted }
        return PreferenceOperation(id: UUID().uuidString, kind: kind, entityID: id,
                                   parents: state?.heads.map(\.id) ?? [], payload: payload, isSeed: false, date: Date())
    }
}
