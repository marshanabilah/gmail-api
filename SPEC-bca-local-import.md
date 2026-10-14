# Spec: BCA Local Import and Review

Module id: `bca-local-import`

## Objective

Turn in-memory Gmail candidates into local transactions on the iPhone. The
first release recognises only successful BCA QRIS payment emails. It stores
the normalized transaction fields needed by the ledger, not the raw email
body, headers, PAN, terminal ID, RRN, or reference number.

Every recognized BCA payment starts in Review. A local merchant rule can
suggest a category, but the owner still taps Accept before it reaches the
ledger. When the owner personally chooses or creates a category, that choice
is itself the acceptance: the payment moves to the ledger and the app saves or
updates its local merchant rule.

Jago, Livin' by Mandiri, OCTO CIMB, and any unknown candidate remain
unsupported in this initial module. They do not create records. Flip remains
excluded upstream by `gmail-mailbox-sync` and must never arrive here.

## User Flow

1. The owner connects one Gmail account and taps Sync Gmail.
2. `gmail-mailbox-sync` reads the owner-maintained `Transaction` label for
   the last 90 days and returns candidates in memory.
3. `bca-local-import` examines each candidate with the BCA parser only.
4. A valid successful BCA QRIS payment becomes a local transaction with status
   `needsReview`. A matching local merchant rule may supply its suggested
   category.
5. Existing Gmail message IDs and transaction fingerprints are ignored so a
   repeat scan cannot add a duplicate.
6. A system-suggested category stays in Review until the owner taps Accept.
   When the owner chooses or creates a category themselves, the transaction
   moves to `ready` immediately and that choice becomes a local merchant rule.

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
- Review status `needsReview` for every new BCA import, including imports with
  a suggested category.

## Duplicate Rules

- If a local `TransactionRecord` already has the same `sourceMessageID`, skip
  the candidate.
- If a prior record has the same normalized fingerprint, skip the candidate.
- Duplicate checks happen before any SwiftData insertion.
- A skipped duplicate does not alter its existing category, status, or manual
  edits.

## Data Boundaries

### Always

- Run parsing and duplicate detection on the iPhone.
- Persist only the normalized fields already represented by
  `TransactionRecord`.
- Route every newly imported BCA transaction to Review.
- Preserve manual transactions, custom categories, and merchant rules.
- Return counts for imported, duplicate, unsupported, and invalid candidates
  without including raw email text in the interface or logs.

### Ask First

- Importing Jago, Livin', OCTO CIMB, or another bank format.
- Adding a direct-to-ledger path that bypasses the owner's explicit action.
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
- Choosing or creating a category in Review moves that transaction to `ready`
  without a second acceptance step and updates the merchant rule.
- Applying saved merchant rules fills only matching Review categories; it
  never changes a transaction's Review status.
- Unsupported candidates produce no local record and do not block recognized
  BCA candidates in the same scan.
- No raw Gmail content or sensitive banking metadata enters SwiftData, UI
  text, debug output, or test fixtures.
- Import errors leave all pre-existing local records unchanged.

## Testing Strategy

- Use only redacted BCA email fixtures with synthetic identifiers and amounts.
- Add unit tests before implementation for valid QRIS input, failed status,
  missing fields, ID duplicate, fingerprint duplicate, existing merchant rule,
  and mixed BCA plus unsupported candidates.
- Test the import coordinator against an in-memory record-store protocol, not
  live Gmail or SwiftData.
- Build the simulator after connecting the app-facing store adapter.
- Do not use a real Gmail scan until the owner approves this draft and Task 6
  in `tasks/todo.md` has completed real Google connection verification.

## Open Questions for Approval

- Should `Transfer to Own CIMB Niaga Account` stay excluded from the first
  import because it is an account move rather than spending?
- When the Review action is specified, should confirming a transaction set it
  to `ready`, or should Review remain a filter over every imported item?
- After BCA is reliable, should Jago or Livin' be the next parser module?
