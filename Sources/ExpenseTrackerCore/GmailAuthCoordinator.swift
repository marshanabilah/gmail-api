import Foundation

public enum GmailOAuthScope {
    public static let readonly = "https://www.googleapis.com/auth/gmail.readonly"
}

public struct GmailAuthorizedAccount: Equatable, Sendable {
    public let identifier: String
    public let email: String?
    public let grantedScopes: Set<String>

    public init(identifier: String, email: String?, grantedScopes: Set<String>) {
        self.identifier = identifier
        self.email = email
        self.grantedScopes = grantedScopes
    }

    public func hasRequiredScope(_ scope: String = GmailOAuthScope.readonly) -> Bool {
        grantedScopes.contains(scope)
    }
}

public enum GmailAuthorizationFailure: Error, Equatable, Sendable {
    case cancelled
    case configurationMissing
    case callbackMismatch
    case credentialInvalid
    case requiredScopeNotGranted
    case unavailable
}

public enum GmailAuthState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(GmailAuthorizedAccount)
    case failed(GmailAuthorizationFailure)
}

@MainActor
public protocol GmailAuthorizationService: AnyObject {
    func restore() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount?
    func authorize() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount
    func disconnect() async
}

@MainActor
public final class GmailAuthCoordinator {
    public private(set) var state: GmailAuthState = .disconnected

    private let service: GmailAuthorizationService

    public init(service: GmailAuthorizationService) {
        self.service = service
    }

    public func restore() async {
        state = .connecting
        do {
            guard let account = try await service.restore() else {
                state = .disconnected
                return
            }
            state = validatedState(for: account)
        } catch {
            state = state(after: error)
        }
    }

    public func connect() async {
        state = .connecting
        do {
            state = validatedState(for: try await service.authorize())
        } catch {
            state = state(after: error)
        }
    }

    public func disconnect() async {
        await service.disconnect()
        state = .disconnected
    }

    private func validatedState(for account: GmailAuthorizedAccount) -> GmailAuthState {
        account.hasRequiredScope() ? .connected(account) : .failed(.requiredScopeNotGranted)
    }

    private func state(after failure: GmailAuthorizationFailure) -> GmailAuthState {
        failure == .cancelled ? .disconnected : .failed(failure)
    }
}
