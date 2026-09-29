from pathlib import Path

from workloads.ml.pipeline.pipeline_definition import build_pipeline_definition


ROOT = Path(__file__).resolve().parents[2]
PIPELINE = (ROOT / "infrastructure/terraform/modules/ml/pipeline.tf").read_text(encoding="utf-8")
ML_MAIN = (ROOT / "infrastructure/terraform/modules/ml/main.tf").read_text(encoding="utf-8")
DEV_MAIN = (ROOT / "infrastructure/terraform/environments/dev/main.tf").read_text(encoding="utf-8")
KMS_MAIN = (ROOT / "infrastructure/terraform/modules/kms/main.tf").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "infrastructure/terraform/bootstrap/modules/dev-operator/main.tf").read_text(encoding="utf-8")
SECURITY = (ROOT / "infrastructure/terraform/modules/security-governance/main.tf").read_text(encoding="utf-8")
PREPARE = (ROOT / "workloads/ml/sagemaker_pipeline_prepare.py").read_text(encoding="utf-8")
EVALUATE = (ROOT / "workloads/ml/sagemaker_pipeline_evaluate.py").read_text(encoding="utf-8")


PIPELINE_CONFIG = {
    "aws_region": "ap-southeast-2",
    "athena_workgroup_name": "insurance-dev-bi",
    "code_uri": "s3://control/artifacts/ml/pipeline",
    "feature_group_name": "insurance-dev-claim-risk-features",
    "gold_database_name": "insurance_dev_gold",
    "glue_job_name": "insurance-dev-claim-risk-postprocess",
    "kms_key_arn": "arn:aws:kms:ap-southeast-2:111122223333:key/example",
    "model_package_group_name": "insurance-dev-claim-fraud",
    "output_prefix": "s3://control/ml/pipeline",
    "processing_image_uri": "processing-image",
    "role_arn": "arn:aws:iam::111122223333:role/sagemaker-role",
    "xgboost_image_uri": "xgboost-image",
}


def _definition() -> dict:
    return build_pipeline_definition(PIPELINE_CONFIG)


def test_real_sagemaker_pipeline_contains_complete_managed_dag() -> None:
    assert 'resource "aws_sagemaker_pipeline" "claim_risk"' in PIPELINE
    definition = _definition()
    top_level = {step["Name"]: step for step in definition["Steps"]}
    assert list(top_level) == [
        "PrepareData",
        "MaterializeFeatureStore",
        "TrainXGBoost",
        "EvaluateModel",
        "ModelQualityGate",
    ]
    assert top_level["MaterializeFeatureStore"]["DependsOn"] == ["PrepareData"]
    assert top_level["TrainXGBoost"]["DependsOn"] == ["MaterializeFeatureStore"]
    assert top_level["EvaluateModel"]["DependsOn"] == ["TrainXGBoost"]

    gate = top_level["ModelQualityGate"]
    assert gate["Type"] == "Condition"
    pass_steps = {step["Name"]: step for step in gate["Arguments"]["IfSteps"]}
    assert list(pass_steps) == [
        "RegisterModel",
        "CreateBatchModel",
        "BatchTransform",
        "PublishAndValidateGold",
    ]
    assert pass_steps["CreateBatchModel"]["Type"] == "Model"
    assert pass_steps["BatchTransform"]["Type"] == "Transform"
    assert gate["Arguments"]["ElseSteps"][0]["Type"] == "Fail"
    assert "aws_sagemaker_endpoint" not in PIPELINE


def test_terraform_registers_python_owned_pipeline_definition() -> None:
    assert 'data "external" "claim_risk_pipeline_definition"' in PIPELINE
    assert 'program = ["python", local.pipeline_definition_script]' in PIPELINE
    assert "pipeline_definition   = data.external.claim_risk_pipeline_definition.result.pipeline_definition" in PIPELINE
    assert "local.pipeline_definition =" not in PIPELINE
    for value in (
        "aws_region",
        "athena_workgroup_name",
        "gold_database_name",
        "glue_job_name",
        "kms_key_arn",
        "model_package_group_name",
        "processing_image_uri",
        "role_arn",
        "xgboost_image_uri",
    ):
        assert value in PIPELINE


