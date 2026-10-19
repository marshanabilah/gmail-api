# Implementation Plan: Gmail Authentication

> Historical planning record. The current implemented behavior and acceptance
> policy are maintained in the module specifications and `tasks/todo.md`.

## Goal

Let the iPhone app connect one personal Google account with the smallest
necessary Gmail permission (`gmail.readonly`), retain credentials securely on
the device, show an understandable connection state, and disconnect without
touching saved ledger data. This capability does not read emails yet; that is
the responsibility of the later `gmail-mailbox-sync` module.

## Boundaries

- iPhone-only: no backend, cloud database, Apps Script, or token relay.
- Read-only Gmail access. The app must never alter messages, labels, or any
  other Gmail state.
- One account is sufficient for this MVP.
- Credentials belong in the iOS Keychain, never UserDefaults, source control,
  or logs.
- Existing manual transactions, categories, and review items survive both
  connection and disconnection.

## Dependency order

```text
OAuth approach decision
        |
        v
Test seam + credential model
        |
        v
Keychain credential store
        |
        v
OAuth coordinator and state machine
        |
        v
SwiftUI connection/disconnection experience
        |
        v
Google Cloud configuration + simulator callback check
```

## Architecture

The app-facing state remains in `SyncModel`, but Gmail authentication gets a
small, separately testable boundary:

```text
SwiftUI views
    -> GmailAuthCoordinator
        -> GmailOAuthClient       (browser/Google implementation)
        -> GmailCredentialStore   (Keychain implementation)
```

`GmailAuthCoordinator` owns the connect, restore, and disconnect state
transitions. The OAuth and Keychain adapters are expressed as protocols, so
tests can use fakes without opening a browser or reading the actual Keychain.
No mailbox request client is introduced here.

## Planned work

The detailed, independently verifiable tasks are in
[todo.md](todo.md). The implementation sequence is intentionally small:

1. Confirm the supported native-iOS OAuth path from official Google and Apple
   documentation, then record the decision before dependencies or settings
   change.
2. Establish the model/protocol/test target foundation.
3. Implement and test secure Keychain persistence.
4. Implement and test the OAuth state coordinator.
5. Connect the existing SwiftUI controls to the coordinator.
6. Configure the user's Google Cloud OAuth client and prove the real callback
   in the simulator.

## Risks and handling

| Risk | Handling |
| --- | --- |
| Callback URL or client configuration mismatch | Treat configuration as a separate final task; test every error as recoverable before a real sign-in attempt. |
| A new Google SDK adds maintenance or privacy surface | Research official options first; request approval before adding any dependency. |
| Tokens accidentally leak into app storage or logs | Keep token types internal, use Keychain only, and make tests assert that disconnect removes credentials. |
| Simulator behavior differs from a real device | Verify the callback in the simulator, then perform one final physical-device sign-in before relying on the feature. |
| Authentication expands into mailbox work | Keep the capability contract strict: no labels, message listing, parsing, or transaction writes in this module. |

## Verification checkpoints

1. **After the foundation and Keychain tasks:** unit tests demonstrate save,
   restore, replacement, and removal against a fake store; the app still
   builds.
2. **After the coordinator task:** unit tests cover success, cancellation,
   expired credentials, configuration failure, and callback/state mismatch;
   no test needs live Google access.
3. **After UI wiring:** the simulator shows idle, connecting, connected, and
   recoverable-error states without affecting manual data.
4. **Completion:** a configured Google test client completes one genuine
   simulator callback using only `gmail.readonly`; disconnect removes access
   locally while preserving the ledger.

## Required user-controlled changes

Before the final verification task, the user will need to create or select a
Google Cloud OAuth client and provide its non-secret client ID and redirect
configuration. The client secret, refresh/access tokens, and real email
contents must never be committed or pasted into the repository.

Adding a Google dependency, adding a URL scheme, changing the bundle
identifier, or changing Google Cloud configuration remains an explicit
ask-before-change step from the approved spec.

---

# Implementation Plan: Gmail Mailbox Sync

Module id: `gmail-mailbox-sync`

## Overview

Add a manual, read-only scan of the user's existing Gmail `Transaction` label.
The scan covers the previous 90 calendar days, filters confirmed Flip receipts,
and returns in-memory `BankEmail` candidates to the existing local-import
boundary. It does not create local transaction records itself. That write path
remains the separate `bca-local-import` module.

