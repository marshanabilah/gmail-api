# Spec: OCTO CIMB QR Purchase Local Import and Review

Module id: `octo-cimb-local-import`

## Objective

Extend the existing read-only Gmail import so a complete OCTO App **Purchase
with QR** receipt becomes one local OCTO CIMB transaction in Review. The
owner can confirm its category before it contributes to spending; Gmail stays
unchanged and receipt metadata stays out of the local ledger.

## Supported Receipt Shape

A candidate is importable only when it contains all of the following:

- The OCTO App transaction-summary heading.
- `Date/Time` in `ddMMMyy HH:mm` format, parsed in `Asia/Jakarta`.
- A nonempty `Transaction ID` as a receipt-completeness check only. Its value
  is not stored.
- `Purchase Type` exactly identifying `Purchase with QR`.
- A nonempty `Merchant Name`.
- A positive `Total Payment` Indonesian-rupiah amount.

The normalized draft contains the Gmail message ID, bank ID `octoCimb`, parsed
Jakarta timestamp, merchant name, total payment, `qrisPayment` kind, and high
parser confidence. It does not store the transaction ID, fee, account
fragment, Point Xtra amount, raw email, or headers.

## User Flow

1. The owner taps Sync Gmail; the app scans the existing `Transaction` label
   for the last 90 days.
2. The importer tries BCA, Mandiri, then OCTO CIMB receipt parsers.
3. A complete, non-duplicate QR-purchase receipt appears in the import
   confirmation and, after the owner imports it, enters Review unless an exact
   trusted bank-and-merchant rule makes it `ready`.
4. Other merchant rules may suggest a category but never bypass Review.
5. The owner accepts a suggestion or chooses a category. Only then does it
   contribute to confirmed spending, category analytics, and the OCTO CIMB
   source total.

## Tech Stack and Project Structure

- `Sources/ExpenseTrackerCore/BankEmailParser.swift` holds the pure parser.
- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift` registers the parser
  in the existing deterministic parser chain.
- `Sources/ExpenseTrackerCore/SpendingAnalytics.swift` maps `octoCimb` to the
  readable source label `OCTO CIMB`.
- `Tests/ExpenseTrackerCoreTests/` contains only anonymized parser and
  mixed-import tests.
- `Sources/ExpenseTracker/` needs no Gmail, SwiftData, or new UI workflow.

## Commands

Focused parser and importer tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1 --filter OCTOCIMB
```

Full tests and core verification:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift run CoreVerification
```

Unsigned simulator build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

## Code Style

Keep parser recognition strict and pure. A missing, malformed, or non-positive
required field returns `unsupported`; a fully matched receipt returns one
normalized draft.

```swift
guard let occurredAt, let merchant, let amount, amount > 0 else {
    return .unsupported
}

return .transaction(TransactionDraft(
    sourceMessageID: email.messageID,
    bankID: "octoCimb",
    occurredAt: occurredAt,
    merchant: merchant,
    amount: amount,
    kind: .qrisPayment,
    confidence: 0.99
))
```

## Testing Strategy

- Write failing tests before parser registration or parsing changes.
- Use synthetic IDs, merchants, timestamps, and amounts only.
- Cover one complete QR-purchase receipt, malformed date, missing transaction
  ID, non-QR purchase type, blank merchant, and zero payment.
- Prove the parser does not use the account fragment, fee, Point Xtra, or
  transaction ID as the merchant label or stored draft data.
- Prove a mixed BCA, Mandiri, OCTO CIMB, and unsupported scan imports every
  valid candidate once; an exact trusted QR/card merchant may become `ready`,
  while every other item remains in Review.
- Prove accepted OCTO CIMB QR purchases count in the OCTO CIMB source total;
  Review items do not.
- Run the full suite, CoreVerification, and an unsigned simulator build. A
  real Gmail scan is optional only after automated verification succeeds.

## Boundaries

### Always

- Parse locally and use the existing one-account, read-only, manual Gmail
  scan.
- Keep the exact `Transaction` label, 90-day window, and Flip exclusion.
- Send every recognized OCTO CIMB QR purchase to Review first.
- Persist only fields already represented by `TransactionRecord`.

### Ask First

- Supporting a different OCTO CIMB purchase, transfer, top-up, language, or
  receipt format.
- Treating an own-account transfer as spending automatically.
- Persisting transaction IDs, account fragments, fees, reward data, raw email,
  or headers.

### Never

- Modify Gmail messages or labels.
- Guess a missing merchant, timestamp, amount, or purchase type.
- Import the previous own-account-transfer receipt as a QR purchase.
- Let an OCTO CIMB item bypass Review except through the shared exact trusted
  bank-and-merchant policy, or alter existing records on later syncs.

## Success Criteria

- A complete redacted OCTO App QR-purchase receipt produces one `octoCimb`
  `qrisPayment` draft with its merchant, Jakarta timestamp, and total payment.
- Incomplete or lookalike receipts create no draft.
- A valid OCTO CIMB candidate enters Review once unless a matching exact
  trusted rule makes it ready; it still participates in duplicate protection
  and merchant-category suggestions.
- After acceptance, the payment appears in confirmed spending and a readable
  `OCTO CIMB` source row; it is excluded while still in Review.
- Tests, CoreVerification, and the unsigned simulator build pass.

## Open Questions

- None for the supported QR-purchase receipt. Other OCTO CIMB formats require
  a separate approved extension.

## Implementation Status

The strict QR-purchase parser, Review importer registration, source analytics
label, and documentation alignment are implemented. Own-account transfers stay
out of the Review importer. Core tests, CoreVerification, and the unsigned
simulator build pass; a live labeled-email import remains optional.
