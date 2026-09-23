import Foundation
import CoreData
import CryptoKit

struct LocalBackupEnvelope: Codable, Identifiable {
    let formatVersion: Int
    let exportedAt: Date
    let payload: LocalBackupPayload
    let payloadSHA256: String

    var id: String { "\(exportedAt.timeIntervalSince1970)-\(payloadSHA256)" }
    var transactionCount: Int { payload.transactions.count }
    var budgetCount: Int { payload.budgets.count }
    var assetCount: Int { payload.assets.count }
    var assetHistoryCount: Int { payload.assets.reduce(0) { $0 + $1.extraCosts.count + $1.saleRecords.count } }
    var wishlistCount: Int { payload.wishItems.count }
    var wishHistoryCount: Int {
        payload.wishItems.reduce(0) { $0 + $1.platformPrices.count + $1.priceHistories.count }
    }
    var customCategoryCount: Int { payload.customCategories.count }
    var customRuleCount: Int { payload.keywordRules.filter { $0.searchTexts?.first?.ruleKind == .local }.count }
}

struct LocalBackupPayload: Codable {
    var transactions: [LocalBackupTransaction]
    var budgets: [LocalBackupBudget]
    var assets: [LocalBackupAsset]
    var wishItems: [LocalBackupWishItem]
    var customCategories: [CustomCategory]
    var keywordRules: [KeywordRule]
}

struct LocalBackupTransaction: Codable {
    var id: UUID
    var amount: Double
    var categoryKey: String
    var subcategoryKey: String?
    var note: String?
    var date: Date
    var isIncome: Bool
    var createdAt: Date
    var fundAccountKey: String?
    var notInBudget: Bool
    var billSource: String?
    var merchantName: String?
    var importFingerprint: String?
}

struct LocalBackupBudget: Codable {
    var id: UUID
    var categoryKey: String
    var monthlyAmount: Double
    var month: Date
    var createdAt: Date
}

struct LocalBackupAsset: Codable {
    var id: UUID
    var name: String
    var category: String
    var purchaseDate: Date
    var purchasePrice: Double
    var currentValue: Double
    var status: AssetStatus
    var notes: String?
    var imageData: Data?
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var extraCosts: [LocalBackupAssetCost]
    var saleRecords: [LocalBackupAssetSale]
}

struct LocalBackupAssetCost: Codable {
    var id: UUID
    var costType: String
    var amount: Double
    var date: Date
    var notes: String?
    var createdAt: Date
}

struct LocalBackupAssetSale: Codable {
    var id: UUID
    var saleDate: Date
    var salePrice: Double
    var platform: String?
    var notes: String?
    var createdAt: Date
}

struct LocalBackupWishItem: Codable {
    var id: UUID
    var name: String
    var category: String
    var targetPrice: Double
    var targetDailyCost: Double
    var priority: Int16
    var notes: String?
    var imageData: Data?
    var isPurchased: Bool
    var createdAt: Date
    var updatedAt: Date
    var platformPrices: [LocalBackupWishPrice]
    var priceHistories: [LocalBackupWishPriceHistory]
}

struct LocalBackupWishPrice: Codable {
    var id: UUID
    var platform: String
    var price: Double
    var url: String?
    var lastUpdated: Date
}

struct LocalBackupWishPriceHistory: Codable {
    var id: UUID
    var price: Double
    var recordedAt: Date
}

@MainActor
final class LocalBackupService {
    static let shared = LocalBackupService()
    static let currentFormatVersion = 1

    func exportBackup(from context: NSManagedObjectContext) throws -> Data {
        let payload = try capturePayload(from: context)
        try validate(payload)
        let checksum = Self.sha256(try Self.encoder().encode(payload))
        let envelope = LocalBackupEnvelope(
            formatVersion: Self.currentFormatVersion,
            exportedAt: Date(),
            payload: payload,
            payloadSHA256: checksum
        )
        return try Self.encoder().encode(envelope)
    }

