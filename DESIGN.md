# Expense tracker design direction

## Product

A personal iPhone expense tracker that imports bank transaction emails from Gmail, keeps financial data on the device, and asks for review only when an import is uncertain.

## Audience

One person tracking daily spending in Indonesian rupiah across Mandiri, BCA, Jago, and OCTO CIMB. They need to trust the numbers quickly, without maintaining a spreadsheet or manually entering routine transactions.

## Visual language

Quiet and grounded, closer to a well-kept personal ledger than a fintech marketing product. The interface uses paper-like warm neutrals for reading comfort, dense but breathable transaction lists, and a restrained deep-teal accent for the next action or selected state. A muted terracotta status is reserved for imports that need review, so uncertainty is visible without feeling alarming.

## Palette

- Base: warm off-white and charcoal text.
- Structure: soft stone neutral for dividers and secondary surfaces.
- Accent: deep teal for a selected state, primary action, and focus treatment.
- Review: muted terracotta only for a real needs-review state.

## Typography

Use the system San Francisco family. It is familiar on iPhone, supports Dynamic Type, and keeps transaction details more legible than a decorative brand typeface.

## Layout

The primary screen answers one question first: what did I spend this month, and which imports need attention? The balance and review count lead, followed by category context and a transaction list. A compact bottom navigation provides Dashboard, Transactions, and Review, with reserved safe-area space.

## Identity motif

Transactions use a short, left-aligned source line (bank and timestamp) above the merchant and amount. This repeated ledger rhythm makes imported records easy to scan without ornamental graphics.

## Dials

ENERGY 1 / RHYTHM 2 / MOTION 1

## Decision reasons

- Warm neutrals reduce the financial-dashboard feel and make frequent review comfortable.
- Deep teal appears only on the active decision point, preserving a clear visual focal point.
- Terracotta encodes only a real uncertainty state, never decoration.
- System typography preserves iOS familiarity and accessibility at every Dynamic Type size.
- The ledger-like source line helps the user verify imported transactions quickly.
- Motion is limited to native state transitions, so the data remains the focus.
