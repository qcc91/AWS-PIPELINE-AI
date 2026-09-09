"""Submit V1 XGBoost training and Batch Transform jobs on demand.

This module deliberately performs no work at import time. The image URI is
resolved by the SageMaker SDK for the selected region/version, never guessed.
"""
from __future__ import annotations

import argparse
import json
import time
from typing import Any


def resolve_xgboost_image_uri(*, region: str, version: str) -> str:
    """Resolve an AWS-published image; raises if the version is unavailable."""
    try:
        from sagemaker import image_uris
    except ImportError as exc:
        raise RuntimeError("Install the SageMaker SDK to resolve the training image") from exc
    return image_uris.retrieve(framework="xgboost", region=region, version=version, image_scope="training")


def build_training_request(*, image_uri: str, role_arn: str, output_path: str, train_uri: str, validation_uri: str, job_name: str) -> dict[str, Any]:
    return {
        "TrainingJobName": job_name,
        "AlgorithmSpecification": {
            "TrainingInputMode": "File",
            "TrainingImage": image_uri,
            "MetricDefinitions": [
                {"Name": "validation:auc", "Regex": r".*validation-auc:([0-9.]+).*"}
            ],
        },
        "RoleArn": role_arn,
        "OutputDataConfig": {"S3OutputPath": output_path},
        "ResourceConfig": {"InstanceType": "ml.m5.large", "InstanceCount": 1, "VolumeSizeInGB": 30},
        "StoppingCondition": {"MaxRuntimeInSeconds": 1800},
        "InputDataConfig": [
            {"ChannelName": "train", "ContentType": "text/csv", "InputMode": "File", "DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": train_uri, "S3DataDistributionType": "FullyReplicated"}}},
            {"ChannelName": "validation", "ContentType": "text/csv", "InputMode": "File", "DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": validation_uri, "S3DataDistributionType": "FullyReplicated"}}},
        ],
        "HyperParameters": {"objective": "binary:logistic", "eval_metric": "auc", "num_round": "50", "max_depth": "4", "eta": "0.2"},
    }


def build_transform_request(*, model_name: str, input_uri: str, output_uri: str, job_name: str) -> dict[str, Any]:
    return {"TransformJobName": job_name, "ModelName": model_name, "TransformInput": {"DataSource": {"S3DataSource": {"S3DataType": "S3Prefix", "S3Uri": input_uri}}, "ContentType": "text/csv", "SplitType": "Line"}, "TransformOutput": {"S3OutputPath": output_uri, "AssembleWith": "Line"}, "TransformResources": {"InstanceType": "ml.m5.large", "InstanceCount": 1}}


def submit_batch_transform(*, region: str, model_name: str, input_uri: str, output_uri: str, job_name: str) -> dict[str, Any]:
    """Submit a real on-demand Batch Transform job; caller owns model lifecycle."""
    import boto3
    request = build_transform_request(model_name=model_name, input_uri=input_uri, output_uri=output_uri, job_name=job_name)
    return boto3.client("sagemaker", region_name=region).create_transform_job(**request)


def wait_for_training(*, client: Any, job_name: str, poll_seconds: int = 20) -> dict[str, Any]:
    """Wait for terminal training state and fail closed on unsuccessful jobs."""
    while True:
        result = client.describe_training_job(TrainingJobName=job_name)
        status = result["TrainingJobStatus"]
        if status in {"Completed", "Failed", "Stopped"}:
            if status != "Completed":
                raise RuntimeError(f"training job {job_name} ended {status}: {result.get('FailureReason', 'unknown')}")
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


def create_model(*, client: Any, model_name: str, image_uri: str, role_arn: str, model_artifact_uri: str) -> dict[str, Any]:
    return client.create_model(ModelName=model_name, ExecutionRoleArn=role_arn, PrimaryContainer={"Image": image_uri, "ModelDataUrl": model_artifact_uri})


