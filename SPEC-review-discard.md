# Spec: Discarding Review Transactions

Module id: `review-discard`

## Objective

Let the owner permanently discard a transaction that reached Review but does
not belong in their personal spending ledger, such as a transfer between their
own accounts. A discarded item leaves Review, Activity, category analytics,
and future Gmail imports while the app keeps only enough local information to
avoid importing the same Gmail message again.

## User Flow

1. The owner opens a Review transaction and chooses Discard.
2. The app asks for confirmation and explains that the transaction will be
   removed from this device's ledger and will not return from a later Gmail
   sync.
3. On confirmation, the app deletes the transaction record and saves a local
   discard marker using its Gmail message ID.
4. A later sync recognizes that marker and skips the matching email without
   showing it in Review or analytics.

The feature is intended for any Review item, not only Mandiri transfers. It
does not alter Gmail, delete Gmail messages, or save bank-email contents.

## Tech Stack and Project Structure

- SwiftUI provides the Review action and confirmation dialog.
- SwiftData stores a local discard marker containing only the Gmail message ID.
- `Sources/ExpenseTracker/TransactionRecord.swift` contains SwiftData models.
- `Sources/ExpenseTracker/ReviewView.swift` owns Review actions.
- `Sources/ExpenseTracker/SyncModel.swift` supplies discard IDs to import
  preview logic.
- `Sources/ExpenseTrackerCore/BCAReviewImporter.swift` skips candidates whose
  message IDs were discarded.
- `Tests/ExpenseTrackerCoreTests/` covers pure import suppression behavior.

## Commands

Run core tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1
```

Build the iPhone app for the simulator:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Code Style

Use a message-ID set at the core import boundary. Keep the local persistence
detail out of the parser and represent a discarded candidate as ignored.

```swift
if discardedMessageIDs.contains(draft.sourceMessageID) {
    ignoredCount += 1
    continue
}
```

## Testing Strategy

- Add failing core tests before changing the importer.
- Verify a valid BCA or Mandiri candidate with a discarded message ID creates
  no import and increments the ignored count.
- Verify an item with a different message ID still imports normally.
- Build the app after adding the SwiftData discard-marker model and Review UI.
- Manually confirm that the destructive action requires confirmation and that
  a discarded item disappears from Review without changing Gmail.

## Boundaries

### Always

- Keep discard decisions local to the iPhone.
- Store only the Gmail message ID in a discard marker.
- Keep discarded transactions out of Review, Activity, and spending analytics.
- Require a confirmation before deleting a local transaction record.
- Preserve all accepted and pending non-discarded transactions.

### Ask First

- Adding an Undo flow, a discarded-items history, or bulk discard.
- Changing a discarded item back into an importable record.
- Persisting a merchant name, amount, bank name, or raw email data in the
  discard marker.

### Never

- Modify or delete Gmail messages or labels.
- Send discard decisions to a server or another device.
- Let a discarded Gmail message return as a new Review item.
- Count a discarded item in spending or category totals.

## Success Criteria

- Review shows a Discard action for every pending transaction.
- Confirming Discard removes that transaction from Review and its local ledger
  record.
- Its Gmail message ID is retained locally only for duplicate suppression.
- A matching future Gmail candidate is ignored; a different valid candidate is
  still imported.
- No discarded item appears in Activity, confirmed spending, pending-review
  totals, or category details.
- Core tests and the iOS Simulator build pass.

## Open Questions

- None for this first version. Undo and a visible discarded-items history are
  intentionally deferred.
