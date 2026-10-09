import Foundation

public enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case cardPurchase
    case qrisPayment
    case transferOut
    case transferIn
    case cashWithdrawal
    case fee
    case refund
    case unknown
}

public enum ImportStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case needsReview
    case ignored
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
