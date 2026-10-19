import XCTest
@testable import ExpenseTrackerCore

final class TrustedImportRuleTests: XCTestCase {
    func testExactRuleReturnsCategoryForSameBankQrisPurchase() {
        let draft = TransactionDraft(
            sourceMessageID: "trusted-qris",
            bankID: "bca",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchant: "ALFAMART REGULAR D",
            amount: 12_000,
            kind: .qrisPayment,
            confidence: 0.99
        )
        let rules = [TrustedImportRule(bankID: "bca", merchant: "Alfamart Regular D", category: "Groceries")]

        XCTAssertEqual(TrustedImportPolicy.category(for: draft, rules: rules), "Groceries")
    }

    func testNearMerchantNameDoesNotMatchTrustedRule() {
        let draft = TransactionDraft(
            sourceMessageID: "near-match",
            bankID: "bca",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchant: "ALFAMART REGULAR B",
            amount: 12_000,
            kind: .qrisPayment,
            confidence: 0.99
        )
        let rules = [TrustedImportRule(bankID: "bca", merchant: "Alfamart Regular D", category: "Groceries")]

        XCTAssertNil(TrustedImportPolicy.category(for: draft, rules: rules))
    }

    func testSameMerchantAtDifferentBankDoesNotMatchTrustedRule() {
        let draft = TransactionDraft(
            sourceMessageID: "different-bank",
            bankID: "jago",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchant: "Example Coffee Shop",
            amount: 12_000,
            kind: .cardPurchase,
            confidence: 0.99
        )

        XCTAssertNil(TrustedImportPolicy.category(
            for: draft,
            rules: [TrustedImportRule(bankID: "bca", merchant: "Example Coffee Shop", category: "Food & drink")]
        ))
    }

    func testTransferAndJagoDebitAlertCannotUseTrustedRule() {
        let transfer = TransactionDraft(
            sourceMessageID: "trusted-transfer",
            bankID: "mandiri",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchant: "Example Recipient",
            amount: 12_000,
            kind: .transferOut,
            confidence: 0.99
        )
        let debitAlert = TransactionDraft(
            sourceMessageID: "trusted-jago-debit",
            bankID: "jago",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            merchant: "Jago debit card spending",
            amount: 12_000,
            kind: .cardPurchase,
            confidence: 0.55
        )

        XCTAssertNil(TrustedImportPolicy.category(
            for: transfer,
            rules: [TrustedImportRule(bankID: "mandiri", merchant: "Example Recipient", category: "Bills")]
        ))
        XCTAssertNil(TrustedImportPolicy.category(
            for: debitAlert,
            rules: [TrustedImportRule(bankID: "jago", merchant: "Jago debit card spending", category: "Shopping")]
        ))
    }
}
