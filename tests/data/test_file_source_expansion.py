import csv
import hashlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.generate_file_sources import COUNTS, generate


def _read(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def test_generator_is_deterministic_and_has_expected_counts(tmp_path):
    first = tmp_path / "first"
    second = tmp_path / "second"
    assert generate(first) == COUNTS
    assert generate(second) == COUNTS
    for name, count in COUNTS.items():
        assert len(_read(first / f"{name}.csv")) == count
        assert hashlib.sha256((first / f"{name}.csv").read_bytes()).digest() == hashlib.sha256(
            (second / f"{name}.csv").read_bytes()
        ).digest()


def test_file_claims_reuse_immutable_oltp_keys_and_fixed_policy_assignments(tmp_path):
    generate(tmp_path)
    claims = _read(tmp_path / "broker_claims.csv")
    products = {row["product_id"] for row in _read(tmp_path / "product_master.csv")}
    assert {row["policy_id"] for row in claims} == {"pol_6001", "pol_6002", "pol_6003"}
    assert {row["customer_id"] for row in claims} == {"cus_4001", "cus_4002", "cus_4003"}
    assert {"prd_5001", "prd_5002"}.issubset(products)
    assert {row["policy_id"]: row["customer_id"] for row in claims} == {
        "pol_6001": "cus_4001", "pol_6002": "cus_4002", "pol_6003": "cus_4003"
    }
    for policy_id in {row["policy_id"] for row in claims}:
        rows = [row for row in claims if row["policy_id"] == policy_id]
        for field in ("broker_id", "claim_type_id", "coverage_code", "vehicle_code"):
            assert len({row[field] for row in rows}) == 1
    assert {row["high_risk_claim"] for row in claims} == {"0", "1"}


def test_all_file_claim_relationships_resolve(tmp_path):
    generate(tmp_path)
    claims = _read(tmp_path / "broker_claims.csv")
    brokers = {row["broker_id"]: row for row in _read(tmp_path / "broker_master.csv")}
    branches = {row["branch_id"]: row for row in _read(tmp_path / "branch_master.csv")}
    claim_types = {row["claim_type_id"]: row for row in _read(tmp_path / "claim_type_reference.csv")}
    regions = {row["region_code"]: row for row in _read(tmp_path / "region_risk_reference.csv")}
    vehicles = {row["vehicle_code"]: row for row in _read(tmp_path / "vehicle_reference.csv")}
    coverages = {row["coverage_code"]: row for row in _read(tmp_path / "coverage_reference.csv")}
    for row in claims:
        assert brokers[row["broker_id"]]["branch_id"] in branches
        assert row["claim_type_id"] in claim_types
        assert row["incident_region_code"] in regions
        assert row["coverage_code"] in coverages
        if row["policy_id"] == "pol_6002":
            assert row["vehicle_code"] in vehicles
        else:
            assert row["vehicle_code"] == ""


def test_required_bi_and_ml_fields_are_present(tmp_path):
    generate(tmp_path)
    expected = {
        "product_master": {"product_category", "coverage_type", "default_excess", "max_sum_insured", "active_flag", "expiry_date"},
        "broker_master": {"broker_tier", "active_flag", "effective_date"},
        "branch_master": {"manager_code", "active_flag"},
        "claim_type_reference": {"claim_type_id", "claim_category", "severity_group", "default_reserve_band", "active_flag"},
        "region_risk_reference": {"urban_rural_class", "accident_risk_score", "natural_hazard_risk_score", "overall_risk_band", "effective_date"},
        "vehicle_reference": {"vehicle_type", "manufacture_year", "value_band", "engine_size_band", "repair_cost_band", "theft_risk_band", "risk_category"},
        "coverage_reference": {"coverage_category", "default_limit", "default_excess", "optional_flag", "active_flag"},
    }
    for name, fields in expected.items():
        assert fields.issubset(_read(tmp_path / f"{name}.csv")[0])


def test_glue_job_routes_all_files_and_keeps_labels_out_of_feature_inputs():
    job = (Path(__file__).resolve().parents[2] / "jobs/glue_claim_pipeline.py").read_text(encoding="utf-8")
    compile(job, "glue_claim_pipeline.py", "exec")
    for name in COUNTS:
        assert name in job
    feature_block = job.split("features = enriched.select(", 1)[1].split(")\n    _write_iceberg(features", 1)[0]
    assert "outcome_severity" not in feature_block
    assert "approved_amount" not in feature_block
    assert "claim_status" not in feature_block
    assert '"high_risk_claim"' in feature_block  # target column, split from X by the ML job
    assert "vehicle_age" in job
    assert "policy_performance" in job
    assert "broker_performance" in job
