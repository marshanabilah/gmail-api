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
