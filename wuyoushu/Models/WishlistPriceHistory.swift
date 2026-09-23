import Foundation
import CoreData

@objc(WishlistPriceHistory)
final class WishlistPriceHistory: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<WishlistPriceHistory> {
        NSFetchRequest<WishlistPriceHistory>(entityName: "WishlistPriceHistory")
    }

    @NSManaged var id: UUID
    @NSManaged private var wishlistItemRaw: WishlistItem?
    @NSManaged var price: Double
    @NSManaged var recordedAt: Date

    var wishlistItem: WishlistItem? {
        get { wishlistItemRaw }
        set { wishlistItemRaw = newValue }
    }

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        wishlistItem: WishlistItem? = nil,
        price: Double,
        recordedAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.wishlistItemRaw = wishlistItem
        self.price = price
        self.recordedAt = recordedAt
    }
}
