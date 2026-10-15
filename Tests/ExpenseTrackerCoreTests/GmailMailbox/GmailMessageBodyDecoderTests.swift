import ExpenseTrackerCore
import XCTest

final class GmailMessageBodyDecoderTests: XCTestCase {
    func testDecoderUsesThePlainTextPartFromAMultipartMessage() throws {
        let plainText = "Status: Successful\nTransaction Type: QRIS Payment"
        let payload = GmailMessagePart(
            mimeType: "multipart/alternative",
            bodyData: nil,
            parts: [
                GmailMessagePart(mimeType: "text/html", bodyData: base64URL("<p>Status: Successful</p>")),
                GmailMessagePart(mimeType: "text/plain", bodyData: base64URL(plainText))
            ]
        )

        XCTAssertEqual(try GmailMessageBodyDecoder().decode(payload), plainText)
    }

    func testDecoderFallsBackToTextFromAnHtmlOnlyMessage() throws {
        let payload = GmailMessagePart(
            mimeType: "text/html",
            bodyData: base64URL("<p>Transfer Successful</p><p>Recipient: Example Person</p>"),
            parts: []
        )

        XCTAssertEqual(
            try GmailMessageBodyDecoder().decode(payload),
            "Transfer Successful\nRecipient: Example Person"
        )
    }

    func testDecoderPreservesMandiriTableFieldsForTheTransferParser() throws {
        let html = """
        <h2>Transfer Successful</h2>
        <table>
          <tr><td>Recipient</td></tr>
          <tr><td>Example Recipient</td></tr>
          <tr><td>Bank Mandiri - 0000</td></tr>
          <tr><td>Date</td><td>2 Oct 2026</td></tr>
          <tr><td>Time</td><td>14:00:45 WIB</td></tr>
          <tr><td>Transfer Amount</td><td>Rp 700.338,00</td></tr>
          <tr><td>Reference No.</td><td>2610021121000000</td></tr>
        </table>
        """
        let payload = GmailMessagePart(mimeType: "text/html", bodyData: base64URL(html))
        let body = try GmailMessageBodyDecoder().decode(payload)

        let result = MandiriTransferEmailParser().parse(BankEmail(
            messageID: "mandiri-html-table",
            sender: "alerts@example.test",
            subject: "Transfer Successful",
            body: body,
            receivedAt: Date(timeIntervalSince1970: 1_728_000_000)
        ))

        guard case .transaction(let draft) = result else {
            return XCTFail("Expected HTML table receipt to parse as a Mandiri transfer")
        }
        XCTAssertEqual(draft.merchant, "Example Recipient")
        XCTAssertEqual(draft.amount, Decimal(string: "700338"))
    }

    func testDecoderRejectsInvalidBase64URLData() {
        let payload = GmailMessagePart(mimeType: "text/plain", bodyData: "not base64!", parts: [])

        XCTAssertThrowsError(try GmailMessageBodyDecoder().decode(payload)) { error in
            XCTAssertEqual(error as? GmailMailboxFailure, .malformedResponse)
        }
    }
}

private func base64URL(_ value: String) -> String {
    Data(value.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
