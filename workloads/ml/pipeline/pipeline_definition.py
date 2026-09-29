"""Build the native SageMaker claim-risk Pipeline service definition.

Terraform owns the durable SageMaker Pipeline resource and supplies environment
specific identifiers through the ``external`` data source.  This module owns
the ML workflow semantics so that training logic is not encoded in HCL.

The implementation intentionally uses the dependency-free SageMaker service
JSON schema rather than importing the SageMaker SDK during ``terraform plan``.
Every step is still a native managed Pipeline step and therefore appears in the
SageMaker Pipelines execution graph.
"""

from __future__ import annotations

import json
import sys
from collections.abc import Mapping
from typing import Any


REQUIRED_CONFIG = (
    "aws_region",
    "athena_workgroup_name",
    "code_uri",
    "feature_group_name",
    "gold_database_name",
    "glue_job_name",
    "kms_key_arn",
    "model_package_group_name",
    "output_prefix",
    "processing_image_uri",
    "role_arn",
    "xgboost_image_uri",
)


def _get(expression: str) -> dict[str, str]:
    return {"Get": expression}


def _join(*values: Any) -> dict[str, dict[str, Any]]:
    return {"Std:Join": {"On": "/", "Values": list(values)}}


def _validated_config(config: Mapping[str, str]) -> dict[str, str]:
    missing = [name for name in REQUIRED_CONFIG if not config.get(name)]
    if missing:
        raise ValueError(f"Missing required pipeline configuration: {', '.join(missing)}")
    return {name: str(config[name]) for name in REQUIRED_CONFIG}


