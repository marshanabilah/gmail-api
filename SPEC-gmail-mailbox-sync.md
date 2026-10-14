# Spec: Gmail Mailbox Sync for the Transaction Label

Module id: `gmail-mailbox-sync`

## Objective

Let the owner of this personal iPhone ledger manually start a read-only scan
of one connected Gmail account. The scan reads only the messages the owner has
already placed under the Gmail label `Transaction`, limited to the previous 90
calendar days.

The result is a deterministic, in-memory collection of non-Flip transaction
email candidates for `bca-local-import`. That later module is responsible for
bank parsing, duplicate checks, categorisation, and saving every initial
candidate to Review. This module does not write to SwiftData or automatically
add anything to the ledger.

The label currently contains transaction notifications from BCA, Jago, and
Livin' by Mandiri. It may also contain Flip transfer receipts. Flip must be
excluded before it reaches a bank parser. The app must never modify Gmail:
it neither creates nor maintains the label, and it does not alter messages.

### Acceptance criteria

- A connected account can manually start a scan of `Transaction`.
- The scan considers messages dated in the last 90 days only.
- The Gmail API is used with the existing `gmail.readonly` permission only.
- Each message is fetched at most once per scan, retaining only the fields
  needed by the next local-import step.
- A confirmed Flip receipt is excluded and cannot create a Review item.
- The resulting candidates retain Gmail message IDs so the importer can
  deduplicate them locally.
- Missing label, expired connection, malformed response, and network failure
  show an actionable error without changing local transaction data.

## Tech Stack

- Swift 6 and SwiftUI, targeting iOS 17 or later.
- The existing Google Sign-In for iOS integration and its Keychain-backed
  sign-in state from `gmail-auth`.
- Gmail REST API, using the authorised user's current access token and
  `URLSession`; no backend, cloud database, Apps Script, or additional OAuth
  scope.
- The existing `BankEmail` value type as the handoff to `bca-local-import`.

The implementation may use these Gmail endpoints after confirming their
current request and response formats against the official Gmail API docs:

- `users.labels.list` to resolve the owner-created `Transaction` label.
- `users.messages.list` to obtain message IDs restricted to that label and
  time window.
- `users.messages.get` to fetch each candidate's headers and decoded text
  body.

## Commands

Run the core unit tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test
```

Build the iPhone app for the simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

Once unit tests pass and the user has configured their own OAuth client, the
only manual verification for this module is one deliberate scan of the
user-maintained `Transaction` label. It is not a background or automatic sync.

## Project Structure

```text
Sources/ExpenseTrackerCore/GmailMailbox/    -> Gmail message models, client protocol, filtering, and fixtures-free logic
Sources/ExpenseTracker/GmailMailbox/        -> URLSession Gmail adapter and SyncModel/UI integration
Tests/ExpenseTrackerCoreTests/GmailMailbox/ -> Fake-client unit tests and redacted email fixtures
SPEC-gmail-mailbox-sync.md                  -> This module's approved requirements
SPEC-gmail-auth.md                          -> Existing connection and read-only credential boundary
```

`gmail-mailbox-sync` provides `BankEmail` candidates in memory. The dependent
`bca-local-import` module owns parser selection, review creation, duplicate
protection, and SwiftData writes.

## Code Style

Keep network access behind a small protocol. Make Gmail-specific transport
models private to the adapter and return simple domain values to the importer.
No type may expose an access token, complete network response, or email body
through logs or user-facing errors.

```swift
protocol GmailMailboxClient: Sendable {
    func transactionLabelID() async throws(GmailMailboxFailure) -> String
    func messageIDs(in labelID: String, after date: Date) async throws(GmailMailboxFailure) -> [String]
    func message(id: String) async throws(GmailMailboxFailure) -> BankEmail
}

