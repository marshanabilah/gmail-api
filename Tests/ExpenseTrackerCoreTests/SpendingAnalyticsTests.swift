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

        XCTAssertEqual(summary.confirmedSpending, 163_000)
        XCTAssertEqual(summary.pendingReviewAmount, 10_000)
        XCTAssertEqual(summary.pendingReviewCount, 1)
        XCTAssertEqual(summary.categories, [
            SpendingCategoryTotal(category: "Bills", amount: 100_000),
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

    func testMonthlySummaryGroupsConfirmedSpendingBySource() throws {
        let october = try date(year: 2026, month: 10, day: 8)

        let summary = SpendingAnalytics.summary(
            for: october,
            transactions: [
                input(date: october, amount: 100_000, kind: .qrisPayment, category: "Food & drink", status: .ready, source: "bca"),
                input(date: october, amount: 20_000, kind: .qrisPayment, category: "Food & drink", status: .ready, source: "bca"),
                input(date: october, amount: 50_000, kind: .transferOut, category: "Bills", status: .ready, source: "mandiri"),
                input(date: october, amount: 30_000, kind: .manualExpense, category: "Shopping", status: .ready, source: "eWallet"),
                input(date: october, amount: 25_000, kind: .manualExpense, category: "Food & drink", status: .ready, source: "cash"),
                input(date: october, amount: 10_000, kind: .cardPurchase, category: "Transport", status: .ready, source: "jago"),
                input(date: october, amount: 90_000, kind: .qrisPayment, category: "Food & drink", status: .needsReview, source: "bca"),
            ],
            calendar: calendar
        )

        XCTAssertEqual(summary.sources, [
            SpendingSourceTotal(source: "BCA", amount: 120_000),
            SpendingSourceTotal(source: "Mandiri", amount: 50_000),
            SpendingSourceTotal(source: "E-wallet", amount: 30_000),
            SpendingSourceTotal(source: "Cash", amount: 25_000),
            SpendingSourceTotal(source: "Jago", amount: 10_000),
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

    func testConfirmedExpenseRuleCountsAcceptedTransfersButExcludesReviewItems() {
        XCTAssertTrue(SpendingAnalytics.isConfirmedExpense(kind: .qrisPayment, status: .ready))
        XCTAssertTrue(SpendingAnalytics.isConfirmedExpense(kind: .manualExpense, status: .ready))
        XCTAssertTrue(SpendingAnalytics.isConfirmedExpense(kind: .transferOut, status: .ready))
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .qrisPayment, status: .needsReview))
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .transferOut, status: .needsReview))
    }

    func testConfirmedExpenseRuleExcludesOtherNonExpenseKinds() {
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .transferIn, status: .ready))
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .cashWithdrawal, status: .ready))
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .refund, status: .ready))
        XCTAssertFalse(SpendingAnalytics.isConfirmedExpense(kind: .unknown, status: .ready))
    }

    func testCategoryNameUsesUncategorizedOnlyForMissingOrBlankStoredValues() {
        XCTAssertEqual(SpendingAnalytics.categoryName(for: nil), "Uncategorized")
        XCTAssertEqual(SpendingAnalytics.categoryName(for: "  "), "Uncategorized")
        XCTAssertEqual(SpendingAnalytics.categoryName(for: "  Food & drink  "), "Food & drink")
    }

    private func input(
        date: Date,
        amount: Decimal,
        kind: TransactionKind,
        category: String?,
        status: ImportStatus,
        source: String = "bca"
    ) -> SpendingAnalyticsInput {
        SpendingAnalyticsInput(
            occurredAt: date,
            amount: amount,
            kind: kind,
            category: category,
            status: status,
            source: source
        )
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
