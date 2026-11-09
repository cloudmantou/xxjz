// Frozen runtime model from main 6643887. Do not evolve this schema.
// Run from the repository root with `swift scripts/generate-legacy-model.swift`.
// New schemas require a new versioned artifact; tests compare all entity hashes.
import Foundation
import CoreData
struct LegacyModel {
    static func makeModel(enableUniqueConstraints: Bool) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let assetEntity = NSEntityDescription()
        assetEntity.name = "AssetItem"
        assetEntity.managedObjectClassName = "AssetItem"

        let extraCostEntity = NSEntityDescription()
        extraCostEntity.name = "AssetExtraCost"
        extraCostEntity.managedObjectClassName = "AssetExtraCost"

        let saleEntity = NSEntityDescription()
        saleEntity.name = "AssetSaleRecord"
        saleEntity.managedObjectClassName = "AssetSaleRecord"

        let wishEntity = NSEntityDescription()
        wishEntity.name = "WishlistItem"
        wishEntity.managedObjectClassName = "WishlistItem"

        let platformEntity = NSEntityDescription()
        platformEntity.name = "WishlistPlatformPrice"
        platformEntity.managedObjectClassName = "WishlistPlatformPrice"

        let historyEntity = NSEntityDescription()
        historyEntity.name = "WishlistPriceHistory"
        historyEntity.managedObjectClassName = "WishlistPriceHistory"

        // MARK: - Bookkeeping Entities

        let transactionEntity = NSEntityDescription()
        transactionEntity.name = "BookkeepingTransaction"
        transactionEntity.managedObjectClassName = "BookkeepingTransaction"

        let budgetEntity = NSEntityDescription()
        budgetEntity.name = "BudgetEntry"
        budgetEntity.managedObjectClassName = "BudgetEntry"

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
            attribute("merchantName", .stringAttributeType, optional: true),
            attribute("importFingerprint", .stringAttributeType, optional: true)
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

    static func attribute(
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

    static func binaryAttribute(
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

    static func relationship(
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

    static func defaultValue(for type: NSAttributeType) -> Any {
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
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        default:
            return ""
        }
    }
}
// Frozen pre-preference-sync schema. Do not regenerate this from the evolving current model.
let model = LegacyModel.makeModel(enableUniqueConstraints: false)
let destination = CommandLine.arguments.dropFirst().first ?? "wuyoushu/Resources/AssetLifeLegacyV1.mom"
try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: true)
    .write(to: URL(fileURLWithPath: destination))
