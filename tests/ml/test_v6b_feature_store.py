import csv
import json
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "workloads" / "ml"))

import sagemaker_pipeline_materialize_feature_store as materialize  # noqa: E402
import sagemaker_pipeline_prepare as prepare  # noqa: E402
from claim_risk import (  # noqa: E402
    FEATURE_STORE_EVENT_TIME,
    feature_names,
    feature_store_feature_definitions,
    prepare_dataset,
)


FEATURE_STORE_TF = (
    ROOT / "infrastructure/terraform/modules/ml/feature_store.tf"
).read_text(encoding="utf-8")
ML_MAIN = (ROOT / "infrastructure/terraform/modules/ml/main.tf").read_text(
    encoding="utf-8"
)


def _prepared(tmp_path: Path) -> dict[str, Path]:
    rows = [
        {
            "claim_id": f"claim-{index}",
            "high_risk_claim": index % 2,
            "claim_amount": 100 + index,
            "incident_date": "2026-08-20",
            "submitted_at": f"2026-09-{index + 1:02d}T00:00:00Z",
            "years_experience": 5,
            "catastrophe_risk_score": 0.2,
            "region_theft_risk_score": 0.3,
            "weather_risk_score": 0.4,
            "accident_risk_score": 0.5,
            "deductible_aud": 500,
            "coverage_limit_aud": 50000,
            "optional_flag": 0,
            "market_value_aud": 25000,
            "safety_rating": 4,
            "vehicle_age": 3,
            "product_type": "AUTO",
            "product_risk_tier": "MEDIUM",
            "broker_tier": "SILVER",
            "claim_category": "COLLISION",
            "overall_risk_band": "MEDIUM",
            "coverage_tier": "STANDARD",
            "repair_cost_band": "HIGH",
            "theft_risk_band": "LOW",
            "vehicle_risk_category": "ELEVATED",
        }
        for index in range(20)
    ]
    prepare_dataset(rows, tmp_path)
    return {name: tmp_path / name for name in (
        "train.csv", "validation.csv", "test.csv", "inference.csv",
        "claim_ids.csv", "metadata.json",
    )}


def test_feature_group_schema_reuses_exact_model_features() -> None:
    definitions = feature_store_feature_definitions()
    assert definitions[:3] == [
        {"feature_name": "claim_id", "feature_type": "String"},
        {"feature_name": "event_time", "feature_type": "String"},
        {"feature_name": "high_risk_claim", "feature_type": "Integral"},
    ]
    assert [item["feature_name"] for item in definitions[3:]] == feature_names()
    assert {item["feature_type"] for item in definitions[3:]} == {"Fractional"}


def test_terraform_feature_group_is_offline_only_encrypted_and_scoped() -> None:
    assert 'resource "aws_sagemaker_feature_group" "claim_risk"' in FEATURE_STORE_TF
    assert 'record_identifier_feature_name = "claim_id"' in FEATURE_STORE_TF
    assert 'event_time_feature_name        = "event_time"' in FEATURE_STORE_TF
    assert "offline_store_config" in FEATURE_STORE_TF
    assert "kms_key_id = var.kms_key_arn" in FEATURE_STORE_TF
    assert "online_store_config" not in FEATURE_STORE_TF
    assert '"s3:ListBucket"' in FEATURE_STORE_TF
    assert '"glue:CreateTable"' in FEATURE_STORE_TF
    assert 'database/insurance_${var.environment}_control' in FEATURE_STORE_TF
    assert 'Action = ["sagemaker:DescribeFeatureGroup", "sagemaker:PutRecord"]' in ML_MAIN
    assert 'database/insurance_${var.environment}_control' in ML_MAIN
    assert (
        'table/insurance_${var.environment}_control/claim_risk_features_offline'
        in ML_MAIN
    )


def test_prepare_submits_exact_xgboost_matrix_to_offline_store(
    tmp_path: Path, monkeypatch
) -> None:
    destinations = _prepared(tmp_path)
    calls = []

    class FeatureStore:
        def put_record(self, **kwargs):
            calls.append(kwargs)

    monkeypatch.setattr(
        prepare.boto3,
        "client",
        lambda service, region_name: FeatureStore(),
    )
    count = prepare._ingest_offline_feature_store(
        feature_group_name="insurance-dev-claim-risk-features",
        destinations=destinations,
        region="ap-southeast-2",
    )
    assert count == 20
    assert {tuple(call["TargetStores"]) for call in calls} == {("OfflineStore",)}
    assert [value["FeatureName"] for value in calls[0]["Record"]] == [
        "claim_id", FEATURE_STORE_EVENT_TIME, "high_risk_claim", *feature_names()
    ]