def wait_for_transform(*, client: Any, job_name: str, poll_seconds: int = 20) -> dict[str, Any]:
    while True:
        result = client.describe_transform_job(TransformJobName=job_name)
        status = result["TransformJobStatus"]
        if status in {"Completed", "Failed", "Stopped"}:
            if status != "Completed":
                raise RuntimeError(f"transform job {job_name} ended {status}: {result.get('FailureReason', 'unknown')}")
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


def run_pipeline(*, client: Any, glue_client: Any, args: Any) -> dict[str, Any]:
    """Execute the complete train/evaluate/model/transform/Glue sequence."""
    image = resolve_xgboost_image_uri(region=args.region, version=args.xgboost_version)
    client.create_training_job(**build_training_request(image_uri=image, role_arn=args.role_arn, output_path=args.output_path, train_uri=args.train_uri, validation_uri=args.validation_uri, job_name=args.job_name))
    training = wait_for_training(client=client, job_name=args.job_name, poll_seconds=args.poll_seconds)
    final_metrics = {
        metric["MetricName"]: float(metric["Value"])
        for metric in training.get("FinalMetricDataList", [])
    }
    validation_auc = final_metrics.get("validation:auc")
    if validation_auc is None or validation_auc != validation_auc:
        raise RuntimeError("training did not emit a finite validation:auc metric")
    if validation_auc < args.min_auc:
        raise RuntimeError(f"validation AUC {validation_auc:.4f} below minimum {args.min_auc:.4f}")
    artifact = training["ModelArtifacts"]["S3ModelArtifacts"]
    model_name = f"{args.job_name}-model"
    create_model(client=client, model_name=model_name, image_uri=image, role_arn=args.role_arn, model_artifact_uri=artifact)
    transform_name = f"{args.job_name}-transform"
    client.create_transform_job(**build_transform_request(model_name=model_name, input_uri=args.inference_uri, output_uri=args.transform_output_uri, job_name=transform_name))
    transform = wait_for_transform(client=client, job_name=transform_name, poll_seconds=args.poll_seconds)
    glue_run = glue_client.start_job_run(JobName=args.postprocess_job_name, Arguments={"--TRANSFORM_OUTPUT_URI": args.transform_output_uri, "--CLAIM_IDS_URI": args.claim_ids_uri, "--GOLD_DATABASE": args.gold_database, "--GOLD_TABLE": "claim_risk", "--MODEL_VERSION": model_name, "--RUN_ID": args.job_name})
    glue_result = wait_for_glue(client=glue_client, job_name=args.postprocess_job_name, run_id=glue_run["JobRunId"], poll_seconds=args.poll_seconds)
    return {"training": training, "validation_auc": validation_auc, "transform": transform, "glue": glue_result, "model_name": model_name}


def main() -> None:
    parser = argparse.ArgumentParser(description="Submit on-demand V1 claim fraud jobs")
    parser.add_argument("--region", default="ap-southeast-2")
    parser.add_argument("--xgboost-version", default="1.7-1")
    parser.add_argument("--role-arn", required=True)
    parser.add_argument("--train-uri", required=True)
    parser.add_argument("--validation-uri", required=True)
    parser.add_argument("--output-path", required=True)
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--inference-uri", required=True)
    parser.add_argument("--transform-output-uri", required=True)
    parser.add_argument("--claim-ids-uri", required=True)
    parser.add_argument("--postprocess-job-name", required=True)
    parser.add_argument("--gold-database", required=True)
    parser.add_argument("--min-auc", type=float, default=0.50)
    parser.add_argument("--poll-seconds", type=int, default=20)
    args = parser.parse_args()
    import boto3
    result = run_pipeline(client=boto3.client("sagemaker", region_name=args.region), glue_client=boto3.client("glue", region_name=args.region), args=args)
    print(json.dumps(result, default=str))


if __name__ == "__main__":
    main()
