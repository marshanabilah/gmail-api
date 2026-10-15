import ExpenseTrackerCore
import XCTest

final class GmailMailboxScannerTests: XCTestCase {
    func testScanReturnsNonFlipCandidatesAndExcludesConfirmedFlipReceipt() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [
                "initial": GmailMessagePage(messageIDs: ["bca-1", "flip-1"], nextPageToken: nil)
            ],
            messages: [
                "bca-1": email(
                    id: "bca-1",
                    body: "Status: Successful\nTransaction Type: QRIS Payment\nPayment to: Example Merchant\nTotal Payment: IDR 12,000.00",
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

    func testScanFollowsPagesWithoutFetchingTheSameMessageTwice() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [
                "initial": GmailMessagePage(messageIDs: ["bca-1", "jago-1"], nextPageToken: "page-2"),
                "page-2": GmailMessagePage(messageIDs: ["jago-1", "livin-1"], nextPageToken: nil)
            ],
            messages: [
                "bca-1": email(id: "bca-1", body: "QRIS Payment", receivedAt: now),
                "jago-1": email(id: "jago-1", body: "using your Jago debit card", receivedAt: now),
                "livin-1": email(id: "livin-1", body: "Transfer Successful\nRecipient\nExample Recipient", receivedAt: now)
            ]
        )

        let result = try await GmailMailboxScanner(client: client).scan(now: now)

        XCTAssertEqual(result.candidates.map(\.messageID), ["bca-1", "jago-1", "livin-1"])
        XCTAssertEqual(client.requestedMessageIDs, ["bca-1", "jago-1", "livin-1"])
    }

    func testScanKeepsAControlEmailThatSharesOnlyOneFlipPhrase() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: ["initial": GmailMessagePage(messageIDs: ["bank-1"], nextPageToken: nil)],
            messages: [
                "bank-1": email(
                    id: "bank-1",
                    body: "Your transaction has been successfully processed. Please keep this receipt.",
                    receivedAt: now
                )
            ]
        )

        let result = try await GmailMailboxScanner(client: client).scan(now: now)

        XCTAssertEqual(result.candidates.map(\.messageID), ["bank-1"])
        XCTAssertEqual(result.excludedFlipMessageCount, 0)
    }

    func testScanExcludesMessagesOlderThanNinetyDays() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let oldDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -91, to: now)!
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: ["initial": GmailMessagePage(messageIDs: ["old-1"], nextPageToken: nil)],
            messages: ["old-1": email(id: "old-1", body: "Old bank alert", receivedAt: oldDate)]
        )

        let result = try await GmailMailboxScanner(
            client: client,
            calendar: Calendar(identifier: .gregorian)
        ).scan(now: now)

        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testScanSkipsAnInaccessibleMessageWithoutDiscardingOtherCandidates() async throws {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [
                "initial": GmailMessagePage(
                    messageIDs: ["bca-1", "inaccessible-1", "mandiri-1"],
                    nextPageToken: nil
                )
            ],
            messages: [
                "bca-1": email(id: "bca-1", body: "QRIS Payment", receivedAt: now),
                "mandiri-1": email(id: "mandiri-1", body: "Transfer Successful", receivedAt: now)
            ],
            messageFailures: ["inaccessible-1": .messageUnavailable]
        )

        let result = try await GmailMailboxScanner(client: client).scan(now: now)

        XCTAssertEqual(result.candidates.map(\.messageID), ["bca-1", "mandiri-1"])
        XCTAssertEqual(result.skippedMessageCount, 1)
    }

    func testScanRejectsAFetchedMessageWhoseIDDoesNotMatchTheListedID() async {
        let now = Date(timeIntervalSince1970: 1_791_763_200)
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: ["initial": GmailMessagePage(messageIDs: ["listed-id"], nextPageToken: nil)],
            messages: ["listed-id": email(id: "different-id", body: "Bank alert", receivedAt: now)]
        )

        do {
            _ = try await GmailMailboxScanner(client: client).scan(now: now)
            XCTFail("Expected a malformed response failure")
        } catch {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    func testScanReportsMissingTransactionLabel() async {
        let client = FakeGmailMailboxClient(labels: [], pages: [:], messages: [:])

        do {
            _ = try await GmailMailboxScanner(client: client).scan(now: .now)
            XCTFail("Expected a missing label failure")
        } catch {
            XCTAssertEqual(error, .transactionLabelNotFound)
        }
    }

    func testScanReportsDuplicateTransactionLabels() async {
        let client = FakeGmailMailboxClient(
            labels: [
                GmailLabel(id: "first", name: "Transaction"),
                GmailLabel(id: "second", name: "Transaction")
            ],
            pages: [:],
            messages: [:]
        )

        do {
            _ = try await GmailMailboxScanner(client: client).scan(now: .now)
            XCTFail("Expected a duplicate label failure")
        } catch {
            XCTAssertEqual(error, .duplicateTransactionLabels)
        }
    }

    func testScanReportsAnInvalidPaginationLoop() async {
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [
                "initial": GmailMessagePage(messageIDs: [], nextPageToken: "repeated"),
                "repeated": GmailMessagePage(messageIDs: [], nextPageToken: "repeated")
            ],
            messages: [:]
        )

        do {
            _ = try await GmailMailboxScanner(client: client).scan(now: .now)
            XCTFail("Expected a malformed response failure")
        } catch {
            XCTAssertEqual(error, .malformedResponse)
        }
    }

    func testScanPropagatesARecoverableMailboxFailure() async {
        let client = FakeGmailMailboxClient(
            labels: [GmailLabel(id: "transaction-label", name: "Transaction")],
            pages: [:],
            messages: [:],
            pageFailure: .authorizationExpired
        )

        do {
            _ = try await GmailMailboxScanner(client: client).scan(now: .now)
            XCTFail("Expected an authorization failure")
        } catch {
            XCTAssertEqual(error, .authorizationExpired)
        }
    }
}

private final class FakeGmailMailboxClient: GmailMailboxClient, @unchecked Sendable {
    let labels: [GmailLabel]
    let pages: [String: GmailMessagePage]
    let messages: [String: BankEmail]
    let pageFailure: GmailMailboxFailure?
    let messageFailures: [String: GmailMailboxFailure]
    private(set) var requestedMessageIDs = [String]()

    init(
        labels: [GmailLabel],
        pages: [String: GmailMessagePage],
        messages: [String: BankEmail],
        pageFailure: GmailMailboxFailure? = nil,
        messageFailures: [String: GmailMailboxFailure] = [:]
    ) {
        self.labels = labels
        self.pages = pages
        self.messages = messages
        self.pageFailure = pageFailure
        self.messageFailures = messageFailures
    }

    func listLabels() async throws(GmailMailboxFailure) -> [GmailLabel] {
        labels
    }

    func messagePage(
        in labelID: String,
        after startDate: Date,
        pageToken: String?
    ) async throws(GmailMailboxFailure) -> GmailMessagePage {
        if let pageFailure {
            throw pageFailure
        }
        guard let page = pages[pageToken ?? "initial"] else {
            throw .malformedResponse
        }
        return page
    }

    func message(id: String) async throws(GmailMailboxFailure) -> BankEmail {
        requestedMessageIDs.append(id)
        if let failure = messageFailures[id] {
            throw failure
        }
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
