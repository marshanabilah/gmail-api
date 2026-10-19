# Spec: BCA Local Import and Review

Module id: `bca-local-import`

## Objective

Turn in-memory Gmail candidates into local transactions on the iPhone. This
module defines successful BCA QRIS payment handling. The shared Review importer
also recognizes the supported Livin' by Mandiri receipt formats under
`SPEC-mandiri-local-import.md` and supported OCTO CIMB QR-purchase receipts
under `SPEC-octo-cimb-local-import.md`. It stores the normalized transaction
fields needed by the ledger, not raw email or sensitive bank metadata.

Recognized BCA payments normally start in Review. A saved exact trusted
bank-and-merchant rule can instead send an eligible QR/card purchase directly
to the ledger. Other local merchant rules can suggest a category, but the
owner still saves the transaction before it reaches the ledger.

Unsupported OCTO CIMB formats and unknown candidates remain unsupported. They
do not create records. Supported Jago formats are defined in
`SPEC-jago-local-import.md`. Flip remains excluded upstream by
`gmail-mailbox-sync` and must never arrive here.

## User Flow

1. The owner connects one Gmail account and taps Sync Gmail.
2. `gmail-mailbox-sync` reads the owner-maintained `Transaction` label for
   the last 90 days and returns candidates in memory.
3. The shared Review importer tries the BCA parser, Mandiri receipt parsers,
   then the supported OCTO CIMB QR-purchase parser.
4. A valid successful BCA QRIS payment becomes a local transaction. An exact
   trusted bank-and-merchant rule makes it `ready`; otherwise it is
   `needsReview`, possibly with a suggested category.
5. Existing Gmail message IDs and transaction fingerprints are ignored so a
   repeat scan cannot add a duplicate.
6. A system-suggested category stays in Review until the owner taps Accept.
   When the owner saves a category themselves, the transaction moves to
   `ready`, creates an exact trusted bank-and-merchant rule for an eligible
   QR/card purchase, and suggests—but does not accept—that category for
   matching pending items that do not already have one.
7. If the scan has no new importable records, the app explains the number that
   were already in the ledger and the number that were unsupported, without
   exposing email content.

The Sync action does not create records until this module is implemented and
the owner explicitly confirms the local Review import after a real
`Transaction` label scan.

## Accepted BCA Email Shape

A candidate is importable only when all of these conditions hold:

- `Status` is `Successful`.
- `Transaction Type` is `QRIS Payment`.
- `Transaction Date` parses as Jakarta time in `dd MMM yyyy HH:mm:ss`.
- `Payment to` is present after trimming whitespace.
- `Total Payment` parses as a positive IDR amount.

The local transaction stores:

- Gmail `messageID` for idempotency only.
- Bank ID `bca`.
- Parsed transaction time, merchant, amount, transaction kind, and parser
  confidence.
- Category produced by an existing local merchant rule, if one matches.
- Status `ready` for an eligible BCA QRIS payment with an exact trusted rule;
  otherwise `needsReview`, including imports with a suggested category.

## Duplicate Rules

- If a local `TransactionRecord` already has the same `sourceMessageID`, skip
  the candidate.
- If a prior record has the same normalized fingerprint, skip the candidate.
- If a local discard marker has the candidate's Gmail message ID, ignore the
  candidate so it cannot return to Review.
- Duplicate checks happen before any SwiftData insertion.
- A skipped duplicate does not alter its existing category, status, or manual
  edits.

## Data Boundaries

### Always

- Run parsing and duplicate detection on the iPhone.
- Persist only the normalized fields already represented by
  `TransactionRecord`.
- Route new transactions to Review unless an eligible QR/card purchase has an
  exact trusted bank-and-merchant rule; those records become `ready`.
- Preserve manual transactions, custom categories, and merchant rules.
- Return counts for imported, duplicate, unsupported, and invalid candidates
  without including raw email text in the interface or logs.

### Ask First

- Importing another Jago or OCTO CIMB format, or another bank format.
- Changing the exact trusted-rule policy or expanding its eligibility.
- Storing any raw email content, Gmail header, account fragment, or reference
  number.
- Changing the 90-day scan window, Gmail label, account count, or OAuth scope.
- Performing the first real scan of the owner's Gmail account.

### Never

- Persist raw email bodies, sender addresses, subjects, account numbers, PANs,
  RRN values, terminal IDs, or reference numbers.
- Modify Gmail messages or labels.
- Guess missing date, merchant, amount, or transaction type values.
- Add an unsupported, malformed, ignored, or Flip candidate to the ledger.
- Overwrite an existing transaction's category, status, or manual correction
  during a later sync.

## Acceptance Criteria

- A valid redacted BCA QRIS email produces exactly one `needsReview` record.
- Failed BCA receipts are ignored rather than added to Review.
- A BCA email missing a required field is unsupported and creates no record.
- A repeated Gmail message ID or matching fingerprint creates no second
  record.
- An existing merchant rule fills the suggested category but keeps the BCA
  QRIS record in Review until the owner accepts it.
- Saving a category in Review moves that transaction to `ready` without a
  second acceptance step, and suggests the category to matching uncategorized
  pending items without accepting them.
- Saving or accepting an eligible QR/card purchase creates or updates an exact
  trusted rule for future imports without an extra control. Transfers, top-ups,
  fuzzy matches, and merchant-less debit alerts remain in Review.
- Applying saved merchant rules fills only matching Review categories; it
  never changes a transaction's Review status.
- Unsupported candidates produce no local record and do not block recognized
  BCA, Mandiri, or OCTO CIMB candidates in the same scan.
- No raw Gmail content or sensitive banking metadata enters SwiftData, UI
  text, debug output, or test fixtures.
- Import errors leave all pre-existing local records unchanged.

## Testing Strategy

- Use only redacted bank-email fixtures with synthetic identifiers and amounts.
- Add unit tests before implementation for valid QRIS input, failed status,
  missing fields, ID duplicate, fingerprint duplicate, existing merchant rule,
  and mixed BCA, Mandiri, plus unsupported candidates.
- Test the import coordinator against an in-memory record-store protocol, not
  live Gmail or SwiftData.
- Build the simulator after connecting the app-facing store adapter.
- Do not use a real Gmail scan until the owner approves this draft and Task 6
  in `tasks/todo.md` has completed real Google connection verification.

## Related Specification

Livin' by Mandiri parsing, transfer semantics, and analytics policy are
defined in `SPEC-mandiri-local-import.md`.
