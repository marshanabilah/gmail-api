from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Optional


@dataclass(frozen=True)
class TransactionDraft:
    source_message_id: str
    bank_id: str
    occurred_at: datetime
    merchant: str
    amount: Decimal
    kind: str
    confidence: float

    @property
    def fingerprint(self) -> str:
        merchant = " ".join(self.merchant.casefold().split())
        return "|".join((
            self.bank_id,
            self.occurred_at.isoformat(),
            str(self.amount),
            self.kind,
            merchant,
        ))

    @property
    def needs_category(self) -> bool:
        return self.kind in {"card_purchase", "qris_payment", "cash_withdrawal", "fee"}


@dataclass(frozen=True)
class ParsedEmail:
    status: str
    draft: Optional[TransactionDraft] = None
