import Foundation
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let sampleAsset = AssetItem(
            context: context,
            name: "iPhone 15 Pro Max",
            category: "电子产品",
            purchasePrice: 9999,
            currentValue: 8200
        )
        let sampleCost = AssetExtraCost(
            context: context,
            asset: sampleAsset,
            costType: "配件",
            amount: 399
        )
        sampleAsset.extraCosts.append(sampleCost)

        let sampleWish = WishlistItem(
            context: context,
            name: "Dyson 吹风机",
            category: "家居用品",
            targetPrice: 2299,
            priority: 4
        )
        let platform = WishlistPlatformPrice(
            context: context,
            wishlistItem: sampleWish,
            platform: "京东",
            price: 2599
        )
        sampleWish.platformPrices.append(platform)

        // Sample bookkeeping transactions
        _ = BookkeepingTransaction(
            context: context,
            amount: 35,
            categoryKey: "dining",
            subcategoryKey: "lunch",
            note: "午餐"
        )
        _ = BookkeepingTransaction(
            context: context,
            amount: 6,
            categoryKey: "transport",
            subcategoryKey: "metro",
            note: "地铁"
        )
        _ = BookkeepingTransaction(
            context: context,
            amount: 10000,
            categoryKey: "salary",
            note: "工资",
            isIncome: true
        )

        // Sample budget
        _ = BudgetEntry(
            context: context,
            categoryKey: "dining",
            monthlyAmount: 2000,
            month: Date().startOfMonth
        )

        try? context.save()
        return controller
    }()

    let container: NSPersistentCloudKitContainer
    let bookkeepingCloudSyncEnabled: Bool

    init(inMemory: Bool = false) {
        let userWantsCloud = !inMemory && (UserDefaults.standard.object(forKey: Constants.ICloud.cloudSyncPreferenceKey) as? Bool ?? true)
        let requestedCloudSync = userWantsCloud
        let model = Self.makeModel(enableUniqueConstraints: !requestedCloudSync)
        let defaultStoreURL = NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("AssetLife.sqlite")
        let loaded = Self.buildContainer(
            model: model,
            storeURL: defaultStoreURL,
            inMemory: inMemory,
            cloudSyncRequested: requestedCloudSync
        )
        container = loaded.container
        bookkeepingCloudSyncEnabled = loaded.cloudSyncEnabled
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func buildContainer(
        model: NSManagedObjectModel,
        storeURL: URL,
        inMemory: Bool,
        cloudSyncRequested: Bool
    ) -> (container: NSPersistentCloudKitContainer, cloudSyncEnabled: Bool) {
        var container = NSPersistentCloudKitContainer(name: "AssetLife", managedObjectModel: model)
        container.persistentStoreDescriptions = [
            makeStoreDescription(
                storeURL: storeURL,
                inMemory: inMemory,
                cloudSyncEnabled: cloudSyncRequested
            )
        ]

        if let error = loadPersistentStoresSync(container: container) {
            guard cloudSyncRequested, !inMemory else {
                fatalError("Core Data persistent store load failed: \(error)")
            }

            // CloudKit can be unavailable for many reasons (account/network/capability mismatch).
            // We gracefully fall back to a local-only store so bookkeeping remains usable.
            print("CloudKit store load failed, fallback to local store: \(error)")

            container = NSPersistentCloudKitContainer(name: "AssetLife", managedObjectModel: model)
            container.persistentStoreDescriptions = [
                makeStoreDescription(
                    storeURL: storeURL,
                    inMemory: false,
                    cloudSyncEnabled: false
                )
            ]

            if let fallbackError = loadPersistentStoresSync(container: container) {
                fatalError("Core Data fallback store load failed: \(fallbackError)")
            }
            return (container, false)
        }

        return (container, cloudSyncRequested && !inMemory)
    }

    private static func makeStoreDescription(
        storeURL: URL,
        inMemory: Bool,
        cloudSyncEnabled: Bool
    ) -> NSPersistentStoreDescription {
        let description: NSPersistentStoreDescription = inMemory
            ? NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            : NSPersistentStoreDescription(url: storeURL)

        if cloudSyncEnabled {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Constants.ICloud.containerIdentifier
            )
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        } else {
            description.cloudKitContainerOptions = nil
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        return description
    }

    private static func loadPersistentStoresSync(container: NSPersistentCloudKitContainer) -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?

        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        return loadError
    }

    private static func makeModel(enableUniqueConstraints: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let assetEntity = NSEntityDescription()
        assetEntity.name = "AssetItem"
        assetEntity.managedObjectClassName = NSStringFromClass(AssetItem.self)

        let extraCostEntity = NSEntityDescription()
        extraCostEntity.name = "AssetExtraCost"
        extraCostEntity.managedObjectClassName = NSStringFromClass(AssetExtraCost.self)

        let saleEntity = NSEntityDescription()
        saleEntity.name = "AssetSaleRecord"
        saleEntity.managedObjectClassName = NSStringFromClass(AssetSaleRecord.self)

        let wishEntity = NSEntityDescription()
        wishEntity.name = "WishlistItem"
        wishEntity.managedObjectClassName = NSStringFromClass(WishlistItem.self)

        let platformEntity = NSEntityDescription()
        platformEntity.name = "WishlistPlatformPrice"
        platformEntity.managedObjectClassName = NSStringFromClass(WishlistPlatformPrice.self)

        let historyEntity = NSEntityDescription()
        historyEntity.name = "WishlistPriceHistory"
        historyEntity.managedObjectClassName = NSStringFromClass(WishlistPriceHistory.self)

        // MARK: - Bookkeeping Entities

        let transactionEntity = NSEntityDescription()
        transactionEntity.name = "BookkeepingTransaction"
        transactionEntity.managedObjectClassName = NSStringFromClass(BookkeepingTransaction.self)

        let budgetEntity = NSEntityDescription()
        budgetEntity.name = "BudgetEntry"
        budgetEntity.managedObjectClassName = NSStringFromClass(BudgetEntry.self)

        assetEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("category", .stringAttributeType),
            attribute("purchaseDate", .dateAttributeType),
            attribute("purchasePrice", .doubleAttributeType),
            attribute("currentValue", .doubleAttributeType),
            attribute("statusRaw", .stringAttributeType),
            attribute("notes", .stringAttributeType, optional: true),
            binaryAttribute("imageData", optional: true),
            attribute("isFavorite", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            assetEntity.uniquenessConstraints = [["id"]]
        }

        extraCostEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("costType", .stringAttributeType),
            attribute("amount", .doubleAttributeType),
            attribute("date", .dateAttributeType),
            attribute("notes", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            extraCostEntity.uniquenessConstraints = [["id"]]
        }

        saleEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("saleDate", .dateAttributeType),
            attribute("salePrice", .doubleAttributeType),
            attribute("platform", .stringAttributeType, optional: true),
            attribute("notes", .stringAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            saleEntity.uniquenessConstraints = [["id"]]
        }

        wishEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("category", .stringAttributeType),
            attribute("targetPrice", .doubleAttributeType),
            attribute("targetDailyCost", .doubleAttributeType),
            attribute("priority", .integer16AttributeType),
            attribute("notes", .stringAttributeType, optional: true),
            binaryAttribute("imageData", optional: true),
            attribute("isPurchased", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            wishEntity.uniquenessConstraints = [["id"]]
        }

        platformEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("platform", .stringAttributeType),
            attribute("price", .doubleAttributeType),
            attribute("url", .stringAttributeType, optional: true),
            attribute("lastUpdated", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            platformEntity.uniquenessConstraints = [["id"]]
        }

        historyEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("price", .doubleAttributeType),
            attribute("recordedAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            historyEntity.uniquenessConstraints = [["id"]]
        }

        transactionEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("amount", .doubleAttributeType),
            attribute("categoryKey", .stringAttributeType),
            attribute("subcategoryKey", .stringAttributeType, optional: true),
            attribute("note", .stringAttributeType, optional: true),
            attribute("date", .dateAttributeType),
            attribute("isIncome", .booleanAttributeType),
            attribute("createdAt", .dateAttributeType),
            attribute("fundAccountKey", .stringAttributeType, optional: true),
            attribute("notInBudget", .booleanAttributeType),
            attribute("billSource", .stringAttributeType, optional: true),
            attribute("merchantName", .stringAttributeType, optional: true)
        ]
        if enableUniqueConstraints {
            transactionEntity.uniquenessConstraints = [["id"]]
        }

        budgetEntity.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("categoryKey", .stringAttributeType),
            attribute("monthlyAmount", .doubleAttributeType),
            attribute("month", .dateAttributeType),
            attribute("createdAt", .dateAttributeType)
        ]
        if enableUniqueConstraints {
            budgetEntity.uniquenessConstraints = [["categoryKey", "month"]]
        }

        let assetToExtra = relationship(
            name: "extraCostsRaw",
            destination: extraCostEntity,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let extraToAsset = relationship(
            name: "assetRaw",
            destination: assetEntity,
            toMany: false,
            deleteRule: .nullifyDeleteRule,
            optional: true
        )
        assetToExtra.inverseRelationship = extraToAsset
        extraToAsset.inverseRelationship = assetToExtra

        let assetToSale = relationship(
            name: "saleRecordsRaw",
            destination: saleEntity,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let saleToAsset = relationship(
            name: "assetRaw",
            destination: assetEntity,
            toMany: false,
            deleteRule: .nullifyDeleteRule,
            optional: true
        )
        assetToSale.inverseRelationship = saleToAsset
        saleToAsset.inverseRelationship = assetToSale

        let wishToPlatform = relationship(
            name: "platformPricesRaw",
            destination: platformEntity,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let platformToWish = relationship(
            name: "wishlistItemRaw",
            destination: wishEntity,
            toMany: false,
            deleteRule: .nullifyDeleteRule,
            optional: true
        )
        wishToPlatform.inverseRelationship = platformToWish
        platformToWish.inverseRelationship = wishToPlatform

        let wishToHistory = relationship(
            name: "priceHistoriesRaw",
            destination: historyEntity,
            toMany: true,
            deleteRule: .cascadeDeleteRule
        )
        let historyToWish = relationship(
            name: "wishlistItemRaw",
            destination: wishEntity,
            toMany: false,
            deleteRule: .nullifyDeleteRule,
            optional: true
        )
        wishToHistory.inverseRelationship = historyToWish
        historyToWish.inverseRelationship = wishToHistory

        assetEntity.properties.append(contentsOf: [assetToExtra, assetToSale])
        extraCostEntity.properties.append(extraToAsset)
        saleEntity.properties.append(saleToAsset)

        wishEntity.properties.append(contentsOf: [wishToPlatform, wishToHistory])
        platformEntity.properties.append(platformToWish)
        historyEntity.properties.append(historyToWish)

        model.entities = [
            assetEntity,
            extraCostEntity,
            saleEntity,
            wishEntity,
            platformEntity,
            historyEntity,
            transactionEntity,
            budgetEntity
        ]

        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        if !optional {
            attr.defaultValue = defaultValue(for: type)
        }
        return attr
    }

    private static func binaryAttribute(
        _ name: String,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = .binaryDataAttributeType
        attr.isOptional = optional
        attr.allowsExternalBinaryDataStorage = true
        return attr
    }

    private static func relationship(
        name: String,
        destination: NSEntityDescription,
        toMany: Bool,
        deleteRule: NSDeleteRule,
        optional: Bool = true
    ) -> NSRelationshipDescription {
        let relation = NSRelationshipDescription()
        relation.name = name
        relation.destinationEntity = destination
        relation.minCount = 0
        relation.maxCount = toMany ? 0 : 1
        relation.deleteRule = deleteRule
        relation.isOptional = optional
        relation.isOrdered = false
        return relation
    }

    private static func defaultValue(for type: NSAttributeType) -> Any {
        switch type {
        case .stringAttributeType:
            return ""
        case .dateAttributeType:
            return Date(timeIntervalSinceReferenceDate: 0)
        case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
            return 0
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            return 0
        case .booleanAttributeType:
            return false
        case .UUIDAttributeType:
            return UUID()
        default:
            return ""
        }
    }
}