def build_pipeline_definition(config: Mapping[str, str]) -> dict[str, Any]:
    """Return the complete native SageMaker Pipeline definition.

    The step names and behavior deliberately match the already validated V6
    managed execution.  Environment-specific AWS identifiers are injected by
    Terraform; execution-varying inputs remain SageMaker Pipeline parameters.
    """

    cfg = _validated_config(config)
    role_arn = cfg["role_arn"]
    kms_key_arn = cfg["kms_key_arn"]
    output_prefix = _get("Parameters.OutputPrefix")
    execution_id = _get("Execution.PipelineExecutionId")

    processing_resources = {
        "ClusterConfig": {
            "InstanceCount": 1,
            "InstanceType": "ml.m5.large",
            "VolumeSizeInGB": 20,
            "VolumeKmsKeyId": kms_key_arn,
        }
    }
    code_input = {
        "InputName": "code",
        "S3Input": {
            "S3Uri": cfg["code_uri"],
            "LocalPath": "/opt/ml/processing/code",
            "S3DataType": "S3Prefix",
            "S3InputMode": "File",
            "S3DataDistributionType": "FullyReplicated",
            "S3CompressionType": "None",
        },
    }

    prepare = {
        "Name": "PrepareData",
        "Type": "Processing",
        "Arguments": {
            "AppSpecification": {
                "ImageUri": cfg["processing_image_uri"],
                "ContainerEntrypoint": ["python3"],
                "ContainerArguments": [
                    "/opt/ml/processing/code/sagemaker_pipeline_prepare.py",
                    "--region",
                    cfg["aws_region"],
                    "--prepared-input-uri",
                    _get("Parameters.PreparedInputUri"),
                    "--athena-workgroup",
                    cfg["athena_workgroup_name"],
                    "--gold-database",
                    cfg["gold_database_name"],
                    "--feature-group-name",
                    cfg["feature_group_name"],
                    "--athena-output-uri",
                    _join(output_prefix, "executions", execution_id, "athena-prepare"),
                ],
            },
            "ProcessingInputs": [code_input],
            "ProcessingOutputConfig": {
                "KmsKeyId": kms_key_arn,
                "Outputs": [
                    {
                        "OutputName": name,
                        "S3Output": {
                            "LocalPath": f"/opt/ml/processing/{name}",
                            "S3Uri": _join(
                                output_prefix,
                                "executions",
                                execution_id,
                                "prepared",
                                name,
                            ),
                            "S3UploadMode": "EndOfJob",
                        },
                    }
                    for name in (
                        "train",
                        "validation",
                        "test",
                        "inference",
                        "manifest",
                        "metadata",
                    )
                ],
            },
            "ProcessingResources": processing_resources,
            "RoleArn": role_arn,
            "StoppingCondition": {"MaxRuntimeInSeconds": 900},
        },
    }

    materialize = {
        "Name": "MaterializeFeatureStore",
        "Type": "Processing",
        "DependsOn": ["PrepareData"],
        "Arguments": {
            "AppSpecification": {
                "ImageUri": cfg["processing_image_uri"],
                "ContainerEntrypoint": ["python3"],
                "ContainerArguments": [
                    "/opt/ml/processing/code/sagemaker_pipeline_materialize_feature_store.py",
                    "--region",
                    cfg["aws_region"],
                    "--feature-group-name",
                    cfg["feature_group_name"],
                    "--athena-workgroup",
                    cfg["athena_workgroup_name"],
                    "--athena-output-uri",
                    _join(
                        output_prefix,
                        "executions",
                        execution_id,
                        "athena-feature-store",
                    ),
                ],
            },
            "ProcessingInputs": [
                code_input,
                *(
                    {
                        "InputName": input_name,
                        "S3Input": {
                            "S3Uri": _get(
                                "Steps.PrepareData.ProcessingOutputConfig."
                                f"Outputs['{name}'].S3Output.S3Uri"
                            ),
                            "LocalPath": f"/opt/ml/processing/input/{name}",
                            "S3DataType": "S3Prefix",
                            "S3InputMode": "File",
                            "S3DataDistributionType": "FullyReplicated",
                            "S3CompressionType": "None",
                        },
                    }
                    for input_name, name in (
                        ("prepared-manifest", "manifest"),
                        ("prepared-metadata", "metadata"),
                    )
                ),
            ],
            "ProcessingOutputConfig": {
                "KmsKeyId": kms_key_arn,
                "Outputs": [
                    {
                        "OutputName": name,
                        "S3Output": {
                            "LocalPath": f"/opt/ml/processing/{name}",
                            "S3Uri": _join(
                                output_prefix,
                                "executions",
                                execution_id,
                                "feature-store-materialized",
                                name,
                            ),
                            "S3UploadMode": "EndOfJob",
                        },
                    }
                    for name in (
                        "train",
                        "validation",
                        "test",
                        "inference",
                        "metadata",
                    )
                ],
            },
            "ProcessingResources": processing_resources,
            "RoleArn": role_arn,
            "StoppingCondition": {"MaxRuntimeInSeconds": 1500},
        },
    }

    train = {
        "Name": "TrainXGBoost",
        "Type": "Training",
        "DependsOn": ["MaterializeFeatureStore"],
        "Arguments": {
            "AlgorithmSpecification": {
                "TrainingImage": cfg["xgboost_image_uri"],
                "TrainingInputMode": "File",
            },
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
            "InputDataConfig": [
                {
                    "ChannelName": channel,
                    "ContentType": "text/csv",
                    "InputMode": "File",
                    "DataSource": {
                        "S3DataSource": {
                            "S3DataType": "S3Prefix",
                            "S3Uri": _get(
                                "Steps.MaterializeFeatureStore.ProcessingOutputConfig."
                                f"Outputs['{channel}'].S3Output.S3Uri"
                            ),
                            "S3DataDistributionType": "FullyReplicated",
                        }
                    },
                }
                for channel in ("train", "validation")
            ],
            "OutputDataConfig": {
                "KmsKeyId": kms_key_arn,
                "S3OutputPath": _join(output_prefix, "executions", execution_id, "model"),
            },
            "ResourceConfig": {
                "InstanceCount": 1,
                "InstanceType": "ml.m5.large",
                "VolumeSizeInGB": 30,
                "VolumeKmsKeyId": kms_key_arn,
            },
            "RoleArn": role_arn,
            "StoppingCondition": {"MaxRuntimeInSeconds": 1800},
        },
    }

    evaluate = {
        "Name": "EvaluateModel",
        "Type": "Processing",
        "DependsOn": ["TrainXGBoost"],
        "PropertyFiles": [
            {
                "PropertyFileName": "EvaluationReport",
                "OutputName": "evaluation",
                "FilePath": "evaluation.json",
            }
        ],
        "Arguments": {
            "AppSpecification": {
                "ImageUri": cfg["xgboost_image_uri"],
                "ContainerEntrypoint": ["python3"],
                "ContainerArguments": [
                    "/opt/ml/processing/code/sagemaker_pipeline_evaluate.py"
                ],
            },
            "ProcessingInputs": [
                code_input,
                {
                    "InputName": "model",
                    "S3Input": {
                        "S3Uri": _get(
                            "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts"
                        ),
                        "LocalPath": "/opt/ml/processing/model",
                        "S3DataType": "S3Prefix",
                        "S3InputMode": "File",
                        "S3DataDistributionType": "FullyReplicated",
                        "S3CompressionType": "None",
                    },
                },
                {
                    "InputName": "test",
                    "S3Input": {
                        "S3Uri": _get(
                            "Steps.MaterializeFeatureStore.ProcessingOutputConfig."
                            "Outputs['test'].S3Output.S3Uri"
                        ),
                        "LocalPath": "/opt/ml/processing/test",
                        "S3DataType": "S3Prefix",
                        "S3InputMode": "File",
                        "S3DataDistributionType": "FullyReplicated",
                        "S3CompressionType": "None",
                    },
                },
            ],
            "ProcessingOutputConfig": {
                "KmsKeyId": kms_key_arn,
                "Outputs": [
                    {
                        "OutputName": "evaluation",
                        "S3Output": {
                            "LocalPath": "/opt/ml/processing/evaluation",
                            "S3Uri": _join(
                                output_prefix,
                                "executions",
                                execution_id,
                                "evaluation",
                            ),
                            "S3UploadMode": "EndOfJob",
                        },
                    }
                ],
            },
            "ProcessingResources": processing_resources,
            "RoleArn": role_arn,
            "StoppingCondition": {"MaxRuntimeInSeconds": 900},
        },
    }

    register = {
        "Name": "RegisterModel",
        "Type": "RegisterModel",
        "Arguments": {
            "ModelPackageGroupName": cfg["model_package_group_name"],
            "ModelApprovalStatus": "PendingManualApproval",
            "InferenceSpecification": {
                "Containers": [
                    {
                        "Image": cfg["xgboost_image_uri"],
                        "ModelDataUrl": _get(
                            "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts"
                        ),
                    }
                ],
                "SupportedContentTypes": ["text/csv"],
                "SupportedResponseMIMETypes": ["text/csv"],
            },
            "ModelMetrics": {
                "ModelQuality": {
                    "Statistics": {
                        "ContentType": "application/json",
                        "S3Uri": _join(
                            _get(
                                "Steps.EvaluateModel.ProcessingOutputConfig."
                                "Outputs['evaluation'].S3Output.S3Uri"
                            ),
                            "evaluation.json",
                        ),
                    }
                }
            },
        },
    }
    create_model = {
        "Name": "CreateBatchModel",
        "Type": "Model",
        "DependsOn": ["RegisterModel"],
        "Arguments": {
            "ExecutionRoleArn": role_arn,
            "PrimaryContainer": {
                "Image": cfg["xgboost_image_uri"],
                "ModelDataUrl": _get(
                    "Steps.TrainXGBoost.ModelArtifacts.S3ModelArtifacts"
                ),
            },
        },
    }
    transform = {
        "Name": "BatchTransform",
        "Type": "Transform",
        "DependsOn": ["CreateBatchModel"],
        "Arguments": {
            "ModelName": _get("Steps.CreateBatchModel.ModelName"),
            "TransformInput": {
                "ContentType": "text/csv",
                "SplitType": "Line",
                "DataSource": {
                    "S3DataSource": {
                        "S3DataType": "S3Prefix",
                        "S3Uri": _get(
                            "Steps.MaterializeFeatureStore.ProcessingOutputConfig."
                            "Outputs['inference'].S3Output.S3Uri"
                        ),
                    }
                },
            },
            "TransformOutput": {
                "AssembleWith": "Line",
                "KmsKeyId": kms_key_arn,
                "S3OutputPath": _join(
                    output_prefix, "executions", execution_id, "predictions"
                ),
            },
            "TransformResources": {
                "InstanceCount": 1,
                "InstanceType": "ml.m5.large",
            },
        },
    }
    publish = {
        "Name": "PublishAndValidateGold",
        "Type": "Processing",
        "DependsOn": ["BatchTransform"],
        "PropertyFiles": [
            {
                "PropertyFileName": "GoldValidation",
                "OutputName": "validation",
                "FilePath": "validation.json",
            }
        ],
        "Arguments": {
            "AppSpecification": {
                "ImageUri": cfg["processing_image_uri"],
                "ContainerEntrypoint": ["python3"],
                "ContainerArguments": [
                    "/opt/ml/processing/code/sagemaker_pipeline_publish.py",
                    "--region",
                    cfg["aws_region"],
                    "--glue-job-name",
                    cfg["glue_job_name"],
                    "--transform-output-uri",
                    _get("Steps.BatchTransform.TransformOutput.S3OutputPath"),
                    "--claim-ids-uri",
                    _get(
                        "Steps.PrepareData.ProcessingOutputConfig."
                        "Outputs['manifest'].S3Output.S3Uri"
                    ),
                    "--gold-database",
                    cfg["gold_database_name"],
                    "--model-version",
                    _get("Steps.RegisterModel.ModelPackageArn"),
                    "--run-id",
                    execution_id,
                    "--athena-workgroup",
                    cfg["athena_workgroup_name"],
                    "--athena-output-uri",
                    _join(output_prefix, "executions", execution_id, "athena"),
                ],
            },
            "ProcessingInputs": [code_input],
            "ProcessingOutputConfig": {
                "KmsKeyId": kms_key_arn,
                "Outputs": [
                    {
                        "OutputName": "validation",
                        "S3Output": {
                            "LocalPath": "/opt/ml/processing/validation",
                            "S3Uri": _join(
                                output_prefix,
                                "executions",
                                execution_id,
                                "gold-validation",
                            ),
                            "S3UploadMode": "EndOfJob",
                        },
                    }
                ],
            },
            "ProcessingResources": processing_resources,
            "RoleArn": role_arn,
            "StoppingCondition": {"MaxRuntimeInSeconds": 1200},
        },
    }

    quality_gate = {
        "Name": "ModelQualityGate",
        "Type": "Condition",
        "Arguments": {
            "Conditions": [
                {
                    "Type": "GreaterThanOrEqualTo",
                    "LeftValue": {
                        "Std:JsonGet": {
                            "PropertyFile": _get(
                                "Steps.EvaluateModel.PropertyFiles.EvaluationReport"
                            ),
                            "Path": "binary_classification_metrics.auc.value",
                        }
                    },
                    "RightValue": _get("Parameters.MinimumAuc"),
                }
            ],
            "IfSteps": [register, create_model, transform, publish],
            "ElseSteps": [
                {
                    "Name": "FailQualityGate",
                    "Type": "Fail",
                    "Arguments": {
                        "ErrorMessage": (
                            "Independent chronological test AUC is below MinimumAuc; "
                            "model was not registered or published."
                        )
                    },
                }
            ],
        },
    }

    return {
        "Version": "2020-12-01",
        "Metadata": {
            "Purpose": "Leakage-safe claim risk training and batch publication"
        },
        "Parameters": [
            {"Name": "PreparedInputUri", "Type": "String", "DefaultValue": ""},
            {
                "Name": "OutputPrefix",
                "Type": "String",
                "DefaultValue": cfg["output_prefix"],
            },
            {"Name": "MinimumAuc", "Type": "Float", "DefaultValue": 0.50},
        ],
        "PipelineExperimentConfig": {
            "ExperimentName": _get("Execution.PipelineName"),
            "TrialName": execution_id,
        },
        "Steps": [prepare, materialize, train, evaluate, quality_gate],
    }


def main() -> None:
    """Terraform external-data protocol entry point."""

    config = json.load(sys.stdin)
    definition = build_pipeline_definition(config)
    json.dump(
        {"pipeline_definition": json.dumps(definition, separators=(",", ":"))},
        sys.stdout,
    )


if __name__ == "__main__":
    main()

