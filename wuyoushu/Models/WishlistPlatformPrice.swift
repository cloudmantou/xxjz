import Foundation
import CoreData

@objc(WishlistPlatformPrice)
final class WishlistPlatformPrice: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<WishlistPlatformPrice> {
        NSFetchRequest<WishlistPlatformPrice>(entityName: "WishlistPlatformPrice")
    }

    @NSManaged var id: UUID
    @NSManaged private var wishlistItemRaw: WishlistItem?
    @NSManaged var platform: String
    @NSManaged var price: Double
    @NSManaged var url: String?
    @NSManaged var lastUpdated: Date

    var wishlistItem: WishlistItem? {
        get { wishlistItemRaw }
        set { wishlistItemRaw = newValue }
    }

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        wishlistItem: WishlistItem? = nil,
        platform: String,
        price: Double,
        url: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.wishlistItemRaw = wishlistItem
        self.platform = platform
        self.price = price
        self.url = url
        self.lastUpdated = lastUpdated
    }
}

extension WishlistPlatformPrice {
    static let platforms = [
        "京东", "天猫", "淘宝", "拼多多", "亚马逊",
        "苏宁", "国美", "官方商城", "线下门店", "其他"
    ]
}
