import XCTest
@testable import AssetLife

final class ExtensionsTests: XCTestCase {

    // MARK: - Double Extensions Tests

    func test_currencyString_formatsCorrectly() {
        let value: Double = 9999.99
        XCTAssertTrue(value.currencyString.contains("9,999.99") || value.currencyString.contains("9999.99"))
    }

    func test_percentString_formatsCorrectly() {
        let value: Double = 15.5
        XCTAssertEqual(value.percentString, "15.5%")
    }

    func test_signedPercentString_positive_includesPlus() {
        let value: Double = 10.0
        XCTAssertEqual(value.signedPercentString, "+10.0%")
    }

    func test_signedPercentString_negative_noPlus() {
        let value: Double = -10.0
        XCTAssertEqual(value.signedPercentString, "-10.0%")
    }

    func test_rounded_toTwoPlaces() {
        let value: Double = 10.555
        XCTAssertEqual(value.rounded(to: 2), 10.56)
    }

    // MARK: - Date Extensions Tests

    func test_date_shortDateString_formatsCorrectly() {
        let date = Date(timeIntervalSince1970: 0)
        let result = date.shortDateString
        XCTAssertTrue(result.contains("1970"))
    }

    func test_date_isToday_returnsTrueForToday() {
        XCTAssertTrue(Date().isToday)
    }

    func test_date_isThisMonth_returnsTrueForCurrentMonth() {
        XCTAssertTrue(Date().isThisMonth)
    }

    func test_date_from_createsCorrectDate() {
        if let date = Date.from(year: 2024, month: 1, day: 15) {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 15)
        } else {
            XCTFail("Failed to create date")
        }
    }
}
