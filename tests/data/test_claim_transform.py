from datetime import datetime, timezone
from decimal import Decimal

from src.batch.claim_transform import (
    REQUIRED_COLUMNS,
    build_claim_daily_summary,
    deduplicate_claims,
    normalize_claim_row,
    validate_headers,
)


def _row(**overrides):
    row = {
        "claim_id": "clm_1",
        "claim_number": "BRK-1",
        "policy_id": "pol_1",
        "customer_id": "cus_1",
        "claim_status": "approved",
        "incident_date": "2026-09-01",
        "submitted_at": "2026-09-02T10:00:00Z",
        "claim_amount": "10.00",
        "approved_amount": "8.00",
        "currency_code": "aud",
        "description": "synthetic fixture",
        "updated_at": "2026-09-02T11:00:00Z",
    }
    row.update(overrides)
    return row


def test_schema_requires_all_claim_columns():
    assert validate_headers(REQUIRED_COLUMNS) == []
    assert "missing columns: claim_id" in validate_headers([column for column in REQUIRED_COLUMNS if column != "claim_id"])


def test_normalize_claim_row_standardizes_types_and_metadata():
    record, errors = normalize_claim_row(
        _row(),
        run_id="run-1",
        source_object="s3://landing/batch/claims.csv",
        ingested_at=datetime(2026, 9, 2, tzinfo=timezone.utc),
    )
    assert errors == []
    assert record["claim_status"] == "APPROVED"
    assert record["claim_amount"] == Decimal("10.00")
    assert record["approved_amount"] == Decimal("8.00")
    assert record["_source_system"] == "broker_csv"
    assert record["_schema_version"] == 1
    assert len(record["_record_hash"]) == 64


def test_invalid_status_and_negative_amount_are_rejected():
    record, errors = normalize_claim_row(
        _row(claim_status="UNKNOWN", claim_amount="-1"),
        run_id="run-1",
        source_object="claims.csv",
        ingested_at=datetime.now(timezone.utc),
    )
    assert record is None
    assert "claim_status is not an allowed value" in errors
    assert "claim_amount must be non-negative" in errors


def test_required_business_keys_currency_and_date_order_are_rejected():
    record, errors = normalize_claim_row(
        _row(claim_number=" ", policy_id="", customer_id="", currency_code="AU", incident_date="2026-09-03"),
        run_id="run-1",
        source_object="claims.csv",
        ingested_at=datetime.now(timezone.utc),
    )
    assert record is None
    assert "claim_number is required" in errors
    assert "policy_id is required" in errors
    assert "customer_id is required" in errors
    assert "currency_code must be a 3-character ISO code" in errors
    assert "incident_date cannot be after submitted_at" in errors


def test_deduplicate_claims_keeps_latest_update():
    base = datetime(2026, 9, 2, tzinfo=timezone.utc)
    old = {"claim_id": "clm_1", "updated_at": base, "claim_amount": Decimal("10.00")}
    new = {"claim_id": "clm_1", "updated_at": base.replace(day=3), "claim_amount": Decimal("12.00")}
    assert deduplicate_claims([old, new]) == [new]


def test_daily_summary_uses_expected_grain_and_decimal_totals():
    records = [
        {"claim_id": "1", "incident_date": datetime(2026, 9, 1).date(), "claim_status": "APPROVED", "currency_code": "AUD", "claim_amount": Decimal("10.00"), "approved_amount": Decimal("8.00")},
        {"claim_id": "2", "incident_date": datetime(2026, 9, 1).date(), "claim_status": "APPROVED", "currency_code": "AUD", "claim_amount": Decimal("5.00"), "approved_amount": None},
    ]
    summary = build_claim_daily_summary(records)
    assert summary[0]["claim_count"] == 2
    assert summary[0]["total_claim_amount"] == Decimal("15.00")
    assert summary[0]["total_approved_amount"] == Decimal("8.00")
