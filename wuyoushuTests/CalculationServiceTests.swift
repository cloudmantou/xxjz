import XCTest
@testable import AssetLife

final class CalculationServiceTests: XCTestCase {

    var sut: CalculationService!

    override func setUp() {
        super.setUp()
        sut = CalculationService.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Holding Days Tests

    func test_holdingDays_sameDay_returnsZero() {
        let date = Date()
        let result = sut.holdingDays(from: date, to: date)
        XCTAssertEqual(result, 0)
    }

    func test_holdingDays_oneDayDifference_returnsOne() {
        let purchaseDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let result = sut.holdingDays(from: purchaseDate, to: Date())
        XCTAssertEqual(result, 1)
    }

    func test_holdingDays_sevenDaysDifference_returnsSeven() {
        let purchaseDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let result = sut.holdingDays(from: purchaseDate, to: Date())
        XCTAssertEqual(result, 7)
    }

    // MARK: - Daily Cost Tests

    func test_dailyCost_zeroHoldingDays_returnsTotalCost() {
        let result = sut.dailyCost(purchasePrice: 1000, totalExtraCosts: 200, holdingDays: 0)
        XCTAssertEqual(result, 1200)
    }

    func test_dailyCost_tenDays_returnsTotalCostDividedByTen() {
        let result = sut.dailyCost(purchasePrice: 1000, totalExtraCosts: 0, holdingDays: 10)
        XCTAssertEqual(result, 100)
    }

    func test_dailyCost_withExtraCosts_includesAllCosts() {
        let result = sut.dailyCost(purchasePrice: 1000, totalExtraCosts: 500, holdingDays: 10)
        XCTAssertEqual(result, 150)
    }

    // MARK: - Lifecycle Progress Tests

    func test_lifecycleProgress_zeroDays_returnsZero() {
        let purchaseDate = Date()
        let result = sut.lifecycleProgress(purchaseDate: purchaseDate, expectedLifeYears: 5)
        XCTAssertEqual(result, 0, accuracy: 0.01)
    }

    func test_lifecycleProgress_halfYear_outOfFiveYears_returnsPoint1() {
        let purchaseDate = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        let result = sut.lifecycleProgress(purchaseDate: purchaseDate, expectedLifeYears: 5)
        XCTAssertEqual(result, 0.1, accuracy: 0.01)
    }

    func test_lifecycleProgress_aboveOne_returnsOne() {
        let purchaseDate = Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        let result = sut.lifecycleProgress(purchaseDate: purchaseDate, expectedLifeYears: 5)
        XCTAssertEqual(result, 1.0, accuracy: 0.01)
    }

    // MARK: - Sale Profit/Loss Tests

    func test_saleProfitLoss_profit_returnsPositive() {
        let result = sut.saleProfitLoss(purchasePrice: 1000, totalCosts: 1200, salePrice: 1500)
        XCTAssertEqual(result, 300)
    }

    func test_saleProfitLoss_loss_returnsNegative() {
        let result = sut.saleProfitLoss(purchasePrice: 1000, totalCosts: 1200, salePrice: 800)
        XCTAssertEqual(result, -400)
    }

    func test_saleProfitLoss_breakEven_returnsZero() {
        let result = sut.saleProfitLoss(purchasePrice: 1000, totalCosts: 1200, salePrice: 1200)
        XCTAssertEqual(result, 0)
    }

    func test_saleProfitLossPercent_profit_returnsPositivePercent() {
        let result = sut.saleProfitLossPercent(purchasePrice: 1000, totalCosts: 1000, salePrice: 1200)
        XCTAssertEqual(result, 20)
    }

    func test_saleProfitLossPercent_loss_returnsNegativePercent() {
        let result = sut.saleProfitLossPercent(purchasePrice: 1000, totalCosts: 1000, salePrice: 800)
        XCTAssertEqual(result, -20)
    }

    // MARK: - Price Change Tests

    func test_priceChangePercent_increase_returnsPositive() {
        let result = sut.priceChangePercent(current: 110, previous: 100)
        XCTAssertEqual(result, 10)
    }

    func test_priceChangePercent_decrease_returnsNegative() {
        let result = sut.priceChangePercent(current: 90, previous: 100)
        XCTAssertEqual(result, -10)
    }

    func test_priceChangePercent_same_returnsZero() {
        let result = sut.priceChangePercent(current: 100, previous: 100)
        XCTAssertEqual(result, 0)
    }

    func test_priceChangePercent_zeroPrevious_returnsZero() {
        let result = sut.priceChangePercent(current: 100, previous: 0)
        XCTAssertEqual(result, 0)
    }

    // MARK: - Price Statistics Tests

    func test_averagePrice_empty_returnsZero() {
        let result = sut.averagePrice([])
        XCTAssertEqual(result, 0)
    }

    func test_averagePrice_singleValue_returnsThatValue() {
        let result = sut.averagePrice([100])
        XCTAssertEqual(result, 100)
    }

    func test_averagePrice_multipleValues_returnsCorrectAverage() {
        let result = sut.averagePrice([100, 200, 300])
        XCTAssertEqual(result, 200)
    }

    func test_lowestPrice_empty_returnsZero() {
        let result = sut.lowestPrice([])
        XCTAssertEqual(result, 0)
    }

    func test_lowestPrice_multipleValues_returnsMinimum() {
        let result = sut.lowestPrice([100, 50, 200, 75])
        XCTAssertEqual(result, 50)
    }

    func test_highestPrice_empty_returnsZero() {
        let result = sut.highestPrice([])
        XCTAssertEqual(result, 0)
    }

    func test_highestPrice_multipleValues_returnsMaximum() {
        let result = sut.highestPrice([100, 50, 200, 75])
        XCTAssertEqual(result, 200)
    }
}
