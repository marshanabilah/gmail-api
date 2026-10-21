import XCTest
@testable import ExpenseTrackerCore

final class LocalNotificationPolicyTests: XCTestCase {
    func testSyncCompletionUsesOnlySafeMailboxCounts() {
        let notification = LocalNotificationPolicy.syncCompletion(
            candidateCount: 2,
            skippedMessageCount: 1
        )

        XCTAssertEqual(notification.kind, .gmailSyncFinished)
        XCTAssertEqual(notification.identifier, "gmail-sync-finished")
        XCTAssertEqual(notification.title, "Gmail sync finished")
        XCTAssertEqual(
            notification.body,
            "2 eligible emails are ready to import. Gmail skipped 1 labeled message."
        )
    }

    func testReviewReminderSchedulesForNineOnTheNextLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 18)))

        let decision = LocalNotificationPolicy.reviewReminder(
            pendingReviewCount: 3,
            now: now,
            calendar: calendar
        )

        let request = try XCTUnwrap(decision.request)
        XCTAssertEqual(request.kind, .reviewReminder)
        XCTAssertEqual(request.identifier, "pending-review-reminder")
        XCTAssertEqual(request.title, "Transactions need review")
        XCTAssertEqual(request.body, "3 transactions are waiting for your review.")
        XCTAssertEqual(
            request.scheduledAt,
            try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9)))
        )
    }

    func testNoPendingReviewsCancelsTheExistingReminder() {
        let decision = LocalNotificationPolicy.reviewReminder(
            pendingReviewCount: 0,
            now: .now
        )

        XCTAssertEqual(decision, .cancel(identifier: "pending-review-reminder"))
    }
}