## Architecture Decisions

- Keep Gmail REST transport behind a narrow client protocol. Core filtering,
  time-window calculation, pagination, and Flip recognition run without
  Google, network, or simulator access.
- Keep access tokens inside the iOS Gmail adapter. The core receives
  `BankEmail` values only and must never log or store an access token.
- Resolve the owner's exact `Transaction` label at scan time. The app does not
  use, create, or change any other label.
- Treat the documented Flip receipt structure as an exclusion before parser
  selection. Unsupported non-Flip messages remain candidates; the downstream
  importer decides whether it recognises their bank format.
- A scan is user initiated. The UI may report a candidate count, but no scan
  writes to SwiftData until the downstream importer is specified and approved.

## Dependency Graph

```text
Configured gmail-auth connection
            |
            v
Official Gmail API request contract
            |
            v
Core mailbox scan + fixture tests
            |
            v
iOS Gmail REST adapter + MIME decoding
            |
            v
Manual scan state in the app
            |
            v
bca-local-import review persistence
            |
            v
One user-authorised real Transaction-label scan
```

Tasks 7 and 8 are safe without a real Gmail account. Task 9 can be unit-tested
with fakes, while its real-account check waits for the unfinished configured
sign-in verification in Task 6 and the later local-import implementation.

## Task List

### Phase: Mailbox foundation

- [x] Task 7: Define and test the mailbox scan contract
- [x] Task 8: Add the iOS Gmail REST adapter and MIME decoder

### Checkpoint: Mailbox foundation

- [x] Core tests pass and the simulator build succeeds
- [x] Review the transport boundary before exposing manual sync in the UI

### Phase: Manual scan handoff

- [x] Task 9: Wire a deliberate manual scan to an in-memory candidate result

### Checkpoint: Mailbox handoff

- [x] Unit tests cover the manual scan state without real Gmail
- [x] No candidate is persisted outside the later `bca-local-import` module
- [x] Human approves the downstream import plan before a real mailbox scan

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Gmail response or token-refresh behavior differs from assumptions | High | Confirm the current official Gmail and Google Sign-In docs before coding the adapter. |
| HTML-only or multipart bank emails decode incorrectly | Medium | Unit-test deterministic Base64URL and multipart fixtures before networking. |
| Flip receipt resembles a transfer alert | High | Require the confirmed success phrase and both destination-field labels before exclusion, with a control fixture to prevent overmatching. |
| Auth configuration is incomplete | Medium | Keep unit tests fake-driven and delay live Gmail verification until Task 6 completes. |
| Scan is mistaken for an import | High | Return candidates in memory only and label the state clearly; SwiftData writes remain out of scope. |

## Open Questions

- Whether a stable Flip sender address or subject can be added as a second,
  verified exclusion signal.
- Whether the existing downstream module keeps the stable ID
  `bca-local-import` while supporting BCA, Jago, and Livin', or is split after
  its own approved spec.

---

# Implementation Plan: Livin' by Mandiri Local Import

Module id: `mandiri-local-import`

## Overview

Extend the current BCA-only Review import so the same confirmed Gmail scan can
stage valid Livin' by Mandiri transfer receipts. Mandiri records remain
`transferOut`, start in Review, use the existing duplicate and merchant-rule
behavior, and count toward confirmed spending only after acceptance.

The unfinished live Gmail sign-out and restoration checks remain in the auth
task list. The user chose to defer those checks; this module does not close or
change them.

## Architecture Decisions

- Keep `MandiriTransferEmailParser` as a pure core parser and tighten it around
  the approved English Livin' receipt shape.
- Introduce a bank-agnostic Review importer that tries BCA and Mandiri parsers
  in a fixed order. A candidate can produce at most one transaction.
- Preserve the existing BCA result shape at the app boundary where practical,
  then rename user-facing BCA-only actions to bank-neutral import language.
- Reuse the current SwiftData write path. No schema change or new persisted
  banking field is needed.
- Keep Flip exclusion in `gmail-mailbox-sync`; the local importer still treats
  any unsupported lookalike as unsupported.

## Dependency Graph

