import os
from datetime import datetime
from pathlib import Path
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, Field

from .parsers import parse_email
from .storage import TransactionStore


DATABASE_PATH = os.getenv("EXPENSE_TRACKER_DB", str(Path("backend/data/expense-tracker.sqlite3")))
store = TransactionStore(DATABASE_PATH)
app = FastAPI(title="Expense Tracker API", version="0.1.0")


class ImportRequest(BaseModel):
    message_id: str = Field(min_length=1)
    body: str = Field(min_length=1)
    received_at: datetime


class ReviewRequest(BaseModel):
    category: str = Field(min_length=1, max_length=80)


def require_api_key(x_api_key: Optional[str] = Header(default=None)) -> None:
    expected = os.getenv("EXPENSE_TRACKER_API_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Set EXPENSE_TRACKER_API_TOKEN before using private endpoints.",
        )
    if x_api_key != expected:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid API key.")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/gmail/configuration", dependencies=[Depends(require_api_key)])
def gmail_configuration() -> dict:
    return {
        "configured": bool(os.getenv("GOOGLE_CLIENT_ID") and os.getenv("GOOGLE_CLIENT_SECRET")),
        "scope": "https://www.googleapis.com/auth/gmail.readonly",
    }


@app.post("/v1/imports/preview", dependencies=[Depends(require_api_key)])
def preview_import(request: ImportRequest) -> dict:
    parsed = parse_email(request.message_id, request.body, request.received_at)
    if parsed.draft is None:
        return {"status": parsed.status, "transaction": None}
    return {"status": parsed.status, "transaction": _draft_payload(parsed.draft)}


@app.post("/v1/imports", dependencies=[Depends(require_api_key)])
def import_email(request: ImportRequest) -> dict:
    parsed = parse_email(request.message_id, request.body, request.received_at)
    if parsed.draft is None:
        return {"status": parsed.status, "transaction": None}
    transaction = store.import_draft(parsed.draft)
    if transaction is None:
        return {"status": "duplicate", "transaction": None}
    return {"status": "imported", "transaction": transaction}


@app.get("/v1/transactions", dependencies=[Depends(require_api_key)])
def transactions() -> List[dict]:
    return store.transactions()


@app.get("/v1/review", dependencies=[Depends(require_api_key)])
def review_queue() -> List[dict]:
    return store.transactions(review_only=True)


@app.post("/v1/review/{transaction_id}", dependencies=[Depends(require_api_key)])
def approve_review(transaction_id: str, request: ReviewRequest) -> dict:
    transaction = store.approve(transaction_id, request.category)
    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found.")
    return transaction


def _draft_payload(draft) -> dict:
    return {
        "source_message_id": draft.source_message_id,
        "bank_id": draft.bank_id,
        "occurred_at": draft.occurred_at.isoformat(),
        "merchant": draft.merchant,
        "amount": str(draft.amount),
        "kind": draft.kind,
        "confidence": draft.confidence,
    }
