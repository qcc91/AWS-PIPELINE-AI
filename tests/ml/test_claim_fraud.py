from datetime import datetime, timezone
import json
from types import SimpleNamespace

import pytest

from jobs.ml_claim_fraud_pipeline import JobExecutionError, bounded_call, build_training_request, build_transform_request, evaluate_auc, evaluate_predictions, run_pipeline, submit_batch_transform, wait_for_training, wait_for_transform
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
    key = "arn:aws:kms:ap-southeast-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    training = build_training_request(image_uri="published", role_arn="arn:aws:iam::123456789012:role/ml", output_path="s3://bucket/models", train_uri="s3://bucket/train", validation_uri="s3://bucket/validation", job_name="job", kms_key_id=key)
    transform = build_transform_request(model_name="model", input_uri="s3://bucket/input", output_uri="s3://bucket/output", job_name="transform", kms_key_id=key)
    assert training["StoppingCondition"]["MaxRuntimeInSeconds"] == 1800
    # AWS built-in XGBoost emits validation:auc automatically and rejects
    # user-supplied MetricDefinitions for this image.
    assert "MetricDefinitions" not in training["AlgorithmSpecification"]
    assert training["ResourceConfig"]["InstanceCount"] == 1
    assert training["ResourceConfig"]["InstanceType"] == "ml.m5.large"
    assert training["HyperParameters"]["seed"] == "42"
    assert training["HyperParameters"]["subsample"] == "0.80"
    assert transform["TransformResources"]["InstanceCount"] == 1
    assert training["OutputDataConfig"]["KmsKeyId"] == key
    assert transform["TransformOutput"]["KmsKeyId"] == key
    assert transform["TransformResources"]["InstanceType"] == "ml.m5.large"
    assert callable(submit_batch_transform)


def test_auc_is_dependency_free_and_requires_both_classes():
    assert evaluate_auc([0.9, 0.1], [1, 0]) == 1.0
    metrics = evaluate_predictions([0.1, 0.4, 0.6, 0.9], [0, 0, 1, 1])
    assert metrics["auc"] == metrics["f1"] == 1.0


def test_terminal_training_and_transform_failures_are_structured_for_audit():
    class TrainingClient:
        def describe_training_job(self, **_kwargs):
            return {"TrainingJobStatus": "Failed", "FailureReason": "bad input"}

    class TransformClient:
        def describe_transform_job(self, **_kwargs):
            return {"TransformJobStatus": "Stopped", "FailureReason": "operator stop"}

    with pytest.raises(JobExecutionError, match="bad input") as training:
        wait_for_training(client=TrainingClient(), job_name="train", poll_seconds=0)
    assert training.value.stage == "training" and training.value.status == "Failed"
    with pytest.raises(JobExecutionError, match="operator stop") as transform:
        wait_for_transform(client=TransformClient(), job_name="transform", poll_seconds=0)
    assert transform.value.stage == "transform" and transform.value.status == "Stopped"


def test_bounded_retry_retries_only_transient_aws_errors(monkeypatch):
    calls = []

    class Transient(Exception):
        response = {"Error": {"Code": "ThrottlingException"}}

    def operation():
        calls.append(1)
        if len(calls) < 3:
            raise Transient()
        return "ok"

    monkeypatch.setattr("jobs.ml_claim_fraud_pipeline.time.sleep", lambda _seconds: None)
    assert bounded_call(operation, max_attempts=3) == "ok"
    assert len(calls) == 3


def test_pipeline_records_training_failure_with_dataset_and_model_run(tmp_path, monkeypatch):
    class Client:
        def create_training_job(self, **_kwargs):
            return {}

        def describe_training_job(self, **_kwargs):
            return {"TrainingJobStatus": "Failed", "FailureReason": "invalid training input"}

    args = SimpleNamespace(
        region="ap-southeast-2", xgboost_version="1.7-1", role_arn="role",
        output_path="s3://bucket/out", train_uri="s3://bucket/train",
        validation_uri="s3://bucket/validation", job_name="model-run-1",
        kms_key_id="key", poll_seconds=0, dataset_version="claim-risk-v2-abc",
        retain_model=False, audit_output=tmp_path / "audit.json",
    )
    monkeypatch.setattr("jobs.ml_claim_fraud_pipeline.resolve_xgboost_image_uri", lambda **_kwargs: "image")
    with pytest.raises(JobExecutionError):
        run_pipeline(client=Client(), glue_client=None, s3_client=None, args=args)
    events = json.loads(args.audit_output.read_text(encoding="utf-8"))
    assert events[-1]["terminal_status"] == "Failed"
    assert events[-1]["model_run_id"] == "model-run-1"
    assert events[-1]["dataset_version"] == "claim-risk-v2-abc"
