# Gmail Authentication Task List

Status key: `[ ]` not started, `[~]` in progress, `[x]` complete.

## 1. Decide the native iOS OAuth integration

- [x] Read the current official Google iOS OAuth guidance and Apple
  `ASWebAuthenticationSession` documentation using the
  source-driven-development workflow.
- [x] Compare a standards-based browser implementation with an official Google
  iOS library only on the criteria relevant here: supported authorization-code
  flow, PKCE/state validation, token refresh, callback handling, maintenance,
  and dependency footprint.
- [x] Record the selected approach and why in `SPEC-gmail-auth.md` (or a short
  linked decision record).
- [x] Ask for approval before adding a dependency or changing URL schemes,
  bundle settings, or Google Cloud configuration.

Acceptance: the approved path is supported by primary documentation and is
compatible with an iPhone-only client using only `gmail.readonly`.

Verification: links to the supporting official documentation and a recorded
decision; no production source changes in this task.

## 2. Create the authentication foundation and test seam

- [x] Add the `GmailAuthorizedAccount`, `GmailAuthorizationService`, and
  `GmailAuthCoordinator` test seam under `Sources/ExpenseTrackerCore/`.
- [x] Use the existing Swift package unit-test target because it exercises the
  iOS-independent state machine without requiring a browser or Keychain.
- [x] Add fake authorization-service implementations used only by tests.
- [x] Keep token-bearing values out of debug descriptions and UI text.
- [ ] Add or configure an Xcode unit-test target if the existing Swift package
  tests cannot exercise the iOS-facing code.

Acceptance: authentication state can be exercised in tests without a browser,
Keychain, network request, or live account.

Verification: the new unit test target (if added) and `swift test` pass; the
iOS app build still passes.

## 3. Implement secure credential persistence

- [x] Use Google Sign-In's SDK-managed iOS Keychain session rather than
  duplicating raw tokens in an app-managed store.
- [x] Make disconnect idempotently remove the SDK session from this app.
- [~] Add live configured-device verification for session restoration and
  removal after Google Cloud setup is available.

Acceptance: a restored credential is available after recreating the auth
coordinator, and disconnect removes only Gmail credentials.

Verification: unit tests for all persistence paths plus a clean iOS build.

## Checkpoint A

- [ ] Review the foundation and Keychain behavior against
  `SPEC-gmail-auth.md` before introducing browser authentication.

## 4. Implement the OAuth coordinator and state machine

- [x] Add `GmailAuthCoordinator` with explicit idle, connecting, connected,
  cancelled, and recoverable-failure outcomes.
- [x] Validate OAuth state/callback results through the selected client adapter
  before saving credentials.
- [x] Restore a valid stored credential on startup; require reconnection for an
  expired or invalid credential.
- [x] Add tests for success, user cancellation, missing configuration,
  callback/state mismatch, expired credentials, and disconnect.

Acceptance: no failure leaves the UI stuck in a connecting state or overwrites
an existing credential with an invalid result.

Verification: unit tests run entirely with fakes and cover each listed state
transition.

## 5. Wire the existing iPhone experience

- [x] Replace the current informational connection sheet behavior with the
  coordinator while retaining the existing calm, compact UI pattern.
- [x] Display a clear connected state and a Disconnect action with a
  confirmation appropriate for a local credential removal.
- [x] Ensure errors explain the next action without exposing sensitive OAuth
  details.
- [x] Confirm by code inspection that manual transactions, saved categories, and review items are
  untouched by connect/disconnect.
- [~] Run the configured simulator connection and disconnect interaction check
  after the Google Cloud client values are available.

Acceptance: a user can start connection, cancel/retry safely, understand their
status, and disconnect without losing ledger data.

Verification: focused unit tests plus one simulator interaction check for the
connection and disconnect paths; build succeeds.

## Checkpoint B

- [ ] Review the completed local behavior before entering real Google Cloud
  configuration.

## 6. Configure and verify the real Google callback

- [ ] With the user's approval and account access, configure the selected
  Google Cloud OAuth client using the final bundle ID and redirect scheme.
- [ ] Put only non-secret configuration in the approved local build settings;
  keep secrets/tokens out of the repository.
- [ ] Complete one simulator sign-in, consent only to `gmail.readonly`, relaunch
  the app, and confirm the connected state restores.
- [ ] Disconnect and confirm the ledger remains intact; schedule one final
  physical-device check before relying on the feature daily.

Acceptance: the simulator round trip works with the user's account and no Gmail
content is read or altered yet.

Verification: configured simulator callback, relaunch restoration, disconnect
check, unit-test suite, and Xcode build.
