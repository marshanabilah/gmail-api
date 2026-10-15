import XCTest
@testable import ExpenseTrackerCore

final class MandiriPaymentEmailParserTests: XCTestCase {
    func testCompletePaymentReceiptParsesAsMandiriPayment() throws {
        let result = MandiriPaymentEmailParser().parse(paymentEmail())
        let draft = try XCTUnwrap(transaction(from: result))

        XCTAssertEqual(draft.bankID, "mandiri")
        XCTAssertEqual(draft.merchant, "EXAMPLE MARKET - QRIS")
        XCTAssertEqual(draft.amount, Decimal(string: "3800.00"))
        XCTAssertEqual(draft.kind, .qrisPayment)
        XCTAssertEqual(draft.confidence, 0.99)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: draft.occurredAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 11)
        XCTAssertEqual(components.hour, 6)
        XCTAssertEqual(components.minute, 14)
        XCTAssertEqual(components.second, 56)
    }

    func testMissingPaymentSuccessfulHeadingIsUnsupported() {
        XCTAssertEqual(
            MandiriPaymentEmailParser().parse(paymentEmail(heading: "Payment Details")),
            .unsupported
        )
    }

    func testMissingRecipientIsUnsupported() {
        XCTAssertEqual(
            MandiriPaymentEmailParser().parse(paymentEmail(recipient: "")),
            .unsupported
        )
    }

    func testMissingTransactionReferenceIsUnsupported() {
        XCTAssertEqual(
            MandiriPaymentEmailParser().parse(paymentEmail(reference: "")),
            .unsupported
        )
    }

    func testZeroPaymentAmountIsUnsupported() {
        XCTAssertEqual(
            MandiriPaymentEmailParser().parse(paymentEmail(amount: "Rp 0,00")),
            .unsupported
        )
    }
}

private func paymentEmail(
    heading: String = "Payment Successful",
    recipient: String = "EXAMPLE MARKET - QRIS",
    amount: String = "Rp 3.800,00",
    reference: String = "610116495573"
) -> BankEmail {
    BankEmail(
        messageID: "mandiri-payment-message-1",
        sender: "alerts@example.test",
        subject: "Payment notification",
        body: """
        \(heading)

        Recipient
        #### \(recipient)
        Example City (ID)

        | Date | 11 Oct 2026 |
        | Time | 06:14:56 WIB |
        | Transaction Amount | \(amount) |
        | Transaction Ref. No. | \(reference) |
        | QRIS Reference No. | CPM-000000000000 |
        | Merchant PAN | 0000000000000000000 |
        | Customer PAN | 0000000000000000000 |
        | Acquirer | Bank Mandiri |
        | Terminal ID | 00000000 |

        Source of Fund
        #### Example Account
        ****0000
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func transaction(from result: BankEmailParseResult) -> TransactionDraft? {
    guard case .transaction(let draft) = result else { return nil }
    return draft
}
