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
        let merchantWords = normalizedWords(in: merchant)
        let normalizedMerchant = merchantWords.joined(separator: " ")

        return rules.first { rule in
            let ruleWords = normalizedWords(in: rule.merchantContains)
            let normalizedRule = ruleWords.joined(separator: " ")
            return !normalizedRule.isEmpty && (
                normalizedMerchant.contains(normalizedRule) ||
                hasDistinctiveSharedPrefix(merchantWords, ruleWords)
            )
        }?.category
    }

    private func normalizedWords(in value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func hasDistinctiveSharedPrefix(_ left: [String], _ right: [String]) -> Bool {
        let sharedPrefix = zip(left, right)
            .prefix { $0.0 == $0.1 }
            .map(\.0)
            .joined(separator: " ")

        return sharedPrefix.count >= 8 && sharedPrefix.contains { $0.isLetter }
    }
}
