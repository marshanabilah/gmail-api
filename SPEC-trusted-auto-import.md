# Spec: Trusted Exact-Match Auto Import

Module id: `trusted-auto-import`

## Objective

Reduce routine Review work without introducing another review-screen control.
When the owner saves a categorized, merchant-bearing transaction from Review,
the app treats that as an explicit trust decision for that exact merchant at
that exact bank. A later matching QR or card-purchase receipt goes directly to
the local ledger with the learned category. Every transaction remains editable
locally from Transactions; Gmail is never changed.

The goal is not a claimed `100%` parser confidence. It is an owner-confirmed,
strict local rule that makes routine purchases faster while keeping ambiguous
financial activity in Review.

## User Flow

1. A new supported bank receipt reaches Review unless a trusted exact-match
   rule applies.
2. The owner chooses a category and taps Save in Review. That transaction is
   accepted and a trusted rule is stored automatically—there is no separate
   “use for future” toggle.
3. Existing matching pending items may receive a category suggestion and stay
   pending; only their own Save action accepts them.
4. A later Gmail receipt with the same bank and normalized merchant name is
   saved directly as `ready` with the trusted category.
5. In Transactions, changing the description or category of a transaction
   that created a trusted rule updates that rule for future exact matches.

## Exact Match and Eligibility

- A match requires the same `bankID` and an equal normalized merchant key.
  Normalization is case-, diacritic-, whitespace-, and punctuation-insensitive;
  it does not use the existing shared-prefix or substring suggestion matcher.
- Only `.qrisPayment` and `.cardPurchase` drafts with a bank-supplied merchant
  name can bypass Review.
- `.transferOut`, `.transferIn`, `.unknown`, top-ups, own-account transfers,
  and the provisional `Jago debit card spending` alert always start in Review.
- A trusted rule supplies a category and `ready` status only. It never changes
  amount, date, transaction kind, source Gmail message ID, or duplicate
  protection.

## Data Model and Migration

- Add an additive SwiftData `TrustedImportRuleRecord` with a unique opaque
  `bankID|normalizedMerchantKey` key, its `bankID`, normalized merchant key,
  readable merchant label, and category.
- Keep existing `MerchantRuleRecord` unchanged as a suggestion-only rule so
  prior category learning is preserved.
- Do not persist raw email content, addresses, account values, or reference
  numbers in the new model.
- Existing transactions and merchant rules stay valid after migration. No
  historical transaction is auto-approved retroactively.

## Commands

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache \
swift test -j 1

TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache \
CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache \
swift run CoreVerification

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet -project ExpenseTracker.xcodeproj -scheme ExpenseTracker \
-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
-derivedDataPath /private/tmp/expense-tracker-derived \
CODE_SIGNING_ALLOWED=NO build
```

## Project Structure

- `Sources/ExpenseTrackerCore/` contains pure exact-match policy and the
  bank-review importer decision.
- `Tests/ExpenseTrackerCoreTests/` contains redacted fixture tests for trusted
  and non-trusted import outcomes.
- `Sources/ExpenseTracker/TransactionRecord.swift` contains SwiftData records.
- `Sources/ExpenseTracker/SyncModel.swift` converts import decisions into local
  records.
- `Sources/ExpenseTracker/ReviewView.swift` and
  `Sources/ExpenseTracker/TransactionsView.swift` create and correct trusted
  rules through the existing Save flow.

## Code Style

Use small, deterministic value types in the core and keep SwiftData writes in
the app target. Rule lookup must be explicit about bank and merchant key:

```swift
let rule = trustedRules.first {
    $0.bankID == draft.bankID &&
    $0.normalizedMerchantKey == normalizedMerchantKey(for: draft.merchant)
}
```

## Testing Strategy

- Write failing core tests before the importer change.
- Test that an exact trusted BCA/Mandiri/OCTO/Jago card or QR purchase returns
  `ready` with its category.
- Test that a different bank, near-but-not-equal merchant, transfer, top-up,
  and Jago debit-card alert remain `needsReview` even with a trusted rule.
- Test that duplicate and discarded-message handling still runs before trusted
  import decisions.
- Run the full Swift test suite, CoreVerification, `git diff --check`, and the
  unsigned iOS build. A real Gmail scan is optional and requires the owner's
  explicit action.

## Boundaries

### Always

- Keep trust rules local to the iPhone.
- Apply exact matching only after parsing and duplicate/discard checks.
- Keep every saved transaction editable without modifying Gmail.
- Keep existing pending-item suggestions separate from auto-acceptance.

### Ask First

- Auto-approving transfers, top-ups, fuzzy merchant matches, or a new bank
  format.
- Adding cloud sync, a second Gmail account, or a raw-email storage field.
- Adding a separate rule-management screen or another review-screen button.

### Never

- Treat parser confidence alone as permission to bypass Review.
- Auto-approve the merchant-less Jago debit-card alert.
- Change Gmail messages, labels, scopes, or the 90-day window.
- Persist raw email data or sensitive bank metadata.

## Success Criteria

- Saving a categorized Review card/QR purchase creates or updates one trusted
  exact-match rule without displaying a new toggle or button.
- A later exact bank-and-merchant match imports directly to Transactions with
  `ready` status and the saved category.
- Non-exact matches and ineligible transaction kinds remain in Review.
- Editing the category or description of a transaction associated with a
  trusted rule updates the future exact-match behavior locally.
- Existing suggestion rules, review suggestions, duplicate protection,
  discard suppression, analytics, and manual entries keep working.

## Open Questions

- Deleting a transaction will not delete its trusted rule in this first
  version. A future rule-management workflow can add an explicit forget path
  if needed.

## Status

Implemented and verified by automated tests and an unsigned iOS build. A real
Gmail import remains an owner-controlled optional check.
