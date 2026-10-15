import XCTest
@testable import ExpenseTrackerCore

final class JagoEmailParserTests: XCTestCase {
    func testStructuredPaymentParsesUsingFirstToValue() throws {
        let result = JagoStructuredPaymentEmailParser().parse(structuredPaymentEmail())
        let draft = try XCTUnwrap(transaction(from: result))

        XCTAssertEqual(draft.bankID, "jago")
        XCTAssertEqual(draft.kind, .cardPurchase)
        XCTAssertEqual(draft.merchant, "Example Restaurant")
        XCTAssertEqual(draft.amount, 54_500)
        XCTAssertEqual(draft.occurredAt, try jakartaDate(day: 10, hour: 7, minute: 59))
        XCTAssertEqual(draft.confidence, 0.99)
    }

    func testFailedStructuredPaymentIsIgnored() {
        XCTAssertEqual(
            JagoStructuredPaymentEmailParser().parse(structuredPaymentEmail(status: "Failed")),
            .ignored
        )
    }

    func testTransferParsesUsingRecipientNotAccountNumber() throws {
        let draft = try XCTUnwrap(transaction(from: JagoTransferEmailParser().parse(transferEmail())))

        XCTAssertEqual(draft.kind, .transferOut)
        XCTAssertEqual(draft.merchant, "Example Recipient")
        XCTAssertEqual(draft.amount, 726_000)
        XCTAssertEqual(draft.occurredAt, try jakartaDate(day: 8, hour: 13, minute: 20))
    }

    func testTopUpParsesUsingDestinationNotPhoneNumber() throws {
        let draft = try XCTUnwrap(transaction(from: JagoTopUpEmailParser().parse(topUpEmail())))

        XCTAssertEqual(draft.kind, .transferOut)
        XCTAssertEqual(draft.merchant, "Example e-wallet")
        XCTAssertEqual(draft.amount, 150_000)
        XCTAssertEqual(draft.occurredAt, try jakartaDate(day: 8, hour: 16, minute: 42))
    }

    func testDebitCardAlertUsesProvisionalLabelAndReceiptTime() throws {
        let email = debitCardEmail()
        let draft = try XCTUnwrap(transaction(from: JagoDebitCardEmailParser().parse(email)))

        XCTAssertEqual(draft.kind, .cardPurchase)
        XCTAssertEqual(draft.merchant, "Jago debit card spending")
        XCTAssertEqual(draft.amount, 400_000)
        XCTAssertEqual(draft.occurredAt, email.receivedAt)
        XCTAssertEqual(draft.confidence, 0.55)
    }

    func testStructuredReceiptWithoutAmountIsUnsupported() {
        XCTAssertEqual(
            JagoStructuredPaymentEmailParser().parse(structuredPaymentEmail(replacing: "Rp 54.500", with: "Rp 0")),
            .unsupported
        )
    }

    func testStructuredReceiptWithoutDateIsUnsupported() {
        XCTAssertEqual(
            JagoTransferEmailParser().parse(transferEmail(replacing: "08 October 2026 13:20 WIB", with: "")),
            .unsupported
        )
    }
}

private func structuredPaymentEmail(
    status: String = "Successful",
    replacing oldValue: String? = nil,
    with newValue: String = ""
) -> BankEmail {
    let body = """
    Thank you for trusting Jago! You have made a payment, and here are the details:
    Transaction Summary
    From
    100410000000
    To
    Example Restaurant
    9360000000000000000
    Amount
    Rp 54.500
    Transaction Date
    10 October 2026, 07:59 WIB
    Transaction Status
    \(status)
    Acquirer Name
    Example Acquirer
    """
    return jagoEmail(
        id: "jago-payment-1",
        body: oldValue.map { body.replacingOccurrences(of: $0, with: newValue) } ?? body
    )
}

private func transferEmail(replacing oldValue: String? = nil, with newValue: String = "") -> BankEmail {
    let body = """
    Thank you for trusting Jago! You have transferred some money and here are the details:
    Transaction Summary
    From
    Example account
    To
    Example Recipient
    BCA • 0000000000
    Amount
    Rp726.000
    Transaction Date
    08 October 2026 13:20 WIB
    """
    return jagoEmail(
        id: "jago-transfer-1",
        body: oldValue.map { body.replacingOccurrences(of: $0, with: newValue) } ?? body
    )
}

private func topUpEmail() -> BankEmail {
    jagoEmail(
        id: "jago-top-up-1",
        body: """
        Thank you for trusting Jago! You just did a top up, here are the details:
        Transaction Summary
        From:
        100410000000
        To:
        Example e-wallet
        081300000000
        Amount:
        Rp150.000
        Transaction Date
        08 October 2026 16:42 WIB
        """
    )
}

private func debitCardEmail() -> BankEmail {
    jagoEmail(
        id: "jago-debit-1",
        body: """
        Hello Example,
        You have recently made a transaction of Rp400.000 using your Jago debit card.
        """
    )
}

private func jagoEmail(id: String, body: String) -> BankEmail {
    BankEmail(
        messageID: id,
        sender: "alerts@example.test",
        subject: "Jago transaction",
        body: body,
        receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
    )
}

private func transaction(from result: BankEmailParseResult) -> TransactionDraft? {
    guard case .transaction(let draft) = result else { return nil }
    return draft
}

private func jakartaDate(day: Int, hour: Int, minute: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
    return try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
}
