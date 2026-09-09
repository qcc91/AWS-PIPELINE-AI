from datetime import datetime, timezone

from jobs.ml_claim_fraud_pipeline import build_training_request, build_transform_request, evaluate_auc, submit_batch_transform
from src.ml.claim_fraud import claim_features, deterministic_dataset, format_claim_risk, to_xgboost_csv


def _row():
    return {"claim_id": "clm-1", "claim_amount": "100.00", "approved_amount": "20.00", "incident_date": "2026-09-01", "submitted_at": "2026-09-03T00:00:00Z", "claim_status": "SUBMITTED", "fraud_label": 1}


def test_features_and_xgboost_csv_are_numeric_and_label_first():
    assert claim_features(_row()) == [100.0, 20.0, 2.0, 0.0]
    assert to_xgboost_csv([_row()]) == "1,100.0,20.0,2.0,0.0\n"
    train, validation = deterministic_dataset()
    assert len(train) == 2 and len(validation) == 2
    assert {row["fraud_label"] for row in train} == {0, 1}
    assert {row["fraud_label"] for row in validation} == {0, 1}


def test_claim_risk_contract_clamps_probability_and_sets_level():
    result = format_claim_risk(["clm-1", "clm-2"], [-1, 0.8], model_version="model-1", run_id="run-1", prediction_timestamp=datetime(2026, 9, 3, tzinfo=timezone.utc))
    assert result[0]["fraud_probability"] == "0.00000"
    assert result[0]["risk_level"] == "LOW"
    assert result[1]["risk_level"] == "HIGH"
    assert set(result[0]) == {"claim_id", "fraud_probability", "risk_level", "model_version", "prediction_timestamp", "_run_id"}


def test_requests_use_batch_and_bounded_resources():
    training = build_training_request(image_uri="published", role_arn="arn:aws:iam::123456789012:role/ml", output_path="s3://bucket/models", train_uri="s3://bucket/train", validation_uri="s3://bucket/validation", job_name="job")
    transform = build_transform_request(model_name="model", input_uri="s3://bucket/input", output_uri="s3://bucket/output", job_name="transform")
    assert training["StoppingCondition"]["MaxRuntimeInSeconds"] == 1800
    assert training["AlgorithmSpecification"]["MetricDefinitions"][0]["Name"] == "validation:auc"
    assert training["ResourceConfig"]["InstanceCount"] == 1
    assert transform["TransformResources"]["InstanceCount"] == 1
    assert callable(submit_batch_transform)


def test_auc_is_dependency_free_and_requires_both_classes():
    assert evaluate_auc([0.9, 0.1], [1, 0]) == 1.0
