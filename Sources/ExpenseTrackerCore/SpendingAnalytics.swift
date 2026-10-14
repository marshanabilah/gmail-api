import Foundation

public struct SpendingAnalyticsInput: Sendable {
    public let occurredAt: Date
    public let amount: Decimal
    public let kind: TransactionKind
    public let category: String?
    public let status: ImportStatus

    public init(
        occurredAt: Date,
        amount: Decimal,
        kind: TransactionKind,
        category: String?,
        status: ImportStatus
    ) {
        self.occurredAt = occurredAt
        self.amount = amount
        self.kind = kind
        self.category = category
        self.status = status
    }
}

public struct SpendingCategoryTotal: Equatable, Sendable {
    public let category: String
    public let amount: Decimal

    public init(category: String, amount: Decimal) {
        self.category = category
        self.amount = amount
    }
}

public struct MonthlySpendingSummary: Equatable, Sendable {
    public let confirmedSpending: Decimal
    public let pendingReviewAmount: Decimal
    public let pendingReviewCount: Int
    public let categories: [SpendingCategoryTotal]

    public init(
        confirmedSpending: Decimal,
        pendingReviewAmount: Decimal,
        pendingReviewCount: Int,
        categories: [SpendingCategoryTotal]
    ) {
        self.confirmedSpending = confirmedSpending
        self.pendingReviewAmount = pendingReviewAmount
        self.pendingReviewCount = pendingReviewCount
        self.categories = categories
    }
}

public enum SpendingAnalytics {
    public static func availableMonths(
        transactions: [SpendingAnalyticsInput],
        currentDate: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let currentMonth = monthStart(for: currentDate, calendar: calendar)
        let transactionMonths = transactions.map { monthStart(for: $0.occurredAt, calendar: calendar) }
        return Array(Set(transactionMonths + [currentMonth])).sorted(by: >)
    }

    public static func summary(
        for month: Date,
        transactions: [SpendingAnalyticsInput],
        calendar: Calendar = .current
    ) -> MonthlySpendingSummary {
        let monthlyTransactions = transactions.filter {
            calendar.isDate($0.occurredAt, equalTo: month, toGranularity: .month)
        }
        let confirmedExpenses = monthlyTransactions.filter {
            isConfirmedExpense(kind: $0.kind, status: $0.status)
        }
        let pendingExpenses = monthlyTransactions.filter {
            $0.status == .needsReview && isExpense($0.kind)
        }
        var categoryAmounts: [String: Decimal] = [:]
        for transaction in confirmedExpenses {
            let category = categoryName(for: transaction.category)
            categoryAmounts[category, default: 0] += transaction.amount
        }
        let categories = categoryAmounts.map { category, amount in
            SpendingCategoryTotal(category: category, amount: amount)
        }.sorted(by: sortsCategoryTotals)

        return MonthlySpendingSummary(
            confirmedSpending: confirmedExpenses.reduce(0) { $0 + $1.amount },
            pendingReviewAmount: pendingExpenses.reduce(0) { $0 + $1.amount },
            pendingReviewCount: pendingExpenses.count,
            categories: categories
        )
    }

    public static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    public static func isConfirmedExpense(kind: TransactionKind, status: ImportStatus) -> Bool {
        status == .ready && isExpense(kind)
    }

    public static func categoryName(for category: String?) -> String {
        guard let category else { return "Uncategorized" }
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCategory.isEmpty ? "Uncategorized" : trimmedCategory
    }

    private static func isExpense(_ kind: TransactionKind) -> Bool {
        switch kind {
        case .cardPurchase, .qrisPayment, .fee, .manualExpense:
            true
        case .transferOut, .transferIn, .cashWithdrawal, .refund, .unknown:
            false
        }
    }

    private static func sortsCategoryTotals(_ lhs: SpendingCategoryTotal, _ rhs: SpendingCategoryTotal) -> Bool {
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
    }
}
