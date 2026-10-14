# Spec: Monthly Spending Analytics

Module id: `spending-analytics`

## Objective

Give the owner a reliable view of spending for any imported calendar month,
without treating unreviewed Gmail imports as confirmed money spent. The
dashboard makes it possible to choose a month and see confirmed spending
grouped by the owner’s existing categories.

## Scope

- Offer the current month and every month that has at least one local
  transaction.
- Calculate month boundaries using the iPhone’s current calendar and time
  zone.
- Show one confirmed-spending total, based only on `ready` records whose kind
  is a card purchase, QRIS payment, fee, or manual expense.
- Show the amount and count of matching `needsReview` records separately as
  pending review. Pending amounts are not added to confirmed spending or
  category totals.
- Group confirmed spending by its stored category and sort the largest amount
  first. A legacy ready record with no category is shown as `Uncategorized`;
  this is an analytics label, not a category the owner can select or save.
- Exclude transfers, refunds, cash withdrawals, and unknown kinds from these
  spending totals.

## Non-goals

- Budgets, charts, trends, forecasts, account balances, or income reporting.
- Modifying Gmail, importing another bank, changing a transaction’s category,
  or automatically accepting Review items.
- Persisting any derived analytics values; all totals are calculated from the
  local transaction records at display time.

## Implementation Boundaries

### Always

- Keep analytics deterministic and testable in `ExpenseTrackerCore`.
- Keep the dashboard as a mapper from local SwiftData records to core inputs.
- Make Review status visible rather than silently including it in spending.

### Ask first

- Including transfers, cash withdrawals, refunds, income, or a projected
  total in spending.
- Adding charts, budget targets, a different time zone, or cross-month rollups.

### Never

- Change a transaction’s status, category, or local merchant rule while
  calculating analytics.
- Count a `needsReview` transaction as confirmed spending.
- Store Gmail contents or sensitive bank fields in the analytics layer.

## Success Criteria

- The user can select the current month or a locally represented earlier month.
- Confirmed spending excludes Review records, transfers, refunds, cash
  withdrawals, and transactions outside the selected calendar month.
- Pending-review amount and count are shown independently for the selected
  month.
- Category totals add up to confirmed spending, except for the explicit
  `Uncategorized` grouping where applicable.
- Unit tests cover month filtering, transaction-kind filtering, category
  grouping, pending-review separation, and an empty current month.

## Commands

Focused test:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test --filter SpendingAnalyticsTests
```

Full test suite:

```sh
TASK_CLANG_CACHE=/private/tmp/expense-tracker-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/expense-tracker-swiftpm-cache CLANG_MODULE_CACHE_PATH=/private/tmp/expense-tracker-clang-cache swift test
```