```text
Approved Mandiri spec
        |
        v
Strict Mandiri parser and focused tests
        |
        v
Multi-bank Review importer and mixed-candidate tests
        |
        v
SyncModel and Dashboard import flow
        |
        v
README and related spec alignment
```

## Task List

### Phase: Core parsing

- [x] Task 11: Tighten the Mandiri parser with redacted tests
- [x] Task 12: Generalize Review import for BCA and Mandiri

### Checkpoint: Core import

- [x] Focused Mandiri and mixed-bank tests pass
- [x] Full core test suite passes

### Phase: App integration

- [x] Task 13: Connect the multi-bank preview and save flow
- [x] Task 14: Align README and existing specs

### Checkpoint: Complete

- [x] Simulator build succeeds
- [x] Import copy describes BCA payments and Mandiri transfers accurately
- [x] Mandiri transfers appear in Review and count toward spending only after
  acceptance
- [x] No real Gmail or sign-out check is required for parser verification

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Generic transfer text matches a non-Livin' email | High | Require the Livin' heading and every approved structured field. |
| One candidate is parsed twice | High | Stop at the first parser that returns a transaction or ignored result. |
| BCA behavior regresses during importer generalization | High | Keep all existing BCA tests and add a mixed-bank test before changing the importer. |
| Pending Mandiri transfer inflates expenses | High | Preserve Review status and verify only accepted transfers count with a focused test. |
| UI copy implies all candidates were imported | Medium | Report imported, duplicate, and untouched counts without exposing email content. |

## Open Questions

- None. Transaction-kind editing remains a separate future capability.

---

# Implementation Plan: Mandiri Transfer Spending Policy

Module id: `mandiri-local-import`

## Overview

Change the approved analytics policy so an accepted Mandiri `transferOut`
record counts as spending. The transfer stays in Review until the owner chooses
or confirms a category. It does not affect spending while its status is
`needsReview`.

## Architecture Decisions

- Keep `transferOut` as the stored transaction kind. The kind records the bank
  event accurately; analytics decides whether the accepted kind is spending.
- Change only the analytics expense predicate. This makes the policy apply to
  accepted Mandiri transfers without changing parser, duplicate, Gmail, or
  SwiftData behavior.
- Do not infer account moves from recipient names, banks, or text. Every
  accepted outgoing transfer counts under the approved personal-ledger policy.
- Keep all existing non-expense kinds, including `transferIn`, cash withdrawal,
  refund, and unknown, out of spending totals.

## Dependency Graph

```text
Approved transfer spending policy
        |
        v
Analytics predicate and regression tests
        |
        v
Dashboard and category-detail verification
        |
        v
README, specs, and task-record alignment
```

## Proposed Work

1. Add failing analytics tests proving an accepted `transferOut` contributes to
   monthly spending and its chosen category, while a Review transfer does not.
2. Change the shared expense predicate and verify category details inherit the
   result through the existing analytics model.
3. Update user-facing documentation and the completed Mandiri plan language so
   it no longer says accepted transfers are excluded from spending.
4. Run focused analytics tests, the complete Swift test suite, the core
   verification executable, and the iOS simulator build.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A pending Review transfer inflates the dashboard | High | Test that only `ready` transfer records count. |
| Other non-expense kinds begin counting accidentally | High | Preserve and test their exclusions. |
| Documentation contradicts the analytics result | Medium | Search and update all Mandiri spending statements before delivery. |

## Open Questions

- None for this implementation. A future account-move exclusion must be
  specified separately because the current email fields are not reliable enough
  to infer it.

---

# Implementation Plan: Discarding Review Transactions

Module id: `review-discard`

## Overview

Add a deliberate Discard action to Review for transactions that do not belong
in the owner's spending ledger. Discarding deletes the transaction record and
persists only its Gmail message ID as a local marker. The marker prevents a
future Gmail scan from staging the same receipt again.

User-facing import copy refers only to BCA or Mandiri. QRIS payment and
transfer are parser-level details, not labels the owner needs to interpret.

## Architecture Decisions

- Add a dedicated `DiscardedImportRecord` rather than reuse `ImportStatus`.
  An ignored transaction record would remain local activity, whereas discard
  must remove it from Review, Activity, and analytics.
- Store only `sourceMessageID` in the discard record. This preserves the
  no-sensitive-data boundary while allowing stable Gmail idempotency.
