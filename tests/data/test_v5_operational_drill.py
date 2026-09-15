from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("v5_operational_drill", ROOT / "scripts/v5/operational_drill.py")
drill = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(drill)


HEADER = "claim_id,claim_number,policy_id,customer_id,claim_status,incident_date,submitted_at,claim_amount,approved_amount,currency_code,description,updated_at\n"
ROW = "clm-1,BRK-1,pol-1,cus-1,SUBMITTED,2026-09-01,2026-09-02T00:00:00Z,100.00,,AUD,fixture,2026-09-02T01:00:00Z\n"


def _manifest(tmp_path: Path) -> Path:
    baseline = tmp_path / "baseline.csv"
    baseline.write_text(HEADER + ROW, encoding="utf-8")
    run_id = drill.new_run_id(
        "batch-ops", now=datetime(2026, 9, 15, tzinfo=timezone.utc), suffix="1234abcd"
    )
    return drill.prepare(baseline, tmp_path / "out", run_id)


def test_prepare_is_unique_scoped_synthetic_and_preserves_replay_bytes(tmp_path):
    path = _manifest(tmp_path)
    manifest = json.loads(path.read_text(encoding="utf-8"))
    assert manifest["run_id"] == "v5-batch-ops-20260915T000000Z-1234abcd"
    assert all(key.startswith(f"batch/v5-drill/{manifest['run_id']}/") for key in manifest["objects"].values())
    assert manifest["safety"] == {
        "aws_write_requires_execute_flag": True,
        "contains_pii": False,
        "delete_operations": False,
        "synthetic": True,
    }
    recovery = path.parent / manifest["files"]["recovery"]["path"]
    replay = path.parent / manifest["files"]["duplicate_replay"]["path"]
    assert recovery.read_bytes() == replay.read_bytes()
    assert manifest["files"]["recovery"]["sha256"] == manifest["files"]["duplicate_replay"]["sha256"]
    bad = path.parent / "broker_claims_v5_bad.csv"
    assert b"-1.00" in bad.read_bytes()
    assert b"-1.00" not in recovery.read_bytes()
    assert manifest["drill_claim_id"].encode() in bad.read_bytes()
    assert manifest["drill_claim_id"].encode() in recovery.read_bytes()
    assert manifest["expected"] == {
        "bad_batch": {"input": 2, "output": 1, "rejected": 1, "duplicate": 0},
        "recovery": {"input": 2, "output": 2, "rejected": 0, "duplicate": 0},
        "duplicate_replay": {"input": 2, "output": 0, "rejected": 0, "duplicate": 2},
        "final_gold_count": 2,
    }
    assert all(Path(key).name.startswith("broker_claims") for key in manifest["objects"].values() if not key.endswith("missing.csv"))


def test_manifest_rejects_object_outside_drill_prefix(tmp_path):
    path = _manifest(tmp_path)
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["objects"]["recovery"] = "batch/untrusted.csv"
    path.write_text(json.dumps(manifest), encoding="utf-8")
    with pytest.raises(ValueError, match="escaped"):
        drill.load_manifest(path)


def test_commands_are_non_destructive_and_kms_encrypted(tmp_path):
    path = _manifest(tmp_path)
    kms = "arn:aws:kms:ap-southeast-2:199476069493:key/example"
    for scenario in ("bad-batch", "recovery", "duplicate-replay"):
        command = drill.aws_command(path, scenario, "aip-dev-operator", kms)
        assert command[:3] == ["aws", "s3", "cp"]
        assert "rm" not in command and "delete-object" not in command
        assert command[command.index("--sse") + 1] == "aws:kms"
        assert command[command.index("--sse-kms-key-id") + 1] == kms

    missing = drill.aws_command(path, "missing-input", None, "")
    assert missing[:3] == ["aws", "stepfunctions", "start-execution"]
    assert "--profile" not in missing
    event = json.loads(missing[missing.index("--input") + 1])
    assert event["id"] == "v5-batch-ops-20260915T000000Z-1234abcd"
    assert event["detail"]["object"]["key"].endswith("/missing.csv")

    cdc = drill.aws_command(path, "cdc-replay", None, "", "oltp/public/claims/LOAD00000001.csv")
    assert cdc[:3] == ["aws", "stepfunctions", "start-execution"]
    assert drill.CDC_STATE_MACHINE_ARN in cdc
    with pytest.raises(ValueError, match="under oltp"):
        drill.aws_command(path, "cdc-replay", None, "", "batch/not-cdc.csv")


def test_execution_requires_explicit_safety_latch(tmp_path):
    path = _manifest(tmp_path)
    with pytest.raises(SystemExit, match="pass --execute"):
        drill.main(["execute", "--manifest", str(path), "--scenario", "missing-input"])


def test_batch_audit_reconciliation_contract():
    valid = {
        "run_id": "r", "pipeline_name": "batch-file", "source": "s", "stage": "silver",
        "status": "SUCCEEDED", "input_count": 3, "output_count": 1,
        "rejected_count": 1, "duplicate_count": 1, "reconciliation_passed": True,
    }
    assert drill.validate_batch_audit(valid) == []
    invalid = dict(valid, duplicate_count=0)
    assert drill.validate_batch_audit(invalid) == ["batch reconciliation failed"]


def test_cdc_replay_regression_uses_change_log_current_state_semantics():
    from src.cdc.transform import process_cdc_changes

    instant = datetime(2026, 9, 15, tzinfo=timezone.utc)
    change = {"claim_id": "v5-cdc-1", "_operation": "I", "_source_order": instant}
    first = process_cdc_changes([change, change], primary_key="claim_id", run_id="v5-cdc-a", source="retained-dms")
    replay = process_cdc_changes([change], primary_key="claim_id", run_id="v5-cdc-b", source="retained-dms", current_state=first.current_state)
    assert first.current_state == replay.current_state
    assert first.audit.duplicate_count == 1
    assert replay.audit.reconciliation_passed is True
