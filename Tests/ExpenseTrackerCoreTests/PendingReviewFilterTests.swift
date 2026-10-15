import XCTest
@testable import ExpenseTrackerCore

final class PendingReviewFilterTests: XCTestCase {
    func testMatchesOnlyTheSelectedJakartaMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let august = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))
        let augustItem = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 23)))
        let septemberItem = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        XCTAssertTrue(PendingReviewFilter.matches(augustItem, month: august, calendar: calendar))
        XCTAssertFalse(PendingReviewFilter.matches(septemberItem, month: august, calendar: calendar))
        XCTAssertTrue(PendingReviewFilter.matches(septemberItem, month: nil, calendar: calendar))
    }
}
