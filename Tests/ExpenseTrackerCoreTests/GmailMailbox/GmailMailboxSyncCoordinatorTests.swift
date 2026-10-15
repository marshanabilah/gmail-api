import ExpenseTrackerCore
import XCTest

@MainActor
final class GmailMailboxSyncCoordinatorTests: XCTestCase {
    func testSyncKeepsCandidatesInMemoryForTheApprovedLocalImporter() async {
        let service = FakeMailboxSyncService(
            result: .success(
                GmailMailboxScanResult(
                    candidates: [
                        makeEmail(id: "bca-1"),
                        makeEmail(id: "jago-1")
                    ],
                    excludedFlipMessageCount: 1,
                    skippedMessageCount: 0
                )
            )
        )
        let coordinator = GmailMailboxSyncCoordinator(service: service)

        await coordinator.sync(now: .now)

        XCTAssertEqual(coordinator.state, .completed(candidateCount: 2))
        XCTAssertEqual(coordinator.latestCandidates.map(\.messageID), ["bca-1", "jago-1"])
        XCTAssertEqual(coordinator.latestSkippedMessageCount, 0)
    }

    func testSyncReportsTheNumberOfMessagesGmailWouldNotReturn() async {
        let service = FakeMailboxSyncService(
            result: .success(
                GmailMailboxScanResult(
                    candidates: [makeEmail(id: "bca-1")],
                    excludedFlipMessageCount: 0,
                    skippedMessageCount: 1
                )
            )
        )
        let coordinator = GmailMailboxSyncCoordinator(service: service)

        await coordinator.sync(now: .now)

        XCTAssertEqual(coordinator.state, .completed(candidateCount: 1))
        XCTAssertEqual(coordinator.latestSkippedMessageCount, 1)
    }

    func testSyncReportsFailureAndAllowsAnotherAttempt() async {
        let service = FakeMailboxSyncService(result: .failure(.unavailable))
        let coordinator = GmailMailboxSyncCoordinator(service: service)

        await coordinator.sync(now: .now)

        XCTAssertEqual(coordinator.state, .failed(.unavailable))
        XCTAssertEqual(service.scanCount, 1)
        XCTAssertTrue(coordinator.latestCandidates.isEmpty)
    }
}

private final class FakeMailboxSyncService: GmailMailboxSyncing, @unchecked Sendable {
    let result: Result<GmailMailboxScanResult, GmailMailboxFailure>
    private(set) var scanCount = 0

    init(result: Result<GmailMailboxScanResult, GmailMailboxFailure>) {
        self.result = result
    }

    func scan(now: Date) async throws(GmailMailboxFailure) -> GmailMailboxScanResult {
        scanCount += 1
        return try result.get()
    }
}

private func makeEmail(id: String) -> BankEmail {
    BankEmail(
        messageID: id,
        sender: "alerts@example.test",
        subject: "Transaction alert",
        body: "A bank transaction email",
        receivedAt: .now
    )
}
