import sqlite3
import threading
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from typing import Dict, Iterable, List, Optional
from uuid import uuid4

from .domain import TransactionDraft


class TransactionStore:
    def __init__(self, path: str) -> None:
        database_path = Path(path)
        database_path.parent.mkdir(parents=True, exist_ok=True)
        self.connection = sqlite3.connect(str(database_path), check_same_thread=False)
        self.connection.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        self._create_tables()

    def _create_tables(self) -> None:
        self.connection.executescript("""
            CREATE TABLE IF NOT EXISTS transactions (
                id TEXT PRIMARY KEY,
                source_message_id TEXT NOT NULL UNIQUE,
                fingerprint TEXT NOT NULL UNIQUE,
                bank_id TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                merchant TEXT NOT NULL,
                amount TEXT NOT NULL,
                kind TEXT NOT NULL,
                confidence REAL NOT NULL,
                category TEXT,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS merchant_rules (
                merchant_contains TEXT PRIMARY KEY,
                category TEXT NOT NULL
            );
        """)
        self.connection.commit()

    def import_draft(self, draft: TransactionDraft) -> Optional[Dict[str, object]]:
        with self.lock:
            category = self.category_for(draft.merchant)
            needs_review = draft.confidence < 0.9 or (draft.needs_category and category is None)
            transaction = {
                "id": str(uuid4()),
                "source_message_id": draft.source_message_id,
                "fingerprint": draft.fingerprint,
                "bank_id": draft.bank_id,
                "occurred_at": draft.occurred_at.isoformat(),
                "merchant": draft.merchant,
                "amount": str(draft.amount),
                "kind": draft.kind,
                "confidence": draft.confidence,
                "category": category,
                "status": "needs_review" if needs_review else "ready",
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            try:
                self.connection.execute("""
                    INSERT INTO transactions (
                        id, source_message_id, fingerprint, bank_id, occurred_at, merchant,
                        amount, kind, confidence, category, status, created_at
                    ) VALUES (
                        :id, :source_message_id, :fingerprint, :bank_id, :occurred_at, :merchant,
                        :amount, :kind, :confidence, :category, :status, :created_at
                    )
                """, transaction)
            except sqlite3.IntegrityError:
                return None
            self.connection.commit()
            return transaction

    def transactions(self, review_only: bool = False) -> List[Dict[str, object]]:
        with self.lock:
            query = "SELECT * FROM transactions"
            parameters = ()
            if review_only:
                query += " WHERE status = ?"
                parameters = ("needs_review",)
            query += " ORDER BY occurred_at DESC"
            return [dict(row) for row in self.connection.execute(query, parameters)]

    def approve(self, transaction_id: str, category: str) -> Optional[Dict[str, object]]:
        with self.lock:
            row = self.connection.execute(
                "SELECT merchant FROM transactions WHERE id = ?", (transaction_id,)
            ).fetchone()
            if row is None:
                return None
            merchant = row["merchant"]
            self.connection.execute(
                "UPDATE transactions SET category = ?, status = 'ready' WHERE id = ?",
                (category, transaction_id),
            )
            self.connection.execute(
                "INSERT INTO merchant_rules (merchant_contains, category) VALUES (?, ?) "
                "ON CONFLICT(merchant_contains) DO UPDATE SET category = excluded.category",
                (merchant.casefold(), category),
            )
            self.connection.commit()
            updated = self.connection.execute("SELECT * FROM transactions WHERE id = ?", (transaction_id,)).fetchone()
            return dict(updated) if updated else None

    def category_for(self, merchant: str) -> Optional[str]:
        with self.lock:
            rules = self.connection.execute("SELECT merchant_contains, category FROM merchant_rules").fetchall()
            normalized = merchant.casefold()
            for rule in rules:
                if rule["merchant_contains"] in normalized:
                    return rule["category"]
            return None
