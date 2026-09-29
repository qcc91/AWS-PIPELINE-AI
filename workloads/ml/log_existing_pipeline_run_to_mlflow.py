"""Backfill one successful SageMaker Pipeline execution into managed MLflow.

This is intentionally a lightweight observability adapter.  It reads the
artifacts and job metadata already produced by a successful managed Pipeline
execution; it does not start a Pipeline, Training, Processing, Transform, or
endpoint workload.

The runtime needs the AWS MLflow authentication plugin and an MLflow client
whose version matches the server version returned by
``DescribeMlflowTrackingServer``.
"""

from __future__ import annotations

import argparse
import json
import re
from collections.abc import Mapping
from datetime import date, datetime
from typing import Any
from urllib.parse import urlparse


DEFAULT_EXPERIMENT_NAME = "insurance-claim-risk"
DEFAULT_PIPELINE_NAME = "insurance-dev-claim-risk"
MAX_JSON_ARTIFACT_BYTES = 1_000_000


def _pipeline_execution_arn(sagemaker: Any, pipeline_name: str, execution_id: str) -> str:
    pipeline_arn = sagemaker.describe_pipeline(PipelineName=pipeline_name)["PipelineArn"]
    return f"{pipeline_arn}/execution/{execution_id}"


def _list_execution_steps(sagemaker: Any, execution_arn: str) -> list[dict[str, Any]]:
    steps: list[dict[str, Any]] = []
    request: dict[str, Any] = {"PipelineExecutionArn": execution_arn}
    while True:
        response = sagemaker.list_pipeline_execution_steps(**request)
        steps.extend(response.get("PipelineExecutionSteps", []))
        token = response.get("NextToken")
        if not token:
            return steps
        request["NextToken"] = token


def _step_resource_arn(
    steps: list[dict[str, Any]], step_name: str, resource_type: str
) -> str:
    matches = [step for step in steps if step.get("StepName") == step_name]
    if len(matches) != 1:
        raise RuntimeError(f"expected one {step_name} step, found {len(matches)}")
    arn = matches[0].get("Metadata", {}).get(resource_type, {}).get("Arn")
    if not arn:
        raise RuntimeError(f"{step_name} has no {resource_type} ARN")
    return str(arn)


def _name_from_arn(arn: str) -> str:
    name = arn.rstrip("/").rsplit("/", 1)[-1]
    if not name:
        raise ValueError(f"resource ARN has no name: {arn}")
    return name


def _processing_output_uri(job: Mapping[str, Any], output_name: str) -> str:
    outputs = job.get("ProcessingOutputConfig", {}).get("Outputs", [])
    matches = [item for item in outputs if item.get("OutputName") == output_name]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one {output_name} output in Processing job, found {len(matches)}"
        )
    return str(matches[0]["S3Output"]["S3Uri"])


def _join_s3(prefix: str, filename: str) -> str:
    parsed = urlparse(prefix)
    if parsed.scheme != "s3" or not parsed.netloc:
        raise ValueError(f"not an S3 URI: {prefix}")
    return f"s3://{parsed.netloc}/{parsed.path.lstrip('/').rstrip('/')}/{filename}"


