import Foundation
import CoreData

@objc(BudgetEntry)
final class BudgetEntry: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<BudgetEntry> {
        NSFetchRequest<BudgetEntry>(entityName: "BudgetEntry")
    }

    @NSManaged var id: UUID
    @NSManaged var categoryKey: String
    @NSManaged var monthlyAmount: Double
    @NSManaged var month: Date
    @NSManaged var createdAt: Date

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        categoryKey: String,
        monthlyAmount: Double,
        month: Date,
        createdAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.categoryKey = categoryKey
        self.monthlyAmount = monthlyAmount
        self.month = month
        self.createdAt = createdAt
    }
}
