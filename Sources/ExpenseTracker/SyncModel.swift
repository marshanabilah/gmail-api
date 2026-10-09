import Foundation
import Observation

enum SyncState: Equatable {
    case idle
    case connecting
    case syncing
    case failed(String)
}

@Observable
final class SyncModel {
    var state: SyncState = .idle
    var showsConnectionSheet = false

    func start() {
        guard GmailConfiguration.current != nil else {
            showsConnectionSheet = true
            return
        }
        state = .failed("Gmail sync is not connected yet. Add the Gmail OAuth client configuration before syncing.")
    }

    func dismissFailure() {
        if case .failed = state {
            state = .idle
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
            !redirectScheme.isEmpty
        else {
            return nil
        }
        return GmailConfiguration(clientID: clientID, redirectScheme: redirectScheme)
    }
}
