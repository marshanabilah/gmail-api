import Foundation

public struct TrustedImportRule: Equatable, Sendable {
    public let bankID: String
    public let merchant: String
    public let normalizedMerchantKey: String
    public let category: String

    public init(bankID: String, merchant: String, category: String) {
        self.bankID = bankID
        self.merchant = merchant
        self.normalizedMerchantKey = TrustedImportPolicy.normalizedMerchantKey(for: merchant)
        self.category = category
    }
}

public enum TrustedImportPolicy {
    public static func category(for draft: TransactionDraft, rules: [TrustedImportRule]) -> String? {
        guard isEligibleForAutoImport(merchant: draft.merchant, kind: draft.kind) else { return nil }

        let merchantKey = normalizedMerchantKey(for: draft.merchant)
        return rules.first {
            $0.bankID == draft.bankID && $0.normalizedMerchantKey == merchantKey
        }?.category
    }

    public static func normalizedMerchantKey(for merchant: String) -> String {
        merchant
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    public static func isEligibleForAutoImport(merchant: String, kind: TransactionKind) -> Bool {
        guard merchant != "Jago debit card spending" else { return false }
        return kind == .qrisPayment || kind == .cardPurchase
    }
}
