import XCTest
@testable import ExpenseTrackerCore

final class MandiriEMoneyTopUpEmailParserTests: XCTestCase {
    func testCompleteEMoneyTopUpReceiptParsesAsMandiriTransferOut() throws {
        let result = MandiriEMoneyTopUpEmailParser().parse(topUpEmail())
        let draft = try XCTUnwrap(transaction(from: result))

        XCTAssertEqual(draft.bankID, "mandiri")
        XCTAssertEqual(draft.merchant, "e-money top-up")
        XCTAssertEqual(draft.amount, Decimal(string: "50000.00"))
        XCTAssertEqual(draft.kind, .transferOut)
        XCTAssertEqual(draft.confidence, 0.99)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: draft.occurredAt)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 36)
        XCTAssertEqual(components.second, 39)
    }

    func testWrongServiceProviderIsUnsupported() {
        XCTAssertEqual(
            MandiriEMoneyTopUpEmailParser().parse(topUpEmail(provider: "Another provider")),
            .unsupported
        )
    }

    func testMissingTopUpSuccessfulHeadingIsUnsupported() {
        XCTAssertEqual(
            MandiriEMoneyTopUpEmailParser().parse(topUpEmail(heading: "Top-up Details")),
            .unsupported
        )
    }

    func testMissingReferenceNumberIsUnsupported() {
        XCTAssertEqual(
            MandiriEMoneyTopUpEmailParser().parse(topUpEmail(reference: "")),
            .unsupported
        )
    }

    func testZeroTopUpAmountIsUnsupported() {
        XCTAssertEqual(
            MandiriEMoneyTopUpEmailParser().parse(topUpEmail(amount: "Rp 0,00")),
            .unsupported
        )
    }
}

private func topUpEmail(
    heading: String = "e-money Top-up Successful",
    provider: String = "e-money",
    amount: String = "Rp 50.000,00",
    reference: String = "7026101220363000004"
) -> BankEmail {
    BankEmail(
        messageID: "mandiri-top-up-message-1",
        sender: "alerts@example.test",
        subject: "e-money Top-up Successful",
        body: """
        \(heading)

        Service Provider
        #### \(provider)
        ****0000

        | Date | 12 Oct 2026 |
        | Time | 20:36:39 WIB |
        | Top-up Amount | \(amount) |
        | Reference Number | \(reference) |
        """,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func transaction(from result: BankEmailParseResult) -> TransactionDraft? {
    guard case .transaction(let draft) = result else { return nil }
    return draft
}
