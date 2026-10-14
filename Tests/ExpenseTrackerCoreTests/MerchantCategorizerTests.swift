import XCTest
@testable import ExpenseTrackerCore

final class MerchantCategorizerTests: XCTestCase {
    func testCategoriesSiblingMerchantNamesUsingTheirSharedSpecificPrefix() {
        let category = MerchantCategorizer().category(
            for: "ALFAMART REGULAR B",
            rules: [MerchantRule(merchantContains: "ALFAMART REGULAR D", category: "Groceries")]
        )

        XCTAssertEqual(category, "Groceries")
    }

    func testDoesNotCategorizeMerchantsWithOnlyAGenericSharedPrefix() {
        let category = MerchantCategorizer().category(
            for: "WARUNG MAKAN PAGI",
            rules: [MerchantRule(merchantContains: "WARUNG TEGAL", category: "Groceries")]
        )

        XCTAssertNil(category)
    }
}
