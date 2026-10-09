# Spec: Gmail Authentication for BCA iPhone-First Sync

Module id: `gmail-auth`

## Objective

Let the owner of this personal iPhone ledger connect one Gmail account with read-only access. The app must hold the resulting credential locally and safely so later modules can read messages from the user's `Transaction` label.

The user starts the connection from the app. The first milestone succeeds when a configured app can complete a Google authorization flow in the simulator, retain the credential securely, show its connected state, and disconnect without changing Gmail or deleting local transactions.

## Tech Stack

- Swift 6 and SwiftUI, targeting iOS 17 or later.
- Google Sign-In for iOS via Swift Package Manager (`GoogleSignIn` and
  `GoogleSignInSwift`), subject to the approved dependency and callback
  configuration change below.
- The SDK-managed iOS Keychain state for credential storage.
- Gmail OAuth scope: `https://www.googleapis.com/auth/gmail.readonly` only.
- No backend, cloud database, or Apps Script service.

## OAuth Integration Decision

Use Google's maintained iOS Sign-In SDK rather than building the authorization
code exchange around `ASWebAuthenticationSession` ourselves. Google's current
iOS guide documents the SDK's Swift Package Manager distribution, callback
handling, sign-in restoration, sign-out behavior, incremental Google API
scopes, and token refresh. The SDK is therefore the smaller and better-tested
surface for this iPhone-only app.

The app will use the SDK's own Keychain-backed sign-in state. Our
`GmailCredentialStore` boundary becomes an abstraction over that state, rather
than a second store of raw refresh or access tokens. This avoids duplicating
sensitive credentials while retaining fakeable storage for unit tests.

Official sources:

- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developers.google.com/identity/sign-in/ios/sign-in
- https://developers.google.com/identity/sign-in/ios/api-access

The first implementation change requires explicit approval to add
`https://github.com/google/GoogleSignIn-iOS` with the `GoogleSignIn` and
`GoogleSignInSwift` products, then add the Google-issued iOS URL scheme to the
app target. It will not add a server client ID, a client secret, or a broader
Gmail scope.

## Commands

Build the iPhone app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -destination 'platform=iOS Simulator,id=034B0CF5-C08A-43D1-BE32-BD397E1DA6CC' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

Run the current core tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test
```

## Project Structure

```text
Sources/ExpenseTracker/SyncModel.swift          -> Connection state consumed by the UI
Sources/ExpenseTracker/GmailConnectionView.swift -> Connection, consent, error, and disconnect UI
Sources/ExpenseTracker/GmailAuth/               -> OAuth client, callback validation, credential store
Tests/ExpenseTrackerTests/                      -> iOS unit tests for auth state and credential-store seams
SPEC-gmail-auth.md                              -> This module's approved requirements
```

## Code Style

Keep state explicit, small, and observable. Dependencies that reach OAuth or Keychain must be expressed behind narrow protocols so tests can use fakes.

```swift
protocol GmailCredentialStore {
    func load() throws -> GmailCredential?
    func save(_ credential: GmailCredential) throws
    func remove() throws
}
```

- Use `Gmail` as the product name and `gmail` only in code identifiers or the OAuth scope.
- Make errors actionable and avoid exposing token values, raw authorization responses, or email content.
- Keep the current local SwiftData ledger independent of authentication state.

## Testing Strategy

- Add an iOS XCTest target before production OAuth code.
- Unit-test the auth state machine with fake OAuth and Keychain dependencies.
- Unit-test that a credential survives an app-model recreation and that disconnect removes only the credential.
- Test configuration failures, user cancellation, callback state mismatch, and expired or invalid credentials without using a real Google account.
- Use the iOS Simulator for the first end-to-end sign-in and callback check. Use one physical-device test only after the simulator flow works.

## Boundaries

### Always

- Request only `gmail.readonly`.
- Store OAuth credentials in Keychain, never `UserDefaults`, SwiftData, source code, logs, or the repository.
- Validate OAuth callback state before accepting a credential.
- Preserve all existing local transactions when connecting or disconnecting Gmail.
- Test state transitions before a simulator sign-in check.

### Ask First

- Adding the Google Sign-In SDK or any third-party OAuth dependency.
- Adding an iOS XCTest target or changing the Xcode project structure.
- Changing the app bundle identifier, URL scheme, entitlements, or Google Cloud configuration.
- Broadening Gmail permissions, adding another Google account, or introducing a backend.

### Never

- Commit client secrets, refresh tokens, authorization codes, or real email data.
- Request `gmail.modify`, `gmail.labels`, `gmail.send`, or broader Gmail scopes.
- Create, rename, apply, remove, archive, mark read, or delete Gmail labels or messages.
- Log raw authorization responses, tokens, or transaction email bodies.

## Success Criteria

- [ ] A user with valid local OAuth configuration can start Google authorization from the app.
- [ ] The consent request names `gmail.readonly` as the only Gmail permission.
- [ ] Cancel, configuration error, callback mismatch, and credential failure each return the app to a clear, recoverable state.
- [ ] A successful credential is stored only in Keychain and is available after app restart.
- [ ] The app visibly identifies whether Gmail is disconnected, connecting, or connected.
- [ ] Disconnect removes the Gmail credential and connection state without deleting local transactions, categories, or merchant rules.
- [ ] No Gmail message or label is changed by this module.
- [ ] Unit tests cover the state transitions and credential-store behavior; the iOS simulator completes one configured sign-in and callback path.

## Open Questions

- Confirm the production callback scheme registered in the Google Cloud OAuth client.
- Decide whether the app should display the connected Gmail address, and if so, how to obtain it without adding unnecessary scopes.
