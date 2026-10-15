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
- [x] Confirm that a separate Xcode unit-test target is not needed: Swift
  package tests exercise the auth state machine, while the thin Google SDK
  adapter is covered by the signed simulator integration check.

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

- [x] Review the foundation and Keychain behavior against
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

- [x] Review the completed local behavior before entering real Google Cloud
  configuration.

## 6. Configure and verify the real Google callback

- [x] With the user's approval and account access, configure the selected
  Google Cloud OAuth client using the final bundle ID and redirect scheme.
- [x] Put only non-secret configuration in the approved local build settings;
  keep secrets/tokens out of the repository.
- [~] Complete one simulator sign-in, consent only to `gmail.readonly`, relaunch
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
- [x] The user approves the downstream local-import plan before a real
  `Transaction` label scan.

---

## BCA Local Import to Review

### 10. Parse and stage successful BCA QRIS payments

- [x] Add a core-only importer for successful BCA QRIS payment candidates.
- [x] Keep failed, malformed, non-BCA, and duplicate candidates out of local
  records.
- [x] Apply an existing merchant rule as a category suggestion while keeping
  every BCA import in `needsReview`.
- [x] Let a user-selected or newly created Review category accept that item
  immediately and update its local merchant rule; require Accept for a
  system-suggested category.

## Monthly Spending Analytics

- [x] Specify month-scoped confirmed spending, separate pending-review totals,
  and category breakdowns in `SPEC-spending-analytics.md`.
- [x] Add a core-only analytics calculation with unit tests for month filtering,
  spending kinds, Review separation, and category grouping.
- [x] Add a Dashboard month picker and category breakdown that read the core
  result without altering local transaction records.
- [x] Preserve candidates only in memory between the manual scan and the
  explicit local import confirmation.
- [x] Add a Review import confirmation that states how many BCA payments will
  be saved and that all other emails remain untouched.
- [x] Complete the owner-confirmed first local import from the real
  `Transaction` label.

Verification:

- [x] Core unit tests cover valid BCA QRIS input, failed status, missing
  fields, duplicate IDs/fingerprints, merchant rules, and mixed candidates.
- [x] Full core test suite passes.
- [x] Signed simulator build succeeds.

---

# Livin' by Mandiri Local Import Task List

Module id: `mandiri-local-import`. The live Gmail sign-out and restoration
checks above remain deferred and are not dependencies for parser work.

## 11. Tighten the Mandiri parser with redacted tests

**Description:** Specify the approved Livin' email shape in focused unit tests,
then make the existing parser accept only complete, positive-value transfer
receipts.

**Acceptance criteria:**

- [x] A complete anonymized receipt yields the expected recipient, Jakarta
  timestamp, amount, `mandiri` bank ID, and `transferOut` kind.
- [x] Missing recipient or reference, invalid or zero amount, and a lookalike
  without the Livin' heading return `unsupported`.
- [x] Tests contain only synthetic identifiers and values.

**Verification:**

- [x] Focused tests pass: `swift test -j 1 --filter MandiriTransferEmailParserTests`
- [x] Existing BCA parser and importer tests still pass.

**Dependencies:** Approved `SPEC-mandiri-local-import.md`.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BankEmailParser.swift`
- `Tests/ExpenseTrackerCoreTests/MandiriTransferEmailParserTests.swift`

**Estimated scope:** Small: 2 files.

## 12. Generalize Review import for BCA and Mandiri

**Description:** Replace the BCA-only parser selection inside the Review
importer with a deterministic BCA plus Mandiri parser chain while preserving
duplicate checks, category suggestions, and Review-first status.

**Acceptance criteria:**

- [x] A mixed candidate set imports one valid BCA payment and one valid
  Mandiri transfer, with unsupported candidates counted once.
- [x] Message-ID and fingerprint duplicates are skipped across both banks.
- [x] Merchant rules may suggest a category, but every imported record remains
  `needsReview`.

**Verification:**

- [x] Focused tests pass: `swift test -j 1 --filter BCAReviewImportTests`
- [x] Full tests pass: `swift test -j 1`

**Dependencies:** Task 11.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift`
- `Tests/ExpenseTrackerCoreTests/BCAReviewImportTests.swift`

