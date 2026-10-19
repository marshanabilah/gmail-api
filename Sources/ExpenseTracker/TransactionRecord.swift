import Foundation
import SwiftData

@Model
final class TransactionRecord {
    @Attribute(.unique) var sourceMessageID: String
    var fingerprint: String
    var bankID: String
    var occurredAt: Date
    var merchant: String
    var amount: Decimal
    var kind: String
    var confidence: Double
    var category: String?
    var status: String

    init(
        sourceMessageID: String,
        fingerprint: String,
        bankID: String,
        occurredAt: Date,
        merchant: String,
        amount: Decimal,
        kind: String,
        confidence: Double,
        category: String?,
        status: String
    ) {
        self.sourceMessageID = sourceMessageID
        self.fingerprint = fingerprint
        self.bankID = bankID
        self.occurredAt = occurredAt
        self.merchant = merchant
        self.amount = amount
        self.kind = kind
        self.confidence = confidence
        self.category = category
        self.status = status
    }
}

@Model
final class MerchantRuleRecord {
    @Attribute(.unique) var merchantContains: String
    var category: String

    init(merchantContains: String, category: String) {
        self.merchantContains = merchantContains
        self.category = category
    }
}

@Model
final class TrustedImportRuleRecord {
    @Attribute(.unique) var key: String
    var bankID: String
    var merchant: String
    var normalizedMerchantKey: String
    var category: String

    init(bankID: String, merchant: String, category: String) {
        let normalizedMerchantKey = TrustedImportPolicy.normalizedMerchantKey(for: merchant)
        self.key = "\(bankID)|\(normalizedMerchantKey)"
        self.bankID = bankID
        self.merchant = merchant
        self.normalizedMerchantKey = normalizedMerchantKey
        self.category = category
    }
}

@Model
final class CategoryRecord {
    @Attribute(.unique) var name: String

    init(name: String) {
        self.name = name
    }
}

@Model
final class DiscardedImportRecord {
    @Attribute(.unique) var sourceMessageID: String

    init(sourceMessageID: String) {
        self.sourceMessageID = sourceMessageID
    }
}
