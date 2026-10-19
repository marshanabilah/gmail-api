# Spec: Jago Local Import and Review

Module id: `jago-local-import`

## Objective

Extend the existing read-only Gmail import so the four supplied Jago receipt
formats become local Jago transactions in Review. Each format keeps only the
facts it actually supplies; in particular, a debit-card alert must never
invent a merchant it does not contain.

## Supported Receipt Shapes

### Structured payment

- The Jago payment introduction, `Thank you for trusting Jago! You have made
  a payment`.
- `Transaction Summary`.
- A nonempty first value under `To`, used as the merchant label.
- A positive rupiah `Amount`.
- `Transaction Date` in `d MMMM yyyy, HH:mm WIB` format, parsed in
  `Asia/Jakarta`.
- `Transaction Status` equal to `Successful`.

It becomes a `cardPurchase` draft with high parser confidence.

### Transfer

- The Jago transfer introduction, `Thank you for trusting Jago! You have
  transferred some money`.
- `Transaction Summary`.
- A nonempty first value under `To`, used as the recipient label.
- A positive rupiah `Amount`.
- `Transaction Date` in `d MMMM yyyy HH:mm WIB` format, parsed in
  `Asia/Jakarta`.

It becomes a `transfer` draft with high parser confidence. Transfers are
eligible spending, following the existing Mandiri transfer policy, but still
wait in Review for the owner to accept, categorize, or discard.

### E-wallet top-up

- The Jago top-up introduction, `Thank you for trusting Jago! You just did a
  top up`.
- `Transaction Summary`.
- A nonempty first value under `To`, used as the destination label.
- A positive rupiah `Amount`.
- `Transaction Date` in `d MMMM yyyy HH:mm WIB` format, parsed in
  `Asia/Jakarta`.

It becomes a `transferOut` draft with high parser confidence. It follows
the existing top-up policy: it is eligible spending after Review acceptance.

### Debit-card alert

- `You have recently made a transaction of` followed by a positive rupiah
  amount.
- `using your Jago debit card`.

This alert becomes a `cardPurchase` draft with the explicit provisional label
`Jago debit card spending`, the Gmail receipt time as its provisional time,
and medium confidence. It is a real transaction but lacks a merchant and
bank-provided transaction time, so it always starts in Review. The owner can
keep the label, edit it to a useful description, choose a category, or
discard it.

Every normalized draft contains the Gmail message ID, bank ID `jago`, parsed
Jakarta timestamp, destination label, amount, transaction kind, and the
appropriate parser confidence. It does not store the From account, recipient account/PAN
value below To, merchant PAN, customer PAN, acquirer, terminal ID, merchant
location, tip, or raw email content.

For the debit-card alert alone, the normalized draft uses Gmail's receipt time
instead of a bank transaction time and the fixed provisional label above. That
is the only permitted fallback.

## User Flow

1. The owner taps Sync Gmail; the app scans the existing `Transaction` label
   for the last 90 days.
2. The importer tries BCA, Mandiri, OCTO CIMB QR-purchase, then the Jago
   structured payment, transfer, top-up, and debit-card parsers.
3. A complete, non-duplicate Jago receipt appears in the import confirmation
   and, after the owner imports it, enters Review. The debit-card alert also
   enters Review, visibly labelled as provisional.
4. A saved merchant rule may suggest a category but never bypasses Review.
5. The owner accepts a suggestion or chooses a category. Only then does the
   payment contribute to confirmed spending and the Jago source total.

## Editing an Imported Description

The current app can edit a transaction's category but cannot yet edit its
visible description. This work adds one local description field to the
existing transaction editor and makes it available directly from Review for
every pending imported transaction before acceptance. Jago debit-card alerts
are one important use case, not a special case.

- The editor initially shows the stored visible description (the `merchant`
  field in the current local model).
- Tapping a Review item opens the shared transaction editor. Saving a valid
  description and category accepts the item into the ledger; Cancel dismisses
  the editor without changing it. The owner can discard it instead without
  visiting Transactions first.
- Saving requires a nonblank trimmed value and updates only that local
  transaction; it never changes Gmail.
- The owner may then choose whether to create or update a merchant category
  rule using the edited description. The default is off, so a one-off debit
  description cannot accidentally alter future categorization.
- Editing a description does not change its source Gmail ID, amount, kind,
  receipt time, or duplicate-suppression identity. It also does not alter
  previously saved transactions.

