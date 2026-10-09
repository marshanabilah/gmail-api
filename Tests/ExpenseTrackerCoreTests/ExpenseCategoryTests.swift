import ExpenseTrackerCore
import XCTest

final class ExpenseCategoryTests: XCTestCase {
    func testAddingCustomCategoryTrimsWhitespaceAndIncludesItOnce() {
        let categories = ExpenseCategory.availableNames(
            savedNames: ["Pet care", "  Pet care  ", "Subscriptions"]
        )

        XCTAssertEqual(
            categories,
            ["Food & drink", "Transport", "Shopping", "Bills", "Health", "Pet care", "Subscriptions"]
        )
    }

    func testCustomCategoryRejectsBlankNameAndDuplicate() {
        XCTAssertNil(ExpenseCategory.customName(from: "   "))
        XCTAssertNil(ExpenseCategory.customName(from: " food & DRINK "))
        XCTAssertNil(ExpenseCategory.customName(from: "pet CARE", existingNames: ["Pet care"]))
    }
}
