from datetime import datetime, timezone

import pytest

from src.batch.claim_transform import process_claim_file
from src.cdc.transform import apply_changes, process_cdc_changes, source_change_id
from src.reliability.control import PipelineAudit, file_identity, reconcile_batch


def _claim(**overrides):
    row = {
        "claim_id": "clm-1", "claim_number": "BRK-1", "policy_id": "pol-1", "customer_id": "cus-1",
        "claim_status": "submitted", "incident_date": "2026-09-01", "submitted_at": "2026-09-02T00:00:00Z",
        "claim_amount": "100.00", "approved_amount": "", "currency_code": "aud", "description": "fixture",
        "updated_at": "2026-09-02T01:00:00Z",
    }
    row.update(overrides)
    return row


def _ts(day: int):
    return datetime(2026, 9, day, tzinfo=timezone.utc)


def test_file_identity_is_content_based_not_object_key_based():
    assert file_identity(b"same bytes") == file_identity(b"same bytes")
    assert file_identity(b"same bytes") != file_identity(b"changed")


def test_duplicate_file_is_traceable_noop():
    content = b"logical-file"
    result = process_claim_file(
        [_claim()], content=content, run_id="replay", source_object="s3://landing/copy.csv",
        ingested_at=_ts(2), processed_file_ids={file_identity(content)},
    )
    assert result.accepted == ()
    assert result.audit.status == "DUPLICATE"
    assert result.audit.duplicate_count == 1
    assert result.audit.reconciliation_passed is True


def test_invalid_record_is_quarantined_and_reconciled():
    result = process_claim_file(
        [_claim(claim_id="good"), _claim(claim_id="bad", claim_amount="-1")],
        content=b"new", run_id="run-2", source_object="s3://landing/new.csv", ingested_at=_ts(2),
    )
    assert [row["claim_id"] for row in result.accepted] == ["good"]
    assert len(result.quarantined) == 1
    assert "claim_amount must be non-negative" in result.quarantined[0].failed_rules
    assert result.audit.input_count == 2
    assert result.audit.output_count == 1
    assert result.audit.rejected_count == 1
    assert result.audit.reconciliation_passed is True


def test_in_file_duplicate_is_counted_and_latest_wins():
    result = process_claim_file(
        [_claim(claim_amount="100"), _claim(claim_amount="120", updated_at="2026-09-03T01:00:00Z")],
        content=b"versions", run_id="run-3", source_object="s3://landing/versions.csv", ingested_at=_ts(3),
    )
    assert len(result.accepted) == 1
    assert str(result.accepted[0]["claim_amount"]) == "120.00"
    assert result.audit.duplicate_count == 1
    assert result.audit.reconciliation_passed is True


def test_cdc_replay_and_rerun_keep_current_state():
    update = {"claim_id": "clm-1", "status": "APPROVED", "_operation": "U", "_source_order": _ts(2)}
    first = apply_changes([update, update], primary_key="claim_id")
    replay = apply_changes([update], primary_key="claim_id", current_state=first)
    assert first == replay
    assert len(replay) == 1


def test_cdc_insert_update_delete_and_older_replay():
    changes = [
        {"claim_id": "a", "status": "NEW", "_operation": "I", "_source_order": _ts(1)},
        {"claim_id": "a", "status": "DONE", "_operation": "U", "_source_order": _ts(3)},
        {"claim_id": "a", "status": "OLD", "_operation": "U", "_source_order": _ts(2)},
        {"claim_id": "b", "_operation": "I", "_source_order": _ts(1)},
        {"claim_id": "b", "_operation": "D", "_source_order": _ts(2)},
    ]
    assert apply_changes(changes, primary_key="claim_id") == [changes[1]]


def test_equal_timestamp_resolution_is_independent_of_arrival_order():
    a = {"claim_id": "a", "status": "A", "_operation": "U", "_source_order": _ts(2)}
    b = {"claim_id": "a", "status": "B", "_operation": "U", "_source_order": _ts(2)}
    assert apply_changes([a, b], primary_key="claim_id") == apply_changes([b, a], primary_key="claim_id")
    assert source_change_id(a, primary_key="claim_id") != source_change_id(b, primary_key="claim_id")


def test_invalid_cdc_change_is_quarantined_and_duplicate_counted():
    good = {"claim_id": "a", "_operation": "I", "_source_order": _ts(1)}
    result = process_cdc_changes(
        [good, good, {"claim_id": "b", "_operation": "X", "_source_order": _ts(1)}],
        primary_key="claim_id", run_id="cdc-1", source="dms",
    )
    assert len(result.current_state) == 1
    assert result.audit.duplicate_count == 1
    assert result.audit.rejected_count == 1
    assert result.quarantined[0].failed_rules == ("unsupported CDC operation: X",)


def test_reconciliation_and_audit_reject_invalid_counts():
    assert reconcile_batch(input_count=3, output_count=1, rejected_count=1, duplicate_count=1)
    assert not reconcile_batch(input_count=3, output_count=1, rejected_count=0, duplicate_count=1)
    with pytest.raises(ValueError):
        PipelineAudit("r", "p", "s", "bronze").finish("SUCCEEDED", input_count=-1, output_count=0)


def test_glue_scripts_expose_stage_audit_quarantine_contract():
    from pathlib import Path

    root = Path(__file__).resolve().parents[2]
    for name in ("glue_claim_pipeline.py", "glue_cdc_pipeline.py"):
        text = (root / "jobs" / name).read_text(encoding="utf-8")
        for token in ("PROCESSING_STAGE", "CONTROL_BUCKET", "QUARANTINE_BUCKET", "pipeline_runs", "bronze", "silver", "gold"):
            assert token in text
