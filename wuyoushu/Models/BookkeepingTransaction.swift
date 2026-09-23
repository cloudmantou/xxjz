import Foundation
import CoreData

enum TransactionKind: Equatable {
    case expense
    case income
    case transfer
}

@objc(BookkeepingTransaction)
final class BookkeepingTransaction: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BookkeepingTransaction> {
        NSFetchRequest<BookkeepingTransaction>(entityName: "BookkeepingTransaction")
    }

    @NSManaged var id: UUID
    @NSManaged var amount: Double
    @NSManaged var categoryKey: String
    @NSManaged var subcategoryKey: String?
    @NSManaged var note: String?
    @NSManaged var date: Date
    @NSManaged var isIncome: Bool
    @NSManaged var createdAt: Date
    @NSManaged var fundAccountKey: String?
    @NSManaged var notInBudget: Bool
    @NSManaged var billSource: String?
    @NSManaged var merchantName: String?
    @NSManaged var importFingerprint: String?

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        amount: Double,
        categoryKey: String,
        subcategoryKey: String? = nil,
        note: String? = nil,
        date: Date = Date(),
        isIncome: Bool = false,
        createdAt: Date = Date(),
        fundAccountKey: String? = nil,
        notInBudget: Bool = false,
        billSource: String? = nil,
        merchantName: String? = nil,
        importFingerprint: String? = nil
    ) {
        self.init(context: context)
        self.id = id
        self.amount = amount
        self.categoryKey = categoryKey
        self.subcategoryKey = subcategoryKey
        self.note = note
        self.date = date
        self.isIncome = isIncome
        self.createdAt = createdAt
        self.fundAccountKey = fundAccountKey
        self.notInBudget = notInBudget
        self.billSource = billSource
        self.merchantName = merchantName
        self.importFingerprint = importFingerprint
    }

    var categoryName: String {
        BookkeepingCategory.find(key: categoryKey)?.localizedName ?? categoryKey
    }

    var categoryEmoji: String {
        BookkeepingCategory.find(key: categoryKey)?.emoji ?? "📦"
    }

    var subcategoryName: String? {
        guard let key = subcategoryKey else { return nil }
        return BookkeepingCategory.findSubcategory(key: key)?.localizedName
    }

    /// Normalize legacy signed amounts so statistics are always based on transaction type.
    var normalizedAmount: Double {
        abs(amount)
    }

    /// Derive the current three transaction kinds from the persisted legacy fields.
    /// New Core Data storage can be introduced with a dedicated migration later.
    var kind: TransactionKind {
        if categoryKey == "transfer" { return .transfer }
        return isIncome ? .income : .expense
    }

    var contributesToIncome: Bool { kind == .income }
    var contributesToExpense: Bool { kind == .expense }

    var amountDisplayText: String {
        switch kind {
        case .income: return "+\(normalizedAmount.currencyString)"
        case .expense: return "-\(normalizedAmount.currencyString)"
        case .transfer: return "↔︎ \(normalizedAmount.currencyString)"
        }
    }

    /// Signed amount derived from transaction type (income positive, expense negative).
    var signedAmount: Double {
        switch kind {
        case .income: return normalizedAmount
        case .expense: return -normalizedAmount
        case .transfer: return 0
        }
    }
}
