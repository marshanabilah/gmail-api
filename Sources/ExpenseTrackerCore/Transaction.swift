import Foundation

public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case cardPurchase
    case qrisPayment
    case transferOut
    case transferIn
    case cashWithdrawal
    case fee
    case refund
    case manualExpense
    case unknown
}

public enum ImportStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case needsReview
    case ignored
}

public enum ManualTransactionSource: String, CaseIterable, Sendable {
    case cash
    case eWallet

    public var displayName: String {
        switch self {
        case .cash: "Cash"
        case .eWallet: "E-wallet"
        }
    }
}

public enum ExpenseCategory {
    public static let defaultNames = ["Food & drink", "Transport", "Shopping", "Bills", "Health"]

    public static func availableNames(savedNames: [String]) -> [String] {
        var names = defaultNames
        for name in savedNames {
            guard let normalizedName = customName(from: name, existingNames: names) else { continue }
            names.append(normalizedName)
        }
        return names
    }

    public static func customName(from candidate: String, existingNames: [String] = defaultNames) -> String? {
        let normalizedName = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return nil }
        guard !existingNames.contains(where: { $0.caseInsensitiveCompare(normalizedName) == .orderedSame }) else {
            return nil
        }
        return normalizedName
    }
}

public struct ManualTransactionInput: Sendable {
    public let merchant: String
    public let amount: Decimal
    public let occurredAt: Date
    public let source: ManualTransactionSource
    public let category: String

    public init(
        merchant: String,
        amount: Decimal,
        occurredAt: Date,
        source: ManualTransactionSource,
        category: String
    ) {
        self.merchant = merchant
        self.amount = amount
        self.occurredAt = occurredAt
        self.source = source
        self.category = category
    }

    public func makeDraft(id: String) -> TransactionDraft? {
        let normalizedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMerchant.isEmpty, amount > 0 else { return nil }

        return TransactionDraft(
            sourceMessageID: id,
            bankID: source.rawValue,
            occurredAt: occurredAt,
            merchant: normalizedMerchant,
            amount: amount,
            kind: .manualExpense,
            confidence: 1
        )
    }
}

public struct TransactionDraft: Equatable, Sendable {
    public let sourceMessageID: String
    public let bankID: String
    public let occurredAt: Date
    public let merchant: String
    public let amount: Decimal
    public let kind: TransactionKind
    public let confidence: Double

    public init(
        sourceMessageID: String,
        bankID: String,
        occurredAt: Date,
        merchant: String,
        amount: Decimal,
        kind: TransactionKind,
        confidence: Double
    ) {
        self.sourceMessageID = sourceMessageID
        self.bankID = bankID
        self.occurredAt = occurredAt
        self.merchant = merchant
        self.amount = amount
        self.kind = kind
        self.confidence = confidence
    }

    public var fingerprint: String {
        let normalizedMerchant = merchant
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(bankID)|\(occurredAt.timeIntervalSince1970)|\(amount)|\(kind.rawValue)|\(normalizedMerchant)"
    }
}

public struct ImportedTransaction: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let draft: TransactionDraft
    public var category: String?
    public var status: ImportStatus

    public init(id: UUID = UUID(), draft: TransactionDraft, category: String? = nil, status: ImportStatus) {
        self.id = id
        self.draft = draft
        self.category = category
        self.status = status
    }
}
