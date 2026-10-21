# Spec: Local Sync and Review Notifications

Module id: `local-notifications`

## Objective

Let the owner know when a manually started Gmail scan finishes and gently
remind them about items still waiting in Review. Notifications are local to the
iPhone. They do not require a server, background Gmail polling, a new Gmail
scope, or any transaction data outside the device.

The app requests notification permission only when the owner starts their
first Gmail sync. A denial never blocks Gmail sync, import, Review, or the
ledger.

## User Flow

1. The owner taps Sync Gmail.
2. If notification permission is undecided, the app asks for it in that
   context. The scan starts whether permission is granted, denied, or
   unavailable.
3. If the scan completes, the app posts one local notification named Gmail
   sync finished. Its body reports only how many labeled emails were found and
   how many Gmail messages were skipped. It does not claim that transactions
   were imported, because import confirmation is a separate owner action.
4. If the app remains in the foreground, the existing in-app sync result is
   the primary feedback. A system banner is not forced.
5. After the owner confirms an import, the app schedules one Review reminder
   for 09:00 on the next device-local calendar day only when one or more items
   still need review.
6. Saving or discarding the final pending Review item cancels the reminder.
   A later import with pending items replaces, rather than duplicates, the
   existing reminder.
7. Tapping a Review reminder opens the app on Review. Tapping a sync-finished
   notification opens the normal app entry screen.

## Privacy and iOS Limits

- Notification text never includes merchant names, amounts, account details,
  Gmail subjects, or email content.
- A scan can report completion only while iOS lets the manually started app
  work run. The app does not promise completion after iOS suspends or ends it.
- Local notifications are reminders and completion feedback. They are not
  real-time bank alerts.

## Tech Stack

- `UserNotifications` for authorization, delivery, pending-request lookup,
  and removal.
- Existing SwiftUI and SwiftData state for pending Review counts and routing.
- Existing `SyncModel` for mailbox completion state.
- No dependency, server, Gmail API change, background task, or new data model.

## Commands

Run focused core tests:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1 --filter LocalNotification
```

Run the full suite:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test -j 1
```

Build the iPhone app:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ExpenseTracker.xcodeproj -scheme ExpenseTracker -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/expense-tracker-derived CODE_SIGNING_ALLOWED=NO build
```

## Project Structure

```text
Sources/ExpenseTrackerCore/LocalNotifications/ -> Pure notification policy and test seam
Sources/ExpenseTracker/LocalNotifications/     -> UserNotifications adapter and SwiftUI routing
Sources/ExpenseTracker/SyncModel.swift         -> Requests permission and reports scan completion
Sources/ExpenseTracker/RootView.swift          -> Routes a Review reminder into Review
Tests/ExpenseTrackerCoreTests/                 -> Policy and formatting tests with fakes
SPEC-local-notifications.md                    -> This module's requirements
```

## Code Style

Keep notification decisions pure and inject the platform adapter. Notification
identifiers are stable constants so a new reminder replaces the old one.

```swift
enum LocalNotificationKind: String, Sendable {
    case gmailSyncFinished
    case reviewReminder
}

struct LocalNotificationRequest: Equatable, Sendable {
    let kind: LocalNotificationKind
    let title: String
    let body: String
}
```

- Use `Gmail` and `Review` in visible copy.
- Keep count grammar correct for one and many emails or messages.
- Do not put transaction data in notification content or identifiers.
- Treat permission and delivery failures as non-blocking local failures.

## Testing Strategy

- Write failing tests first for sync-finished wording, skipped-message wording,
  and Review-reminder scheduling policy.
- Test that no reminder is scheduled for zero pending items and that an
  existing reminder is replaced when pending items remain.
- Exercise clearing the final pending item through the reminder reconciliation
  path, which uses the same zero-pending pure-policy decision.
- Treat permission denial and notification-service failure as non-blocking;
  the adapter returns without changing mailbox or ledger state.
- Verify reminder routing with the app delegate and RootView build path. A
  device prompt is optional and owner-controlled.
- Run the full suite and unsigned iOS build. One owner-controlled device test
  may verify permission, a scheduled reminder, and notification tap routing.

## Boundaries

### Always

- Keep notifications local and optional.
- Start sync regardless of notification authorization result.
- Send no bank, merchant, amount, account, email, or category details in a
  notification.
- Maintain at most one pending Review reminder.
- Preserve the existing manual Gmail scan and explicit import confirmation.

### Ask First

- Changing the reminder time from 09:00 device-local time.
- Adding recurring reminders, notifications for spending limits, or new
  notification preferences.
- Adding background Gmail work, remote push notifications, a server, or any
  additional Gmail permission.

### Never

- Present a local notification as proof that Gmail has real-time delivery.
- Fail or retry a Gmail sync because notifications are unavailable.
- Include raw email content or banking data in notification text, logs, or
  identifiers.
- Create more than one pending Review reminder at a time.

## Success Criteria

- The first owner-started sync can request local-notification permission
  without blocking the scan.
- A completed scan produces privacy-safe local completion feedback when
  permission is available.
- A completed import with pending Review items schedules one next-day 09:00
  local reminder, and no pending items cancels it.
- A Review reminder opens Review when tapped.
- Permission denial and notification errors leave Gmail sync and local ledger
  behavior intact.
- Focused tests, the full suite, and an unsigned iOS build pass.

## Implementation Status

- Complete on 21 October 2026: the core policy has focused tests, the iPhone
  adapter requests permission without blocking sync, and reminder taps route
  to Review.
- Verified with the full Swift test suite, `CoreVerification`, whitespace
  validation, and an unsigned iOS simulator build.
- A physical-device notification permission and tap check remains optional.

## Open Questions

- None for the first version. Notification Settings can later expose a custom
  reminder time or disable the reminder without changing Gmail behavior.
