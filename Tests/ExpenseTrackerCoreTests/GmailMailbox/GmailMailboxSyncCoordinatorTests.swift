import ExpenseTrackerCore
import XCTest

@MainActor
final class GmailMailboxSyncCoordinatorTests: XCTestCase {
    func testSyncReportsCandidateCountWithoutExposingCandidateContent() async {
        let service = FakeMailboxSyncService(
            result: .success(
                GmailMailboxScanResult(
                    candidates: [
                        makeEmail(id: "bca-1"),
                        makeEmail(id: "jago-1")
                    ],
                    excludedFlipMessageCount: 1
                )
            )
        )
        let coordinator = GmailMailboxSyncCoordinator(service: service)

        await coordinator.sync(now: .now)

        XCTAssertEqual(coordinator.state, .completed(candidateCount: 2))
    }

    func testSyncReportsFailureAndAllowsAnotherAttempt() async {
        let service = FakeMailboxSyncService(result: .failure(.unavailable))
        let coordinator = GmailMailboxSyncCoordinator(service: service)

        await coordinator.sync(now: .now)

        XCTAssertEqual(coordinator.state, .failed(.unavailable))
        XCTAssertEqual(service.scanCount, 1)
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