def test_offline_readback_rebuilds_training_channels_without_feature_engineering(
    tmp_path: Path,
) -> None:
    destinations = _prepared(tmp_path / "prepared")
    records = prepare._prepared_feature_store_records(destinations)
    rows = [
        {value["FeatureName"]: value["ValueAsString"] for value in record}
        for record in records
    ]
    with destinations["claim_ids.csv"].open(newline="", encoding="utf-8") as handle:
        manifests = list(csv.DictReader(handle))
    output = tmp_path / "materialized"
    materialize.write_materialized_channels(
        rows=rows, manifests=manifests, output_root=output
    )
    for name in ("train", "validation", "test", "inference"):
        assert (output / name / f"{name}.csv").read_text(encoding="utf-8") == (
            destinations[f"{name}.csv"].read_text(encoding="utf-8")
        )


def test_offline_query_is_point_in_time_keyed_and_deduplicated(tmp_path: Path) -> None:
    destinations = _prepared(tmp_path)
    with destinations["claim_ids.csv"].open(newline="", encoding="utf-8") as handle:
        manifests = list(csv.DictReader(handle))[:2]
    query = materialize._offline_query(
        {
            "Catalog": "AwsDataCatalog",
            "Database": "sagemaker_featurestore",
            "TableName": "insurance_dev_claim_risk_features_123",
        },
        manifests,
    )
    assert 'PARTITION BY "claim_id", "event_time"' in query
    assert 'ORDER BY "api_invocation_time" DESC, "write_time" DESC' in query
    assert '"is_deleted" = false' in query
    assert "record_rank = 1" in query
    assert all(row["claim_id"] in query for row in manifests)


def test_pipeline_materializes_offline_store_before_training() -> None:
    from workloads.ml.pipeline.pipeline_definition import build_pipeline_definition

    definition = build_pipeline_definition({
        "aws_region": "ap-southeast-2",
        "athena_workgroup_name": "insurance-dev-bi",
        "code_uri": "s3://control/artifacts/ml/pipeline",
        "feature_group_name": "insurance-dev-claim-risk-features",
        "gold_database_name": "insurance_dev_gold",
        "glue_job_name": "postprocess",
        "kms_key_arn": "arn:aws:kms:ap-southeast-2:111122223333:key/example",
        "model_package_group_name": "insurance-dev-claim-fraud",
        "output_prefix": "s3://control/ml/pipeline",
        "processing_image_uri": "processing-image",
        "role_arn": "arn:aws:iam::111122223333:role/sagemaker-role",
        "xgboost_image_uri": "xgboost-image",
    })
    steps = {step["Name"]: step for step in definition["Steps"]}
    assert steps["MaterializeFeatureStore"]["DependsOn"] == ["PrepareData"]
    assert steps["TrainXGBoost"]["DependsOn"] == ["MaterializeFeatureStore"]
    channels = steps["TrainXGBoost"]["Arguments"]["InputDataConfig"]
    assert all(
        "Steps.MaterializeFeatureStore" in channel["DataSource"]["S3DataSource"]["S3Uri"]["Get"]
        for channel in channels
    )


def test_event_time_is_normalized_to_supported_utc_precision() -> None:
    assert prepare._iso_event_time("2026-09-01 09:00:00.123456 UTC") == (
        "2026-09-01T09:00:00.123Z"
    )
    assert prepare._iso_event_time("2026-09-01") == "2026-09-01T00:00:00Z"


def test_offline_readback_has_a_bounded_timeout(monkeypatch) -> None:
    class SageMaker:
        def describe_feature_group(self, **kwargs):
            return {
                "OfflineStoreConfig": {
                    "DataCatalogConfig": {
                        "Catalog": "AwsDataCatalog",
                        "Database": "sagemaker_featurestore",
                        "TableName": "claim_risk",
                    }
                }
            }

    class Athena:
        def start_query_execution(self, **kwargs):
            return {"QueryExecutionId": "query-1"}

        def get_query_execution(self, **kwargs):
            return {"QueryExecution": {"Status": {"State": "FAILED"}}}

    monkeypatch.setattr(
        materialize.boto3,
        "client",
        lambda service, region_name: SageMaker()
        if service == "sagemaker"
        else Athena(),
    )
    ticks = iter([0.0, 0.0, 0.0, 0.0, 2.0])
    monkeypatch.setattr(materialize.time, "monotonic", lambda: next(ticks))
    monkeypatch.setattr(materialize.time, "sleep", lambda seconds: None)
    with pytest.raises(TimeoutError, match="offline readback timed out"):
        materialize.wait_for_offline_records(
            region="ap-southeast-2",
            feature_group_name="insurance-dev-claim-risk-features",
            workgroup="insurance-dev-bi",
            output_uri="s3://control/results",
            manifests=[{
                "claim_id": "claim-1",
                "event_time": "2026-09-01T00:00:00Z",
                "as_of_date": "2026-09-01",
            }],
            timeout_seconds=1,
            poll_seconds=0,
        )
