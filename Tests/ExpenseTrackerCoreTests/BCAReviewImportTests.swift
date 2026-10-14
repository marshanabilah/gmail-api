import XCTest
@testable import ExpenseTrackerCore

final class BCAReviewImportTests: XCTestCase {
    func testSuccessfulQRISPaymentCreatesNeedsReviewImport() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-1")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertEqual(result.imports.count, 1)
        XCTAssertEqual(result.imports.first?.draft.bankID, "bca")
        XCTAssertEqual(result.imports.first?.draft.kind, .qrisPayment)
        XCTAssertEqual(result.imports.first?.status, .needsReview)
        XCTAssertEqual(result.unsupportedCount, 0)
        XCTAssertEqual(result.ignoredCount, 0)
        XCTAssertEqual(result.duplicateCount, 0)
    }

    func testSuccessfulQRISPaymentWithTableCellsOnSeparateLinesCreatesNeedsReviewImport() {
        let email = BankEmail(
            messageID: "bca-table-cells",
            sender: "alerts@example.test",
            subject: "QRIS payment",
            body: """
            Status
            :
            Successful
            Transaction Date
            :
            08 Oct 2026 17:54:32
            Transaction Type
            :
            QRIS Payment
            Payment to
            :
            Example Store
            Total Payment
            :
            IDR 3,800.00
            """,
            receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )

        let result = BCAReviewImporter().importCandidates(
            [email],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertEqual(result.imports.count, 1)
        XCTAssertEqual(result.imports.first?.draft.merchant, "Example Store")
    }

    func testFailedBCAReceiptIsIgnored() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-failed", status: "Failed")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.ignoredCount, 1)
    }

    func testMissingRequiredBCAFieldIsUnsupported() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-missing", merchant: "")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.unsupportedCount, 1)
    }

    func testExistingMessageIDIsSkipped() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-duplicate")],
            existingMessageIDs: ["bca-duplicate"],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.duplicateCount, 1)
    }

    func testExistingFingerprintIsSkipped() {
        let email = bcaEmail(id: "bca-duplicate-fingerprint")
        let draft = try! XCTUnwrap(BCAEmailParser().parse(email).transactionDraft)
        let result = BCAReviewImporter().importCandidates(
            [email],
            existingMessageIDs: [],
            existingFingerprints: [draft.fingerprint],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.duplicateCount, 1)
    }

    func testMatchingMerchantRuleSuggestsCategoryButKeepsBCAItemInReview() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-rule", merchant: "Example Market")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: [MerchantRule(merchantContains: "market", category: "Food & drink")]
        )

        XCTAssertEqual(result.imports.first?.category, "Food & drink")
        XCTAssertEqual(result.imports.first?.status, .needsReview)
    }

    func testUncategorizedBCAItemStaysInReview() {
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-no-rule", merchant: "New Merchant")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertNil(result.imports.first?.category)
        XCTAssertEqual(result.imports.first?.status, .needsReview)
    }

    func testUnsupportedCandidateDoesNotBlockValidBCAImport() {
        let unsupported = BankEmail(
            messageID: "jago-1",
            sender: "alerts@example.test",
            subject: "Debit card transaction",
            body: "You have recently made a transaction using your Jago debit card.",
            receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )
        let result = BCAReviewImporter().importCandidates(
            [bcaEmail(id: "bca-valid"), unsupported],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertEqual(result.imports.count, 1)
        XCTAssertEqual(result.unsupportedCount, 1)
    }
}

private func bcaEmail(
    id: String,
    status: String = "Successful",
    merchant: String = "Example Store"
) -> BankEmail {
    BankEmail(
        messageID: id,
        sender: "alerts@example.test",
        subject: "QRIS payment",
        body: """
        Status: \(status)
        Transaction Date: 08 Oct 2026 17:54:32
        Transaction Type: QRIS Payment
        Payment to: \(merchant)
        Total Payment: IDR 3,800.00
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private extension BankEmailParseResult {
    var transactionDraft: TransactionDraft? {
        guard case .transaction(let draft) = self else { return nil }
        return draft
    }
}