- Extend the bank-agnostic importer with a `discardedMessageIDs` input. It
  reports matching candidates as ignored without invoking a bank parser or
  inserting a transaction.
- Keep Discard available only in Review and require a confirmation dialog.
  This is the last local decision before a record is removed.
- Keep user-facing copy bank-level: “BCA or Mandiri transaction.” No UI copy
  distinguishes QRIS payments from transfers.

## Dependency Graph

```text
Discard marker model
        |
        v
Importer suppression contract and core tests
        |
        v
SwiftData persistence and Review discard confirmation
        |
        v
Dashboard import feedback and documentation alignment
```

## Proposed Work

1. Add tests for a discarded message ID and extend the core importer so it
   ignores only that exact candidate while preserving normal imports.
2. Add the SwiftData discard-marker model, supply its IDs to import previews,
   and add a confirmation-backed Discard action in Review.
3. Replace user-facing receipt-kind wording with BCA or Mandiri naming and
   update the specs, README, plan, and task record.
4. Run focused core tests, the full suite, core verification, an unsigned
   simulator build, and one manual simulator discard plus re-sync check.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A discarded receipt returns after the next sync | High | Persist the Gmail message ID before removing its transaction and test the importer boundary. |
| Discarded activity remains in spending or Activity | High | Delete the transaction record rather than changing its status; verify each derived view uses current records. |
| A user removes an item by mistake | Medium | Require a confirmation dialog that describes the local, non-reversible decision. |
| Copy exposes parser internals | Low | Use BCA or Mandiri in every owner-facing import message. |

## Open Questions

- None for this version. Undo, a discarded-items history, and bulk discard
  remain separate future features.

## Implementation Status

Core suppression, SwiftData marker persistence, Review confirmation, and
bank-level owner-facing import feedback are implemented. Core tests,
CoreVerification, and the unsigned simulator build passed. A manual simulator
discard and later Gmail re-sync remain optional final checks.

---

# Implementation Plan: Additional Livin' by Mandiri Receipts

Module id: `mandiri-local-import`

## Overview

Extend the existing Mandiri Review import with two strict, locally parsed
receipt shapes: Payment Successful and e-money Top-up Successful. Each valid
receipt enters Review, follows the established category workflow and duplicate
protection, and remains separate from Gmail after the scan. An accepted e-money
top-up uses the existing `transferOut` policy and therefore counts as spending.

## Architecture Decisions

- Add dedicated pure parsers for Mandiri payment and e-money top-up receipts.
  Keep `MandiriTransferEmailParser` unchanged so each strict receipt contract
  remains easy to test and a future email variation does not blur the rules.
- Keep the strict parsers separate because their required receipt fields differ.
  Their focused tests pin the common line, Jakarta-date, and rupiah behavior;
  extract a shared helper only when another format makes that trade-off useful.
- The bank-agnostic importer tries BCA, Mandiri transfer, Mandiri payment, and
  Mandiri e-money top-up parsers in that order. It stops at the first recognized
  or ignored result, so a candidate produces at most one Review item.
- Use `qrisPayment` for a Mandiri payment and `transferOut` for an e-money
  top-up. Both already become spending only after the owner accepts and
  categorizes them, so no analytics or persistence schema change is needed.
- The e-money merchant label is the constant `e-money top-up`. Do not persist a
  card fragment, reference number, PAN, location, or account details.
- Owner-facing import text names the bank, not the receipt mechanism. It says
  BCA or Mandiri transaction rather than QRIS payment or transfer.

## Dependency Graph

```text
Strict payment and e-money parser tests
        |
        v
Pure receipt parsers and shared parse helpers
        |
        v
BankReviewImporter registration and mixed-candidate tests
        |
        v
Dashboard wording and documentation alignment
        |
        v
Core suite, app build, optional live Gmail confirmation
```

## Proposed Work

1. Write failing, anonymized parser tests for Payment Successful. Verify its
   recipient, Jakarta timestamp, amount, `qrisPayment` kind, and rejection of
   a missing success heading, recipient, reference, or positive amount.
2. Write failing, anonymized parser tests for e-money Top-up Successful. Verify
   the stable `e-money top-up` label, Jakarta timestamp, amount, `transferOut`
   kind, and rejection of an invalid provider, missing reference, or zero
   amount.
