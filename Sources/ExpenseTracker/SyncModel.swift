import Foundation
import Observation
import SwiftData

enum SyncState: Equatable {
    case idle
    case connecting
    case connected(GmailAuthorizedAccount)
    case syncing
    case failed(String)
}

@MainActor
@Observable
final class SyncModel {
    var state: SyncState = .idle
    var showsConnectionSheet = false
    var lastSyncCandidateCount: Int?
    var lastSyncSkippedMessageCount = 0
    var canRetryMailboxSync = false
    private var hasRestoredConnection = false
    private let auth: GmailAuthCoordinator
    private let mailbox: GmailMailboxSyncCoordinator

    init() {
        auth = GmailAuthCoordinator(service: GoogleGmailAuthorizationService())
        mailbox = GmailMailboxSyncCoordinator(
            service: GmailMailboxScanner(client: GoogleGmailMailboxClient())
        )
    }

    func restoreConnection() {
        guard !hasRestoredConnection, GmailConfiguration.current != nil else {
            return
        }
        hasRestoredConnection = true
        Task {
            await auth.restore()
            applyAuthenticationState()
        }
    }

    func start() {
        guard GmailConfiguration.current != nil else {
            showsConnectionSheet = true
            return
        }
        state = .connecting
        Task {
            await auth.connect()
            applyAuthenticationState()
        }
    }

    func disconnect() {
        lastSyncCandidateCount = nil
        lastSyncSkippedMessageCount = 0
        canRetryMailboxSync = false
        Task {
            await auth.disconnect()
            applyAuthenticationState()
        }
    }

    func syncMailbox() {
        guard case .connected = state else { return }
        beginMailboxSync()
    }

    func retryMailboxSync() {
        guard canRetryMailboxSync else { return }
        beginMailboxSync()
    }

    func bankReviewPreview(
        existingMessageIDs: Set<String>,
        existingFingerprints: Set<String>,
        rules: [MerchantRule]
    ) -> BankReviewImportResult? {
        guard !mailbox.latestCandidates.isEmpty else { return nil }
        return BankReviewImporter().importCandidates(
            mailbox.latestCandidates,
            existingMessageIDs: existingMessageIDs,
            existingFingerprints: existingFingerprints,
            rules: rules
        )
    }

    func saveBankReviewImports(_ preview: BankReviewImportResult, in modelContext: ModelContext) -> Bool {
        var records = [TransactionRecord]()
        for imported in preview.imports {
            let draft = imported.draft
            let record = TransactionRecord(
                sourceMessageID: draft.sourceMessageID,
                fingerprint: draft.fingerprint,
                bankID: draft.bankID,
                occurredAt: draft.occurredAt,
                merchant: draft.merchant,
                amount: draft.amount,
                kind: draft.kind.rawValue,
                confidence: draft.confidence,
                category: imported.category,
                status: imported.status.rawValue
            )
            records.append(record)
            modelContext.insert(record)
        }

        do {
            try modelContext.save()
            return true
        } catch {
            for record in records {
                modelContext.delete(record)
            }
            return false
        }
    }

    func dismissFailure() {
        if case .failed = state {
            if canRetryMailboxSync {
                canRetryMailboxSync = false
                applyAuthenticationState()
            } else {
                state = .idle
            }
        }
    }

    private func beginMailboxSync() {
        guard case .connected = auth.state else { return }
        lastSyncCandidateCount = nil
        lastSyncSkippedMessageCount = 0
        canRetryMailboxSync = false
        state = .syncing
        Task {
            await mailbox.sync(now: .now)
            applyMailboxSyncState()
        }
    }

    private func applyMailboxSyncState() {
        switch mailbox.state {
        case .idle:
            applyAuthenticationState()
        case .syncing:
            state = .syncing
        case .completed(let candidateCount):
            lastSyncCandidateCount = candidateCount
            lastSyncSkippedMessageCount = mailbox.latestSkippedMessageCount
            applyAuthenticationState()
        case .failed(let failure):
            canRetryMailboxSync = true
            state = .failed(message(for: failure))
        }
    }

    private func applyAuthenticationState() {
        switch auth.state {
        case .disconnected:
            state = .idle
        case .connecting:
            state = .connecting
        case .connected(let account):
            state = .connected(account)
        case .failed(let failure):
            state = .failed(message(for: failure))
        }
    }

    private func message(for failure: GmailAuthorizationFailure) -> String {
        switch failure {
        case .configurationMissing:
            "Gmail is not configured on this build yet. Add the Google iOS client ID and redirect scheme, then try again."
        case .callbackMismatch:
            "Google returned to an unexpected callback. Check the iOS redirect scheme and try again."
        case .credentialInvalid:
            "Your Gmail connection needs to be renewed. Connect Gmail again to continue."
        case .secureStorageUnavailable:
            "This simulator build cannot save the Gmail connection yet. In Xcode, choose your Apple Development Team under Signing & Capabilities, then run the app again."
        case .requiredScopeNotGranted:
            "Gmail read-only access was not granted. Connect again and allow read-only access to continue."
        case .unavailable:
            "Gmail could not connect right now. Check your connection and try again."
        case .cancelled:
            ""
        }
    }

    private func message(for failure: GmailMailboxFailure) -> String {
        switch failure {
        case .transactionLabelNotFound:
            "Add a Gmail label named Transaction, then try again."
        case .duplicateTransactionLabels:
            "Gmail has more than one Transaction label. Rename one, then try again."
        case .authorizationExpired:
            "Your Gmail connection needs to be renewed. Connect Gmail again to continue."
        case .messageUnavailable:
            "Gmail could not read one labeled message. Try syncing again."
        case .unavailable:
            "Gmail could not sync right now. Check your connection and try again."
        case .malformedResponse:
            "Gmail returned a message the app could not safely read. Try again later."
        }
    }
}

struct GmailConfiguration: Equatable {
    let clientID: String
    let redirectScheme: String

    static var current: GmailConfiguration? {
        guard
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GmailClientID") as? String,
            let redirectScheme = Bundle.main.object(forInfoDictionaryKey: "GmailRedirectScheme") as? String,
            !clientID.isEmpty,
            !redirectScheme.isEmpty,
            !clientID.contains("$("),
            !redirectScheme.contains("$(")
        else {
            return nil
        }
        return GmailConfiguration(clientID: clientID, redirectScheme: redirectScheme)
    }
}