def test_prepare_reads_real_gold_features_through_athena() -> None:
    assert '"claim_risk_features"' in PREPARE
    assert "start_query_execution" in PREPARE
    assert "ORDER BY submitted_at, claim_id" in PREPARE
    assert "data/sample/ml_claim_training.csv" not in PIPELINE


def test_pipeline_uses_registry_kms_and_project_visible_tags() -> None:
    definition = _definition()
    gate = definition["Steps"][4]
    register = gate["Arguments"]["IfSteps"][0]
    assert register["Arguments"]["ModelPackageGroupName"] == "insurance-dev-claim-fraud"
    assert register["Arguments"]["ModelApprovalStatus"] == "PendingManualApproval"
    assert 'ProjectUserTagManagedBy' in PIPELINE
    assert 'AmazonDataZoneProject' in PIPELINE
    assert 'var.unified_studio_project_id' in PIPELINE
    assert 'Action = "kms:CreateGrant"' in ML_MAIN
    assert '"kms:GrantIsForAWSResource" = "true"' in ML_MAIN
    assert "aws_resource_grant_role_arns" in DEV_MAIN
    assert "module.ml.sagemaker_role_arn" in DEV_MAIN
    assert 'Action    = "kms:CreateGrant"' in KMS_MAIN
    assert '"kms:GrantIsForAWSResource" = "true"' in KMS_MAIN
    assert '"${local.control_arn}/athena-results/*"' in ML_MAIN


def test_property_files_use_the_service_json_schema_keys() -> None:
    definition = _definition()
    evaluate = definition["Steps"][3]
    gate = definition["Steps"][4]
    publish = gate["Arguments"]["IfSteps"][3]
    assert evaluate["PropertyFiles"] == [
        {
            "PropertyFileName": "EvaluationReport",
            "OutputName": "evaluation",
            "FilePath": "evaluation.json",
        }
    ]
    assert publish["PropertyFiles"][0]["PropertyFileName"] == "GoldValidation"
    assert gate["Arguments"]["Conditions"][0]["LeftValue"] == {
        "Std:JsonGet": {
            "PropertyFile": {
                "Get": "Steps.EvaluateModel.PropertyFiles.EvaluationReport"
            },
            "Path": "binary_classification_metrics.auc.value",
        }
    }


def test_pipeline_parameters_and_native_outputs_preserve_runtime_contract() -> None:
    definition = _definition()
    assert definition["Parameters"] == [
        {"Name": "PreparedInputUri", "Type": "String", "DefaultValue": ""},
        {
            "Name": "OutputPrefix",
            "Type": "String",
            "DefaultValue": "s3://control/ml/pipeline",
        },
        {"Name": "MinimumAuc", "Type": "Float", "DefaultValue": 0.50},
    ]
    gate = definition["Steps"][4]
    transform = gate["Arguments"]["IfSteps"][2]
    publish = gate["Arguments"]["IfSteps"][3]
    assert transform["Arguments"]["TransformResources"] == {
        "InstanceCount": 1,
        "InstanceType": "ml.m5.large",
    }
    assert publish["Arguments"]["AppSpecification"]["ContainerArguments"][0] == (
        "/opt/ml/processing/code/sagemaker_pipeline_publish.py"
    )


def test_bootstrap_permission_is_scoped_to_exact_pipeline() -> None:
    assert 'Sid      = "ManageClaimRiskSageMakerPipeline"' in BOOTSTRAP
    assert 'pipeline/insurance-${var.environment}-claim-risk' in BOOTSTRAP
    assert 'pipeline/*' not in BOOTSTRAP


def test_ml_engineer_can_list_and_run_the_managed_pipeline() -> None:
    assert 'Sid = "ListManagedPipelines"' in SECURITY
    assert 'Action = "sagemaker:ListPipelines"' in SECURITY
    assert 'Sid = "RunClaimRiskPipeline"' in SECURITY
    assert '"sagemaker:StartPipelineExecution"' in SECURITY
    assert '"sagemaker:StopPipelineExecution"' in SECURITY
    assert 'var.sagemaker_pipeline_arn' in SECURITY
    assert '"sagemaker:DescribeProcessingJob"' in SECURITY
    assert 'Sid = "ReadSageMakerJobLogs"' in SECURITY


def test_model_archive_extraction_rejects_paths_and_links() -> None:
    assert "is_relative_to(extraction_root)" in EVALUATE
    assert "member.issym() or member.islnk()" in EVALUATE
