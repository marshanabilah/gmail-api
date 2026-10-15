import XCTest
@testable import ExpenseTrackerCore

final class BCAReviewImportTests: XCTestCase {
    func testMixedBCAAndMandiriCandidatesBothEnterReview() {
        let result = BankReviewImporter().importCandidates(
            [bcaEmail(id: "bca-mixed"), mandiriImportEmail(id: "mandiri-mixed")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertEqual(result.imports.map(\.draft.bankID), ["bca", "mandiri"])
        XCTAssertEqual(result.imports.map(\.status), [.needsReview, .needsReview])
        XCTAssertEqual(result.unsupportedCount, 0)
    }

    func testMandiriMessageIDAndFingerprintDuplicatesAreSkipped() throws {
        let email = mandiriImportEmail(id: "mandiri-duplicate")
        let draft = try XCTUnwrap(transactionDraft(from: MandiriTransferEmailParser().parse(email)))
        let result = BankReviewImporter().importCandidates(
            [email, mandiriImportEmail(id: "mandiri-second")],
            existingMessageIDs: ["mandiri-duplicate"],
            existingFingerprints: [draft.fingerprint],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.duplicateCount, 2)
    }

    func testMandiriMerchantRuleSuggestsCategoryWithoutBypassingReview() {
        let result = BankReviewImporter().importCandidates(
            [mandiriImportEmail(id: "mandiri-rule", recipient: "Example Recipient")],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: [MerchantRule(merchantContains: "recipient", category: "Bills")]
        )

        XCTAssertEqual(result.imports.first?.category, "Bills")
        XCTAssertEqual(result.imports.first?.status, .needsReview)
        XCTAssertEqual(result.imports.first?.draft.kind, .transferOut)
    }

    func testMandiriPaymentAndTopUpCandidatesEnterReviewWithMerchantRules() {
        let result = BankReviewImporter().importCandidates(
            [mandiriPaymentImportEmail(), mandiriTopUpImportEmail()],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: [
                MerchantRule(merchantContains: "market", category: "Food & drink"),
                MerchantRule(merchantContains: "e-money", category: "Transport")
            ]
        )

        XCTAssertEqual(result.imports.map(\.draft.kind), [.qrisPayment, .transferOut])
        XCTAssertEqual(result.imports.map(\.status), [.needsReview, .needsReview])
        XCTAssertEqual(result.imports.map(\.category), ["Food & drink", "Transport"])
        XCTAssertEqual(result.unsupportedCount, 0)
    }

    func testDiscardedMessageIDIsIgnoredBeforeParsingAndOtherCandidatesStillImport() {
        let discarded = bcaEmail(id: "discarded-message")
        let importable = bcaEmail(id: "still-importable", merchant: "Example Market")

        let result = BankReviewImporter().importCandidates(
            [discarded, importable],
            existingMessageIDs: [],
            existingFingerprints: [],
            discardedMessageIDs: ["discarded-message"],
            rules: []
        )

        XCTAssertEqual(result.imports.map(\.draft.sourceMessageID), ["still-importable"])
        XCTAssertEqual(result.ignoredCount, 1)
        XCTAssertEqual(result.unsupportedCount, 0)
    }

    func testCandidateUnsupportedByBothParsersIsCountedOnce() {
        let unsupported = BankEmail(
            messageID: "unknown-1",
            sender: "alerts@example.test",
            subject: "Account notice",
            body: "This message is not a supported transaction receipt.",
            receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )
        let result = BankReviewImporter().importCandidates(
            [unsupported],
            existingMessageIDs: [],
            existingFingerprints: [],
            rules: []
        )

        XCTAssertTrue(result.imports.isEmpty)
        XCTAssertEqual(result.unsupportedCount, 1)
    }

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

private func mandiriImportEmail(
    id: String,
    recipient: String = "Example Recipient"
) -> BankEmail {
    BankEmail(
        messageID: id,
        sender: "alerts@example.test",
        subject: "Transfer notification",
        body: """
        Transfer Successful
        Recipient
        \(recipient)
        Bank Mandiri - 0000
        Date | 2 Oct 2026
        Time | 14:00:45 WIB
        Transfer Amount | Rp 700.338,00
        Reference No. | 2610021121000000
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func mandiriPaymentImportEmail() -> BankEmail {
    BankEmail(
        messageID: "mandiri-payment-import",
        sender: "alerts@example.test",
        subject: "Payment notification",
        body: """
        Payment Successful
        Recipient
        Example Market - QRIS
        Example City (ID)
        Date | 11 Oct 2026
        Time | 06:14:56 WIB
        Transaction Amount | Rp 3.800,00
        Transaction Ref. No. | 610116495573
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func mandiriTopUpImportEmail() -> BankEmail {
    BankEmail(
        messageID: "mandiri-top-up-import",
        sender: "alerts@example.test",
        subject: "e-money Top-up Successful",
        body: """
        e-money Top-up Successful
        Service Provider
        e-money
        Date | 12 Oct 2026
        Time | 20:36:39 WIB
        Top-up Amount | Rp 50.000,00
        Reference Number | 7026101220363000004
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func transactionDraft(from result: BankEmailParseResult) -> TransactionDraft? {
    guard case .transaction(let draft) = result else { return nil }
    return draft
}

private extension BankEmailParseResult {
    var transactionDraft: TransactionDraft? {
        guard case .transaction(let draft) = self else { return nil }
        return draft
    }
}
