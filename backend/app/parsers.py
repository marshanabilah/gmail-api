import re
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Dict, Optional

from .domain import ParsedEmail, TransactionDraft


JAKARTA = timezone(timedelta(hours=7))


def parse_email(message_id: str, body: str, received_at: datetime) -> ParsedEmail:
    for parser in (parse_bca_qris, parse_jago_debit_card, parse_octo_cimb_transfer, parse_mandiri_transfer):
        result = parser(message_id, body, received_at)
        if result.status != "unsupported":
            return result
    return ParsedEmail(status="unsupported")


def parse_bca_qris(message_id: str, body: str, received_at: datetime) -> ParsedEmail:
    fields = _colon_fields(body)
    if not fields:
        return ParsedEmail(status="unsupported")
    if fields.get("status", "").casefold() != "successful":
        return ParsedEmail(status="ignored")
    if fields.get("transaction type", "").casefold() != "qris payment":
        return ParsedEmail(status="unsupported")
    occurred_at = _date(fields.get("transaction date"), "%d %b %Y %H:%M:%S")
    amount = _idr(fields.get("total payment"), decimal_separator=".")
    merchant = fields.get("payment to")
    if not all((occurred_at, amount is not None, merchant)):
        return ParsedEmail(status="unsupported")
    return ParsedEmail("transaction", TransactionDraft(
        message_id, "bca", occurred_at, merchant, amount, "qris_payment", 0.99
    ))


def parse_jago_debit_card(message_id: str, body: str, received_at: datetime) -> ParsedEmail:
    if "using your jago debit card" not in body.casefold():
        return ParsedEmail(status="unsupported")
    amount = _first_idr(body, decimal_separator=",")
    if amount is None:
        return ParsedEmail(status="unsupported")
    return ParsedEmail("transaction", TransactionDraft(
        message_id, "jago", received_at, "Jago debit card transaction", amount, "card_purchase", 0.55
    ))


def parse_octo_cimb_transfer(message_id: str, body: str, received_at: datetime) -> ParsedEmail:
    if "octo app transaction" not in body.casefold():
        return ParsedEmail(status="unsupported")
    fields = _stacked_fields(body)
    if fields.get("status", "").casefold() != "success":
        return ParsedEmail(status="ignored")
    transaction_type = fields.get("transaction type")
    occurred_at = _date(fields.get("date/time"), "%d %B %Y %H:%M:%S")
    amount = _idr(fields.get("transfer amount"), decimal_separator=".")
    if not all((transaction_type, occurred_at, amount is not None)):
        return ParsedEmail(status="unsupported")
    kind = "transfer_out" if "to own" in transaction_type.casefold() else "unknown"
    confidence = 0.99 if kind == "transfer_out" else 0.7
    return ParsedEmail("transaction", TransactionDraft(
        message_id, "octo_cimb", occurred_at, transaction_type, amount, kind, confidence
    ))


def parse_mandiri_transfer(message_id: str, body: str, received_at: datetime) -> ParsedEmail:
    if "transfer successful" not in body.casefold():
        return ParsedEmail(status="unsupported")
    recipient = _mandiri_recipient(body)
    date = _table_or_stacked_field(body, "Date")
    time = _table_or_stacked_field(body, "Time")
    amount = _idr(_table_or_stacked_field(body, "Transfer Amount"), decimal_separator=",")
    occurred_at = _date("{} {}".format(date or "", (time or "").replace(" WIB", "")), "%d %b %Y %H:%M:%S")
    if not all((recipient, occurred_at, amount is not None)):
        return ParsedEmail(status="unsupported")
    return ParsedEmail("transaction", TransactionDraft(
        message_id, "mandiri", occurred_at, recipient, amount, "transfer_out", 0.75
    ))


def _colon_fields(body: str) -> Dict[str, str]:
    fields = {}
    for line in body.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key, value = key.strip(), value.strip()
        if key and value:
            fields[key.casefold()] = value
    return fields


def _stacked_fields(body: str) -> Dict[str, str]:
    labels = {"date/time", "transaction type", "transfer amount", "status"}
    fields = {}
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    for index, line in enumerate(lines[:-1]):
        if line.rstrip(":").casefold() in labels:
            fields[line.rstrip(":").casefold()] = lines[index + 1]
    return fields


def _table_or_stacked_field(body: str, label: str) -> Optional[str]:
    wanted = label.casefold()
    lines = [line.strip() for line in body.splitlines() if line.strip()]
    for index, line in enumerate(lines):
        cells = [cell.strip() for cell in line.split("|", 1)]
        if len(cells) == 2 and cells[0].casefold() == wanted:
            return cells[1]
        if line.rstrip(":").casefold() == wanted and index + 1 < len(lines):
            return lines[index + 1]
    return None


def _mandiri_recipient(body: str) -> Optional[str]:
    lines = [line.strip().strip("#").strip() for line in body.splitlines()]
    try:
        start = next(index for index, line in enumerate(lines) if line.casefold() == "recipient")
    except StopIteration:
        return None
    for line in lines[start + 1:]:
        if line and "bank mandiri" not in line.casefold():
            return line
    return None


def _first_idr(value: str, decimal_separator: str) -> Optional[Decimal]:
    match = re.search(r"Rp\s*([0-9.,]+)", value, flags=re.IGNORECASE)
    return _idr(match.group(0) if match else None, decimal_separator)


def _idr(value: Optional[str], decimal_separator: str) -> Optional[Decimal]:
    if not value:
        return None
    numeric = re.sub(r"(?i)IDR|RP|\s", "", value)
    if decimal_separator == ",":
        numeric = numeric.replace(".", "").replace(",", ".")
    else:
        numeric = numeric.replace(",", "")
    try:
        return Decimal(numeric)
    except InvalidOperation:
        return None


def _date(value: Optional[str], pattern: str) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.strptime(value, pattern).replace(tzinfo=JAKARTA)
    except ValueError:
        return None
