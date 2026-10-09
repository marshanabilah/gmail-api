# Expense Tracker

A personal iPhone expense tracker that imports transaction emails from Gmail, keeps the ledger on the device, and sends uncertain imports to review instead of asking for routine manual entry.

The app is designed for Indonesian rupiah transactions and will support Mandiri, BCA, Jago, and OCTO CIMB as their email formats are added.

## Current state

The project contains a native SwiftUI foundation and a local import core.

- Local SwiftData models for transactions and learned merchant categories
- Dashboard, transaction history, and review screens
- Google Sign-In foundation for one Gmail account, with Gmail read-only access only
- Duplicate protection using Gmail message IDs and transaction fingerprints
- BCA QRIS email parsing for successful transactions
- Jago debit-card email parsing, sent to review because the alert does not include a merchant or transaction timestamp
- Merchant corrections that create a local matching rule for future imports

The app can start Google authorization after you add your own iOS OAuth client
configuration. It does not download Gmail messages yet. The next capability is
reading the user-maintained `Ledger/BCA` label for an initial 90-day scan.

## Privacy model

Gmail is an import source, not the place where the ledger lives.

- The intended OAuth scope is `gmail.readonly`.
- The transaction store is local to the device.
- Parsers extract only the fields needed for the ledger.
- Account numbers, PANs, terminal IDs, and bank reference numbers are not persisted as transactions.
- Categorization rules stay on the device.

An optional cloud categorizer may be added later, but it should receive only a normalized merchant name and transaction context, never a complete bank email.

## Import flow

```text
Gmail, read-only
  → identify bank transaction alerts
  → parse bank-specific fields on device
  → reject duplicates
  → apply local merchant rules
  → save to the local ledger
  → send uncertain imports to Review
  → save approved category as a local merchant rule
```

## Supported message formats

| Bank | Transaction | Result |
| --- | --- | --- |
| BCA | Successful QRIS payment email with transaction date, merchant, and total payment | High-confidence transaction |
| Jago | Debit-card alert containing only an amount | Low-confidence transaction in Review |
| OCTO CIMB | Successful transfer between own CIMB Niaga accounts | High-confidence transfer, excluded from spending |
| Mandiri | Successful Livin' transfer with recipient, date, time, and amount | Low-confidence transfer in Review |

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

This checks the import policy, duplicate handling, merchant categorization, BCA QRIS parsing, and Jago debit-card parsing with redacted fixtures.

### Run the unit tests

```sh
swift test
```

This includes category tests for custom names, duplicate prevention, and the built-in category list.

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
