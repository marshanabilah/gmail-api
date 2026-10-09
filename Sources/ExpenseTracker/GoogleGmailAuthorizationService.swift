import GoogleSignIn
import UIKit

@MainActor
final class GoogleGmailAuthorizationService: GmailAuthorizationService {
    private let configuration: GmailConfiguration?

    init(configuration: GmailConfiguration? = .current) {
        self.configuration = configuration
    }

    static func handleRedirect(_ url: URL) {
        GIDSignIn.sharedInstance.handle(url)
    }

    func restore() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount? {
        guard configureGoogleSignIn() else {
            throw .configurationMissing
        }

        let result: Result<GmailAuthorizedAccount?, GmailAuthorizationFailure> = await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let user {
                    switch self.account(from: user) {
                    case .success(let account):
                        continuation.resume(returning: .success(account))
                    case .failure(let failure):
                        continuation.resume(returning: .failure(failure))
                    }
                } else if self.isMissingStoredCredential(error) {
                    continuation.resume(returning: .success(nil))
                } else {
                    continuation.resume(returning: .failure(self.failure(from: error)))
                }
            }
        }

        switch result {
        case .success(let account): return account
        case .failure(let failure): throw failure
        }
    }

    func authorize() async throws(GmailAuthorizationFailure) -> GmailAuthorizedAccount {
        guard configureGoogleSignIn() else {
            throw .configurationMissing
        }
        guard let presenter = activeViewController() else {
            throw .unavailable
        }

        let result: Result<GmailAuthorizedAccount, GmailAuthorizationFailure> = await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: [GmailOAuthScope.readonly]
            ) { signInResult, error in
                guard let signInResult else {
                    continuation.resume(returning: .failure(self.failure(from: error)))
                    return
                }
                continuation.resume(returning: self.account(from: signInResult.user))
            }
        }

        switch result {
        case .success(let account): return account
        case .failure(let failure): throw failure
        }
    }

    func disconnect() async {
        GIDSignIn.sharedInstance.signOut()
    }

    private func configureGoogleSignIn() -> Bool {
        guard let configuration else {
            return false
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: configuration.clientID)
        return true
    }

    private func account(from user: GIDGoogleUser) -> Result<GmailAuthorizedAccount, GmailAuthorizationFailure> {
        guard let identifier = user.userID ?? user.profile?.email else {
            return .failure(.credentialInvalid)
        }
        return .success(
            GmailAuthorizedAccount(
                identifier: identifier,
                email: user.profile?.email,
                grantedScopes: Set(user.grantedScopes ?? [])
            )
        )
    }

    private func isMissingStoredCredential(_ error: Error?) -> Bool {
        let nsError = error as NSError?
        return nsError?.domain == kGIDSignInErrorDomain && nsError?.code == -4
    }

    private func failure(from error: Error?) -> GmailAuthorizationFailure {
        let nsError = error as NSError?
        guard nsError?.domain == kGIDSignInErrorDomain else {
            return .unavailable
        }
        switch nsError?.code {
        case -5: return .cancelled
        case -9: return .callbackMismatch
        case -11: return .credentialInvalid
        default: return .unavailable
        }
    }

    private func activeViewController() -> UIViewController? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else {
            return nil
        }
        return window.rootViewController?.presentedViewController ?? window.rootViewController
    }
}
