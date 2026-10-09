import Foundation

public struct ImportEngine: Sendable {
    public let reviewThreshold: Double
    private let categorizer: MerchantCategorizer

    public init(reviewThreshold: Double = 0.9, categorizer: MerchantCategorizer = MerchantCategorizer()) {
        self.reviewThreshold = reviewThreshold
        self.categorizer = categorizer
    }

    public func importDrafts(
        _ drafts: [TransactionDraft],
        existingMessageIDs: Set<String>,
        existingFingerprints: Set<String>,
        rules: [MerchantRule]
    ) -> [ImportedTransaction] {
        var seenMessageIDs = existingMessageIDs
        var seenFingerprints = existingFingerprints

        return drafts.compactMap { draft in
            guard seenMessageIDs.insert(draft.sourceMessageID).inserted else { return nil }
            guard seenFingerprints.insert(draft.fingerprint).inserted else { return nil }

            let category = categorizer.category(for: draft.merchant, rules: rules)
            let needsCategory = switch draft.kind {
            case .cardPurchase, .qrisPayment, .cashWithdrawal, .fee:
                true
            case .transferOut, .transferIn, .refund, .unknown:
                false
            }
            let status: ImportStatus = draft.confidence >= reviewThreshold && (!needsCategory || category != nil) ? .ready : .needsReview
            return ImportedTransaction(draft: draft, category: category, status: status)
        }
    }
}