def _read_s3_json(s3: Any, uri: str) -> dict[str, Any]:
    parsed = urlparse(uri)
    if parsed.scheme != "s3" or not parsed.netloc or not parsed.path.lstrip("/"):
        raise ValueError(f"not an S3 object URI: {uri}")
    response = s3.get_object(Bucket=parsed.netloc, Key=parsed.path.lstrip("/"))
    declared_size = int(response.get("ContentLength", 0))
    if declared_size > MAX_JSON_ARTIFACT_BYTES:
        raise RuntimeError(f"refusing to read oversized JSON artifact: {uri}")
    body = response["Body"].read(MAX_JSON_ARTIFACT_BYTES + 1)
    if len(body) > MAX_JSON_ARTIFACT_BYTES:
        raise RuntimeError(f"refusing to read oversized JSON artifact: {uri}")
    value = json.loads(body.decode("utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"expected a JSON object in {uri}")
    return value


def _metric_values(evaluation: Mapping[str, Any]) -> dict[str, float]:
    raw = evaluation.get("binary_classification_metrics")
    if not isinstance(raw, Mapping) or not raw:
        raise RuntimeError("evaluation has no binary_classification_metrics")
    metrics: dict[str, float] = {}
    for name, entry in raw.items():
        value = entry.get("value") if isinstance(entry, Mapping) else entry
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RuntimeError(f"evaluation metric {name} is not numeric")
        metrics[str(name)] = float(value)
    row_count = evaluation.get("row_count")
    if isinstance(row_count, (int, float)) and not isinstance(row_count, bool):
        metrics["evaluation_row_count"] = float(row_count)
    return metrics


def _iso(value: Any) -> str:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    return str(value or "")


def collect_execution_evidence(
    *,
    sagemaker: Any,
    s3: Any,
    pipeline_name: str,
    execution_id: str,
    source_git_sha: str,
    environment: str,
) -> dict[str, Any]:
    """Collect small, real evidence from an already successful execution."""
    if not re.fullmatch(r"[A-Za-z0-9-]+", execution_id):
        raise ValueError("pipeline execution ID contains unsupported characters")
    if not re.fullmatch(r"[0-9a-f]{40}", source_git_sha):
        raise ValueError("source Git SHA must be a 40-character lowercase hexadecimal SHA")

    execution_arn = _pipeline_execution_arn(sagemaker, pipeline_name, execution_id)
    execution = sagemaker.describe_pipeline_execution(
        PipelineExecutionArn=execution_arn
    )
    status = execution.get("PipelineExecutionStatus")
    if status != "Succeeded":
        raise RuntimeError(
            f"only a Succeeded Pipeline execution may be logged; {execution_id} is {status}"
        )
    steps = _list_execution_steps(sagemaker, execution_arn)

    prepare = sagemaker.describe_processing_job(
        ProcessingJobName=_name_from_arn(
            _step_resource_arn(steps, "PrepareData", "ProcessingJob")
        )
    )
    evaluate = sagemaker.describe_processing_job(
        ProcessingJobName=_name_from_arn(
            _step_resource_arn(steps, "EvaluateModel", "ProcessingJob")
        )
    )
    publish = sagemaker.describe_processing_job(
        ProcessingJobName=_name_from_arn(
            _step_resource_arn(steps, "PublishAndValidateGold", "ProcessingJob")
        )
    )
    training = sagemaker.describe_training_job(
        TrainingJobName=_name_from_arn(
            _step_resource_arn(steps, "TrainXGBoost", "TrainingJob")
        )
    )

    evaluation_uri = _join_s3(
        _processing_output_uri(evaluate, "evaluation"), "evaluation.json"
    )
    metadata_uri = _join_s3(
        _processing_output_uri(prepare, "metadata"), "metadata.json"
    )
    validation_uri = _join_s3(
        _processing_output_uri(publish, "validation"), "validation.json"
    )
    evaluation_json = _read_s3_json(s3, evaluation_uri)
    metadata_json = _read_s3_json(s3, metadata_uri)
    validation_json = _read_s3_json(s3, validation_uri)

    execution_parameters = {
        item["Name"]: item.get("Value", "")
        for item in execution.get("PipelineParameters", [])
    }
    model_package_arn = ""
    try:
        model_package_arn = _step_resource_arn(steps, "RegisterModel", "RegisterModel")
    except RuntimeError:
        # Older API responses did not always return nested Condition-step model
        # package metadata. The run remains useful with the model S3 URI.
        pass

    dataset_version = str(
        metadata_json.get("dataset_version")
        or metadata_json.get("validation", {}).get("dataset_version")
        or "unknown"
    )
    model_uri = str(training["ModelArtifacts"]["S3ModelArtifacts"])
    parameters = {
        "model_family": "XGBoost",
        "environment": environment,
        "sagemaker_pipeline_name": pipeline_name,
        "sagemaker_pipeline_execution_id": execution_id,
        "source_git_sha": source_git_sha,
        "gold_input_reference": execution_parameters.get("PreparedInputUri")
        or "Athena Gold claim_risk_features",
        "dataset_version": dataset_version,
        **{
            f"xgboost.{key}": str(value)
            for key, value in sorted(training.get("HyperParameters", {}).items())
        },
    }
    lineage = {
        "pipeline_name": pipeline_name,
        "pipeline_execution_id": execution_id,
        "pipeline_execution_arn": execution_arn,
        "pipeline_execution_status": status,
        "pipeline_execution_start_time": _iso(execution.get("CreationTime")),
        "pipeline_execution_end_time": _iso(execution.get("LastModifiedTime")),
        "source_git_sha": source_git_sha,
        "prepared_input_uri": execution_parameters.get("PreparedInputUri", ""),
        "dataset_version": dataset_version,
        "evaluation_uri": evaluation_uri,
        "feature_metadata_uri": metadata_uri,
        "gold_validation_uri": validation_uri,
        "model_artifact_uri": model_uri,
        "model_package_arn": model_package_arn,
    }
    return {
        "parameters": parameters,
        "metrics": _metric_values(evaluation_json),
        "evaluation": evaluation_json,
        "feature_metadata": metadata_json,
        "gold_validation": validation_json,
        "lineage": lineage,
    }


def log_evidence(
    *,
    mlflow: Any,
    client_factory: Any,
    tracking_server_arn: str,
    experiment_name: str,
    evidence: Mapping[str, Any],
) -> dict[str, Any]:
    """Write one MLflow run, reusing a finished run for the same execution."""
    mlflow.set_tracking_uri(tracking_server_arn)
    # MlflowClient resolves its backing store during construction.  Construct
    # it only after the managed tracking-server ARN has replaced the local
    # default URI, otherwise the duplicate-run lookup can silently hit a local
    # file store.
    client = client_factory()
    experiment = mlflow.set_experiment(experiment_name)
    execution_id = str(evidence["lineage"]["pipeline_execution_id"])
    existing = client.search_runs(
        experiment_ids=[str(experiment.experiment_id)],
        filter_string=(
            "tags.`sagemaker.pipeline_execution_id` = " f"'{execution_id}'"
        ),
        max_results=10,
        order_by=["attributes.start_time DESC"],
    )
    for run in existing:
        if run.info.status == "FINISHED":
            return {
                "experiment_name": experiment_name,
                "experiment_id": str(experiment.experiment_id),
                "run_id": run.info.run_id,
                "pipeline_execution_id": execution_id,
                "reused_existing_run": True,
            }

    tags = {
        "sagemaker.pipeline_name": str(evidence["lineage"]["pipeline_name"]),
        "sagemaker.pipeline_execution_id": execution_id,
        "sagemaker.pipeline_execution_arn": str(
            evidence["lineage"]["pipeline_execution_arn"]
        ),
        "sagemaker.pipeline_execution_status": str(
            evidence["lineage"]["pipeline_execution_status"]
        ),
        "git.commit": str(evidence["lineage"]["source_git_sha"]),
        "mlflow.runName": (
            f"{evidence['lineage']['pipeline_name']}-{execution_id}"
        ),
    }
    with mlflow.start_run(run_name=tags["mlflow.runName"], tags=tags) as active_run:
        mlflow.log_params(dict(evidence["parameters"]))
        mlflow.log_metrics(dict(evidence["metrics"]))
        mlflow.log_dict(dict(evidence["evaluation"]), "evaluation/evaluation.json")
        mlflow.log_dict(
            dict(evidence["feature_metadata"]), "data/feature-metadata.json"
        )
        mlflow.log_dict(
            dict(evidence["gold_validation"]), "validation/gold-validation.json"
        )
        mlflow.log_dict(dict(evidence["lineage"]), "lineage/lineage.json")
        run_id = active_run.info.run_id

    return {
        "experiment_name": experiment_name,
        "experiment_id": str(experiment.experiment_id),
        "run_id": run_id,
        "pipeline_execution_id": execution_id,
        "reused_existing_run": False,
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Log an existing successful SageMaker Pipeline execution to managed MLflow; "
            "does not run or retrain the Pipeline."
        )
    )
    parser.add_argument("--tracking-server-arn", required=True)
    parser.add_argument("--pipeline-execution-id", required=True)
    parser.add_argument("--source-git-sha", required=True)
    parser.add_argument("--pipeline-name", default=DEFAULT_PIPELINE_NAME)
    parser.add_argument("--experiment-name", default=DEFAULT_EXPERIMENT_NAME)
    parser.add_argument("--environment", default="dev", choices=("dev",))
    parser.add_argument("--region", default="ap-southeast-2")
    parser.add_argument("--profile")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    import boto3

    boto3.setup_default_session(
        profile_name=args.profile or None,
        region_name=args.region,
    )
    # Load the AWS MLflow plugin only after selecting the intended AWS profile.
    import mlflow
    from mlflow.tracking import MlflowClient

    session = boto3.Session()
    evidence = collect_execution_evidence(
        sagemaker=session.client("sagemaker", region_name=args.region),
        s3=session.client("s3", region_name=args.region),
        pipeline_name=args.pipeline_name,
        execution_id=args.pipeline_execution_id,
        source_git_sha=args.source_git_sha,
        environment=args.environment,
    )
    result = log_evidence(
        mlflow=mlflow,
        client_factory=MlflowClient,
        tracking_server_arn=args.tracking_server_arn,
        experiment_name=args.experiment_name,
        evidence=evidence,
    )
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
