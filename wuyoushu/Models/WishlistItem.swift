import Foundation
import CoreData

@objc(WishlistItem)
final class WishlistItem: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<WishlistItem> {
        NSFetchRequest<WishlistItem>(entityName: "WishlistItem")
    }

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var category: String
    @NSManaged var targetPrice: Double
    @NSManaged var targetDailyCost: Double
    @NSManaged var priority: Int16
    @NSManaged var notes: String?
    @NSManaged var imageData: Data?
    @NSManaged var isPurchased: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged private var platformPricesRaw: NSSet?
    @NSManaged private var priceHistoriesRaw: NSSet?

    var platformPrices: [WishlistPlatformPrice] {
        get {
            (platformPricesRaw as? Set<WishlistPlatformPrice> ?? [])
                .sorted { $0.lastUpdated > $1.lastUpdated }
        }
        set {
            platformPricesRaw = NSSet(array: newValue)
        }
    }

    var priceHistories: [WishlistPriceHistory] {
        get {
            (priceHistoriesRaw as? Set<WishlistPriceHistory> ?? [])
                .sorted { $0.recordedAt > $1.recordedAt }
        }
        set {
            priceHistoriesRaw = NSSet(array: newValue)
        }
    }

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        name: String,
        category: String,
        targetPrice: Double,
        targetDailyCost: Double = 0,
        priority: Int = 3,
        notes: String? = nil,
        imageData: Data? = nil,
        isPurchased: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.name = name
        self.category = category
        self.targetPrice = targetPrice
        self.targetDailyCost = targetDailyCost
        self.priority = Int16(priority)
        self.notes = notes
        self.imageData = imageData
        self.isPurchased = isPurchased
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.platformPricesRaw = NSSet()
        self.priceHistoriesRaw = NSSet()
    }

    var currentLowestPrice: Double? {
        platformPrices.map(\.price).min()
    }

    var averagePrice: Double? {
        guard !platformPrices.isEmpty else { return nil }
        return platformPrices.map(\.price).reduce(0, +) / Double(platformPrices.count)
    }
}

extension WishlistItem {
    static let categories = [
        "电子产品", "数码配件", "家居用品", "服饰鞋包", "图书音像",
        "运动户外", "美妆护肤", "食品饮料", "其他"
    ]

    static let priorities = [
        (1, "最低"),
        (2, "较低"),
        (3, "中等"),
        (4, "较高"),
        (5, "最高")
    ]
}
