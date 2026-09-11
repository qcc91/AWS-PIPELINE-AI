import csv
import json
from pathlib import Path

import pytest

from src.ml.claim_risk import CATEGORICAL_LEVELS, NUMERIC_FEATURES, DatasetValidationError, chronological_split, dataset_version, evaluate_binary, feature_names, prepare_dataset, validate_feature_dataset, vectorize


def _rows(count=20):
    rows = []
    for index in range(count):
        rows.append({
            "claim_id": f"claim-{index}", "high_risk_claim": index % 2,
            "claim_amount": 100 + index, "incident_date": "2026-08-20",
            "submitted_at": "2026-09-01T00:00:00Z", "years_experience": 5,
            "catastrophe_risk_score": 0.2, "region_theft_risk_score": 0.3,
            "weather_risk_score": 0.4, "accident_risk_score": 0.5,
            "deductible_aud": 500, "coverage_limit_aud": 50000,
            "optional_flag": 0, "market_value_aud": 25000,
            "safety_rating": 4, "vehicle_age": 3,
            "product_type": "AUTO", "product_risk_tier": "MEDIUM", "broker_tier": "SILVER",
            "claim_category": "COLLISION", "overall_risk_band": "MEDIUM", "coverage_tier": "STANDARD",
            "repair_cost_band": "HIGH", "theft_risk_band": "LOW", "vehicle_risk_category": "ELEVATED",
        })
    return rows


def test_feature_contract_contains_no_post_submission_fields():
    names = feature_names()
    assert not {"approved_amount", "paid_amount", "claim_status", "outcome_severity", "high_risk_claim"}.intersection(names)
    assert len(vectorize(_rows(1)[0])) == len(NUMERIC_FEATURES) + sum(map(len, CATEGORICAL_LEVELS.values()))


def test_split_is_deterministic_stratified_and_disjoint():
    first = chronological_split(_rows())
    second = chronological_split(_rows())
    assert first == second
    assert {int(row["high_risk_claim"]) for rows in first.values() for row in rows} == {0, 1}
    id_sets = [{row["claim_id"] for row in first[name]} for name in ("train", "validation", "test")]
    assert not (id_sets[0] & id_sets[1] or id_sets[0] & id_sets[2] or id_sets[1] & id_sets[2])
    assert sum(map(len, id_sets)) == 20


def test_prepare_writes_label_first_headerless_and_auditable_manifest(tmp_path: Path):
    metadata = prepare_dataset(_rows(), tmp_path)
    assert metadata["row_count"] == 20
    assert sum(metadata["split_counts"].values()) == 20
    assert len((tmp_path / "train.csv").read_text().splitlines()[0].split(",")) == len(feature_names()) + 1
    with (tmp_path / "claim_ids.csv").open() as handle:
        manifest = list(csv.DictReader(handle))
    assert len(manifest) == 20 and {row["source_split"] for row in manifest} == {"train", "validation", "test"}
    assert {row["feature_version"] for row in manifest} == {"v1"}
    assert len({row["dataset_version"] for row in manifest}) == 1
    assert json.loads((tmp_path / "metadata.json").read_text())["seed"] == 42


def test_v2_validation_is_traceable_and_order_independent():
    rows = _rows()
    result = validate_feature_dataset(rows)
    assert result["status"] == "PASSED"
    assert result["unique_claim_count"] == len(rows)
    assert result["as_of_date_min"] == result["as_of_date_max"] == "2026-09-01"
    assert dataset_version(rows) == dataset_version(list(reversed(rows)))


@pytest.mark.parametrize(
    "mutation, expected",
    [
        ({"claim_amount": ""}, "claim_amount"),
        ({"claim_amount": "-1"}, "claim_amount"),
        ({"high_risk_claim": "invalid"}, "high_risk_claim"),
        ({"as_of_date": "2026-09-02"}, "as_of_date"),
    ],
)
def test_v2_validation_rejects_null_invalid_label_and_future_as_of(mutation, expected):
    rows = _rows()
    rows[0].update(mutation)
    with pytest.raises(DatasetValidationError, match=expected):
        validate_feature_dataset(rows)


def test_v2_validation_rejects_duplicate_claims_and_single_class():
    rows = _rows()
    rows[1]["claim_id"] = rows[0]["claim_id"]
    with pytest.raises(DatasetValidationError, match="duplicate claim_id"):
        validate_feature_dataset(rows)
    rows = _rows()
    for row in rows:
        row["high_risk_claim"] = 0
    with pytest.raises(DatasetValidationError, match="both classes"):
        validate_feature_dataset(rows)


def test_metrics_report_auc_logloss_and_threshold_metrics():
    metrics = evaluate_binary([0, 0, 1, 1], [0.1, 0.4, 0.6, 0.9])
    assert metrics["auc"] == 1.0
    assert metrics["accuracy"] == 1.0
    assert 0 < metrics["log_loss"] < 1
    with pytest.raises(ValueError):
        evaluate_binary([1, 1], [0.8, 0.9])


def test_athena_utc_timestamp_format_is_supported():
    row = _rows(1)[0] | {"submitted_at": "2026-09-01 09:00:00.000000 UTC"}
    assert vectorize(row)[1] == 12.0


def test_real_v1_population_has_required_time_split_and_balance():
    with (Path(__file__).parents[2] / "data" / "file_sources" / "broker_claims.csv").open(newline="", encoding="utf-8") as handle:
        splits = chronological_split(list(csv.DictReader(handle)))
    assert {name: len(rows) for name, rows in splits.items()} == {"train": 72, "validation": 24, "test": 24}
    assert {name: sum(int(row["high_risk_claim"]) for row in rows) for name, rows in splits.items()} == {"train": 21, "validation": 9, "test": 9}
