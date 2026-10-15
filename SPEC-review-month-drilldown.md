# Spec: Analytics Pending Review Month Drill-down

Module id: `review-month-drilldown`

## Objective

Make a monthly Analytics pending-review total actionable. When the owner taps
the pending-review row for a selected month, the app switches to Review and
displays only that month's pending items, newest first. Dashboard retains its
compact current-month pending-review summary but never lists pending items.

## User Flow

1. Transactions → Analytics shows the selected month's pending-review amount
   and count.
2. Tapping that row selects the Review tab and passes the selected Analytics
   month to Review.
3. Review shows a clear `October 2026 · Pending review` context and lists only
   `needsReview` transactions in that month, sorted newest first.
4. The owner can accept, categorize, discard, or edit an item exactly as in
   the unfiltered Review flow.
5. A visible `Show all` control removes the month filter and returns to the
   normal all-pending list. Returning to Dashboard does not alter data.

## Boundaries

### Always

- Use the selected Analytics month and the app's Jakarta calendar.
- Keep Dashboard's compact pending-review total and count, without a pending
  transaction list or month drill-down.
- Keep all pending transactions accessible through `Show all`.
- Preserve current accept, category, discard, merchant-rule, and duplicate
  behavior.
- Keep filtering local; no Gmail call or data migration is involved.

### Never

- Hide pending items outside the chosen month without a clear filter label.
- Change transaction status, category, source, or month merely by navigation.
- Route a pending amount to Transactions or Analytics instead of Review.

## Testing Strategy

- Add pure date-filter tests for same-month inclusion and adjacent-month
  exclusion in `Asia/Jakarta`.
- Verify Analytics navigation selects Review with the intended month.
- Verify `Show all` restores every pending item and Review actions continue to
  work under either scope.
- Run the full suite and unsigned simulator build; a manual tap-through is
  optional after automated verification.

## Success Criteria

- Tapping an Analytics month’s pending-review total opens Review scoped to
  that month.
- The newest pending item for that month appears first.
- The filter is visible and reversible with `Show all`.
- Existing Review behavior and automated verification remain intact.
