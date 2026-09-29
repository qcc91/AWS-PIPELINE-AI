import io
from types import SimpleNamespace

import pytest

from workloads.ml.log_existing_pipeline_run_to_mlflow import (
    collect_execution_evidence,
    log_evidence,
)


EXECUTION_ID = "g46dxu0f1ydw"
GIT_SHA = "81d45cd25b449336ef62b59b82f5e18e603ae1ac"


class FakeSageMaker:
    def __init__(self, status="Succeeded"):
        self.status = status

    def describe_pipeline(self, **kwargs):
        assert kwargs == {"PipelineName": "insurance-dev-claim-risk"}
        return {
            "PipelineArn": "arn:aws:sagemaker:ap-southeast-2:111122223333:pipeline/insurance-dev-claim-risk"
        }

    def describe_pipeline_execution(self, **kwargs):
        assert kwargs["PipelineExecutionArn"].endswith(f"/execution/{EXECUTION_ID}")
        return {
            "PipelineExecutionStatus": self.status,
            "CreationTime": "2026-09-27T01:00:00Z",
            "LastModifiedTime": "2026-09-27T01:15:00Z",
            "PipelineParameters": [
                {
                    "Name": "PreparedInputUri",
                    "Value": "s3://control/ml/runs/accepted/input/",
                },
                {"Name": "MinimumAuc", "Value": "0.5"},
            ],
        }

    def list_pipeline_execution_steps(self, **kwargs):
        assert kwargs["PipelineExecutionArn"].endswith(f"/execution/{EXECUTION_ID}")
        return {
            "PipelineExecutionSteps": [
                {
                    "StepName": "PrepareData",
                    "Metadata": {
                        "ProcessingJob": {
                            "Arn": "arn:aws:sagemaker:region:account:processing-job/prepare-job"
                        }
                    },
                },
                {
                    "StepName": "TrainXGBoost",
                    "Metadata": {
                        "TrainingJob": {
                            "Arn": "arn:aws:sagemaker:region:account:training-job/train-job"
                        }
                    },
                },
                {
                    "StepName": "EvaluateModel",
                    "Metadata": {
                        "ProcessingJob": {
                            "Arn": "arn:aws:sagemaker:region:account:processing-job/evaluate-job"
                        }
                    },
                },
                {
                    "StepName": "RegisterModel",
                    "Metadata": {
                        "RegisterModel": {
                            "Arn": "arn:aws:sagemaker:region:account:model-package/group/1"
                        }
                    },
                },
                {
                    "StepName": "PublishAndValidateGold",
                    "Metadata": {
                        "ProcessingJob": {
                            "Arn": "arn:aws:sagemaker:region:account:processing-job/publish-job"
                        }
                    },
                },
            ]
        }

    def describe_processing_job(self, ProcessingJobName):
        outputs = {
            "prepare-job": (
                "metadata",
                f"s3://control/ml/pipeline/executions/{EXECUTION_ID}/prepared/metadata",
            ),
            "evaluate-job": (
                "evaluation",
                f"s3://control/ml/pipeline/executions/{EXECUTION_ID}/evaluation",
            ),
            "publish-job": (
                "validation",
                f"s3://control/ml/pipeline/executions/{EXECUTION_ID}/gold-validation",
            ),
        }
        name, uri = outputs[ProcessingJobName]
        return {
            "ProcessingOutputConfig": {
                "Outputs": [{"OutputName": name, "S3Output": {"S3Uri": uri}}]
            }
        }

    def describe_training_job(self, **kwargs):
        assert kwargs == {"TrainingJobName": "train-job"}
        return {
            "HyperParameters": {
                "objective": "binary:logistic",
                "eval_metric": "auc",
                "num_round": "100",
                "max_depth": "3",
                "eta": "0.08",
                "seed": "42",
            },
            "ModelArtifacts": {
                "S3ModelArtifacts": f"s3://control/ml/pipeline/executions/{EXECUTION_ID}/model/model.tar.gz"
            },
        }


class FakeS3:
    def get_object(self, Bucket, Key):
        assert Bucket == "control"
        if Key.endswith("evaluation/evaluation.json"):
            payload = b'''{
              "binary_classification_metrics": {
                "auc": {"value": 0.622222},
                "accuracy": {"value": 0.625},
                "log_loss": {"value": 0.656316},
                "precision": {"value": 0.0},
                "recall": {"value": 0.0},
                "f1": {"value": 0.0}
              },
              "row_count": 24,
              "split": "chronological_test"
            }'''
        elif Key.endswith("prepared/metadata/metadata.json"):
            payload = b'''{
              "dataset_version": "claim-risk-v1-abc123",
              "features": ["claim_amount", "reporting_delay_days"],
              "row_count": 120
            }'''
        elif Key.endswith("gold-validation/validation.json"):
            payload = b'''{
              "row_count": 120,
              "unique_claim_count": 120,
              "invalid_probability_count": 0
            }'''
        else:
            raise AssertionError(Key)
        return {"Body": io.BytesIO(payload), "ContentLength": len(payload)}


