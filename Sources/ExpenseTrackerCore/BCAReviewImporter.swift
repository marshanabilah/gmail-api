import Foundation

public struct BankReviewImportResult: Equatable, Sendable {
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

public struct BankReviewImporter: Sendable {
    private let bcaParser: BCAEmailParser
    private let mandiriParser: MandiriTransferEmailParser
    private let categorizer: MerchantCategorizer

    public init(
        bcaParser: BCAEmailParser = BCAEmailParser(),
        mandiriParser: MandiriTransferEmailParser = MandiriTransferEmailParser(),
        categorizer: MerchantCategorizer = MerchantCategorizer()
    ) {
        self.bcaParser = bcaParser
        self.mandiriParser = mandiriParser
        self.categorizer = categorizer
    }

    public func importCandidates(
        _ candidates: [BankEmail],
        existingMessageIDs: Set<String>,
        existingFingerprints: Set<String>,
        rules: [MerchantRule]
    ) -> BankReviewImportResult {
        var seenMessageIDs = existingMessageIDs
        var seenFingerprints = existingFingerprints
        var imports = [ImportedTransaction]()
        var duplicateCount = 0
        var ignoredCount = 0
        var unsupportedCount = 0

        for candidate in candidates {
            switch parse(candidate) {
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

        return BankReviewImportResult(
            imports: imports,
            duplicateCount: duplicateCount,
            ignoredCount: ignoredCount,
            unsupportedCount: unsupportedCount
        )
    }

    private func parse(_ candidate: BankEmail) -> BankEmailParseResult {
        let bcaResult = bcaParser.parse(candidate)
        guard case .unsupported = bcaResult else { return bcaResult }
        return mandiriParser.parse(candidate)
    }
}

public typealias BCAReviewImportResult = BankReviewImportResult
public typealias BCAReviewImporter = BankReviewImporter
