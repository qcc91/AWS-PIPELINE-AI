from datetime import datetime, timezone

import pytest

from src.streaming.producer import build_event


def test_build_event_matches_envelope_contract():
    event = build_event("CLAIM_SUBMITTED", {"claim_amount": "10.00", "currency_code": "AUD"}, event_timestamp=datetime(2026, 9, 8, tzinfo=timezone.utc), claim_id="clm_1", policy_id="pol_1", customer_id="cus_1")
    assert event["schema_version"] == 1
    assert event["event_timestamp"].endswith("Z")
    assert event["payload"]["currency_code"] == "AUD"


def test_required_business_ids_are_enforced():
    with pytest.raises(ValueError, match="business identifiers"):
        build_event("POLICY_VIEWED", {"channel": "web"})


def test_unknown_event_type_is_rejected():
    with pytest.raises(ValueError, match="unsupported"):
        build_event("UNKNOWN", {"x": 1}, customer_id="cus_1")
