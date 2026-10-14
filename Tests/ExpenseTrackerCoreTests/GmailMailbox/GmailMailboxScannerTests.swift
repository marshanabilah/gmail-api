import ExpenseTrackerCore
import XCTest

final class GmailMailboxScannerTests: XCTestCase {
    func testScanReturnsNonFlipCandidatesAndExcludesConfirmedFlipReceipt() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [
                nil: GmailMessagePage(messageIDs: ["bca-1", "flip-1"], nextPageToken: nil)
            ],
            messages: [
                "bca-1": email(
                    id: "bca-1",
                    body: "Status: Successful\nTransaction Type: QRIS Payment\nTotal Payment: IDR 12,000.00",
                    receivedAt: now
                ),
                "flip-1": email(
                    id: "flip-1",
                    body: "Your transaction has been successfully processed.\nDestination Bank\nExample Bank\nDestination Account Number\n0000",
                    receivedAt: now
                )
            ]
        )

        let result = try await GmailMailboxScanner(client: client).scan(now: now)

        XCTAssertEqual(result.candidates.map(\.messageID), ["bca-1"])
        XCTAssertEqual(result.excludedFlipMessageCount, 1)
    }
}

private final class FakeGmailMailboxClient: GmailMailboxClient, @unchecked Sendable {
    let labels: [GmailLabel]
    let pages: [String?: GmailMessagePage]
    let messages: [String: BankEmail]

    init(labels: [GmailLabel], pages: [String?: GmailMessagePage], messages: [String: BankEmail]) {
        self.labels = labels
        self.pages = pages
        self.messages = messages
    }

    func listLabels() async throws(GmailMailboxFailure) -> [GmailLabel] {
        labels
    }

    func messagePage(
        in labelID: String,
        after startDate: Date,
        pageToken: String?
    ) async throws(GmailMailboxFailure) -> GmailMessagePage {
        guard let page = pages[pageToken] else {
            throw .malformedResponse
        }
        return page
    }

    func message(id: String) async throws(GmailMailboxFailure) -> BankEmail {
        guard let message = messages[id] else {
            throw .malformedResponse
        }
        return message
    }
}

private func email(id: String, body: String, receivedAt: Date) -> BankEmail {
    BankEmail(
        messageID: id,
        sender: "alerts@example.test",
        subject: "Transaction alert",
        body: body,
        receivedAt: receivedAt
    )
}
