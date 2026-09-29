from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DEV_MAIN = (ROOT / "infrastructure/terraform/environments/dev/main.tf").read_text(encoding="utf-8")
DEV_VARIABLES = (ROOT / "infrastructure/terraform/environments/dev/variables.tf").read_text(encoding="utf-8")
DEV_VERSIONS = (ROOT / "infrastructure/terraform/environments/dev/versions.tf").read_text(encoding="utf-8")
MLFLOW = (ROOT / "infrastructure/terraform/modules/ml/mlflow.tf").read_text(encoding="utf-8")
ML_MAIN = (ROOT / "infrastructure/terraform/modules/ml/main.tf").read_text(encoding="utf-8")
SECURITY = (ROOT / "infrastructure/terraform/modules/security-governance/main.tf").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "infrastructure/terraform/bootstrap/modules/dev-operator/main.tf").read_text(encoding="utf-8")


def test_small_dev_tracking_server_is_terraform_managed_and_protected() -> None:
    assert 'resource "aws_sagemaker_mlflow_tracking_server" "claim_risk"' in MLFLOW
    assert re.search(r'tracking_server_size\s*=\s*"Small"', MLFLOW)
    assert "mlflow_version" not in MLFLOW
    assert "automatic_model_registration = false" in MLFLOW
    assert 'condition     = var.environment == "dev"' in MLFLOW
    assert MLFLOW.count("prevent_destroy = true") == 2
    assert 'resource "aws_sagemaker_endpoint"' not in MLFLOW
    assert 'resource "aws_sagemaker_endpoint"' not in ML_MAIN


def test_tracking_role_is_restricted_to_encrypted_mlflow_prefix() -> None:
    assert 'name = "insurance-${var.environment}-claim-risk-mlflow-role"' in MLFLOW
    assert 'Principal = { Service = "sagemaker.amazonaws.com" }' in MLFLOW
    assert 'Resource = "${local.control_arn}/${local.mlflow_artifact_prefix}/*"' in MLFLOW
    assert '"kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"' in MLFLOW
    assert "AmazonS3FullAccess" not in MLFLOW
    assert "s3:*" not in MLFLOW
    assert "kms:*" not in MLFLOW
    assert "module.ml.mlflow_tracking_role_arn" in DEV_MAIN


def test_existing_unified_studio_project_gets_native_mlflow_connection() -> None:
    assert 'source  = "hashicorp/awscc"' in DEV_VERSIONS
    assert 'resource "awscc_datazone_connection" "claim_risk_mlflow"' in DEV_MAIN
    assert 'scope                  = "PROJECT"' in DEV_MAIN
    assert "project_identifier     = var.sagemaker_unified_studio_project_id" in DEV_MAIN
    assert "domain_identifier      = var.sagemaker_unified_studio_domain_id" in DEV_MAIN
    assert "tracking_server_arn = module.ml.mlflow_tracking_server_arn" in DEV_MAIN
    assert 'default     = "dzd-cvpo8yttzkms0y"' in DEV_VARIABLES
    assert "AmazonDataZoneProject   = var.unified_studio_project_id" in MLFLOW


def test_ml_engineer_can_log_backfill_run_without_administering_server() -> None:
    assert 'Sid = "WriteClaimRiskMlflowRun"' in SECURITY
    assert 'Sid = "OpenClaimRiskMlflowUI"' in SECURITY
    assert 'Action = "sagemaker-mlflow:AccessUI", Resource = var.mlflow_tracking_server_arn' in SECURITY
    assert '"sagemaker:CreatePresignedMlflowTrackingServerUrl"' in SECURITY
    for action in (
        "CreateExperiment",
        "CreateRun",
        "GetExperiment",
        "LogBatch",
        "LogMetric",
        "LogParam",
        "SetTag",
        "UpdateRun",
    ):
        assert f'"sagemaker-mlflow:{action}"' in SECURITY
    assert 'Sid = "UseClaimRiskMlflowArtifacts"' in SECURITY
    assert 'Resource = "${local.control_arn}/mlflow/*"' in SECURITY
    assert "sagemaker:CreateMlflowTrackingServer" not in SECURITY
    assert "sagemaker:DeleteMlflowTrackingServer" not in SECURITY


def test_terraform_execution_permissions_are_exact_and_non_destructive() -> None:
    assert 'Sid    = "V6BManageClaimRiskMlflowTrackingServer"' in BOOTSTRAP
    assert "mlflow-tracking-server/insurance-${var.environment}-claim-risk" in BOOTSTRAP
    assert 'Sid    = "V6BManageUnifiedStudioMlflowConnectionThroughCloudControl"' in BOOTSTRAP
    assert 'Sid    = "V6BManageUnifiedStudioMlflowConnection"' in BOOTSTRAP
    assert "cloudformation:DeleteResource" not in BOOTSTRAP
    assert "datazone:DeleteConnection" not in BOOTSTRAP
    assert "sagemaker:DeleteMlflowTrackingServer" not in BOOTSTRAP


def test_v6b_has_no_prod_resources() -> None:
    prod_root = ROOT / "infrastructure/terraform/environments/prod"
    prod_text = "\n".join(path.read_text(encoding="utf-8") for path in prod_root.glob("*.tf"))
    assert "mlflow" not in prod_text.lower()
    assert "awscc_datazone_connection" not in prod_text
