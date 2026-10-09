# BCA iPhone-First Sync

## Problem Statement

How might we import routine BCA transaction emails into a private iPhone ledger without operating a server or claiming iOS can guarantee background sync?

## Recommended Direction

The iPhone connects to Gmail through read-only OAuth. When the user opens the app or taps Sync, it reads the user's existing `Transaction` label, identifies eligible bank transaction alerts, parses them locally, removes duplicates, applies local merchant rules, and sends uncertain items to Review.

The `Transaction` label currently includes BCA, Jago, and Livin' by Mandiri emails. Flip messages are explicitly excluded. The app does not create Gmail labels or modify the inbox.

## Key Assumptions to Validate

- [ ] BCA transaction alerts have a stable sender and format that the app can identify safely.
- [ ] The BCA QRIS parser handles representative real emails; unhandled cases safely go to Review.
- [ ] Opening the app for a sync is frequent enough for everyday use.
- [ ] The iPhone can retain a valid Google OAuth refresh path without a server.

## MVP Scope

- Connect and disconnect Gmail.
- Store read-only OAuth credentials securely on-device.
- Sync when the user opens the app or taps Sync.
- Discover messages only from the existing `Transaction` label.
- Treat BCA, Jago, and Livin' by Mandiri as eligible bank-message candidates, while excluding Flip.
- Parse, deduplicate, and locally categorize BCA transaction emails first.
- Show clear sync progress and errors.
- Route uncertain imports to Review.

## Not Doing

- Background server polling. It adds cost and operational work before the core import path is proven.
- Apps Script automation. Reconsider it only if on-open sync is not enough.
- Live imports for OCTO CIMB. BCA reliability comes first; Jago and Livin' policy will be specified before their messages are imported.
- Gmail labels or other inbox changes. The app remains strictly read-only.
- Cloud categorization. Local merchant rules are sufficient for this milestone.

## Open Questions

- Which BCA, Jago, and Livin' sender addresses and subject patterns should the label query accept?
- Does the existing QRIS parser cover the real BCA variants in the mailbox?
- Which OAuth flow and secure token-storage approach best fit the iOS app?
