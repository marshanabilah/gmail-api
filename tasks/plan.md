# Implementation Plan: Gmail Authentication

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
