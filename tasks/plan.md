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
