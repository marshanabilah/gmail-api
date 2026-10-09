import sys
import tempfile
import unittest
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain import TransactionDraft
from app.parsers import parse_email
from app.storage import TransactionStore


class ParserTests(unittest.TestCase):
    def test_bca_qris_email_parses(self):
        parsed = parse_email(
            "bca-1",
            """Status : Successful
Transaction Date : 08 Oct 2026 17:54:32
Transaction Type : QRIS Payment
Payment to : Example Store
Total Payment : IDR 3,800.00""",
            datetime(2026, 10, 8, 10, 54, 32, tzinfo=timezone.utc),
        )
        self.assertEqual(parsed.status, "transaction")
        self.assertEqual(parsed.draft.amount, Decimal("3800.00"))
        self.assertEqual(parsed.draft.merchant, "Example Store")

    def test_jago_email_requires_review_after_import(self):
        parsed = parse_email(
            "jago-1",
            "You have recently made a transaction of Rp52.200 using your Jago debit card.",
            datetime(2026, 10, 8, 10, 54, 32, tzinfo=timezone.utc),
        )
        self.assertEqual(parsed.draft.confidence, 0.55)


class StoreTests(unittest.TestCase):
    def test_duplicate_message_is_not_imported_twice(self):
        with tempfile.TemporaryDirectory() as directory:
            store = TransactionStore(str(Path(directory) / "tracker.sqlite3"))
            draft = TransactionDraft(
                "message-1", "bca", datetime(2026, 10, 8, tzinfo=timezone.utc),
                "Example Store", Decimal("3800"), "qris_payment", 0.99,
            )
            self.assertIsNotNone(store.import_draft(draft))
            self.assertIsNone(store.import_draft(draft))

    def test_approved_review_creates_a_merchant_rule(self):
        with tempfile.TemporaryDirectory() as directory:
            store = TransactionStore(str(Path(directory) / "tracker.sqlite3"))
            draft = TransactionDraft(
                "message-2", "jago", datetime(2026, 10, 8, tzinfo=timezone.utc),
                "Example Merchant", Decimal("52000"), "card_purchase", 0.55,
            )
            imported = store.import_draft(draft)
            approved = store.approve(imported["id"], "Shopping")
            self.assertEqual(approved["status"], "ready")
            self.assertEqual(store.category_for("Example Merchant Branch"), "Shopping")
