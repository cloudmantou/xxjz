import Foundation
import CoreData

@objc(AssetExtraCost)
final class AssetExtraCost: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AssetExtraCost> {
        NSFetchRequest<AssetExtraCost>(entityName: "AssetExtraCost")
    }

    @NSManaged var id: UUID
    @NSManaged private var assetRaw: AssetItem?
    @NSManaged var costType: String
    @NSManaged var amount: Double
    @NSManaged var date: Date
    @NSManaged var notes: String?
    @NSManaged var createdAt: Date

    var asset: AssetItem? {
        get { assetRaw }
        set { assetRaw = newValue }
    }

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        asset: AssetItem? = nil,
        costType: String,
        amount: Double,
        date: Date = Date(),
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.assetRaw = asset
        self.costType = costType
        self.amount = amount
        self.date = date
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension AssetExtraCost {
    static let costTypes = [
        "维修", "升级", "保险", "配件", "运费", "税费", "其他"
    ]
}
