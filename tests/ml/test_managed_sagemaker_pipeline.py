from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PIPELINE = (ROOT / "infrastructure/terraform/modules/ml/pipeline.tf").read_text(encoding="utf-8")
ML_MAIN = (ROOT / "infrastructure/terraform/modules/ml/main.tf").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "infrastructure/terraform/bootstrap/modules/dev-operator/main.tf").read_text(encoding="utf-8")
SECURITY = (ROOT / "infrastructure/terraform/modules/security-governance/main.tf").read_text(encoding="utf-8")
PREPARE = (ROOT / "workloads/ml/sagemaker_pipeline_prepare.py").read_text(encoding="utf-8")
EVALUATE = (ROOT / "workloads/ml/sagemaker_pipeline_evaluate.py").read_text(encoding="utf-8")


def test_real_sagemaker_pipeline_contains_complete_managed_dag() -> None:
    assert 'resource "aws_sagemaker_pipeline" "claim_risk"' in PIPELINE
    for step in (
        'Name = "PrepareData"',
        'Name      = "TrainXGBoost"',
        'Name      = "EvaluateModel"',
        'Name = "ModelQualityGate"',
        'Name = "RegisterModel"',
        'Name      = "BatchTransform"',
        'Name      = "PublishAndValidateGold"',
    ):
        assert step in PIPELINE
    assert 'Type = "Condition"' in PIPELINE
    assert 'Type = "Fail"' in PIPELINE
    assert "aws_sagemaker_endpoint" not in PIPELINE


def test_prepare_reads_real_gold_features_through_athena() -> None:
    assert '"claim_risk_features"' in PREPARE
    assert "start_query_execution" in PREPARE
    assert "ORDER BY submitted_at, claim_id" in PREPARE
    assert "data/sample/ml_claim_training.csv" not in PIPELINE


def test_pipeline_uses_registry_kms_and_project_visible_tags() -> None:
    assert "aws_sagemaker_model_package_group.claim_fraud" in PIPELINE
    assert 'ModelApprovalStatus   = "PendingManualApproval"' in PIPELINE
    assert 'ProjectUserTagManagedBy' in PIPELINE
    assert 'Action = "kms:CreateGrant"' in ML_MAIN
    assert '"kms:GrantIsForAWSResource" = "true"' in ML_MAIN


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


def test_model_archive_extraction_rejects_paths_and_links() -> None:
    assert "is_relative_to(extraction_root)" in EVALUATE
    assert "member.issym() or member.islnk()" in EVALUATE