    func decodeAndValidate(_ data: Data) throws -> LocalBackupEnvelope {
        let envelope = try Self.decoder().decode(LocalBackupEnvelope.self, from: data)
        guard envelope.formatVersion == Self.currentFormatVersion else {
            throw LocalBackupError.unsupportedVersion(envelope.formatVersion)
        }
        let actualChecksum = Self.sha256(try Self.encoder().encode(envelope.payload))
        guard actualChecksum.caseInsensitiveCompare(envelope.payloadSHA256) == .orderedSame else {
            throw LocalBackupError.checksumMismatch
        }
        try validate(envelope.payload)
        return envelope
    }

    func restore(_ envelope: LocalBackupEnvelope, into context: NSManagedObjectContext) throws {
        guard envelope.formatVersion == Self.currentFormatVersion else {
            throw LocalBackupError.unsupportedVersion(envelope.formatVersion)
        }
        let actualChecksum = Self.sha256(try Self.encoder().encode(envelope.payload))
        guard actualChecksum.caseInsensitiveCompare(envelope.payloadSHA256) == .orderedSame else {
            throw LocalBackupError.checksumMismatch
        }
        try validate(envelope.payload)

        let previousPayload = try capturePayload(from: context)
        var rulesReplaced = false
        var categoriesReplaced = false
        do {
            guard RuleUpdateService.shared.replaceRulesForLocalRestore(envelope.payload.keywordRules) else {
                throw LocalBackupError.ruleStoreWriteFailed
            }
            rulesReplaced = true
            guard CustomCategoryStore.shared.replaceAll(envelope.payload.customCategories) else {
                throw LocalBackupError.categoryStoreWriteFailed
            }
            categoriesReplaced = true
            try replaceCoreData(with: envelope.payload, in: context)
        } catch {
            context.rollback()
            var rollbackFailed = false
            if categoriesReplaced && !CustomCategoryStore.shared.replaceAll(previousPayload.customCategories) {
                print("[LocalBackup] Failed to roll back custom categories after restore error")
                rollbackFailed = true
            }
            if rulesReplaced && !RuleUpdateService.shared.replaceRulesForLocalRestore(previousPayload.keywordRules) {
                print("[LocalBackup] Failed to roll back keyword rules after restore error")
                rollbackFailed = true
            }
            if rollbackFailed { throw LocalBackupError.rollbackFailed }
            throw error
        }
    }

