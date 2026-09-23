import Foundation
import CoreData

@objc(AssetSaleRecord)
final class AssetSaleRecord: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AssetSaleRecord> {
        NSFetchRequest<AssetSaleRecord>(entityName: "AssetSaleRecord")
    }

    @NSManaged var id: UUID
    @NSManaged private var assetRaw: AssetItem?
    @NSManaged var saleDate: Date
    @NSManaged var salePrice: Double
    @NSManaged var platform: String?
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
        saleDate: Date = Date(),
        salePrice: Double,
        platform: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.assetRaw = asset
        self.saleDate = saleDate
        self.salePrice = salePrice
        self.platform = platform
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension AssetSaleRecord {
    static let platforms = [
        "闲鱼", "转转", "拍拍", "线下", "其他"
    ]
}
