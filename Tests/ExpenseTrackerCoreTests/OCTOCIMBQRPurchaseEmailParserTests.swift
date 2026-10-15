import XCTest
@testable import ExpenseTrackerCore

final class OCTOCIMBQRPurchaseEmailParserTests: XCTestCase {
    private let parser = OCTOCIMBQRPurchaseEmailParser()

    func testCompleteQRPurchaseParsesWithMerchantAndTotalPayment() throws {
        let result = parser.parse(completeReceipt())

        guard case .transaction(let draft) = result else {
            return XCTFail("Expected a transaction")
        }
        XCTAssertEqual(draft.bankID, "octoCimb")
        XCTAssertEqual(draft.kind, .qrisPayment)
        XCTAssertEqual(draft.merchant, "Example Coffee Shop")
        XCTAssertEqual(draft.amount, 55_200)
        XCTAssertEqual(draft.occurredAt, try jakartaDate(year: 2026, month: 10, day: 15, hour: 12, minute: 35))
        XCTAssertEqual(draft.confidence, 0.99)
    }

    func testMissingTransactionIDIsUnsupported() {
        XCTAssertEqual(parser.parse(completeReceipt(replacing: "Transaction ID:\ntransaction-123\n", with: "")), .unsupported)
    }

    func testNonQRPurchaseTypeIsUnsupported() {
        XCTAssertEqual(parser.parse(completeReceipt(replacing: "Purchase with QR", with: "Card purchase")), .unsupported)
    }

    func testMissingMerchantIsUnsupported() {
        XCTAssertEqual(parser.parse(completeReceipt(replacing: "Merchant Name:\nExample Coffee Shop\n", with: "")), .unsupported)
    }

    func testZeroTotalPaymentIsUnsupported() {
        XCTAssertEqual(parser.parse(completeReceipt(replacing: "IDR 55,200.00", with: "IDR 0.00")), .unsupported)
    }

    private func completeReceipt(replacing oldValue: String? = nil, with newValue: String = "") -> BankEmail {
        let body = """
        Below is the summary of OCTO App transaction that you have performed:
        Date/Time:
        15Oct26 12:35
        Transaction ID:
        transaction-123
        Purchase Type:
        Purchase with QR
        Merchant Name:
        Example Coffee Shop
        Fee:
        IDR 0.00
        Total Payment:
        IDR 55,200.00
        Source of Fund Account:
        ••••3100
        Poin Xtra used:
        0 Point(s) - equivalent to IDR 0.00
        """
        return BankEmail(
            messageID: "octo-qr-1",
            sender: "alerts@example.test",
            subject: "OCTO App transaction",
            body: oldValue.map { body.replacingOccurrences(of: $0, with: newValue) } ?? body,
            receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )
    }

    private func jakartaDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Jakarta"))
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
