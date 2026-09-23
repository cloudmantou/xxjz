import XCTest
@testable import AssetLife

final class ModelTests: XCTestCase {

    // MARK: - AssetItem Tests

    func test_assetItem_defaultValues() {
        let asset = AssetItem(
            name: "Test Asset",
            category: "电子产品",
            purchasePrice: 1000,
            currentValue: 800
        )

        XCTAssertEqual(asset.name, "Test Asset")
        XCTAssertEqual(asset.category, "电子产品")
        XCTAssertEqual(asset.purchasePrice, 1000)
        XCTAssertEqual(asset.currentValue, 800)
        XCTAssertEqual(asset.status, .active)
        XCTAssertNotNil(asset.id)
        XCTAssertNotNil(asset.createdAt)
    }

    func test_assetItem_defaultsCurrentValueToPurchasePrice() {
        let asset = AssetItem(
            name: "Default Value Asset",
            category: "电子产品",
            purchasePrice: 1888
        )

        XCTAssertEqual(asset.currentValue, 1888)
        XCTAssertFalse(asset.isFavorite)
    }

    func test_persistenceModel_includesAssetFavoriteAttribute() throws {
        let model = PersistenceController.preview.container.managedObjectModel
        let assetEntity = try XCTUnwrap(model.entitiesByName["AssetItem"])

        XCTAssertNotNil(assetEntity.attributesByName["isFavorite"])
    }

    func test_assetItem_totalExtraCost_empty_returnsZero() {
        let asset = AssetItem(
            name: "Test",
            category: "Test",
            purchasePrice: 1000,
            currentValue: 800
        )

        XCTAssertEqual(asset.totalExtraCost, 0)
    }

    func test_assetItem_totalCost_includesPurchaseAndExtra() {
        let asset = AssetItem(
            name: "Test",
            category: "Test",
            purchasePrice: 1000,
            currentValue: 800
        )

        let cost = AssetExtraCost(costType: "维修", amount: 200)
        cost.asset = asset
        asset.extraCosts.append(cost)

        XCTAssertEqual(asset.totalExtraCost, 200)
        XCTAssertEqual(asset.totalCost, 1200)
    }

    // MARK: - AssetExtraCost Tests

    func test_assetExtraCost_defaultValues() {
        let cost = AssetExtraCost(costType: "维修", amount: 100)

        XCTAssertEqual(cost.costType, "维修")
        XCTAssertEqual(cost.amount, 100)
        XCTAssertNotNil(cost.id)
    }

    // MARK: - AssetSaleRecord Tests

    func test_assetSaleRecord_defaultValues() {
        let record = AssetSaleRecord(salePrice: 500)

        XCTAssertEqual(record.salePrice, 500)
        XCTAssertNotNil(record.id)
    }

    // MARK: - WishlistItem Tests

    func test_wishlistItem_defaultValues() {
        let item = WishlistItem(
            name: "Test Item",
            category: "电子产品",
            targetPrice: 1000
        )

        XCTAssertEqual(item.name, "Test Item")
        XCTAssertEqual(item.category, "电子产品")
        XCTAssertEqual(item.targetPrice, 1000)
        XCTAssertEqual(item.targetDailyCost, 0)
        XCTAssertEqual(item.priority, 3)
        XCTAssertFalse(item.isPurchased)
    }

    func test_persistenceModel_includesWishlistDailyCostAttribute() throws {
        let model = PersistenceController.preview.container.managedObjectModel
        let wishlistEntity = try XCTUnwrap(model.entitiesByName["WishlistItem"])

        XCTAssertNotNil(wishlistEntity.attributesByName["targetDailyCost"])
    }

    func test_wishlistItem_currentLowestPrice_empty_returnsNil() {
        let item = WishlistItem(
            name: "Test",
            category: "Test",
            targetPrice: 1000
        )

        XCTAssertNil(item.currentLowestPrice)
    }

    func test_wishlistItem_currentLowestPrice_returnsMinimum() {
        let item = WishlistItem(
            name: "Test",
            category: "Test",
            targetPrice: 1000
        )

        let price1 = WishlistPlatformPrice(platform: "京东", price: 800)
        let price2 = WishlistPlatformPrice(platform: "天猫", price: 900)
        let price3 = WishlistPlatformPrice(platform: "淘宝", price: 750)

        price1.wishlistItem = item
        price2.wishlistItem = item
        price3.wishlistItem = item

        item.platformPrices.append(contentsOf: [price1, price2, price3])

        XCTAssertEqual(item.currentLowestPrice, 750)
    }

    // MARK: - WishlistPlatformPrice Tests

    func test_wishlistPlatformPrice_defaultValues() {
        let price = WishlistPlatformPrice(platform: "京东", price: 999)

        XCTAssertEqual(price.platform, "京东")
        XCTAssertEqual(price.price, 999)
        XCTAssertNotNil(price.id)
    }

    // MARK: - WishlistPriceHistory Tests

    func test_wishlistPriceHistory_defaultValues() {
        let history = WishlistPriceHistory(price: 899)

        XCTAssertEqual(history.price, 899)
        XCTAssertNotNil(history.id)
        XCTAssertNotNil(history.recordedAt)
    }
}