**Estimated scope:** Small: 2 files.

## Checkpoint E: Core import

- [x] Mandiri parser tests pass.
- [x] Mixed-bank import and duplicate tests pass.
- [x] All existing core tests pass without a real Gmail account.

## 13. Connect the multi-bank preview and save flow

**Description:** Use the generalized importer from `SyncModel` and replace the
BCA-only Dashboard action and confirmation with accurate bank-neutral copy.
The existing SwiftData record shape and explicit confirmation remain intact.

**Acceptance criteria:**

- [x] One import action previews valid BCA and Mandiri candidates from the most
  recent manual Gmail scan.
- [x] Confirming saves both bank types to Review through the existing atomic
  write path.
- [x] Empty and mixed results explain what happened without displaying raw
  email content or sensitive banking fields.

**Verification:**

- [x] Full tests pass: `swift test -j 1`
- [x] Simulator build succeeds with code signing disabled.
- [x] No manual UI run was needed; core tests and the simulator build verified
  the flow without reinstalling, signing out, or starting Gmail consent.

**Dependencies:** Checkpoint E.

**Files likely touched:**

- `Sources/ExpenseTracker/SyncModel.swift`
- `Sources/ExpenseTracker/DashboardView.swift`

**Estimated scope:** Small: 2 files.

## 14. Align README and existing specs

**Description:** Update project documentation so supported banks, transfer
semantics, Review behavior, commands, and deferred auth checks match the code.

**Acceptance criteria:**

- [x] README lists BCA and Mandiri as active Gmail imports and explains that
  Mandiri transfers count as spending only after acceptance.
- [x] Gmail and BCA specs no longer describe the importer as BCA-only.
- [x] Completed Mandiri tasks and verification results are reflected in this
  task list after the checks pass.

**Verification:**

- [x] Documentation search finds no stale claim that Livin' is parse-only.
- [x] `git diff --check` passes.

**Dependencies:** Task 13.

**Files likely touched:**

- `README.md`
- `SPEC-bca-local-import.md`
- `SPEC-gmail-mailbox-sync.md`
- `SPEC-mandiri-local-import.md`

**Estimated scope:** Medium: 4 files.

## Checkpoint F: Mandiri complete

- [x] All core tests pass.
- [x] The simulator build succeeds.
- [x] BCA behavior remains unchanged.
- [x] Mandiri transfers enter Review and count toward spending only after
  acceptance.
- [x] README and specs match the implementation.

---

# Mandiri Transfer Spending Policy Task List

Module id: `mandiri-local-import`. This policy applies accepted Mandiri
transfers to spending analytics while keeping Review items separate.

## 15. Count accepted Mandiri transfers as spending

**Description:** Change the shared analytics classification so a Mandiri
`transferOut` record counts only after it is accepted from Review. Keep the
stored transaction kind unchanged and leave all other non-expense kinds out of
spending totals.

**Acceptance criteria:**

- [x] An accepted `transferOut` is included in the selected month's total and
  its assigned category breakdown.
- [x] A `needsReview` `transferOut` remains excluded until accepted.
- [x] `transferIn`, cash withdrawal, refund, unknown, and all non-ready
  records remain excluded.
- [x] README, relevant specifications, and historical Mandiri task/plan
  records describe the revised policy accurately.

**Verification:**

- [x] Add and observe focused failing analytics tests before changing the
  production predicate.
- [x] Focused analytics tests pass after the change.
- [x] Full core tests, CoreVerification, and the unsigned iOS simulator build
  pass.
- [x] `git diff --check` passes and the documentation search finds no stale
  Mandiri exclusion claim.