    private func capturePayload(from context: NSManagedObjectContext) throws -> LocalBackupPayload {
        var transactions: [LocalBackupTransaction] = []
        var budgets: [LocalBackupBudget] = []
        var assets: [LocalBackupAsset] = []
        var wishItems: [LocalBackupWishItem] = []

        try context.performAndWait {
            transactions = try context.fetch(BookkeepingTransaction.fetchRequest()).map {
                LocalBackupTransaction(
                    id: $0.id,
                    amount: $0.amount,
                    categoryKey: $0.categoryKey,
                    subcategoryKey: $0.subcategoryKey,
                    note: $0.note,
                    date: $0.date,
                    isIncome: $0.isIncome,
                    createdAt: $0.createdAt,
                    fundAccountKey: $0.fundAccountKey,
                    notInBudget: $0.notInBudget,
                    billSource: $0.billSource,
                    merchantName: $0.merchantName,
                    importFingerprint: $0.importFingerprint
                )
            }
            budgets = try context.fetch(BudgetEntry.fetchRequest()).map {
                LocalBackupBudget(
                    id: $0.id,
                    categoryKey: $0.categoryKey,
                    monthlyAmount: $0.monthlyAmount,
                    month: $0.month,
                    createdAt: $0.createdAt
                )
            }
            assets = try context.fetch(AssetItem.fetchRequest()).map { asset in
                LocalBackupAsset(
                    id: asset.id,
                    name: asset.name,
                    category: asset.category,
                    purchaseDate: asset.purchaseDate,
                    purchasePrice: asset.purchasePrice,
                    currentValue: asset.currentValue,
                    status: asset.status,
                    notes: asset.notes,
                    imageData: asset.imageData,
                    isFavorite: asset.isFavorite,
                    createdAt: asset.createdAt,
                    updatedAt: asset.updatedAt,
                    extraCosts: asset.extraCosts.map {
                        LocalBackupAssetCost(
                            id: $0.id,
                            costType: $0.costType,
                            amount: $0.amount,
                            date: $0.date,
                            notes: $0.notes,
                            createdAt: $0.createdAt
                        )
                    }.sorted { $0.id.uuidString < $1.id.uuidString },
                    saleRecords: asset.saleRecords.map {
                        LocalBackupAssetSale(
                            id: $0.id,
                            saleDate: $0.saleDate,
                            salePrice: $0.salePrice,
                            platform: $0.platform,
                            notes: $0.notes,
                            createdAt: $0.createdAt
                        )
                    }.sorted { $0.id.uuidString < $1.id.uuidString }
                )
            }
            wishItems = try context.fetch(WishlistItem.fetchRequest()).map { wish in
                LocalBackupWishItem(
                    id: wish.id,
                    name: wish.name,
                    category: wish.category,
                    targetPrice: wish.targetPrice,
                    targetDailyCost: wish.targetDailyCost,
                    priority: wish.priority,
                    notes: wish.notes,
                    imageData: wish.imageData,
                    isPurchased: wish.isPurchased,
                    createdAt: wish.createdAt,
                    updatedAt: wish.updatedAt,
                    platformPrices: wish.platformPrices.map {
                        LocalBackupWishPrice(
                            id: $0.id,
                            platform: $0.platform,
                            price: $0.price,
                            url: $0.url,
                            lastUpdated: $0.lastUpdated
                        )
                    }.sorted { $0.id.uuidString < $1.id.uuidString },
                    priceHistories: wish.priceHistories.map {
                        LocalBackupWishPriceHistory(id: $0.id, price: $0.price, recordedAt: $0.recordedAt)
                    }.sorted { $0.id.uuidString < $1.id.uuidString }
                )
            }
        }

        return LocalBackupPayload(
            transactions: transactions.sorted { $0.id.uuidString < $1.id.uuidString },
            budgets: budgets.sorted { $0.id.uuidString < $1.id.uuidString },
            assets: assets.sorted { $0.id.uuidString < $1.id.uuidString },
            wishItems: wishItems.sorted { $0.id.uuidString < $1.id.uuidString },
            customCategories: try CustomCategoryStore.shared.backupSnapshot().sorted { $0.id < $1.id },
            keywordRules: try KeywordRulesTable.shared.fetchAllRulesStrict().sorted { $0.ruleId < $1.ruleId }
        )
    }

