import XCTest
@testable import ExpenseTrackerCore

final class SpendingAnalyticsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    }

    func testMonthlySummaryUsesOnlyConfirmedExpenseTransactionsForSpendingAndCategories() throws {
        let october = try date(year: 2026, month: 10, day: 8)
        let september = try date(year: 2026, month: 9, day: 30)

        let summary = SpendingAnalytics.summary(
            for: october,
            transactions: [
                input(date: october, amount: 38_000, kind: .qrisPayment, category: "Food & drink", status: .ready),
                input(date: october, amount: 25_000, kind: .manualExpense, category: "Transport", status: .ready),
                input(date: october, amount: 10_000, kind: .qrisPayment, category: "Food & drink", status: .needsReview),
                input(date: october, amount: 100_000, kind: .transferOut, category: "Bills", status: .ready),
                input(date: september, amount: 70_000, kind: .qrisPayment, category: "Food & drink", status: .ready),
            ],
            calendar: calendar
        )

        XCTAssertEqual(summary.confirmedSpending, 63_000)
        XCTAssertEqual(summary.pendingReviewAmount, 10_000)
        XCTAssertEqual(summary.pendingReviewCount, 1)
        XCTAssertEqual(summary.categories, [
            SpendingCategoryTotal(category: "Food & drink", amount: 38_000),
            SpendingCategoryTotal(category: "Transport", amount: 25_000),
        ])
    }

    func testMonthlySummaryGroupsConfirmedTransactionsWithoutACategoryAsUncategorized() throws {
        let october = try date(year: 2026, month: 10, day: 8)

        let summary = SpendingAnalytics.summary(
            for: october,
            transactions: [
                input(date: october, amount: 15_000, kind: .cardPurchase, category: nil, status: .ready),
            ],
            calendar: calendar
        )

        XCTAssertEqual(summary.categories, [
            SpendingCategoryTotal(category: "Uncategorized", amount: 15_000),
        ])
    }

    func testAvailableMonthsIncludesCurrentMonthEvenBeforeAnyTransactionExists() throws {
        let october = try date(year: 2026, month: 10, day: 8)
        let august = try date(year: 2026, month: 8, day: 20)

        XCTAssertEqual(
            SpendingAnalytics.availableMonths(transactions: [input(date: august, amount: 1, kind: .manualExpense, category: "Food & drink", status: .ready)], currentDate: october, calendar: calendar),
            [try monthStart(year: 2026, month: 10), try monthStart(year: 2026, month: 8)]
        )
    }

    private func input(date: Date, amount: Decimal, kind: TransactionKind, category: String?, status: ImportStatus) -> SpendingAnalyticsInput {
        SpendingAnalyticsInput(occurredAt: date, amount: amount, kind: kind, category: category, status: status)
    }

    private func date(year: Int, month: Int, day: Int) throws -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else {
            throw NSError(domain: "SpendingAnalyticsTests", code: 1)
        }
        return date
    }

    private func monthStart(year: Int, month: Int) throws -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            throw NSError(domain: "SpendingAnalyticsTests", code: 1)
        }
        return date
    }
}
