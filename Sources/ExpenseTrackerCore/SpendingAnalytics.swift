import Foundation

public struct SpendingAnalyticsInput: Sendable {
    public let occurredAt: Date
    public let amount: Decimal
    public let kind: TransactionKind
    public let category: String?
    public let status: ImportStatus
    public let source: String

    public init(
        occurredAt: Date,
        amount: Decimal,
        kind: TransactionKind,
        category: String?,
        status: ImportStatus,
        source: String
    ) {
        self.occurredAt = occurredAt
        self.amount = amount
        self.kind = kind
        self.category = category
        self.status = status
        self.source = source
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

public struct SpendingSourceTotal: Equatable, Sendable {
    public let source: String
    public let amount: Decimal

    public init(source: String, amount: Decimal) {
        self.source = source
        self.amount = amount
    }
}

public struct MonthlySpendingSummary: Equatable, Sendable {
    public let confirmedSpending: Decimal
    public let pendingReviewAmount: Decimal
    public let pendingReviewCount: Int
    public let categories: [SpendingCategoryTotal]
    public let sources: [SpendingSourceTotal]

    public init(
        confirmedSpending: Decimal,
        pendingReviewAmount: Decimal,
        pendingReviewCount: Int,
        categories: [SpendingCategoryTotal],
        sources: [SpendingSourceTotal]
    ) {
        self.confirmedSpending = confirmedSpending
        self.pendingReviewAmount = pendingReviewAmount
        self.pendingReviewCount = pendingReviewCount
        self.categories = categories
        self.sources = sources
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
        var sourceAmounts: [String: Decimal] = [:]
        for transaction in confirmedExpenses {
            let category = categoryName(for: transaction.category)
            categoryAmounts[category, default: 0] += transaction.amount
            let source = sourceName(for: transaction.source)
            sourceAmounts[source, default: 0] += transaction.amount
        }
        let categories = categoryAmounts.map { category, amount in
            SpendingCategoryTotal(category: category, amount: amount)
        }.sorted(by: sortsCategoryTotals)
        let sources = sourceAmounts.map { source, amount in
            SpendingSourceTotal(source: source, amount: amount)
        }.sorted(by: sortsSourceTotals)

        return MonthlySpendingSummary(
            confirmedSpending: confirmedExpenses.reduce(0) { $0 + $1.amount },
            pendingReviewAmount: pendingExpenses.reduce(0) { $0 + $1.amount },
            pendingReviewCount: pendingExpenses.count,
            categories: categories,
            sources: sources
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

    public static func sourceName(for source: String) -> String {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch normalizedSource.lowercased() {
        case "bca": "BCA"
        case "mandiri": "Mandiri"
        case "cash": "Cash"
        case "ewallet", "e-wallet": "E-wallet"
        case "": "Other"
        default:
            normalizedSource.prefix(1).uppercased() + normalizedSource.dropFirst()
        }
    }

    private static func isExpense(_ kind: TransactionKind) -> Bool {
        switch kind {
        case .cardPurchase, .qrisPayment, .fee, .manualExpense, .transferOut:
            true
        case .transferIn, .cashWithdrawal, .refund, .unknown:
            false
        }
    }

    private static func sortsCategoryTotals(_ lhs: SpendingCategoryTotal, _ rhs: SpendingCategoryTotal) -> Bool {
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        return lhs.category.localizedCaseInsensitiveCompare(rhs.category) == .orderedAscending
    }

    private static func sortsSourceTotals(_ lhs: SpendingSourceTotal, _ rhs: SpendingSourceTotal) -> Bool {
        if lhs.amount != rhs.amount {
            return lhs.amount > rhs.amount
        }
        return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
    }
}
