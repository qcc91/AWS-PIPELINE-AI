"""Data-contract checks for the V1 claim-risk training population.

These tests intentionally validate the deterministic business fixture rather
than the legacy four-row fraud smoke fixture.
"""

from __future__ import annotations

import csv
from datetime import datetime
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.generate_file_sources import generate


def _read(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _auc(values: list[float], labels: list[int]) -> float:
    positives = [value for value, label in zip(values, labels) if label == 1]
    negatives = [value for value, label in zip(values, labels) if label == 0]
    comparisons = sum(
        (positive > negative) + 0.5 * (positive == negative)
        for positive in positives
        for negative in negatives
    )
    return comparisons / (len(positives) * len(negatives))


def test_target_balance_and_chronological_splits_contain_both_classes(tmp_path):
    generate(tmp_path)
    claims = sorted(
        _read(tmp_path / "broker_claims.csv"),
        key=lambda row: (row["submitted_at"], row["claim_id"]),
    )
    labels = [int(row["high_risk_claim"]) for row in claims]

    assert len(labels) == 120
    assert sum(labels) == 39
    assert 0.20 <= sum(labels) / len(labels) <= 0.35

    # Chronological 60/20/20, not a random split that can move future examples
    # into the training population.
    for partition in (claims[:72], claims[72:96], claims[96:]):
        assert {int(row["high_risk_claim"]) for row in partition} == {0, 1}


def test_fixture_has_learnable_but_not_single_field_perfect_signal(tmp_path):
    generate(tmp_path)
    claims = _read(tmp_path / "broker_claims.csv")
    regions = {
        row["region_code"]: row
        for row in _read(tmp_path / "region_risk_reference.csv")
    }
    labels = [int(row["high_risk_claim"]) for row in claims]
    candidate_numeric_features = {
        "claim_amount": [float(row["claim_amount"]) for row in claims],
        "catastrophe_risk_score": [
            float(regions[row["incident_region_code"]]["catastrophe_risk_score"])
            for row in claims
        ],
        "weather_risk_score": [
            float(regions[row["incident_region_code"]]["weather_risk_score"])
            for row in claims
        ],
        "accident_risk_score": [
            float(regions[row["incident_region_code"]]["accident_risk_score"])
            for row in claims
        ],
    }
    aucs = [_auc(values, labels) for values in candidate_numeric_features.values()]

    assert max(aucs) >= 0.65  # useful signal exists
    assert max(aucs) < 0.90  # no single numeric input trivially determines y


def test_reference_snapshots_are_available_before_every_prediction(tmp_path):
    generate(tmp_path)
    claims = _read(tmp_path / "broker_claims.csv")
    earliest_prediction = min(
        datetime.fromisoformat(row["submitted_at"].replace("Z", "+00:00"))
        for row in claims
    )

    for name in (
        "product_master",
        "broker_master",
        "branch_master",
        "claim_type_reference",
        "region_risk_reference",
        "vehicle_reference",
        "coverage_reference",
    ):
        for row in _read(tmp_path / f"{name}.csv"):
            source_time = datetime.fromisoformat(
                row["source_updated_at"].replace("Z", "+00:00")
            )
            assert source_time <= earliest_prediction


def test_future_outcomes_are_label_only_not_candidate_features():
    glue_job = (ROOT / "jobs" / "glue_claim_pipeline.py").read_text(encoding="utf-8")
    feature_block = glue_job.split("features = enriched.select(", 1)[1].split(
        ")\n    _write_iceberg(features", 1
    )[0]

    for forbidden in (
        "approved_amount",
        "claim_status",
        "outcome_severity",
        "paid_amount",
        "settlement_duration",
    ):
        assert forbidden not in feature_block
    assert '"high_risk_claim"' in feature_block  # y is exported separately from X
