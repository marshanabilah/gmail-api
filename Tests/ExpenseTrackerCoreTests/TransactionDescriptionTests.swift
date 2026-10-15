import XCTest
@testable import ExpenseTrackerCore

final class TransactionDescriptionTests: XCTestCase {
    func testNormalizesWhitespaceAroundDescription() {
        XCTAssertEqual(TransactionDescription.normalized("  Dinner with friends  "), "Dinner with friends")
    }

    func testRejectsBlankDescription() {
        XCTAssertNil(TransactionDescription.normalized(" \n "))
    }
}