3. Add the two parsers and any narrowly shared receipt-field helper. Register
   them in the bank-agnostic importer and add mixed-candidate, duplicate, and
   merchant-rule tests. Confirm neither parser can store sensitive receipt
   fields.
4. Replace the remaining owner-facing receipt-type wording with BCA or Mandiri
   naming and update the README and Gmail/import specs to reflect all supported
   Mandiri formats.
5. Run focused parser and importer tests, the complete core suite, core
   verification, and the unsigned simulator build. A live Gmail scan is an
   optional final confirmation and should only happen after unit verification.

## Verification Checkpoints

### Checkpoint: Receipt recognition

- Both new parser test groups pass.
- A malformed or lookalike receipt returns `unsupported` and creates no draft.
- Existing BCA and Mandiri transfer tests still pass.

### Checkpoint: Import integration

- A mixed candidate scan imports each supported BCA or Mandiri draft once.
- Duplicate message IDs and fingerprints remain skipped.
- Every recognized item starts in Review, including top-ups.

### Checkpoint: Ready to test in Gmail

- Core suite, `CoreVerification`, and unsigned simulator build pass.
- Import feedback correctly distinguishes no new import from unsupported
  messages without exposing raw email data.
- User may run one manual sync to confirm real labeled Mandiri messages enter
  Review.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A generic payment message is mistaken for a bank receipt | High | Require the success heading and every structured field before creating a draft. |
| HTML tables lose field boundaries | High | Keep the existing HTML table-decoding regression test and add receipt fixtures with separate lines. |
| E-money account fragments enter the local ledger | High | Use a constant label and test that no card fragment is used as a merchant. |
| A parser blocks another valid Mandiri format | Medium | Keep a fixed parser order and test a mixed scan through the bank-agnostic importer. |
| UI wording promises an import when none occurred | Medium | Test and review zero-import copy separately from parser results. |

## Open Questions

- None. The owner confirmed that accepted e-money top-ups count as spending.

---

# Implementation Plan: Transaction Analytics and Source Breakdown

Module id: `spending-analytics`

## Overview

Move detailed monthly analytics from Dashboard into an Analytics mode within
Transactions. Add a confirmed-spending breakdown by stored transaction source,
alongside the existing category breakdown. Both detail routes remain editable
ledger views, while Dashboard keeps only compact current-month context.

## Architecture Decisions

- Extend the existing pure `SpendingAnalyticsInput` with a stored source ID.
  Its core result maps known IDs to BCA, Mandiri, Cash, and E-wallet and gives
  any future source its own readable row. This avoids a SwiftData migration and
  guarantees source totals account for every confirmed expense.
- Keep category and source grouping in the same core summary so both use the
  identical month and confirmed-expense predicate.
- Place a native Transactions/Analytics picker inside `TransactionsView`.
  The ledger remains the default mode and keeps Add transaction.
- Reuse one detail screen with a filter descriptor for full month, category,
  or source. It must only show confirmed expenses for category/source filters.
- Dashboard uses the current month only and removes its month picker,
  category breakdown, source breakdown, and analytics detail sheet.

## Dependency Graph

```text
Source-aware core summary and tests
        |
        v
Transactions Analytics mode and drill-down
        |
        v
Compact Dashboard and documentation alignment
        |
        v
Full verification
```

## Proposed Work

1. Add failing source-grouping tests, then extend the core analytics input and
   summary with source totals while preserving every existing month, category,
   and Review rule.
2. Add the Transactions/Analytics mode, source rows, and reusable month,
   category, and source detail filtering. Preserve transaction editing and
   deletion from every detail route.
3. Remove duplicated detailed analytics from Dashboard, retain compact current
   month and Gmail state, and align the README, spec, and task record.
4. Run focused analytics tests, the complete suite, CoreVerification, an
   unsigned simulator build, and one optional manual UI check without starting
   a Gmail scan.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Source totals omit a future bank | High | Treat an unrecognized nonempty source as its own readable group and test it. |
| Category and source totals disagree | High | Produce both from the same confirmed-expense collection and assert each total. |
| Dashboard and Transactions show competing analytics | Medium | Remove Dashboard’s picker, breakdowns, and detail route in the final UI slice. |
| Detail filters show Review items as spending | High | Reuse the existing confirmed-expense predicate for category and source detail filters. |

