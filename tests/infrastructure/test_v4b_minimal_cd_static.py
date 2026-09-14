from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTROL = (ROOT / "terraform/cicd-control/main.tf").read_text()
BUILDSPEC = (ROOT / "buildspecs/v4b-minimal-cd.yml").read_text()
BOOTSTRAP = (ROOT / "terraform/bootstrap/modules/dev-operator/main.tf").read_text()


def test_cd_is_minimal_and_isolated_from_full_foundation():
    assert "terraform/cicd-proof/$TARGET_ENV" in BUILDSPEC
    assert "terraform/environments" not in BUILDSPEC
    for expensive in ("aws_db_instance", "aws_dms_", "aws_sagemaker_", "aws_bedrock", "aws_vpc", "aws_glue_job"):
        assert expensive not in CONTROL


def test_pipeline_has_exact_plan_promotion_and_manual_prod_gate():
    for stage in ("DEVPlan", "DEVApply", "DEVValidate", "PRODPlan", "PRODApproval", "PRODApply"):
        assert stage in CONTROL
    assert "ApplyApprovedBinaryPlan" in CONTROL
    assert 'terraform apply -input=false -lock-timeout=2m "$PLAN_PATH"' in BUILDSPEC
    assert "Plan/source mismatch" in BUILDSPEC
    assert "Plan checksum mismatch" in BUILDSPEC
    assert "terraform apply -auto-approve" not in BUILDSPEC


def test_state_is_separate_encrypted_versioned_and_uses_lockfile():
    assert 'default     = "aip-insurance-dev-tfstate-dev01"' in (ROOT / "terraform/cicd-control/variables.tf").read_text()
    assert 'key          = "cicd-proof/dev/terraform.tfstate"' in (ROOT / "terraform/cicd-proof/dev/backend.hcl.example").read_text()
    assert 'key          = "cicd-proof/prod/terraform.tfstate"' in (ROOT / "terraform/cicd-proof/prod/backend.hcl.example").read_text()
    assert 'kms_key_id   = "alias/insurance/dev/terraform-state"' in (ROOT / "terraform/cicd-proof/dev/backend.hcl.example").read_text()
    assert 'use_lockfile = true' in BUILDSPEC
    assert "aws_dynamodb" not in CONTROL
    assert "workspace" not in BUILDSPEC.lower()


def test_codebuild_uses_three_separate_narrow_execution_boundaries():
    assert 'Action = "sts:AssumeRole"' in CONTROL
    assert "AdministratorAccess" not in CONTROL
    assert "aws_iam_access_key" not in CONTROL
    assert "aws_access_key_id" not in CONTROL.lower()
    assert 'for_each = toset(["dev", "prod_plan", "prod_apply"])' in CONTROL
    assert 'name     = "insurance-dev-v4b-proof-${replace(each.key, "_", "-")}-role"' in CONTROL
    assert 'Resource = aws_iam_role.proof[each.key].arn' in CONTROL
    assert 'TARGET_TERRAFORM_EXECUTION_ROLE_ARN' in CONTROL
    assert 'TARGET_TERRAFORM_EXECUTION_ROLE_ARN' in BUILDSPEC
    assert 'DEV_TERRAFORM_EXECUTION_ROLE_ARN' not in BUILDSPEC
    assert 'PROD_TERRAFORM_EXECUTION_ROLE_ARN' not in BUILDSPEC
    assert "terraform_execution_role_arn" not in BUILDSPEC
    assert "iam:CreateAccessKey" not in BOOTSTRAP


def test_prod_apply_requires_human_approval_and_does_not_replan_before_apply():
    approval = CONTROL.index('name = "PRODApproval"')
    prod_apply = CONTROL.index('name = "PRODApply"')
    assert approval < prod_apply
    apply_case = BUILDSPEC.split("DEV_APPLY|PROD_APPLY)", 1)[1]
    apply_block = apply_case.split("DEV_VALIDATE)", 1)[0]
    assert apply_block.index('terraform apply -input=false -lock-timeout=2m "$PLAN_PATH"') < apply_block.index(
        "terraform plan -input=false -lock-timeout=2m -detailed-exitcode"
    )
    assert "ProdPlanVariables.PLAN_SHA256" in CONTROL
    assert "Plan execution metadata mismatch" in BUILDSPEC
    assert "Approval/hash mismatch" in BUILDSPEC
    assert 'ProjectName          = aws_codebuild_project.deploy["prod_plan"].name' in CONTROL
    assert 'ProjectName   = aws_codebuild_project.deploy["prod_apply"].name' in CONTROL
    assert 'resource "aws_iam_role_policy" "proof_write"' in CONTROL
    assert 'if key != "prod_plan"' in CONTROL
    assert 'PLAN_LOCK_ARGS=(-lock=false)' in BUILDSPEC


def test_stage_order_is_explicit_and_safe():
    positions = [CONTROL.index(f'name = "{name}"') for name in ("DEVPlan", "DEVApply", "DEVValidate", "PRODPlan", "PRODApproval", "PRODApply")]
    assert positions == sorted(positions)
    assert 'dynamic "stage"' not in CONTROL


def test_create_log_group_is_request_tag_scoped():
    assert 'Action   = "logs:CreateLogGroup"' in CONTROL
    assert '"aws:RequestTag/Purpose" = "v4b-deployment-proof"' in CONTROL


def test_pipeline_source_is_protected_main_via_connection():
    assert 'provider         = "CodeStarSourceConnection"' in CONTROL
    assert 'BranchName       = "main"' in CONTROL
    assert "github_token" not in CONTROL.lower()
    assert "DetectChanges    = \"true\"" in CONTROL
