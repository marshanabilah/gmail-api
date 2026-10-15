import XCTest
@testable import ExpenseTrackerCore

final class MandiriTransferEmailParserTests: XCTestCase {
    func testCompleteLivinReceiptParsesAsMandiriTransferOut() throws {
        let result = MandiriTransferEmailParser().parse(mandiriEmail())
        let draft = try XCTUnwrap(transaction(from: result))

        XCTAssertEqual(draft.bankID, "mandiri")
        XCTAssertEqual(draft.merchant, "EXAMPLE RECIPIENT")
        XCTAssertEqual(draft.amount, Decimal(string: "700338.00"))
        XCTAssertEqual(draft.kind, .transferOut)
        XCTAssertEqual(draft.confidence, 0.99)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: draft.occurredAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 2)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(components.second, 45)
    }

    func testMissingRecipientIsUnsupported() {
        let result = MandiriTransferEmailParser().parse(mandiriEmail(recipient: ""))

        XCTAssertEqual(result, .unsupported)
    }

    func testMissingReferenceNumberIsUnsupported() {
        let result = MandiriTransferEmailParser().parse(mandiriEmail(referenceNumber: ""))

        XCTAssertEqual(result, .unsupported)
    }

    func testRecipientContainingFieldLabelTextStillParses() throws {
        let result = MandiriTransferEmailParser().parse(mandiriEmail(recipient: "UPDATE CAFE"))
        let draft = try XCTUnwrap(transaction(from: result))

        XCTAssertEqual(draft.merchant, "UPDATE CAFE")
    }

    func testZeroAmountIsUnsupported() {
        let result = MandiriTransferEmailParser().parse(mandiriEmail(amount: "Rp 0,00"))

        XCTAssertEqual(result, .unsupported)
    }

    func testLookalikeWithoutTransferSuccessfulHeadingIsUnsupported() {
        let result = MandiriTransferEmailParser().parse(mandiriEmail(heading: "Transfer Details"))

        XCTAssertEqual(result, .unsupported)
    }
}

private func mandiriEmail(
    heading: String = "Transfer Successful",
    recipient: String = "EXAMPLE RECIPIENT",
    amount: String = "Rp 700.338,00",
    referenceNumber: String = "2610021121000000"
) -> BankEmail {
    BankEmail(
        messageID: "mandiri-message-1",
        sender: "alerts@example.test",
        subject: "Transfer notification",
        body: """
        \(heading)

        Recipient
        #### \(recipient)
        Bank Mandiri - 0000000000000

        | Date | 2 Oct 2026 |
        | Time | 14:00:45 WIB |
        | Transfer Amount | \(amount) |
        | Reference No. | \(referenceNumber) |
        | Description | - |

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
