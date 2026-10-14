# Spec: Livin' by Mandiri Local Import and Review

Module id: `mandiri-local-import`

## Objective

Extend the existing manual Gmail import so a successful Livin' by Mandiri
transfer receipt can become a normalized local transaction on the iPhone. The
app reads only candidates already returned by `gmail-mailbox-sync`, parses the
known English email format, and sends every new Mandiri transfer to Review.

Mandiri transfers remain `transferOut` records. They can appear in activity and
can be categorized, but they do not contribute to confirmed spending totals.
This prevents account moves and person-to-person transfers from inflating the
expense dashboard. Changing a transfer into an expense is outside this module.

The app stores only normalized transaction fields. It does not store the raw
email, recipient account number, source account fragment, reference number, or
email headers.

## Supported Email Shape

A candidate is importable only when all of these conditions hold:

- The body contains the Livin' heading `Transfer Successful`.
- A recipient name is present under `Recipient`.
- `Date` parses as `d MMM yyyy` using an English POSIX locale.
- `Time` parses as `HH:mm:ss WIB` and combines with the date in the
  `Asia/Jakarta` time zone.
- `Transfer Amount` parses as a positive Indonesian rupiah amount.
- `Reference No.` is present so malformed receipts are not accepted, although
  the value is not persisted.

The normalized draft contains:

- Gmail message ID for local idempotency.
- Bank ID `mandiri`.
- Parsed Jakarta transaction time.
- Recipient name as the transaction merchant label.
- Transfer amount.
- Transaction kind `transferOut`.
- Parser confidence appropriate for a fully structured receipt.

## User Flow

1. The owner manually syncs the Gmail label `Transaction` for the last 90
   days.
2. `gmail-mailbox-sync` removes confirmed Flip receipts and returns the other
   candidates in memory.
3. The local importer tries the supported BCA and Mandiri parsers.
4. Valid, non-duplicate BCA payments and Mandiri transfers are shown in one
   import confirmation.
5. After confirmation, each new record starts in Review. A saved merchant rule
   may suggest a category but does not accept the record.
6. Choosing or creating a category accepts that record immediately. Accepting
   a suggested category remains an explicit action.
7. A later Gmail sync cannot overwrite a saved transaction or create a
   duplicate.

## Tech Stack and Project Structure

- Swift 6 and Swift Package Manager for parser and importer logic.
- SwiftUI and SwiftData for the app-facing confirmation and local persistence.
- `Sources/ExpenseTrackerCore/BankEmailParser.swift` for bank parsing.
- `Sources/ExpenseTrackerCore/` for the bank-agnostic Review importer.
- `Tests/ExpenseTrackerCoreTests/` for redacted parser and import fixtures.
- `Sources/ExpenseTracker/SyncModel.swift` for the app-to-core boundary.
- `Sources/ExpenseTracker/DashboardView.swift` for the explicit import action.

## Commands

Run the core unit tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1
```

Build the iPhone app for the simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

## Code Style

Keep recognition strict and return `unsupported` rather than guessing a
missing field. Keep the parser pure and independent of Gmail, SwiftUI, and
SwiftData.

```swift
guard isLivinTransfer(email.body) else { return .unsupported }
guard let occurredAt, let recipient, let amount else { return .unsupported }

return .transaction(TransactionDraft(
    sourceMessageID: email.messageID,
    bankID: "mandiri",
    occurredAt: occurredAt,
    merchant: recipient,
    amount: amount,
    kind: .transferOut,
    confidence: 0.99
))
```

## Duplicate and Import Rules

- Skip a candidate when its Gmail message ID already exists locally.
- Skip a candidate when its normalized transaction fingerprint already exists
  locally.
- Duplicate checks happen before SwiftData insertion.
- Unsupported or malformed Mandiri candidates create no local record and do
  not block valid candidates from the same scan.
- Existing categories, statuses, and manual corrections are never changed by
  a later import.
- The confirmation reports recognized imports, duplicates, and candidates
  left untouched without displaying email contents or bank identifiers.

## Testing Strategy

- Add failing tests before changing the importer or parser.
- Use only anonymized Livin' fixtures with synthetic names, account fragments,
  reference numbers, message IDs, dates, and amounts.
- Cover one valid receipt, a missing recipient, missing reference number,
  invalid or zero amount, and a lookalike message without the Livin' heading.
- Cover message-ID and fingerprint duplicate handling.
- Cover a mixed scan containing valid BCA, valid Mandiri, unsupported, and
  Flip-excluded candidates.
- Prove that imported Mandiri records start in Review and remain
  `transferOut`, so spending analytics exclude them.
- Run the full core suite and simulator build. Do not require a real Gmail scan
  for parser verification.

## Boundaries

### Always

- Parse locally on the iPhone.
- Use the existing one-account, read-only, manually triggered Gmail flow.
- Route recognized Mandiri transfers to Review.
- Keep Mandiri transfers out of confirmed spending totals.
- Preserve the current 90-day window, exact `Transaction` label, and Flip
  exclusion.
- Persist only fields already represented by `TransactionRecord`.

### Ask First

- Treating a Mandiri transfer as an expense.
- Adding transaction-kind editing or automatic transfer detection based on a
  recipient name.
- Supporting a different Mandiri email template or language.
- Storing reference numbers, account fragments, recipient bank details, raw
  email text, or headers.
- Changing Gmail scopes, labels, scan cadence, or account count.

### Never

- Import a Flip receipt as a Mandiri receipt.
- Infer a missing recipient, timestamp, amount, reference, or transaction
  type.
- Include `transferOut` records in confirmed spending analytics.
- Log or persist raw email contents or sensitive banking fields.
- Modify Gmail messages or labels.

## Success Criteria

- A valid anonymized Livin' transfer receipt produces one Mandiri
  `needsReview` record with the correct recipient, Jakarta timestamp, amount,
  and `transferOut` kind.
- Missing or invalid required fields create no record.
- Repeat message IDs and matching fingerprints create no duplicate.
- A mixed candidate set imports valid BCA and Mandiri records without one
  parser blocking the other.
- Flip receipts and unsupported bank formats remain untouched.
- A merchant rule can suggest a category but cannot bypass Review.
- Categorizing or accepting a Mandiri transfer does not add its amount to the
  spending dashboard.
- Core tests and the simulator build pass.
- README and existing Gmail/BCA documentation describe the multi-bank import
  behavior accurately before implementation is considered complete.

## Open Questions

- None for this slice. Treating selected bank transfers as expenses can be
  specified later as a separate transaction-kind editing feature.
