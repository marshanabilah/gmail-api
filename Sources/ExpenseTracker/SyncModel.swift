import Foundation
import Observation

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
    private let auth: GmailAuthCoordinator

    init() {
        auth = GmailAuthCoordinator(service: GoogleGmailAuthorizationService())
    }

    func restoreConnection() {
        guard GmailConfiguration.current != nil else {
            return
        }
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
        Task {
            await auth.disconnect()
            applyAuthenticationState()
        }
    }

    func dismissFailure() {
        if case .failed = state {
            state = .idle
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
        case .requiredScopeNotGranted:
            "Gmail read-only access was not granted. Connect again and allow read-only access to continue."
        case .unavailable:
            "Gmail could not connect right now. Check your connection and try again."
        case .cancelled:
            ""
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
