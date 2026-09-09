from datetime import datetime, timezone

from src.cdc.transform import apply_changes


def ts(day: int):
    return datetime(2026, 9, day, tzinfo=timezone.utc)


def test_insert_update_delete_produces_current_state():
    changes = [
        {"claim_id": "clm_1", "claim_status": "SUBMITTED", "_operation": "I", "_source_order": ts(1)},
        {"claim_id": "clm_1", "claim_status": "APPROVED", "_operation": "U", "_source_order": ts(2)},
        {"claim_id": "clm_2", "claim_status": "SUBMITTED", "_operation": "I", "_source_order": ts(1)},
        {"claim_id": "clm_2", "claim_status": "SUBMITTED", "_operation": "D", "_source_order": ts(3)},
    ]
    assert apply_changes(changes, primary_key="claim_id") == [
        {"claim_id": "clm_1", "claim_status": "APPROVED", "_operation": "U", "_source_order": ts(2)}
    ]


def test_older_update_cannot_overwrite_newer_state():
    changes = [
        {"customer_id": "cus_1", "name": "new", "_operation": "U", "_source_order": ts(3)},
        {"customer_id": "cus_1", "name": "old", "_operation": "U", "_source_order": ts(2)},
    ]
    assert apply_changes(changes, primary_key="customer_id")[0]["name"] == "new"