func isFlipReceipt(_ email: BankEmail) -> Bool {
    let body = email.body.lowercased()
    return body.contains("your transaction has been successfully processed")
        && body.contains("destination bank")
        && body.contains("destination account number")
}
```

- Use `Gmail` in user-facing text and `gmail` in code identifiers.
- Name time boundaries explicitly, such as `startDate` and `messageReceivedAt`.
- Decode Base64URL MIME content locally and handle plain-text and HTML email
  parts without rendering remote content.
- Keep redacted samples in tests only. No real sender addresses, account
  numbers, recipient names, message IDs, transaction IDs, or email bodies
  belong in source control.
- Treat the known Flip structure as an exclusion rule, not a general-purpose
  bank detector. Other unsupported messages are safely passed to the importer,
  which leaves them unsupported rather than guessing.

## Testing Strategy

- Write core unit tests first using a fake `GmailMailboxClient`; no test needs
  a live Google account, network request, Keychain, or simulator.
- Use redacted fixtures for BCA, Jago, Livin', and the confirmed Flip receipt
  structure. Preserve only the field labels and safe placeholder values.
- Test resolving the exact label name `Transaction`, a missing label, and
  duplicate label names as a recoverable configuration error.
- Test the 90-day cutoff, newest-first ordering, pagination, duplicate Gmail
  message IDs, and a message fetched only once during a scan.
- Test Flip exclusion using the confirmed phrases `transaction has been
  successfully processed`, `Destination Bank`, and `Destination Account
  Number`, plus a control email that shares only one phrase and must not be
  excluded.
- Test expired authorisation, HTTP failure, malformed MIME, and rate-limit
  responses as non-destructive errors with no partial local writes.
- After core tests and the simulator build pass, perform one opt-in scan of
  the real `Transaction` label. Verify the resulting local candidates through
  the Review screen when `bca-local-import` is connected. Do not use routine
  UI testing for parser or filtering changes.

## Boundaries

### Always

- Use the current one-account `gmail.readonly` authorisation only.
- Resolve and read the exact user-maintained label `Transaction`.
- Limit the first scan to the previous 90 calendar days, calculated on-device
  at the time the user taps Sync.
- Read message content only in memory and pass the minimum required fields to
  the local importer.
- Exclude a confirmed Flip receipt before parser selection.
- Preserve Gmail message IDs for the downstream local duplicate check.
- Leave every initial imported candidate for Review through the downstream
  importer, even when a parser has high confidence.
- Return an understandable, retryable state when Gmail is unavailable.

### Ask First

- Scanning more than 90 days, another Gmail account, another label, or a
  background/automatic sync schedule.
- Requesting any Gmail scope beyond `gmail.readonly`.
- Persisting raw message content, headers, or new Gmail metadata in SwiftData.
- Adding a Gmail SDK, server, cloud store, analytics service, or third-party
  email-processing service.
- Changing the initial Review-only policy or allowing high-confidence imports
  directly into the ledger.

### Never

- Create, rename, apply, remove, archive, mark read, delete, or otherwise
  modify Gmail labels or messages.
- Commit OAuth tokens, a client secret, live message content, unredacted
  email headers, or personal banking data.
- Log access tokens, decoded message bodies, account numbers, PANs, transfer
  references, or recipient details.
- Import a recognized Flip receipt or treat it as a BCA, Jago, or Mandiri
  transaction.
- Run Gmail scans without a deliberate user action in this initial version.

## Success Criteria

- [ ] The app finds exactly one `Transaction` label or reports a clear error.
- [ ] A manually started scan lists only messages newer than the computed
  90-day cutoff and follows any Gmail pagination.
- [ ] Each listed message is fetched once, decoded locally, and represented as
  a `BankEmail` candidate with its Gmail message ID.
- [ ] The confirmed Flip receipt fixture is excluded before the importer sees
  it; the control fixture is not falsely excluded.
- [ ] Gmail remains unchanged after success, cancellation, or failure.
- [ ] No raw email content or credentials are persisted or logged.
- [ ] Core unit tests cover successful pagination, label errors, auth/network
  errors, cutoff handling, MIME decoding, duplicate IDs, and Flip exclusion.
- [ ] The app and core tests build cleanly before one user-authorised real
  label scan.

## Open Questions

- Is there a stable Flip sender address or subject line we can use as an
  additional guard? The current rule deliberately uses the confirmed email
  structure only, so it remains safe without guessing a sender.
- For the first real scan, should every non-Flip message under `Transaction`
  be handed to the importer, including any future bank format it does not yet
  recognise? This spec assumes yes: unsupported formats stay unsupported and
  cannot become transactions.
- The existing capability map names the downstream module `bca-local-import`,
  while the label now contains BCA, Jago, and Livin'. We should decide during
  that module's spec whether to keep the stable module ID while broadening its
  parser coverage, or split parser work into a later capability.