**Dependencies:** Approved `SPEC-mandiri-local-import.md` and the approved
Mandiri Transfer Spending Policy plan.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/SpendingAnalytics.swift`
- `Tests/ExpenseTrackerCoreTests/SpendingAnalyticsTests.swift`
- `README.md`
- `SPEC-mandiri-local-import.md`
- `SPEC-spending-analytics.md`
- `tasks/plan.md`
- `tasks/todo.md`

**Estimated scope:** Small: one logic file, one test file, and documentation.

---

# Additional Livin' by Mandiri Receipts Task List

Module id: `mandiri-local-import`. The review-discard capability remains a
separate approved plan and is not a dependency for these receipt parsers.

## 16. Define strict Mandiri payment parsing with tests

**Description:** Add redacted, core-only tests for a Payment Successful
receipt, then implement the pure parser that accepts only its complete
structured shape.

**Acceptance criteria:**

- [x] A complete payment receipt yields the recipient, Jakarta timestamp,
  positive amount, `mandiri` bank ID, and `qrisPayment` kind.
- [x] A missing success heading, recipient, transaction reference, or positive
  amount returns `unsupported`.
- [x] PANs, account fragments, location, and reference values do not become
  part of the transaction draft.

**Verification:**

- [x] Observe the focused test fail before the parser is added.
- [x] Focused tests pass: `swift test -j 1 --filter MandiriPaymentEmailParserTests`
- [x] Existing Mandiri transfer tests still pass.

**Dependencies:** Approved additional Mandiri receipt plan.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BankEmailParser.swift`
- `Tests/ExpenseTrackerCoreTests/MandiriPaymentEmailParserTests.swift`

**Estimated scope:** Small: 2 files.

## 17. Define strict Mandiri e-money top-up parsing with tests

**Description:** Add redacted tests for e-money Top-up Successful, then
implement a pure parser with a safe constant merchant label.

**Acceptance criteria:**

- [x] A complete receipt yields `e-money top-up`, its Jakarta timestamp,
  positive amount, `mandiri` bank ID, and `transferOut` kind.
- [x] A wrong provider, missing success heading or reference, and a zero amount
  return `unsupported`.
- [x] No card fragment or reference value is used as the merchant label.

**Verification:**

- [x] Observe the focused test fail before the parser is added.
- [x] Focused tests pass: `swift test -j 1 --filter MandiriEMoneyTopUpEmailParserTests`
- [x] Existing transfer and payment parser tests still pass.

**Dependencies:** Task 16 only for shared receipt parsing helpers; the
independent behavior remains covered in its own tests.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BankEmailParser.swift`
- `Tests/ExpenseTrackerCoreTests/MandiriEMoneyTopUpEmailParserTests.swift`

**Estimated scope:** Small: 2 files.

## Checkpoint G: Mandiri receipt recognition

- [x] All three Mandiri parser suites pass.
- [x] Malformed and lookalike receipts create no transaction draft.
- [x] Existing BCA tests remain green.

## 18. Register the new parsers in the Review importer

**Description:** Extend the deterministic bank parser chain, then prove a
mixed scan stages valid BCA and all supported Mandiri receipts exactly once.

**Acceptance criteria:**

- [x] Valid payment and e-money top-up candidates enter Review with normal
  merchant-rule suggestions.
- [x] Existing message-ID and fingerprint duplicate protection applies to the
  new formats.
- [x] Unsupported candidates remain untouched and cannot block a valid import.

**Verification:**

- [x] Focused tests pass: `swift test -j 1 --filter BCAReviewImportTests`
- [x] Full core suite passes: `swift test -j 1`

**Dependencies:** Checkpoint G.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift`
- `Tests/ExpenseTrackerCoreTests/BCAReviewImportTests.swift`

**Estimated scope:** Small: 2 files.

## 19. Align import feedback and documentation

**Description:** Keep owner-facing import feedback at bank level and update
the README and specs to list the newly supported Mandiri receipts accurately.

**Acceptance criteria:**

- [x] User-facing import messages refer to BCA or Mandiri transactions, not
  receipt mechanisms.
- [x] README and active import specifications list Mandiri transfer, payment,
  and e-money top-up support while retaining the Review-first rule.