def _evidence():
    return collect_execution_evidence(
        sagemaker=FakeSageMaker(),
        s3=FakeS3(),
        pipeline_name="insurance-dev-claim-risk",
        execution_id=EXECUTION_ID,
        source_git_sha=GIT_SHA,
        environment="dev",
    )


def test_collects_real_metrics_params_artifacts_and_lineage_without_new_workload():
    evidence = _evidence()

    assert evidence["metrics"] == {
        "auc": 0.622222,
        "accuracy": 0.625,
        "log_loss": 0.656316,
        "precision": 0.0,
        "recall": 0.0,
        "f1": 0.0,
        "evaluation_row_count": 24.0,
    }
    assert evidence["parameters"]["model_family"] == "XGBoost"
    assert evidence["parameters"]["xgboost.objective"] == "binary:logistic"
    assert evidence["parameters"]["xgboost.num_round"] == "100"
    assert evidence["parameters"]["dataset_version"] == "claim-risk-v1-abc123"
    assert evidence["parameters"]["gold_input_reference"].endswith("/accepted/input/")
    assert evidence["lineage"]["pipeline_execution_id"] == EXECUTION_ID
    assert evidence["lineage"]["source_git_sha"] == GIT_SHA
    assert evidence["lineage"]["model_artifact_uri"].endswith("model.tar.gz")
    assert evidence["gold_validation"]["invalid_probability_count"] == 0


def test_rejects_unsuccessful_execution_instead_of_logging_partial_evidence():
    with pytest.raises(RuntimeError, match="only a Succeeded Pipeline execution"):
        collect_execution_evidence(
            sagemaker=FakeSageMaker(status="Failed"),
            s3=FakeS3(),
            pipeline_name="insurance-dev-claim-risk",
            execution_id=EXECUTION_ID,
            source_git_sha=GIT_SHA,
            environment="dev",
        )


class FakeRunContext:
    def __init__(self, run_id):
        self.info = SimpleNamespace(run_id=run_id)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False


class FakeMlflow:
    def __init__(self):
        self.tracking_uri = None
        self.params = None
        self.metrics = None
        self.artifacts = []
        self.tags = None

    def set_tracking_uri(self, uri):
        self.tracking_uri = uri

    def set_experiment(self, name):
        assert name == "insurance-claim-risk"
        return SimpleNamespace(experiment_id="7")

    def start_run(self, run_name, tags):
        assert run_name == f"insurance-dev-claim-risk-{EXECUTION_ID}"
        self.tags = tags
        return FakeRunContext("new-run-id")

    def log_params(self, params):
        self.params = params

    def log_metrics(self, metrics):
        self.metrics = metrics

    def log_dict(self, value, path):
        self.artifacts.append((path, value))


class FakeMlflowClient:
    def __init__(self, runs=None):
        self.runs = runs or []

    def search_runs(self, **kwargs):
        assert kwargs["experiment_ids"] == ["7"]
        assert EXECUTION_ID in kwargs["filter_string"]
        return self.runs


def test_logs_one_lightweight_run_with_no_model_or_dataset_copy():
    mlflow = FakeMlflow()

    def client_factory():
        assert mlflow.tracking_uri is not None
        return FakeMlflowClient()

    result = log_evidence(
        mlflow=mlflow,
        client_factory=client_factory,
        tracking_server_arn=(
            "arn:aws:sagemaker:ap-southeast-2:111122223333:"
            "mlflow-tracking-server/insurance-dev-claim-risk"
        ),
        experiment_name="insurance-claim-risk",
        evidence=_evidence(),
    )

    assert result["run_id"] == "new-run-id"
    assert result["reused_existing_run"] is False
    assert mlflow.params["sagemaker_pipeline_execution_id"] == EXECUTION_ID
    assert mlflow.metrics["auc"] == 0.622222
    assert mlflow.tags["git.commit"] == GIT_SHA
    assert [path for path, _ in mlflow.artifacts] == [
        "evaluation/evaluation.json",
        "data/feature-metadata.json",
        "validation/gold-validation.json",
        "lineage/lineage.json",
    ]
    assert not any("model.tar.gz" in path for path, _ in mlflow.artifacts)


def test_reuses_finished_run_for_same_pipeline_execution():
    existing = SimpleNamespace(
        info=SimpleNamespace(status="FINISHED", run_id="existing-run-id")
    )
    mlflow = FakeMlflow()
    result = log_evidence(
        mlflow=mlflow,
        client_factory=lambda: FakeMlflowClient([existing]),
        tracking_server_arn="tracking-server-arn",
        experiment_name="insurance-claim-risk",
        evidence=_evidence(),
    )

    assert result["run_id"] == "existing-run-id"
    assert result["reused_existing_run"] is True
    assert mlflow.params is None
