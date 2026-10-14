# Capability Map: BCA iPhone-First Sync

| Module id | Responsibility | Depends on |
|---|---|---|
| `gmail-auth` | Google sign-in, read-only consent, secure token storage, and disconnect | None |
| `gmail-mailbox-sync` | Find the user-created `Transaction` label, list and fetch its Gmail messages, and exclude Flip | `gmail-auth` |
| `bca-local-import` | Parse, deduplicate, suggest categories, stage BCA payments in Review, and save accepted items locally | `gmail-mailbox-sync` |

Build order: `gmail-auth` -> `gmail-mailbox-sync` -> `bca-local-import`

The app never creates labels or edits Gmail. The user creates and maintains the `Transaction` label and its Gmail filter. Its current bank-message candidates are BCA, Jago, and Livin' by Mandiri; Flip is excluded.

The downstream specification is [SPEC-bca-local-import.md](SPEC-bca-local-import.md). It intentionally limits writes to successful BCA QRIS payments, sends every new record to Review, and requires an explicit owner action before a Review item reaches the ledger.
