import XCTest
@testable import AssetLife

@MainActor
final class AppRouterTests: XCTestCase {

    func test_trigger_addAsset_switchesTabAndSheet() {
        let router = AppRouter()

        router.trigger(.addAsset)

        XCTAssertEqual(router.selectedTab, .asset)
        XCTAssertTrue(router.showAddAssetSheet)
        XCTAssertFalse(router.showAddWishSheet)
    }

    func test_handleDeepLink_addWishAction_switchesTabAndSheet() {
        let router = AppRouter()
        let url = URL(string: "assetlife://open?action=addWish")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.selectedTab, .asset)
        XCTAssertEqual(router.selectedAssetSection, .wish)
        XCTAssertTrue(router.showAddWishSheet)
        XCTAssertFalse(router.showAddAssetSheet)
    }

    func test_handleDeepLink_tabProfile_switchesTab() {
        let router = AppRouter()
        let url = URL(string: "assetlife://open?tab=profile")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.selectedTab, .profile)
    }

    func test_handleDeepLink_invalidScheme_keepsDefaultTab() {
        let router = AppRouter()
        let url = URL(string: "https://example.com?action=addAsset")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.selectedTab, .home)
        XCTAssertFalse(router.showAddAssetSheet)
        XCTAssertFalse(router.showAddWishSheet)
    }

    // MARK: - Quick Record Tests

    func test_trigger_quickRecord_showsSheet() {
        let router = AppRouter()

        router.trigger(.quickRecord)

        XCTAssertTrue(router.showQuickRecordSheet)
        XCTAssertFalse(router.showAddAssetSheet)
        XCTAssertFalse(router.showAddWishSheet)
        XCTAssertEqual(router.previousTabBeforeQuickRecord, .home)
    }

    func test_handleDeepLink_recordScreen_withParams() {
        let router = AppRouter()
        let url = URL(string: "assetlife://record?amount=25&category=dining&note=lunch")!

        router.handleDeepLink(url)

        XCTAssertTrue(router.showQuickRecordSheet)
        XCTAssertEqual(router.pendingRecordParams?.amount, 25)
        XCTAssertEqual(router.pendingRecordParams?.categoryKey, "dining")
        XCTAssertEqual(router.pendingRecordParams?.note, "lunch")
    }

    func test_handleDeepLink_recordAmount_setsParamsAmount() {
        let router = AppRouter()
        let url = URL(string: "assetlife://record?amount=100")!

        router.handleDeepLink(url)

        XCTAssertEqual(router.pendingRecordParams?.amount, 100)
    }

    func test_handleDeepLink_recordEmpty_noParams() {
        let router = AppRouter()
        let url = URL(string: "assetlife://record")!

        router.handleDeepLink(url)

        XCTAssertTrue(router.showQuickRecordSheet)
        XCTAssertNil(router.pendingRecordParams?.amount)
    }

    func test_dismissQuickRecord_restoresPreviousTab() {
        let router = AppRouter()
        router.selectedTab = .asset

        router.trigger(.quickRecord)
        XCTAssertTrue(router.showQuickRecordSheet)

        router.dismissQuickRecord(printTargetURI: nil)

        XCTAssertFalse(router.showQuickRecordSheet)
        XCTAssertEqual(router.selectedTab, .asset)
        XCTAssertNil(router.previousTabBeforeQuickRecord)
    }
}
