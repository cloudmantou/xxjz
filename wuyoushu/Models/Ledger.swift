import Foundation
import CoreData

@objc(Ledger)
final class Ledger: NSManagedObject, Identifiable {
    static let personalID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var emoji: String
    @NSManaged var currencyCode: String
    @NSManaged var createdAt: Date
    @NSManaged var archived: Bool
    @NSManaged var targetCents: Int64
    @NSManaged var targetDate: Date?
    @NSManaged var transactionsRaw: NSSet?
    @NSManaged var budgetsRaw: NSSet?
    @NSManaged var activitiesRaw: NSSet?
    var isPersonalDefault: Bool { id == Self.personalID }
    @nonobjc class func fetchRequest() -> NSFetchRequest<Ledger> { NSFetchRequest(entityName: "Ledger") }
}

@objc(LedgerActivity)
final class LedgerActivity: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var targetID: UUID
    @NSManaged var date: Date
    @NSManaged var author: String
    @NSManaged var action: String
    @NSManaged var snapshot: Data?
    @NSManaged var ledgerRaw: Ledger?
    @nonobjc class func fetchRequest() -> NSFetchRequest<LedgerActivity> { NSFetchRequest(entityName: "LedgerActivity") }
}

/// Pass this immutable scope into background work before it starts. A selection change
/// must never move an in-flight import into another ledger.
struct LedgerScope {
    let objectID: NSManagedObjectID?
    let store: NSPersistentStore?
    let isPersonal: Bool
    let name: String

    func predicate(_ additional: NSPredicate? = nil, includesDeleted: Bool = false) -> NSPredicate {
        let ledger: NSPredicate
        if isPersonal {
            ledger = NSPredicate(format: "ledgerRaw == nil OR ledgerRaw.id == %@", Ledger.personalID as NSUUID)
        } else if let objectID {
            ledger = NSPredicate(format: "ledgerRaw == %@", objectID)
        } else { ledger = NSPredicate(value: false) }
        var predicates = [ledger]
        if !includesDeleted { predicates.append(NSPredicate(format: "isTrashed == NO")) }
        if let additional { predicates.append(additional) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
    func apply<T>(_ request: NSFetchRequest<T>, includesDeleted: Bool = false) {
        request.predicate = predicate(request.predicate, includesDeleted: includesDeleted)
        if let store { request.affectedStores = [store] }
    }
    func attach(_ object: NSManagedObject, in context: NSManagedObjectContext) throws {
        if let store { context.assign(object, to: store) }
        if let objectID {
            let ledger = try context.existingObject(with: objectID)
            guard !ledger.isDeleted else { throw LedgerError.unavailable }
            object.setValue(ledger, forKey: "ledgerRaw")
        } else if !isPersonal { throw LedgerError.unavailable }
    }
}

enum LedgerError: LocalizedError {
    case unavailable, readOnly, invalidName, invalidAmount, defaultNotShareable, cloudUnavailable, archived, cloudTimedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: return "账本暂不可用，可能尚未下载或已停止共享。请重新选择账本。"
        case .readOnly: return "你对这个账本只有查看权限，无法修改记录。"
        case .invalidName: return "请输入 1 至 40 个字的账本名称。"
        case .invalidAmount: return "请输入有效金额，最多保留两位小数。"
        case .defaultNotShareable: return "个人默认账本保留为私密账本。请新建家庭、情侣或攒钱账本，再邀请成员。"
        case .cloudUnavailable: return "请开启 iCloud 同步并登录 iCloud 后重试。"
        case .cloudTimedOut: return "iCloud 响应超时。系统可能仍在处理，请稍后重新打开共享管理检查结果。"
        case .archived: return "此账本已归档，请先取消归档再记账。"
        }
    }
}

enum LedgerMoney {
    static func cents(_ text: String) throws -> Int64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.range(of: #"^\d{1,12}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else { throw LedgerError.invalidAmount }
        return NSDecimalNumber(decimal: value * 100).int64Value
    }
    static func total(_ transactions: [BookkeepingTransaction]) -> Decimal {
        transactions.filter { !$0.isTrashed }.reduce(Decimal.zero) { sum, transaction in
            guard transaction.signedAmount.isFinite else { return sum }
            guard let value = Decimal(string: String(transaction.signedAmount), locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return sum }
            return sum + value
        }
    }
}
