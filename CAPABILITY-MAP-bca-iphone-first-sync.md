# Capability Map: iPhone-First Gmail Import

> The original filename is retained for history. This map describes the
> current supported import flow.

| Module id | Responsibility | Depends on |
|---|---|---|
| `gmail-auth` | Google sign-in, read-only consent, secure token storage, and disconnect | None |
| `gmail-mailbox-sync` | Find the user-created `Transaction` label, list and fetch its Gmail messages, and exclude Flip | `gmail-auth` |
| `local-import` | Parse supported BCA, Mandiri, OCTO CIMB, and Jago receipts; deduplicate; suggest categories; and save local transactions | `gmail-mailbox-sync` |
| `trusted-auto-import` | Send an eligible exact bank-and-merchant QR/card match directly to Transactions after the owner has previously saved it | `local-import` |

Build order: `gmail-auth` -> `gmail-mailbox-sync` -> `local-import` -> `trusted-auto-import`

The app never creates labels or edits Gmail. The user creates and maintains the `Transaction` label and its Gmail filter. Its current bank-message candidates are BCA, Jago, and Livin' by Mandiri; Flip is excluded.

The downstream specifications are [SPEC-bca-local-import.md](SPEC-bca-local-import.md),
[SPEC-mandiri-local-import.md](SPEC-mandiri-local-import.md),
[SPEC-octo-cimb-local-import.md](SPEC-octo-cimb-local-import.md),
[SPEC-jago-local-import.md](SPEC-jago-local-import.md), and
[SPEC-trusted-auto-import.md](SPEC-trusted-auto-import.md). Eligible exact
trusted QR/card matches enter Transactions directly; other supported records
go to Review.
