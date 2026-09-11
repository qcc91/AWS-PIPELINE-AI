"""Submit V1 XGBoost training and Batch Transform jobs on demand.

This module deliberately performs no work at import time. The image URI is
resolved by the SageMaker SDK for the selected region/version, never guessed.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TRANSIENT_ERROR_CODES = {"Throttling", "ThrottlingException", "TooManyRequestsException", "ServiceUnavailable", "InternalFailure"}


class JobExecutionError(RuntimeError):
    """Terminal AWS job failure with structured details for audit recording."""

    def __init__(self, stage: str, job_name: str, status: str, reason: str):
        self.stage, self.job_name, self.status, self.reason = stage, job_name, status, reason
        super().__init__(f"{stage} job {job_name} ended {status}: {reason}")


def _event(events: list[dict[str, Any]], stage: str, status: str, **details: Any) -> None:
    events.append({"timestamp": datetime.now(timezone.utc).isoformat(), "stage": stage, "status": status, **details})


def _error_code(exc: Exception) -> str:
    response = getattr(exc, "response", {})
    return str(response.get("Error", {}).get("Code", "")) if isinstance(response, dict) else ""


def bounded_call(operation, *, max_attempts: int = 3, base_delay_seconds: float = 1.0):
    """Retry only explicitly transient AWS API failures with exponential backoff."""
    for attempt in range(1, max_attempts + 1):
        try:
            return operation()
        except Exception as exc:
            if _error_code(exc) not in TRANSIENT_ERROR_CODES or attempt == max_attempts:
                raise
            time.sleep(base_delay_seconds * (2 ** (attempt - 1)))
    raise AssertionError("unreachable")


def resolve_xgboost_image_uri(*, region: str, version: str) -> str:
    """Resolve an AWS-published image; raises if the version is unavailable."""
    try:
        from sagemaker import image_uris
    except ImportError as exc:
        raise RuntimeError("Install the SageMaker SDK to resolve the training image") from exc
    return image_uris.retrieve(framework="xgboost", region=region, version=version, image_scope="training")


def build_training_request(*, image_uri: str, role_arn: str, output_path: str, train_uri: str, validation_uri: str, job_name: str, kms_key_id: str | None = None) -> dict[str, Any]:
    return {
        "TrainingJobName": job_name,
        "AlgorithmSpecification": {
            "TrainingInputMode": "File",
            "TrainingImage": image_uri,
        },
        "RoleArn": role_arn,
        "OutputDataConfig": {
            "S3OutputPath": output_path,
            **({"KmsKeyId": kms_key_id} if kms_key_id else {}),
        },
        "ResourceConfig": {"InstanceType": "ml.m5.large", "InstanceCount": 1, "VolumeSizeInGB": 30},
        "StoppingCondition": {"MaxRuntimeInSeconds": 1800},
        "InputDataConfig": [
            {"ChannelName": "train", "ContentType": "text/csv", "InputMode": "File", "DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": train_uri, "S3DataDistributionType": "FullyReplicated"}}},
            {"ChannelName": "validation", "ContentType": "text/csv", "InputMode": "File", "DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": validation_uri, "S3DataDistributionType": "FullyReplicated"}}},
        ],
        "HyperParameters": {
            "objective": "binary:logistic",
            "eval_metric": "auc",
            "num_round": "100",
            "max_depth": "3",
            "eta": "0.08",
            "min_child_weight": "2",
            "subsample": "0.80",
            "colsample_bytree": "0.80",
            "seed": "42",
            "early_stopping_rounds": "12",
        },
    }


def build_transform_request(*, model_name: str, input_uri: str, output_uri: str, job_name: str, kms_key_id: str | None = None) -> dict[str, Any]:
    return {"TransformJobName": job_name, "ModelName": model_name, "TransformInput": {"DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": input_uri}}, "ContentType": "text/csv", "SplitType": "Line"}, "TransformOutput": {"S3OutputPath": output_uri, "AssembleWith": "Line", **({"KmsKeyId": kms_key_id} if kms_key_id else {})}, "TransformResources": {"InstanceType": "ml.m5.large", "InstanceCount": 1}}


def submit_batch_transform(*, region: str, model_name: str, input_uri: str, output_uri: str, job_name: str, kms_key_id: str | None = None) -> dict[str, Any]:
    """Submit a real on-demand Batch Transform job; caller owns model lifecycle."""
    import boto3
    request = build_transform_request(model_name=model_name, input_uri=input_uri, output_uri=output_uri, job_name=job_name, kms_key_id=kms_key_id)
    return boto3.client("sagemaker", region_name=region).create_transform_job(**request)


def wait_for_training(*, client: Any, job_name: str, poll_seconds: int = 20) -> dict[str, Any]:
    """Wait for terminal training state and fail closed on unsuccessful jobs."""
    while True:
        result = client.describe_training_job(TrainingJobName=job_name)
        status = result["TrainingJobStatus"]
        if status in {"Completed", "Failed", "Stopped"}:
            if status != "Completed":
                raise JobExecutionError("training", job_name, status, result.get("FailureReason", "unknown"))
            return result
        time.sleep(poll_seconds)


def evaluate_auc(probabilities: list[float], labels: list[int]) -> float:
    """Small dependency-free AUC implementation for the V1 validation split."""
    pairs = list(zip(probabilities, labels))
    positives = sum(labels)
    negatives = len(labels) - positives
    if not positives or not negatives:
        raise ValueError("validation set must contain both classes")
    concordant = sum(1 for score, label in pairs if label for other_score, other_label in pairs if not other_label and score > other_score)
    ties = sum(1 for score, label in pairs if label for other_score, other_label in pairs if not other_label and score == other_score)
    return (concordant + 0.5 * ties) / (positives * negatives)


def evaluate_predictions(probabilities: list[float], labels: list[int], threshold: float = 0.5) -> dict[str, float | int]:
    """Evaluate the untouched chronological test split after Batch Transform."""
    if len(probabilities) != len(labels) or not labels:
        raise ValueError("probabilities and labels must have equal non-zero length")
    auc = evaluate_auc(probabilities, labels)
    clipped = [min(1 - 1e-15, max(1e-15, float(value))) for value in probabilities]
    log_loss = -sum(y * math.log(p) + (1 - y) * math.log(1 - p) for y, p in zip(labels, clipped)) / len(labels)
    predicted = [int(value >= threshold) for value in probabilities]
    tp = sum(y == p == 1 for y, p in zip(labels, predicted))
    fp = sum(y == 0 and p == 1 for y, p in zip(labels, predicted))
    fn = sum(y == 1 and p == 0 for y, p in zip(labels, predicted))
    accuracy = sum(y == p for y, p in zip(labels, predicted)) / len(labels)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"row_count": len(labels), "auc": auc, "log_loss": log_loss, "accuracy": accuracy, "precision": precision, "recall": recall, "f1": f1}


def _split_s3_uri(uri: str) -> tuple[str, str]:
    if not uri.startswith("s3://") or "/" not in uri[5:]:
        raise ValueError(f"invalid S3 URI: {uri}")
    return tuple(uri[5:].split("/", 1))  # type: ignore[return-value]


def evaluate_transform_test(*, s3_client: Any, transform_output_uri: str, claim_ids_uri: str) -> dict[str, float | int]:
    """Load ordered predictions and score only rows marked test in the sidecar."""
    output_bucket, output_prefix = _split_s3_uri(transform_output_uri)
    paginator = s3_client.get_paginator("list_objects_v2")
    keys = sorted(
        item["Key"]
        for page in paginator.paginate(Bucket=output_bucket, Prefix=output_prefix.rstrip("/") + "/")
        for item in page.get("Contents", [])
        if item["Key"].endswith(".out")
    )
    if not keys:
        raise RuntimeError("Batch Transform produced no .out objects")
    probabilities = [
        float(line.split(",", 1)[0])
        for key in keys
        for line in s3_client.get_object(Bucket=output_bucket, Key=key)["Body"].read().decode().splitlines()
        if line.strip()
    ]
    manifest_bucket, manifest_key = _split_s3_uri(claim_ids_uri)
    manifest_text = s3_client.get_object(Bucket=manifest_bucket, Key=manifest_key)["Body"].read().decode()
    manifest = list(csv.DictReader(io.StringIO(manifest_text)))
    if len(manifest) != len(probabilities):
        raise RuntimeError(f"prediction/manifest row mismatch: {len(probabilities)} != {len(manifest)}")
    claim_ids = [row["claim_id"] for row in manifest]
    if len(set(claim_ids)) != len(claim_ids):
        raise RuntimeError("prediction manifest contains duplicate claim_id values")
    if any(not math.isfinite(value) or value < 0 or value > 1 for value in probabilities):
        raise RuntimeError("Batch Transform produced an invalid probability")
    test_pairs = [(probability, int(row["high_risk_claim"])) for probability, row in zip(probabilities, manifest) if row["source_split"] == "test"]
    metrics = evaluate_predictions([pair[0] for pair in test_pairs], [pair[1] for pair in test_pairs])
    return {
        **metrics,
        "prediction_input_count": len(manifest),
        "prediction_output_count": len(probabilities),
        "unique_claim_count": len(set(claim_ids)),
        "duplicate_claim_count": 0,
        "reconciliation_status": "PASSED",
    }


def create_model(*, client: Any, model_name: str, image_uri: str, role_arn: str, model_artifact_uri: str) -> dict[str, Any]:
    return client.create_model(ModelName=model_name, ExecutionRoleArn=role_arn, PrimaryContainer={"Image": image_uri, "ModelDataUrl": model_artifact_uri})


def wait_for_transform(*, client: Any, job_name: str, poll_seconds: int = 20) -> dict[str, Any]:
    while True:
        result = client.describe_transform_job(TransformJobName=job_name)
        status = result["TransformJobStatus"]
        if status in {"Completed", "Failed", "Stopped"}:
            if status != "Completed":
                raise JobExecutionError("transform", job_name, status, result.get("FailureReason", "unknown"))
            return result
        time.sleep(poll_seconds)


def wait_for_glue(*, client: Any, job_name: str, run_id: str, poll_seconds: int = 20) -> dict[str, Any]:
    """Wait for the claim-risk Iceberg materialization and fail closed."""
    while True:
        result = client.get_job_run(JobName=job_name, RunId=run_id, PredecessorsIncluded=False)["JobRun"]
        status = result["JobRunState"]
        if status in {"SUCCEEDED", "FAILED", "ERROR", "TIMEOUT", "STOPPED"}:
            if status != "SUCCEEDED":
                raise RuntimeError(f"Glue job {job_name}/{run_id} ended {status}: {result.get('ErrorMessage', 'unknown')}")
            return result
        time.sleep(poll_seconds)


def run_pipeline(*, client: Any, glue_client: Any, s3_client: Any, args: Any) -> dict[str, Any]:
    """Execute the complete train/evaluate/model/transform/Glue sequence."""
    events: list[dict[str, Any]] = []
    model_name: str | None = None
    cleanup_error: Exception | None = None
    image = resolve_xgboost_image_uri(region=args.region, version=args.xgboost_version)
    try:
        _event(events, "training", "SUBMITTING", model_run_id=args.job_name, dataset_version=args.dataset_version)
        bounded_call(lambda: client.create_training_job(**build_training_request(image_uri=image, role_arn=args.role_arn, output_path=args.output_path, train_uri=args.train_uri, validation_uri=args.validation_uri, job_name=args.job_name, kms_key_id=args.kms_key_id)))
        training = wait_for_training(client=client, job_name=args.job_name, poll_seconds=args.poll_seconds)
        final_metrics = {metric["MetricName"]: float(metric["Value"]) for metric in training.get("FinalMetricDataList", [])}
        validation_auc = final_metrics.get("validation:auc")
        if validation_auc is None or validation_auc != validation_auc:
            raise RuntimeError("training did not emit a finite validation:auc metric")
        if validation_auc < args.min_auc:
            raise RuntimeError(f"validation AUC {validation_auc:.4f} below minimum {args.min_auc:.4f}")
        _event(events, "training", "SUCCEEDED", model_run_id=args.job_name, dataset_version=args.dataset_version, metrics=final_metrics)
        artifact = training["ModelArtifacts"]["S3ModelArtifacts"]
        model_name = f"{args.job_name}-model"
        bounded_call(lambda: create_model(client=client, model_name=model_name, image_uri=image, role_arn=args.role_arn, model_artifact_uri=artifact))
        transform_name = f"{args.job_name}-transform"
        _event(events, "transform", "SUBMITTING", model_run_id=args.job_name, dataset_version=args.dataset_version, job_name=transform_name)
        bounded_call(lambda: client.create_transform_job(**build_transform_request(model_name=model_name, input_uri=args.inference_uri, output_uri=args.transform_output_uri, job_name=transform_name, kms_key_id=args.kms_key_id)))
        transform = wait_for_transform(client=client, job_name=transform_name, poll_seconds=args.poll_seconds)
        test_metrics = evaluate_transform_test(s3_client=s3_client, transform_output_uri=args.transform_output_uri, claim_ids_uri=args.claim_ids_uri)
        _event(events, "transform", "SUCCEEDED", model_run_id=args.job_name, dataset_version=args.dataset_version, reconciliation=test_metrics)
        glue_run = bounded_call(lambda: glue_client.start_job_run(JobName=args.postprocess_job_name, Arguments={"--TRANSFORM_OUTPUT_URI": args.transform_output_uri, "--CLAIM_IDS_URI": args.claim_ids_uri, "--GOLD_DATABASE": args.gold_database, "--GOLD_TABLE": "claim_risk", "--MODEL_VERSION": model_name, "--RUN_ID": args.job_name}))
        glue_result = wait_for_glue(client=glue_client, job_name=args.postprocess_job_name, run_id=glue_run["JobRunId"], poll_seconds=args.poll_seconds)
        _event(events, "postprocess", "SUCCEEDED", model_run_id=args.job_name, glue_run_id=glue_run["JobRunId"])
        return {"training": training, "validation_auc": validation_auc, "test_metrics": test_metrics, "transform": transform, "glue": glue_result, "model_name": model_name, "model_run_id": args.job_name, "audit_events": events, "model_deleted_after_transform": not args.retain_model}
    except Exception as exc:
        _event(
            events,
            getattr(exc, "stage", "pipeline"),
            "FAILED",
            model_run_id=args.job_name,
            dataset_version=args.dataset_version,
            job_name=getattr(exc, "job_name", args.job_name),
            terminal_status=getattr(exc, "status", None),
            failure_reason=getattr(exc, "reason", str(exc)),
        )
        raise
    finally:
        if model_name and not args.retain_model:
            try:
                client.delete_model(ModelName=model_name)
                _event(events, "model_cleanup", "SUCCEEDED", model_run_id=args.job_name, model_name=model_name)
            except Exception as exc:
                _event(events, "model_cleanup", "FAILED", model_run_id=args.job_name, error=str(exc))
                cleanup_error = exc
        if getattr(args, "audit_output", None):
            Path(args.audit_output).parent.mkdir(parents=True, exist_ok=True)
            Path(args.audit_output).write_text(json.dumps(events, indent=2, default=str) + "\n", encoding="utf-8")
        if cleanup_error and sys.exc_info()[0] is None:
            raise RuntimeError(f"transient SageMaker model cleanup failed: {cleanup_error}") from cleanup_error


def main() -> None:
    parser = argparse.ArgumentParser(description="Submit on-demand V1 claim fraud jobs")
    parser.add_argument("--region", default="ap-southeast-2")
    parser.add_argument("--xgboost-version", default="1.7-1")
    parser.add_argument("--role-arn", required=True)
    parser.add_argument("--train-uri", required=True)
    parser.add_argument("--validation-uri", required=True)
    parser.add_argument("--output-path", required=True)
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--dataset-version", required=True, help="stable version emitted by dataset preparation metadata")
    parser.add_argument("--inference-uri", required=True)
    parser.add_argument("--transform-output-uri", required=True)
    parser.add_argument("--claim-ids-uri", required=True)
    parser.add_argument("--postprocess-job-name", required=True)
    parser.add_argument("--gold-database", required=True)
    parser.add_argument("--kms-key-id", required=True, help="KMS key used for model and Batch Transform S3 outputs")
    parser.add_argument("--min-auc", type=float, default=0.50)
    parser.add_argument("--poll-seconds", type=int, default=20)
    parser.add_argument("--retain-model", action="store_true", help="Keep the transient SageMaker Model after Batch Transform")
    parser.add_argument("--audit-output", type=Path, help="write structured stage/failure audit JSON locally")
    args = parser.parse_args()
    import boto3
    result = run_pipeline(client=boto3.client("sagemaker", region_name=args.region), glue_client=boto3.client("glue", region_name=args.region), s3_client=boto3.client("s3", region_name=args.region), args=args)
    print(json.dumps(result, default=str))


if __name__ == "__main__":
    main()
