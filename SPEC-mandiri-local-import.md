# Spec: Livin' by Mandiri Local Import and Review

Module id: `mandiri-local-import`

## Objective

Extend the existing manual Gmail import so supported Livin' by Mandiri
receipts can become normalized local transactions on the iPhone. The app reads
only candidates already returned by `gmail-mailbox-sync`, parses the known
English receipt formats. Transfers and e-money top-ups always go to Review;
an eligible QR payment with an exact trusted bank-and-merchant rule can go
directly to the ledger.

Mandiri transfers remain `transferOut` records so the source activity stays
truthful. Once the owner accepts one in Review, it contributes to confirmed
spending totals and the category selected by the owner.

Policy assumption for this personal ledger: every accepted Mandiri outgoing
transfer and accepted e-money top-up is an expense. The receipts do not
reliably distinguish an expense from a move between the owner's accounts, so
the first version does not try to infer that distinction. Review remains the
owner's safeguard before an amount affects analytics.

The app stores only normalized transaction fields. It does not store the raw
email, recipient account number, source account fragment, reference number, or
email headers.

## Supported Receipt Shapes

A candidate is importable only when it matches one complete shape below.

### Transfer Successful

- The body contains the Livin' heading `Transfer Successful`.
- A recipient name is present under `Recipient`.
- `Date` parses as `d MMM yyyy` using an English POSIX locale.
- `Time` parses as `HH:mm:ss WIB` and combines with the date in the
  `Asia/Jakarta` time zone.
- `Transfer Amount` parses as a positive Indonesian rupiah amount.
- `Reference No.` is present so malformed receipts are not accepted, although
  the value is not persisted.

The normalized draft uses the recipient as its merchant label and
`transferOut` as its kind.

### Payment Successful

- The body contains the Livin' heading `Payment Successful`.
- A recipient name is present under `Recipient`.
- `Date` and `Time` parse with the same Jakarta rules as a transfer.
- `Transaction Amount` parses as a positive Indonesian rupiah amount.
- `Transaction Ref. No.` is present.

The normalized draft uses the recipient as its merchant label and
`qrisPayment` as its kind. QRIS reference, merchant PAN, customer PAN,
terminal ID, acquirer, account fragments, and location are validation context
only when present. None are stored.

### e-money Top-up Successful

- The body contains `e-money Top-up Successful`.
- `Service Provider` identifies `e-money`.
- `Date` and `Time` parse with the same Jakarta rules as a transfer.
- `Top-up Amount` parses as a positive Indonesian rupiah amount.
- `Reference Number` is present.

The normalized draft uses the stable merchant label `e-money top-up` rather
than an account fragment, and `transferOut` as its kind. Once accepted, it
counts as spending under the approved personal-ledger policy.

### Shared Requirements

- Every supported draft contains:

- Gmail message ID for local idempotency.
- Bank ID `mandiri`.
- Parsed Jakarta transaction time.
- An approved merchant label.
- The parsed amount.
- The kind stated by its receipt shape.
- Parser confidence appropriate for a fully structured receipt.

## User Flow

1. The owner manually syncs the Gmail label `Transaction` for the last 90
   days.
2. `gmail-mailbox-sync` removes confirmed Flip receipts and returns the other
   candidates in memory.
3. The local importer tries the supported BCA and Mandiri parsers.
4. Valid, non-duplicate BCA and Mandiri transactions are shown in one import
   confirmation.
5. After confirmation, transfers and top-ups start in Review. An exact trusted
   rule can make an eligible QR payment `ready`; other merchant rules only
   suggest a category and do not accept the record.
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
guard isSupportedLivinReceipt(email.body) else { return .unsupported }
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
- Cover valid Transfer Successful, Payment Successful, and e-money Top-up
  Successful receipts, plus a missing required field, invalid or zero amount,
  and a lookalike message without the required heading.
- Prove a payment receipt stores only its recipient label and never a PAN,
  account fragment, reference number, or location.
- Prove an e-money top-up uses `e-money top-up` rather than an account
  fragment, and counts as spending only after the owner accepts it.
- Cover message-ID and fingerprint duplicate handling.
- Cover a mixed scan containing valid BCA, valid Mandiri, unsupported, and
  Flip-excluded candidates.
- Prove that imported Mandiri records start in Review and remain
  `transferOut`; they count as spending only after the owner accepts them.
- Run the full core suite and simulator build. Do not require a real Gmail scan
  for parser verification.

## Boundaries

### Always

- Parse locally on the iPhone.
- Use the existing one-account, read-only, manually triggered Gmail flow.
- Route recognized Mandiri transactions to Review.
- Count accepted Mandiri `transferOut` records, including e-money top-ups, in
  confirmed spending and their selected category total.
- Preserve the current 90-day window, exact `Transaction` label, and Flip
  exclusion.
- Persist only fields already represented by `TransactionRecord`.

### Ask First

- Adding transaction-kind editing or automatic transfer detection based on a
  recipient name.
- Excluding selected Mandiri recipients or account moves from spending after
  this initial policy ships.
- Supporting a different Mandiri email template or language beyond the three
  receipt shapes above.
- Storing reference numbers, account fragments, recipient bank details, raw
  email text, or headers.
- Changing Gmail scopes, labels, scan cadence, or account count.

### Never

- Import a Flip receipt as a Mandiri receipt.
- Infer a missing merchant label, timestamp, amount, reference, or transaction
  type.
- Change how other transaction kinds contribute to spending analytics.
- Log or persist raw email contents or sensitive banking fields.
- Modify Gmail messages or labels.

## Success Criteria

- Valid anonymized Livin' transfer, payment, and e-money top-up receipts each
  produce one Mandiri `needsReview` record with the correct merchant label,
  Jakarta timestamp, amount, and kind.
- Missing or invalid required fields create no record.
- Repeat message IDs and matching fingerprints create no duplicate.
- A mixed candidate set imports valid BCA and Mandiri records without one
  parser blocking the other.
- Flip receipts and unsupported bank formats remain untouched.
- A merchant rule can suggest a category but cannot bypass Review.
- Categorizing and accepting a Mandiri transfer or e-money top-up adds its
  amount to the selected month's spending total and chosen category.
- Core tests and the simulator build pass.
- README and existing Gmail/BCA documentation describe the multi-bank import
  behavior accurately before implementation is considered complete.

## Open Questions

- None for the three supported receipt shapes. A future account-move action
  would be a separate capability because the current emails do not identify it
  reliably.

## Implementation Status

Transfer, payment, and e-money top-up support, the shared BCA plus Mandiri
Review import, duplicate protection, merchant-rule suggestions, bank-neutral
import confirmation, and accepted transfer spending policy are implemented.
Live Gmail sign-out and restoration checks remain deferred and are not required
to verify these parsers.