    private func replaceCoreData(with payload: LocalBackupPayload, in context: NSManagedObjectContext) throws {
        try context.performAndWait {
            for entityName in [
                "AssetExtraCost", "AssetSaleRecord",
                "WishlistPlatformPrice", "WishlistPriceHistory",
                "AssetItem", "WishlistItem",
                "BookkeepingTransaction", "BudgetEntry"
            ] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                for object in try context.fetch(request) {
                    context.delete(object)
                }
            }

            for item in payload.transactions {
                _ = BookkeepingTransaction(
                    context: context,
                    id: item.id,
                    amount: item.amount,
                    categoryKey: item.categoryKey,
                    subcategoryKey: item.subcategoryKey,
                    note: item.note,
                    date: item.date,
                    isIncome: item.isIncome,
                    createdAt: item.createdAt,
                    fundAccountKey: item.fundAccountKey,
                    notInBudget: item.notInBudget,
                    billSource: item.billSource,
                    merchantName: item.merchantName,
                    importFingerprint: item.importFingerprint
                )
            }
            for item in payload.budgets {
                _ = BudgetEntry(
                    context: context,
                    id: item.id,
                    categoryKey: item.categoryKey,
                    monthlyAmount: item.monthlyAmount,
                    month: item.month,
                    createdAt: item.createdAt
                )
            }

            var assetsByID: [UUID: AssetItem] = [:]
            for item in payload.assets {
                let asset = AssetItem(
                    context: context,
                    id: item.id,
                    name: item.name,
                    category: item.category,
                    purchaseDate: item.purchaseDate,
                    purchasePrice: item.purchasePrice,
                    currentValue: item.currentValue,
                    status: item.status,
                    notes: item.notes,
                    imageData: item.imageData,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                asset.isFavorite = item.isFavorite
                assetsByID[item.id] = asset
            }
            for item in payload.assets {
                guard let asset = assetsByID[item.id] else { continue }
                for cost in item.extraCosts {
                    _ = AssetExtraCost(
                        context: context,
                        id: cost.id,
                        asset: asset,
                        costType: cost.costType,
                        amount: cost.amount,
                        date: cost.date,
                        notes: cost.notes,
                        createdAt: cost.createdAt
                    )
                }
                for sale in item.saleRecords {
                    _ = AssetSaleRecord(
                        context: context,
                        id: sale.id,
                        asset: asset,
                        saleDate: sale.saleDate,
                        salePrice: sale.salePrice,
                        platform: sale.platform,
                        notes: sale.notes,
                        createdAt: sale.createdAt
                    )
                }
            }

            for item in payload.wishItems {
                let wish = WishlistItem(
                    context: context,
                    id: item.id,
                    name: item.name,
                    category: item.category,
                    targetPrice: item.targetPrice,
                    targetDailyCost: item.targetDailyCost,
                    priority: Int(item.priority),
                    notes: item.notes,
                    imageData: item.imageData,
                    isPurchased: item.isPurchased,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                for price in item.platformPrices {
                    _ = WishlistPlatformPrice(
                        context: context,
                        id: price.id,
                        wishlistItem: wish,
                        platform: price.platform,
                        price: price.price,
                        url: price.url,
                        lastUpdated: price.lastUpdated
                    )
                }
                for history in item.priceHistories {
                    _ = WishlistPriceHistory(
                        context: context,
                        id: history.id,
                        wishlistItem: wish,
                        price: history.price,
                        recordedAt: history.recordedAt
                    )
                }
            }
            try context.save()
        }
    }

    private func validate(_ payload: LocalBackupPayload) throws {
        guard Self.unique(payload.transactions.map(\.id)),
              Self.unique(payload.budgets.map(\.id)),
              Self.unique(payload.assets.map(\.id)),
              Self.unique(payload.wishItems.map(\.id)),
              Self.unique(payload.customCategories.map(\.id)),
              Self.unique(payload.keywordRules.map(\.ruleId)) else {
            throw LocalBackupError.duplicateIdentifiers
        }
        guard Self.unique(payload.assets.flatMap { $0.extraCosts.map(\.id) }),
              Self.unique(payload.assets.flatMap { $0.saleRecords.map(\.id) }),
              Self.unique(payload.wishItems.flatMap { $0.platformPrices.map(\.id) }),
              Self.unique(payload.wishItems.flatMap { $0.priceHistories.map(\.id) }) else {
            throw LocalBackupError.duplicateIdentifiers
        }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum LocalBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case checksumMismatch
    case duplicateIdentifiers
    case ruleStoreWriteFailed
    case categoryStoreWriteFailed
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "不支持的备份版本：\(version)"
        case .checksumMismatch: return "备份校验失败，文件可能已损坏或被修改。"
        case .duplicateIdentifiers: return "备份内有重复标识，无法安全恢复。"
        case .ruleStoreWriteFailed: return "自定义规则写入失败，当前数据未完成恢复。"
        case .categoryStoreWriteFailed: return "自定义分类写入失败，当前数据未完成恢复。"
        case .rollbackFailed: return "恢复失败，部分本地配置未能自动回滚。请保留当前文件，并用恢复前的备份重试。"
        }
    }
}
