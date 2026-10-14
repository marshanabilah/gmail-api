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
    private let service: any GmailMailboxSyncing

    public init(service: any GmailMailboxSyncing) {
        self.service = service
    }

    public func sync(now: Date) async {
        guard state != .syncing else { return }
        latestCandidates = []
        state = .syncing

        do {
            let result = try await service.scan(now: now)
            latestCandidates = result.candidates
            state = .completed(candidateCount: result.candidates.count)
        } catch {
            state = .failed(error)
        }
    }
}
