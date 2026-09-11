"""Pure-Python validation and normalization helpers for broker claim CSVs.

The Glue job contains the distributed equivalent of these rules. Keeping the
small contract logic dependency-free makes it possible to test the V1 happy
path without Spark or AWS credentials.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from hashlib import sha256
from dataclasses import dataclass
from typing import Iterable, Mapping

from src.reliability.control import PipelineAudit, QuarantineRecord, file_identity, reconcile_batch

REQUIRED_COLUMNS = (
    "claim_id",
    "claim_number",
    "policy_id",
    "customer_id",
    "claim_status",
    "incident_date",
    "submitted_at",
    "claim_amount",
    "approved_amount",
    "currency_code",
    "description",
    "updated_at",
)
VALID_CLAIM_STATUSES = frozenset(
    {"SUBMITTED", "UNDER_REVIEW", "APPROVED", "REJECTED", "PAID", "CLOSED"}
)
MONEY_QUANTUM = Decimal("0.01")


@dataclass(frozen=True)
class BatchFileResult:
    """Outcome of one logical file before persistence to trusted layers."""

    source_file_id: str
    accepted: tuple[dict[str, object], ...]
    quarantined: tuple[QuarantineRecord, ...]
    audit: PipelineAudit


def validate_headers(headers: Iterable[str]) -> list[str]:
    """Return schema errors; additional nullable columns are forward compatible."""

    normalized = [str(header).strip() for header in headers]
    errors: list[str] = []
    duplicates = sorted({header for header in normalized if normalized.count(header) > 1})
    if duplicates:
        errors.append(f"duplicate columns: {','.join(duplicates)}")
    missing = [column for column in REQUIRED_COLUMNS if column not in normalized]
    if missing:
        errors.append(f"missing columns: {','.join(missing)}")
    return errors


def _text(value: object) -> str:
    return "" if value is None else str(value).strip()


def _timestamp(value: object) -> datetime | None:
    text = _text(value)
    if not text:
        return None
    parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def _money(value: object, field: str, errors: list[str], *, required: bool) -> Decimal | None:
    text = _text(value)
    if not text:
        if required:
            errors.append(f"{field} is required")
        return None
    try:
        amount = Decimal(text).quantize(MONEY_QUANTUM, rounding=ROUND_HALF_UP)
    except (InvalidOperation, ValueError):
        errors.append(f"{field} is not a decimal amount")
        return None
    if amount < 0:
        errors.append(f"{field} must be non-negative")
    return amount


def normalize_claim_row(
    row: Mapping[str, object], *, run_id: str, source_object: str, ingested_at: datetime
) -> tuple[dict[str, object] | None, list[str]]:
    """Normalize one CSV row and return ``(record, errors)``."""

    errors: list[str] = []
    record = {column: _text(row.get(column)) for column in REQUIRED_COLUMNS}
    record["claim_status"] = record["claim_status"].upper()
    record["currency_code"] = record["currency_code"].upper()
    for field in ("claim_id", "claim_number", "policy_id", "customer_id", "claim_status", "currency_code", "submitted_at", "updated_at", "incident_date"):
        if not record[field]:
            errors.append(f"{field} is required")
    if record["claim_status"] and record["claim_status"] not in VALID_CLAIM_STATUSES:
        errors.append("claim_status is not an allowed value")
    if record["currency_code"] and len(record["currency_code"]) != 3:
        errors.append("currency_code must be a 3-character ISO code")

    parsed_incident: date | None = None
    for field in ("incident_date",):
        if record[field]:
            try:
                parsed_incident = date.fromisoformat(record[field])
            except ValueError:
                errors.append(f"{field} is not an ISO date")

    submitted: datetime | None = None
    updated: datetime | None = None
    for field in ("submitted_at", "updated_at"):
        if record[field]:
            try:
                parsed = _timestamp(record[field])
                if field == "submitted_at":
                    submitted = parsed
                else:
                    updated = parsed
            except ValueError:
                errors.append(f"{field} is not an ISO-8601 timestamp with timezone")
    if parsed_incident and submitted and parsed_incident > submitted.date():
        errors.append("incident_date cannot be after submitted_at")
    if submitted and updated and updated < submitted:
        errors.append("updated_at cannot be before submitted_at")

    claim_amount = _money(record["claim_amount"], "claim_amount", errors, required=True)
    approved_amount = _money(record["approved_amount"], "approved_amount", errors, required=False)
    if claim_amount is not None and approved_amount is not None and approved_amount > claim_amount:
        errors.append("approved_amount cannot exceed claim_amount")
    if errors:
        return None, errors

    canonical = "|".join(record[column] for column in REQUIRED_COLUMNS)
    normalized = dict(record)
    normalized.update(
        {
            "incident_date": parsed_incident,
            "submitted_at": submitted,
            "updated_at": updated,
            "claim_amount": claim_amount,
            "approved_amount": approved_amount,
            "_run_id": _text(run_id),
            "_source_system": "broker_csv",
            "_source_object": _text(source_object),
            "_ingested_at": ingested_at.astimezone(timezone.utc),
            "_record_hash": sha256(canonical.encode("utf-8")).hexdigest(),
            "_schema_version": 1,
        }
    )
    return normalized, []


def deduplicate_claims(records: Iterable[Mapping[str, object]]) -> list[dict[str, object]]:
    """Keep the newest update per claim_id, deterministically."""

    latest: dict[str, tuple[datetime, int, Mapping[str, object]]] = {}
    for position, record in enumerate(records):
        claim_id = _text(record.get("claim_id"))
        updated = record.get("updated_at")
        if not claim_id or not isinstance(updated, datetime):
            continue
        current = latest.get(claim_id)
        if current is None or (updated, position) >= (current[0], current[1]):
            latest[claim_id] = (updated, position, record)
    return [dict(item[2]) for item in sorted(latest.values(), key=lambda item: _text(item[2].get("claim_id")))]


def build_claim_daily_summary(records: Iterable[Mapping[str, object]]) -> list[dict[str, object]]:
    """Build the Gold daily summary grain used by Athena/BI."""

    grouped: dict[tuple[date, str, str], dict[str, object]] = {}
    for record in records:
        key = (record["incident_date"], _text(record["claim_status"]), _text(record["currency_code"]))
        current = grouped.setdefault(
            key,
            {
                "incident_date": key[0],
                "claim_status": key[1],
                "currency_code": key[2],
                "claim_count": 0,
                "total_claim_amount": Decimal("0.00"),
                "total_approved_amount": Decimal("0.00"),
            },
        )
        current["claim_count"] += 1
        current["total_claim_amount"] += record["claim_amount"]
        current["total_approved_amount"] += record.get("approved_amount") or Decimal("0.00")
    return [grouped[key] for key in sorted(grouped)]


def process_claim_file(
    rows: Iterable[Mapping[str, object]],
    *,
    content: bytes,
    run_id: str,
    source_object: str,
    ingested_at: datetime,
    processed_file_ids: set[str] | frozenset[str] = frozenset(),
) -> BatchFileResult:
    """Validate a file with content identity, quarantine, and reconciliation.

    A file already present in ``processed_file_ids`` is a successful duplicate
    no-op. Within a new file, invalid rows are quarantined and repeated claim
    versions are deterministically collapsed before trusted output.
    """

    materialized = [dict(row) for row in rows]
    source_file_id = file_identity(content)
    audit = PipelineAudit(
        run_id=run_id,
        pipeline_name="batch-file",
        source=source_object,
        stage="silver",
        source_identity=source_file_id,
    )
    if source_file_id in processed_file_ids:
        audit.finish(
            "DUPLICATE",
            input_count=len(materialized),
            output_count=0,
            duplicate_count=len(materialized),
            reconciliation_passed=True,
        )
        return BatchFileResult(source_file_id, (), (), audit)

    valid: list[dict[str, object]] = []
    quarantined: list[QuarantineRecord] = []
    for row in materialized:
        record, errors = normalize_claim_row(
            row, run_id=run_id, source_object=source_object, ingested_at=ingested_at
        )
        if record is not None:
            record["_source_file_id"] = source_file_id
            valid.append(record)
        else:
            quarantined.append(
                QuarantineRecord.create(
                    run_id=run_id,
                    source=source_object,
                    entity="claim",
                    source_record=row,
                    failed_rules=errors,
                    rejected_at=ingested_at,
                )
            )

    accepted = deduplicate_claims(valid)
    duplicate_count = len(valid) - len(accepted)
    reconciled = reconcile_batch(
        input_count=len(materialized),
        output_count=len(accepted),
        rejected_count=len(quarantined),
        duplicate_count=duplicate_count,
    )
    status = "SUCCEEDED" if accepted or not quarantined else "QUARANTINED"
    audit.finish(
        status,
        input_count=len(materialized),
        output_count=len(accepted),
        rejected_count=len(quarantined),
        duplicate_count=duplicate_count,
        reconciliation_passed=reconciled,
    )
    return BatchFileResult(source_file_id, tuple(accepted), tuple(quarantined), audit)
