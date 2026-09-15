"""V5 operational regression checks for the existing batch ML path.

These tests deliberately avoid SageMaker and Glue calls.  They protect the
replay and failure-detection contracts used by the low-cost runbook.
"""

from datetime import datetime, timezone
from pathlib import Path

from src.ml.claim_fraud import format_claim_risk


ROOT = Path(__file__).resolve().parents[2]


def test_claim_risk_contract_is_deterministic_for_the_same_run():
    timestamp = datetime(2026, 9, 10, 8, 30, tzinfo=timezone.utc)
    arguments = {
        "claim_ids": ["claim-1", "claim-2", "claim-3"],
        "probabilities": [0.1, 0.5, 0.9],
        "model_version": "claim-risk-v1",
        "run_id": "accepted-run",
        "prediction_timestamp": timestamp,
    }

    first = format_claim_risk(**arguments)
    second = format_claim_risk(**arguments)

    assert first == second
    assert [row["risk_level"] for row in first] == ["LOW", "MEDIUM", "HIGH"]
    assert {row["_run_id"] for row in first} == {"accepted-run"}


def test_glue_postprocess_replay_is_guarded_and_snapshot_based():
    job = (ROOT / "jobs" / "glue_claim_risk_postprocess.py").read_text(
        encoding="utf-8"
    )

    # A replay may replace the same current snapshot only after cardinality,
    # identity and probability checks pass.  It must never append duplicates.
    assert "if input_count != prediction_count:" in job
    assert "if unique_claim_count != input_count:" in job
    assert "if invalid_manifest_count:" in job
    assert "if invalid_probability_count:" in job
    assert '.using("iceberg").createOrReplace()' in job
    assert '.mode("append")' not in job
    assert 'withColumn("model_run_id", lit(args["RUN_ID"]))' in job
    assert 'withColumn("_run_id", lit(args["RUN_ID"]))' in job