## Open Questions

- None. The owner approved the Transactions/Analytics placement and source
  grouping model.

## Implementation Status

Source grouping, the Transactions/Analytics switch, category and source
drill-downs, compact Dashboard, and documentation alignment are implemented.
Core tests, CoreVerification, and the unsigned simulator build pass. A manual
Analytics navigation check remains optional.

---

# Implementation Plan: OCTO CIMB QR Purchase Import

Module id: `octo-cimb-local-import`

## Overview

Add one strict OCTO App QR-purchase receipt to the existing local Gmail Review
flow. The receipt becomes an OCTO CIMB QR payment in Review only after it has
all approved fields; accepted records then join the existing spending and
source analytics.

## Architecture Decisions

- Add a dedicated `OCTOCIMBQRPurchaseEmailParser`. Do not register the
  existing own-account-transfer parser with `BankReviewImporter`, because that
  would broaden imports beyond the approved QR-purchase scope.
- The parser requires the transaction-summary heading, transaction ID, QR
  purchase type, merchant, Jakarta time, and positive total payment. The ID
  validates receipt completeness but is not persisted.
- Register the QR parser after BCA and Mandiri parsers. The fixed chain still
  stops after the first recognized or ignored result, preserving exactly one
  result per Gmail message.
- Extend source-name mapping with `octoCimb` → `OCTO CIMB`; no SwiftData schema
  change is needed.

## Dependency Graph

```text
Strict QR-purchase parser tests
        |
        v
Pure OCTO CIMB QR parser
        |
        v
Importer registration + source analytics mapping
        |
        v
Documentation and full verification
```

## Proposed Work

1. Add failing redacted tests for complete and malformed OCTO CIMB QR-purchase
   receipts, then implement the dedicated pure parser.
2. Register only that parser in `BankReviewImporter`, add mixed-scan and
   duplicate coverage, and add the `OCTO CIMB` source display mapping.
3. Update README and import specs so active support, strict boundaries, and
   parse-only own transfers match the code.
4. Run focused tests, the full suite, CoreVerification, an unsigned simulator
   build, and optionally one manual Gmail import after automated checks pass.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Own-account transfers enter Review | High | Use a separate QR parser and test that transfer receipts remain unsupported by the Review importer. |
| Receipt metadata reaches local storage | High | Construct drafts from merchant, time, amount, kind, bank ID, and Gmail ID only; add fixture assertions. |
| OCR-like HTML line changes break parsing | Medium | Test the normalized labeled receipt text emitted by the Gmail body decoder and require every field. |
| OCTO CIMB total is missing from source analytics | Medium | Add source grouping coverage for `octoCimb` and map it to one stable display label. |

## Open Questions

- None. The owner approved only OCTO CIMB QR-purchase receipts for this module.

## Implementation Status

The dedicated QR-purchase parser is registered for Review, own-account
transfers remain parse-only, and `octoCimb` maps to `OCTO CIMB` in analytics.
Core tests, CoreVerification, and the unsigned simulator build pass. A live
labeled-email import remains optional.

---

# Implementation Plan: Jago Local Import and Description Editing

Module id: `jago-local-import`

## Overview

Add the supplied Jago payment, transfer, e-wallet top-up, and debit-card email
formats to the local Gmail Review flow. Structured receipts use their bank
fields; the debit-card alert gets an explicit provisional label and Gmail
receipt time because its email omits both merchant and bank transaction time.
Extend the existing transaction editor so the owner can revise any local
transaction description, including that provisional label.

## Architecture Decisions

- Implement four narrow pure parsers in `BankEmailParser.swift` and register
  all four after the currently supported BCA, Mandiri, and OCTO parsers.
- Preserve the provided first `To` value only for structured Jago payments,
  transfers, and top-ups. Never persist account/PAN values below it or any
  other sensitive receipt metadata.
- Use `cardPurchase` for structured payments and debit-card alerts;
  use `transferOut` for transfers and top-ups, consistent with existing
  Mandiri semantics.
- The debit-card alert always creates a medium-confidence Review item named
  `Jago debit card spending`, timestamped with `BankEmail.receivedAt`. It
  does not create or match a merchant rule automatically.
