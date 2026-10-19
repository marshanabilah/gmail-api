# Spec: Monthly Spending Analytics

Module id: `spending-analytics`

## Objective

Give the owner a reliable view of spending for any imported calendar month,
without treating unreviewed Gmail imports as confirmed money spent. Analytics
lives in the Transactions tab, where the owner can inspect confirmed spending
by category or payment source and open the matching transactions.

## Scope

- Keep the Transactions tab's normal ledger list and Add transaction action.
  Add a native in-tab switch between **Transactions** and **Analytics**.
- Offer the current month and every month that has at least one local
  transaction in Analytics.
- Calculate month boundaries using the iPhone’s current calendar and time
  zone.
- Show one confirmed-spending total, based only on `ready` records whose kind
  is a card purchase, QRIS payment, fee, manual expense, or outgoing transfer.
  The current Gmail flow creates outgoing transfers from supported Mandiri and
  Jago receipts.
- Show the amount and count of matching `needsReview` records separately as
  pending review. Pending amounts are not added to confirmed spending or
  category totals.
- Group confirmed spending by its stored category and sort the largest amount
  first. A legacy ready record with no category is shown as `Uncategorized`;
  this is an analytics label, not a category the owner can select or save.
- Let the owner open a category to inspect its matching confirmed transactions
  in the selected month, and open the selected month's full activity list.
  Full activity retains Review items with their status visible; category detail
  does not include them.
- Let the owner edit an individual transaction's category from either detail
  list. Saving a correction affects that record only, except an existing exact
  trusted bank-and-merchant rule is corrected for future imports. This never
  recategorizes historical records.
- Group the same confirmed spending by source. Current readable sources include
  BCA, Mandiri, Jago, OCTO CIMB, Cash, and E-wallet. Source totals use the
  stored transaction source and sort largest amount first. A source row is
  tappable and opens only its matching confirmed transactions in the selected
  month.
- Preserve the confirmed-spending total if a future supported bank introduces
  another stored source. Its readable source name appears as its own row rather
  than being silently excluded or combined with an unrelated bank.
- Category totals and source totals are two views of the same confirmed
  spending and each must add up to the selected month’s confirmed total.
- Keep Dashboard compact: it shows the current month’s confirmed total and
  pending-review state, Gmail status/actions, and recent activity. It does not
  offer a month picker, category breakdown, source breakdown, or analytics
  detail sheets.
- Exclude incoming transfers, refunds, cash withdrawals, and unknown kinds
  from these spending totals.

## Non-goals

- Budgets, charts, trends, forecasts, account balances, or income reporting.
- Modifying Gmail, importing another bank, changing a transaction’s category,
  or automatically accepting Review items.
- Persisting any derived analytics values; all totals are calculated from the
  local transaction records at display time.

## Implementation Boundaries

### Always

- Keep analytics deterministic and testable in `ExpenseTrackerCore`.
- Keep each SwiftUI view as a mapper from local SwiftData records to core
  inputs. The core analytics module owns month, category, and source grouping.
- Make Review status visible rather than silently including it in spending.

### Ask first

- Including cash withdrawals, refunds, income, or a projected total in
  spending.
- Adding charts, budget targets, a different time zone, or cross-month rollups.

### Never

- Change a transaction’s status, category, or local merchant rule while
  calculating analytics.
- Count a `needsReview` transaction as confirmed spending.
- Store Gmail contents or sensitive bank fields in the analytics layer.

## Success Criteria

- The user can select the current month or a locally represented earlier month.
- The user can inspect all local activity in the selected month and each
  category's or source's confirmed transactions in that month.
- Confirmed spending excludes Review records, incoming transfers, refunds,
  cash withdrawals, and transactions outside the selected calendar month.
- Pending-review amount and count are shown independently for the selected
  month.
- Category totals add up to confirmed spending, except for the explicit
  `Uncategorized` grouping where applicable.
- Source totals add up to confirmed spending, including manual Cash and
  E-wallet entries.
- Transactions can be switched between the normal ledger and Analytics without
  moving to another tab.
- Dashboard contains no duplicate analytics drill-down controls.
- Unit tests cover month filtering, transaction-kind filtering, category and
  source grouping, pending-review separation, and an empty current month.

## Commands

Focused test:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test --filter SpendingAnalyticsTests
```

Full test suite:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test
```

## Implementation Status

Transactions owns the month picker, category breakdown, source breakdown, and
drill-down lists. Dashboard now keeps compact current-month, Gmail, Review,
and recent-activity context. Core tests, CoreVerification, and the unsigned
simulator build pass; a manual Analytics navigation check is optional.
