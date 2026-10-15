import Foundation

public protocol GmailMailboxSyncing: Sendable {
    func scan(now: Date) async throws(GmailMailboxFailure) -> GmailMailboxScanResult
}

extension GmailMailboxScanner: GmailMailboxSyncing {}

public enum GmailMailboxSyncState: Equatable, Sendable {
    case idle
    case syncing
    case completed(candidateCount: Int)
    case failed(GmailMailboxFailure)
}

@MainActor
public final class GmailMailboxSyncCoordinator {
    public private(set) var state: GmailMailboxSyncState = .idle
    public private(set) var latestCandidates = [BankEmail]()
    public private(set) var latestSkippedMessageCount = 0
    private let service: any GmailMailboxSyncing

    public init(service: any GmailMailboxSyncing) {
        self.service = service
    }

    public func sync(now: Date) async {
        guard state != .syncing else { return }
        latestCandidates = []
        latestSkippedMessageCount = 0
        state = .syncing

        do {
            let result = try await service.scan(now: now)
            latestCandidates = result.candidates
            latestSkippedMessageCount = result.skippedMessageCount
            state = .completed(candidateCount: result.candidates.count)
        } catch {
            state = .failed(error)
        }
    }
}
