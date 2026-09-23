import Foundation
import CoreData

enum AssetStatus: String, Codable, CaseIterable {
    case active = "使用中"
    case sold = "已卖出"
    case disposed = "已报废"

    var localizedTitle: String {
        L10n.tr(rawValue)
    }

    var color: String {
        switch self {
        case .active: return "green"
        case .sold: return "blue"
        case .disposed: return "gray"
        }
    }
}

@objc(AssetItem)
final class AssetItem: NSManagedObject, Identifiable {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AssetItem> {
        NSFetchRequest<AssetItem>(entityName: "AssetItem")
    }

    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var category: String
    @NSManaged var purchaseDate: Date
    @NSManaged var purchasePrice: Double
    @NSManaged var currentValue: Double
    @NSManaged private var statusRaw: String
    @NSManaged var notes: String?
    @NSManaged var imageData: Data?
    @NSManaged var isFavorite: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged private var extraCostsRaw: NSSet?
    @NSManaged private var saleRecordsRaw: NSSet?

    var status: AssetStatus {
        get { AssetStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var extraCosts: [AssetExtraCost] {
        get {
            (extraCostsRaw as? Set<AssetExtraCost> ?? [])
                .sorted { $0.date > $1.date }
        }
        set {
            extraCostsRaw = NSSet(array: newValue)
        }
    }

    var saleRecords: [AssetSaleRecord] {
        get {
            (saleRecordsRaw as? Set<AssetSaleRecord> ?? [])
                .sorted { $0.saleDate > $1.saleDate }
        }
        set {
            saleRecordsRaw = NSSet(array: newValue)
        }
    }

    convenience init(
        context: NSManagedObjectContext = PersistenceController.preview.container.viewContext,
        id: UUID = UUID(),
        name: String,
        category: String,
        purchaseDate: Date = Date(),
        purchasePrice: Double,
        currentValue: Double? = nil,
        status: AssetStatus = .active,
        notes: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.name = name
        self.category = category
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.currentValue = currentValue ?? purchasePrice
        self.statusRaw = status.rawValue
        self.notes = notes
        self.imageData = imageData
        self.isFavorite = false
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.extraCostsRaw = NSSet()
        self.saleRecordsRaw = NSSet()
    }

    var totalExtraCost: Double {
        extraCosts.reduce(0) { $0 + $1.amount }
    }

    var totalCost: Double {
        purchasePrice + totalExtraCost
    }

    var holdingDays: Int {
        Calendar.current.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 0
    }

    var dailyCost: Double {
        guard holdingDays > 0 else { return totalCost }
        return totalCost / Double(holdingDays)
    }
}
