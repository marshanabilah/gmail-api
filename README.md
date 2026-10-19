# Expense Tracker

A personal iPhone expense tracker that imports transaction emails from Gmail, keeps the ledger on the device, and sends uncertain imports to review instead of asking for routine manual entry.

The app is designed for Indonesian rupiah transactions. BCA, Livin' by
Mandiri, supported OCTO CIMB QR purchases, and the supported Jago receipt
formats are connected to the Gmail Review flow.

## Current state

The project contains a native SwiftUI foundation and a local import core.

- Local SwiftData models for transactions and learned merchant categories
- Dashboard, transaction history, analytics, and review screens
- Month-by-month confirmed-spending totals with category and source breakdowns
  in Transactions; pending Review items are shown separately rather than
  counted as spending
- Google Sign-In for one Gmail account, with Gmail read-only access only
- Manual 90-day scans of the owner-maintained `Transaction` Gmail label
- A labeled message that Gmail refuses to return is skipped without discarding
  the rest of the scan; the app reports how many messages it skipped
- Duplicate protection using Gmail message IDs and transaction fingerprints
- A local Review discard action that removes a non-spending item and prevents
  the same Gmail message from being imported again
- BCA QRIS payments, supported Livin' by Mandiri transactions, and supported
  OCTO CIMB QR purchases imported through a deliberate Review flow
- Local suggestion rules plus exact trusted rules for routine QR/card purchases
- Saving a Review item can suggest its category to matching pending items;
  those items remain pending, while eligible saved purchases teach exact future
  imports automatically
- Manual cash and e-wallet entries, custom categories, transaction deletion, and light/dark appearance

The app reads only the owner-maintained `Transaction` label when they tap
Sync Gmail. It does not modify Gmail and does not run in the background.

## Privacy model

Gmail is an import source, not the place where the ledger lives.

- The intended OAuth scope is `gmail.readonly`.
- The transaction store is local to the device.
- Parsers extract only the fields needed for the ledger.
- Account numbers, PANs, terminal IDs, and bank reference numbers are not persisted as transactions.
- Discard markers retain only a Gmail message ID, not bank or transaction data.
- Categorization rules stay on the device.

An optional cloud categorizer may be added later, but it should receive only a normalized merchant name and transaction context, never a complete bank email.

## Import flow

```text
Gmail, read-only
  → identify bank transaction alerts
  → parse bank-specific fields on device
  → reject duplicates
  → exact trusted QR/card matches go directly to the local ledger
  → other supported transactions receive a category suggestion when available and enter Review
  → saving or accepting an eligible Review purchase teaches its exact bank-and-merchant rule
  → transfers, top-ups, fuzzy matches, and merchant-less debit alerts stay in Review
  → owner may discard an item that does not belong in the ledger
  → save the accepted transaction and update the local merchant rule
```

Mandiri transfers and e-money top-ups are stored as outgoing transfers and
always appear in Review. Mandiri QR payments are stored as payments and may
enter Transactions directly when an exact trusted rule applies. Once accepted
or trusted, they count toward confirmed spending totals.

## Supported message formats

| Bank | Transaction | Result |
| --- | --- | --- |
| BCA | Successful QRIS payment email with transaction date, merchant, and total payment | Imported to Review, unless an exact trusted BCA merchant rule applies |
| Jago | Structured payment receipt with destination, time, and amount | Imported to Review, unless an exact trusted Jago merchant rule applies |
| Jago | Transfer or e-wallet top-up receipt with destination, time, and amount | Imported to Review; accepted items count as spending |
| Jago | Debit-card alert containing only an amount | Imported to Review as `Jago debit card spending`, using Gmail receipt time provisionally; edit the local description before or after categorizing if helpful |
| OCTO CIMB | OCTO App Purchase with QR receipt with transaction time, merchant, and total payment | Imported to Review, unless an exact trusted OCTO CIMB merchant rule applies |
| OCTO CIMB | Own-account transfer receipt | Parsed only; not imported in the current Gmail flow |
| Mandiri | Successful Livin' payment with its required receipt fields | Imported to Review, unless an exact trusted Mandiri merchant rule applies |
| Mandiri | Successful Livin' transfer or e-money top-up with its required receipt fields | Imported to Review; accepted items count as spending |

## Development

### Requirements

- macOS
- Full Xcode with the iOS simulator, not Command Line Tools alone
- iOS 17 or later
- A Google Cloud project with the Gmail API enabled
- An iOS OAuth client configured for the app bundle identifier

### Run the import-core verification

```sh
swift run CoreVerification
```

This checks the import policy, duplicate handling, merchant categorization,
BCA QRIS parsing, Mandiri receipt parsing, and Jago debit-card parsing with
redacted fixtures.

### Run the unit tests

```sh
swift test
```

This includes category, Gmail sync, BCA and Mandiri import,
duplicate-prevention, analytics, and merchant-rule tests using synthetic,
redacted fixtures.

### Gmail configuration

The iOS app expects two configuration values:

- `GmailClientID`
- `GmailRedirectScheme`

Create an iOS OAuth client in Google Cloud for
`com.marshanabilah.expensetracker`. In the target's Build Settings, add its
non-secret client ID as `GmailClientID` and its Google-issued iOS URL scheme as
`GmailRedirectScheme`. The app has no client secret and uses the SDK-managed
Keychain state for its local sign-in session.

Use an iOS OAuth client and request only `https://www.googleapis.com/auth/gmail.readonly`. Google’s Gmail scope documentation explains why this is the least-privileged scope that can read the email content required for parsing: <https://developers.google.com/workspace/gmail/api/auth/scopes>.

The project resolves Google Sign-In through Swift Package Manager. Its
configuration and callback behavior follow Google's iOS setup guide:
<https://developers.google.com/identity/sign-in/ios/start-integrating>.

## Adding a bank parser

Send a redacted copy of at least a few transaction emails for each bank. Preserve the field labels, ordering, and transaction types. Replace names, account numbers, PANs, reference IDs, merchants, and amounts with safe example values if needed.

Each parser should:

1. Accept only a clearly recognized bank email format.
2. Ignore failed, reversed, or promotional messages.
3. Extract only the data needed for a transaction.
4. Set a lower confidence score when merchant, amount, or timestamp is missing.
5. Send ambiguous records to Review.

## Design direction

The app’s intended visual language is recorded in [DESIGN.md](DESIGN.md). It is a calm, ledger-like interface with warm neutrals, a deep-teal action color, and terracotta reserved for a real needs-review state.
