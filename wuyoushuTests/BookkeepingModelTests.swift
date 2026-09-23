import XCTest
import CoreData
@testable import AssetLife

final class BookkeepingModelTests: XCTestCase {

    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController.preview.container.viewContext
    }

    // MARK: - BookkeepingTransaction Tests

    func test_transaction_defaultValues() {
        let transaction = BookkeepingTransaction(
            context: context,
            amount: 35,
            categoryKey: "dining",
            subcategoryKey: "lunch",
            note: "午餐"
        )

        XCTAssertEqual(transaction.amount, 35)
        XCTAssertEqual(transaction.categoryKey, "dining")
        XCTAssertEqual(transaction.subcategoryKey, "lunch")
        XCTAssertEqual(transaction.note, "午餐")
        XCTAssertFalse(transaction.isIncome)
        XCTAssertNotNil(transaction.id)
        XCTAssertNotNil(transaction.createdAt)
    }

    func test_transaction_income() {
        let transaction = BookkeepingTransaction(
            context: context,
            amount: 10000,
            categoryKey: "salary",
            note: "工资",
            isIncome: true
        )

        XCTAssertTrue(transaction.isIncome)
        XCTAssertEqual(transaction.amount, 10000)
    }

    func test_transaction_categoryName() {
        let transaction = BookkeepingTransaction(
            context: context,
            amount: 35,
            categoryKey: "dining"
        )

        XCTAssertEqual(transaction.categoryName, "餐饮")
        XCTAssertEqual(transaction.categoryEmoji, "🍽️")
    }

    func test_transaction_subcategoryName() {
        let transaction = BookkeepingTransaction(
            context: context,
            amount: 35,
            categoryKey: "dining",
            subcategoryKey: "lunch"
        )

        XCTAssertEqual(transaction.subcategoryName, "午餐")
    }

    func test_transaction_unknownCategory() {
        let transaction = BookkeepingTransaction(
            context: context,
            amount: 10,
            categoryKey: "unknown_cat"
        )

        XCTAssertEqual(transaction.categoryName, "unknown_cat")
        XCTAssertEqual(transaction.categoryEmoji, "📦")
        XCTAssertNil(transaction.subcategoryName)
    }

    // MARK: - BudgetEntry Tests

    func test_budgetEntry_defaultValues() {
        let budget = BudgetEntry(
            context: context,
            categoryKey: "dining",
            monthlyAmount: 2000,
            month: Date().startOfMonth
        )

        XCTAssertEqual(budget.categoryKey, "dining")
        XCTAssertEqual(budget.monthlyAmount, 2000)
        XCTAssertNotNil(budget.id)
        XCTAssertNotNil(budget.createdAt)
    }

    // MARK: - BookkeepingCategory Tests

    func test_expenseCategories_count() {
        XCTAssertEqual(BookkeepingCategory.expenseCategories.count, 10)
    }

    func test_incomeCategories_count() {
        XCTAssertEqual(BookkeepingCategory.incomeCategories.count, 6)
    }

    func test_findCategory() {
        let cat = BookkeepingCategory.find(key: "dining")
        XCTAssertNotNil(cat)
        XCTAssertEqual(cat?.name, "餐饮")
        XCTAssertEqual(cat?.emoji, "🍽️")
    }

    func test_findCategory_unknown() {
        let cat = BookkeepingCategory.find(key: "nonexistent")
        XCTAssertNil(cat)
    }

    func test_findSubcategory() {
        let sub = BookkeepingCategory.findSubcategory(key: "lunch")
        XCTAssertNotNil(sub)
        XCTAssertEqual(sub?.name, "午餐")
        XCTAssertEqual(sub?.emoji, "🍱")
    }

    func test_findSubcategory_unknown() {
        let sub = BookkeepingCategory.findSubcategory(key: "nonexistent")
        XCTAssertNil(sub)
    }

    func test_allCategoriesHaveValidSubcategories() {
        for cat in BookkeepingCategory.expenseCategories {
            XCTAssertFalse(cat.key.isEmpty)
            XCTAssertFalse(cat.name.isEmpty)
            XCTAssertFalse(cat.emoji.isEmpty)
            for sub in cat.subcategories {
                XCTAssertFalse(sub.key.isEmpty)
                XCTAssertFalse(sub.name.isEmpty)
            }
        }
    }
}
