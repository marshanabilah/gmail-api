import Foundation

public struct MerchantRule: Equatable, Sendable {
    public let merchantContains: String
    public let category: String

    public init(merchantContains: String, category: String) {
        self.merchantContains = merchantContains
        self.category = category
    }
}

public struct MerchantCategorizer: Sendable {
    public init() {}

    public func category(for merchant: String, rules: [MerchantRule]) -> String? {
        let normalizedMerchant = merchant.lowercased()
        return rules.first { normalizedMerchant.contains($0.merchantContains.lowercased()) }?.category
    }
}