- [x] Documentation does not claim that raw email or sensitive banking fields
  are persisted.

**Verification:**

- [x] `git diff --check` passes.
- [x] A repository search finds no stale statement that Mandiri supports only
  transfers.

**Dependencies:** Task 18.

**Files likely touched:**

- `Sources/ExpenseTracker/DashboardView.swift`
- `README.md`
- `SPEC-mandiri-local-import.md`
- `SPEC-gmail-mailbox-sync.md`
- `SPEC-bca-local-import.md`

**Estimated scope:** Medium: 5 files.

## Checkpoint H: Ready for Gmail confirmation

- [x] `swift test -j 1`, `swift run CoreVerification`, and the unsigned iOS
  simulator build pass.
- [x] New payment and top-up items begin in Review and count as spending only
  after acceptance.
- [ ] Optional manual Gmail sync confirms labeled Mandiri messages are visible
  in Review without reconnecting or reinstalling the app.

---

# Discarding Review Transactions Task List

Module id: `review-discard`.

## 20. Suppress discarded Gmail message IDs in the core importer

**Description:** Add a failing importer test, then accept a set of locally
discarded Gmail message IDs at the import boundary. The importer must count an
exact match as ignored before parser selection and leave unrelated candidates
unchanged.

**Acceptance criteria:**

- [x] A valid candidate with a discarded message ID creates no import and
  increments the ignored count.
- [x] A different valid candidate still enters Review normally.
- [x] Existing duplicate, unsupported, and merchant-rule behavior remains
  unchanged.

**Verification:**

- [x] Observe the focused test fail before the importer change.
- [x] Focused tests pass: `swift test -j 1 --filter BCAReviewImportTests`

**Dependencies:** Approved `SPEC-review-discard.md`.

**Files likely touched:**

- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift`
- `Tests/ExpenseTrackerCoreTests/BCAReviewImportTests.swift`

**Estimated scope:** Small: 2 files.

## 21. Persist discard markers and pass them into previews

**Description:** Add the local SwiftData model containing only the Gmail
message ID, include it in the model container, and pass its IDs to the import
preview.

**Acceptance criteria:**

- [x] A discard marker stores only a unique `sourceMessageID`.
- [x] Import previews use existing transaction IDs, fingerprints, and discarded
  message IDs together.
- [x] No raw email, merchant, amount, or category is saved in the marker.

**Verification:**

- [x] The iOS simulator build succeeds with code signing disabled.
- [x] Code inspection confirms the marker contains no extra fields.

**Dependencies:** Task 20.

**Files likely touched:**

- `Sources/ExpenseTracker/TransactionRecord.swift`
- `Sources/ExpenseTracker/ExpenseTrackerApp.swift`
- `Sources/ExpenseTracker/SyncModel.swift`
- `Sources/ExpenseTracker/DashboardView.swift`

**Estimated scope:** Medium: 4 files.

## 22. Add Review discard confirmation

**Description:** Add a per-item Discard action in Review. Confirmation creates
the marker and deletes the pending transaction in one local save, so it leaves
Review, Activity, and analytics.

**Acceptance criteria:**

- [x] Every Review item exposes Discard.
- [x] Discard requires a confirmation that explains the local, non-reversible
  effect and future import suppression.
- [x] Confirming creates the marker and removes only the selected transaction.

**Verification:**

- [x] Unsigned simulator build succeeds.
- [ ] Manual simulator check: discard one Review item, confirm it disappears,
  and verify accepted or other pending items remain.

**Dependencies:** Task 21.

**Files likely touched:**

- `Sources/ExpenseTracker/ReviewView.swift`
- `Sources/ExpenseTracker/TransactionRecord.swift`

**Estimated scope:** Small: 2 files.

## Checkpoint I: Discard complete

- [x] Full core suite and `CoreVerification` pass.
- [x] Unsigned simulator build succeeds.
- [x] A discarded candidate is ignored in a later import preview.
- [x] README, specs, plan, and task record accurately describe the completed
  local discard behavior.