## Tech Stack and Project Structure

- `Sources/ExpenseTrackerCore/BankEmailParser.swift` holds the pure parser.
- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift` registers it in the
  deterministic parser chain.
- `Sources/ExpenseTrackerCore/SpendingAnalytics.swift` already maps `jago` to
  the readable source label `Jago`.
- `Tests/ExpenseTrackerCoreTests/` contains only anonymized parser and
  mixed-import fixtures.
- `Sources/ExpenseTracker/` needs no Gmail, SwiftData, or new UI workflow.

## Commands

Focused parser tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1 --filter JagoEmailParserTests
```

Full verification:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift run CoreVerification
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

## Code Style

Keep recognition strict and pure. Structured receipts require their relevant
merchant, amount, time, heading, and payment success state. The debit-card
alert is the explicit exception: only its fixed label and Gmail receipt time
may stand in for information the email does not provide.

```swift
guard isSupportedStructuredJagoReceipt(lines), let merchant, let occurredAt,
      let amount, amount > 0 else {
    return .unsupported
}
```

## Testing Strategy

- Write failing tests before parser registration or parsing changes.
- Use synthetic names, account fragments, PANs, timestamps, IDs, and amounts.
- Cover one complete structured payment, transfer, top-up, and debit-card
  alert; missing or zero amount; missing date; and failed payment status.
- Prove the debit-card alert uses only its amount, Gmail receipt time, and the
  fixed provisional label; it must not derive a merchant from unrelated text.
- Prove the draft merchant is the first To value and never any PAN, account,
  terminal, acquirer, location, or tip value.
- Prove a mixed BCA, Mandiri, OCTO CIMB, Jago, and unsupported scan imports
  every valid candidate once and leaves every new record in Review.
- Prove accepted Jago payments, transfers, and top-ups count in the Jago
  source total; Review items do not.
- Cover local description edits: blank input is rejected; a valid edit changes
  only the chosen record; and merchant-rule creation remains an explicit
  choice.
- Cover Review description edits: saving does not accept an item or create a
  merchant rule; category selection and discard remain available afterward.
- Run full tests, CoreVerification, and an unsigned simulator build. A real
  Gmail scan remains optional until automated verification passes.

## Boundaries

### Always

- Parse locally and use the existing one-account, read-only, manual Gmail
  scan.
- Keep the exact `Transaction` label, 90-day window, and Flip exclusion.
- Route every recognized Jago structured payment, transfer, and top-up to
  Review first.
- Route every recognized Jago debit-card alert to Review with its fixed,
  visible provisional label.
- Persist only fields already represented by `TransactionRecord`.

### Ask First

- Supporting another Jago email template, language, or receipt type.
- Changing the debit-card fallback label, using a different fallback time, or
  auto-creating a merchant rule from its provisional label.
- Persisting account/PAN values, terminal ID, acquirer, location, tip, raw
  email, or headers.

### Never

- Modify Gmail messages or labels.
- Guess a debit-card merchant or bank transaction time not present in the
  email.
- Let a Jago item bypass Review or alter existing records on later syncs.

## Success Criteria

- Complete anonymized Jago structured payment, transfer, and top-up receipts
  each produce one `jago` draft using only the first To value as the visible
  label, its Jakarta timestamp, amount, and corresponding transaction kind.
- A complete anonymized Jago debit-card alert produces one medium-confidence
  `jago` `cardPurchase` draft named `Jago debit card spending`, timed from the
  Gmail receipt, with no merchant rule automatically created.
- Incomplete, failed, or lookalike structured emails create no draft. A valid
  debit-card alert creates only its fixed provisional draft.
- Every valid Jago candidate enters Review once and participates in normal
  duplicate protection and merchant-category suggestions.
- After acceptance, the Jago transaction appears in confirmed spending and
  the Jago source total; it is excluded while still in Review.
- Tests, CoreVerification, and the unsigned simulator build pass.

## Open Questions

- Other Jago email formats will be specified separately after receiving a
  redacted structured example for each.

## Implementation Status

The four approved Jago parsers are registered in the local Review importer.
Debit-card alerts use the approved provisional label and Gmail receipt time,
and local transaction descriptions can be edited without modifying Gmail.
Core tests, CoreVerification, and the unsigned simulator build pass.
