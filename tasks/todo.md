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

---

# Gmail Mailbox Sync Task List

Module id: `gmail-mailbox-sync`. These tasks extend the active authentication
work without replacing its unfinished real-account verification.

## 7. Define and test the mailbox scan contract

**Description:** Confirm the Gmail REST request contract against official
documentation, then add a core-only mailbox client protocol and scan
orchestrator. It resolves `Transaction`, applies the 90-day cutoff, follows
pagination, eliminates repeated Gmail IDs, and excludes the confirmed Flip
receipt structure before handing candidates to the importer.

**Acceptance criteria:**

- [x] The contract uses only `gmail.readonly` and does not expose token values
  to the core module.
- [x] Fake-client tests cover label resolution, cutoff, pagination, repeated
  message IDs, a missing label, and retryable authorization/network failures.
- [x] Redacted BCA, Jago, Livin', Flip, and Flip-control fixtures prove that
  only the confirmed Flip structure is excluded.

**Verification:**

- [x] Tests pass: `TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test`
- [x] Manual check: inspect fixtures to confirm no real account, recipient,
  transaction, or message identifiers appear.

**Dependencies:** Approved `SPEC-gmail-mailbox-sync.md`; no live Google
configuration required.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/GmailMailbox/GmailMailboxClient.swift`
- `Sources/ExpenseTrackerCore/GmailMailbox/GmailMailboxScanner.swift`
- `Tests/ExpenseTrackerCoreTests/GmailMailbox/GmailMailboxScannerTests.swift`
- `Tests/ExpenseTrackerCoreTests/GmailMailbox/Fixtures.swift`

**Estimated scope:** Medium: 4 files.

## 8. Add the iOS Gmail REST adapter and MIME decoder

**Description:** Implement the production adapter that acquires an authorised
access token from the established Google Sign-In session, lists the resolved
label's messages, fetches each message once, and converts MIME content into a
`BankEmail`. Keep credentials and raw transport types within the app target.

**Acceptance criteria:**

- [x] The adapter confirms current official Gmail API and Google Sign-In token
  refresh guidance before implementation.
- [x] It decodes Base64URL plain-text and HTML-only multipart content without
  rendering remote content.
- [x] HTTP, malformed response, expired authorization, and rate-limit failures
  become typed recoverable mailbox failures with no local writes or sensitive
  logs.

**Verification:**

- [x] Tests pass: `TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test`
- [x] Build succeeds: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build`

**Dependencies:** Task 7 and the existing `gmail-auth` adapter. No real Gmail
scan occurs in this task.

**Files likely touched:**

- `Sources/ExpenseTracker/GmailMailbox/GoogleGmailMailboxClient.swift`
- `Sources/ExpenseTracker/GmailMailbox/GmailMessageDecoder.swift`
- `Sources/ExpenseTracker/GoogleGmailAuthorizationService.swift`
- `Tests/ExpenseTrackerCoreTests/GmailMailbox/GmailMessageDecoderTests.swift`

**Estimated scope:** Medium: 4 files.

## Checkpoint C: Mailbox foundation

- [x] Tasks 7 and 8 satisfy every core success criterion in
  `SPEC-gmail-mailbox-sync.md` that does not require a live account.
- [x] Core tests and the simulator build pass.
- [x] Review the token boundary and the redacted Flip fixture before UI wiring.

## 9. Wire a deliberate manual scan to an in-memory candidate result

**Description:** Give a connected user one explicit Sync action. The app shows
whether it is scanning, failed, or found candidates, but it does not write
records to SwiftData. The result is the handoff point for the later approved
`bca-local-import` work.

**Acceptance criteria:**

- [x] A Sync action is available only for a connected account and can run one
  scan at a time.
- [x] Cancelled, unavailable, expired, and mailbox failures return to a clear
  retryable state without erasing manual records or categories.
- [x] A successful fake scan reports only a candidate count, never email body
  text or sensitive details, and produces no local transaction records.

**Verification:**

- [x] Tests pass: `TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test`
- [x] Build succeeds: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build`
- [x] Manual check: use a fake client or preview state. Do not start a real
  Gmail scan until Task 6 and the downstream import module are approved.

**Dependencies:** Checkpoint C. A real-account verification additionally
depends on Task 6 and the approved `bca-local-import` plan.

**Files likely touched:**

- `Sources/ExpenseTracker/SyncModel.swift`
- `Sources/ExpenseTracker/DashboardView.swift`
- `Sources/ExpenseTracker/GmailMailbox/GmailMailboxSyncService.swift`
- `Tests/ExpenseTrackerCoreTests/GmailMailbox/GmailMailboxSyncTests.swift`

**Estimated scope:** Medium: 4 files.

## Checkpoint D: Mailbox handoff

- [x] Core tests and the simulator build pass.
- [x] The app can prove the manual-sync state using fakes without Gmail access.
- [x] No raw email content, Gmail metadata, or candidate is persisted by this
  module.
- [ ] The user approves the downstream local-import plan before a real
  `Transaction` label scan.