- Add a local editable description to the existing category editor by editing
  `TransactionRecord.merchant`; this avoids a data-model migration and keeps
  the current visible transaction label as the owner-facing description.
- Description changes never mutate Gmail, source IDs, amount, kind, timestamp,
  fingerprint, or prior transactions. Creating a category rule stays opt-in.

## Dependency Graph

```text
Red parser tests + edit-behavior tests
        |
        +--> Pure Jago parsers
        |          |
        |          v
        |   Importer registration + analytics coverage
        |
        +--> Transaction description editor
                    |
                    v
           Documentation and full verification
```

## Proposed Work

1. Add failing anonymized tests for the four Jago formats, then implement
   strict local parsers. Validate success status for structured payments, use
   only permitted fields, and prove the debit alert uses its fixed fallback.
2. Register the parsers in the deterministic Review importer; add mixed-import,
   duplicate, analytics, and category-rule coverage so every valid Jago item
   reaches Review exactly once and accepted spending appears under Jago.
3. Extend the transaction editor with an editable description field, nonblank
   validation, and an opt-in merchant-rule toggle that uses the final edited
   description.
4. Align README and import specs, then run focused tests, the full suite,
   CoreVerification, an unsigned simulator build, and an optional live Gmail
   scan after the automated checks pass.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Account or PAN becomes a visible description | High | Tests assert the first `To` value only; debit alerts use a constant label. |
| Debit-card timing is presented as bank-confirmed | Medium | Use medium confidence and describe receipt time as provisional in Review. |
| An edited description silently changes future categorization | High | Leave “use for future transactions” off by default and test that only an explicit toggle writes a rule. |
| Jago top-ups or transfers are omitted from spending | High | Reuse `transferOut`, the existing confirmed-expense behavior, and source analytics tests. |
| Existing category editing regresses | Medium | Preserve category, delete, and duplicate-suppression behavior in unit and build verification. |

## Open Questions

- None. The owner approved importing debit-card alerts with a provisional
  description and adding local description editing.

---

# Implementation Plan: Analytics Pending Review Month Drill-down

Module id: `review-month-drilldown`

## Overview

Keep Dashboard focused on current confirmed spending and Gmail state. Make the
pending-review amount in Transactions → Analytics act as a month-specific
drill-down to Review, where the owner sees only that month's pending items
until choosing `Show all`.

## Architecture Decisions

- Lift the selected tab and optional Review month filter into `RootView` so
  Analytics can navigate to Review without presentation workarounds.
- Treat the filter as view state only; it never changes SwiftData records,
  Gmail state, or analytics totals.
- Use the existing Jakarta month calendar helper for filtering and preserve
  Review's descending date sort.
- Remove Dashboard's pending-review line and explanatory copy completely.

## Proposed Work

1. Add a pure month-filter helper with focused date-boundary tests.
2. Wire `RootView`, Transactions Analytics, and Review through the optional
   month filter; make the Analytics pending row a button and provide `Show all`
   in Review.
3. Remove Dashboard pending-review UI and align documentation/task records.
4. Run focused tests, full tests, CoreVerification, an unsigned simulator
   build, and an optional manual tap-through.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| The selected month does not reach Review | High | Keep tab and filter state in RootView and test the filter separately. |
| Older pending transactions become inaccessible | High | Always show an explicit `Show all` action. |
| Review actions break while filtered | Medium | Filter only the displayed collection; reuse every existing action unchanged. |
| Dashboard repeats Review information | Low | Remove its pending amount/count and retain only confirmed spending. |

## Open Questions

- None. The owner approved Analytics as the entry point and Review as the only
  pending-review destination.

---

# Implementation Plan: Edit Pending Review Descriptions

Module id: `review-description-editing`

## Overview

Allow every pending imported transaction—BCA, Mandiri, OCTO CIMB, Jago, and
future sources—to have its local description edited before acceptance. The
edit remains in Review and never changes Gmail or creates a merchant rule.

## Proposed Work

1. Add a focused Review description sheet using the existing shared
   normalization rule.
2. Save edits from Review directly into the ledger after a valid category and
   description; provide Cancel to dismiss without changing the pending item.
   Preserve discard and month-filter behavior.
3. Add focused coverage for normalization and run the full test/build checks.

## Open Questions

- None. The edit applies to every pending imported transaction.
