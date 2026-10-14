import Foundation

public struct BCAReviewImportResult: Equatable, Sendable {
    public let imports: [ImportedTransaction]
    public let duplicateCount: Int
    public let ignoredCount: Int
    public let unsupportedCount: Int

    public init(
        imports: [ImportedTransaction],
        duplicateCount: Int,
        ignoredCount: Int,
        unsupportedCount: Int
    ) {
        self.imports = imports
        self.duplicateCount = duplicateCount
        self.ignoredCount = ignoredCount
        self.unsupportedCount = unsupportedCount
    }
}

public struct BCAReviewImporter: Sendable {
    private let parser: BCAEmailParser
    private let categorizer: MerchantCategorizer

    public init(
        parser: BCAEmailParser = BCAEmailParser(),
        categorizer: MerchantCategorizer = MerchantCategorizer()
    ) {
        self.parser = parser
        self.categorizer = categorizer
    }

    public func importCandidates(
        _ candidates: [BankEmail],
        existingMessageIDs: Set<String>,
        existingFingerprints: Set<String>,
        rules: [MerchantRule]
    ) -> BCAReviewImportResult {
        var seenMessageIDs = existingMessageIDs
        var seenFingerprints = existingFingerprints
        var imports = [ImportedTransaction]()
        var duplicateCount = 0
        var ignoredCount = 0
        var unsupportedCount = 0

        for candidate in candidates {
            switch parser.parse(candidate) {
            case .ignored:
                ignoredCount += 1
            case .unsupported:
                unsupportedCount += 1
            case .transaction(let draft):
                guard seenMessageIDs.insert(draft.sourceMessageID).inserted else {
                    duplicateCount += 1
                    continue
                }
                guard seenFingerprints.insert(draft.fingerprint).inserted else {
                    duplicateCount += 1
                    continue
                }

                imports.append(
                    ImportedTransaction(
                        draft: draft,
                        category: categorizer.category(for: draft.merchant, rules: rules),
                        status: .needsReview
                    )
                )
            }
        }

        return BCAReviewImportResult(
            imports: imports,
            duplicateCount: duplicateCount,
            ignoredCount: ignoredCount,
            unsupportedCount: unsupportedCount
        )
    }
}
