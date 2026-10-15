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
behavior, and stay outside confirmed spending totals.

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
- [x] Mandiri transfers appear in Review and remain outside spending totals
- [x] No real Gmail or sign-out check is required for parser verification

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Generic transfer text matches a non-Livin' email | High | Require the Livin' heading and every approved structured field. |
| One candidate is parsed twice | High | Stop at the first parser that returns a transaction or ignored result. |
| BCA behavior regresses during importer generalization | High | Keep all existing BCA tests and add a mixed-bank test before changing the importer. |
| Mandiri transfer inflates expenses | High | Preserve `transferOut` and verify analytics exclusion with a focused test. |
| UI copy implies all candidates were imported | Medium | Report imported, duplicate, and untouched counts without exposing email content. |

## Open Questions

- None. Transaction-kind editing remains a separate future capability.
