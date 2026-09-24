from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECURITY = (ROOT / "infrastructure/terraform/modules/security-governance/main.tf").read_text(encoding="utf-8")
DEV = (ROOT / "infrastructure/terraform/environments/dev/main.tf").read_text(encoding="utf-8")
LF = (ROOT / "infrastructure/terraform/modules/lakeformation/main.tf").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "infrastructure/terraform/bootstrap/modules/dev-operator/main.tf").read_text(encoding="utf-8")
STATE_BACKEND = (ROOT / "infrastructure/terraform/bootstrap/modules/state-backend/main.tf").read_text(encoding="utf-8")
PLATFORM_KMS = (ROOT / "infrastructure/terraform/modules/kms/main.tf").read_text(encoding="utf-8")
PLATFORM_KMS_VARIABLES = (ROOT / "infrastructure/terraform/modules/kms/variables.tf").read_text(encoding="utf-8")
MONITORING = (ROOT / "infrastructure/terraform/modules/monitoring/main.tf").read_text(encoding="utf-8")
MONITORING_VARIABLES = (ROOT / "infrastructure/terraform/modules/monitoring/variables.tf").read_text(encoding="utf-8")


def test_operator_and_terraform_roles_are_bootstrap_owned():
    assert 'resource "aws_iam_user" "operator"' in BOOTSTRAP
    assert 'resource "aws_iam_role" "operator"' in BOOTSTRAP
    assert 'resource "aws_iam_role" "terraform_execution"' in BOOTSTRAP
    assert 'resource "aws_iam_user_login_profile"' not in BOOTSTRAP
    assert 'resource "aws_iam_access_key"' not in BOOTSTRAP
    assert 'arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess' in BOOTSTRAP
    assert 'AWSSignInLocalDevelopmentAccess' not in BOOTSTRAP
    assert 'AdministratorAccess' not in BOOTSTRAP
    assert '"aws:MultiFactorAuthPresent" = "true"' in BOOTSTRAP
    assert 'resource "aws_iam_role" "operator"' not in SECURITY
    assert 'resource "aws_iam_role" "terraform_execution"' not in SECURITY
    assert 'Principal = { AWS = var.operator_role_arn }' in SECURITY
    assert 'Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }' not in SECURITY
    assert 'count  = var.v3_operator_role_arn != null && var.v3_terraform_execution_role_arn != null ? 1 : 0' in DEV
    assert 'Resource = sort(tolist(var.target_role_arns))' in BOOTSTRAP


def test_terraform_refresh_permissions_cover_provider_reads_without_admin_access():
    for action in [
        "s3:GetBucketNotification",
        "s3:GetBucketOwnershipControls",
        "s3:GetObject",
        "rds:ListTagsForResource",
        "dms:ListTagsForResource",
        "kms:ListAliases",
        "cloudtrail:DescribeTrails",
        "s3vectors:ListTagsForResource",
    ]:
        assert action in BOOTSTRAP
    assert 'Resource = sort(tolist(var.project_bucket_arns))' in BOOTSTRAP
    assert 'for arn in var.project_bucket_arns : "${arn}/*"' in BOOTSTRAP


def test_terraform_execution_cannot_administer_bootstrap_identity_or_state_key():
    execution_policy = BOOTSTRAP.split(
        'resource "aws_iam_role_policy" "terraform_execution"', 1
    )[1]
    role_admin = execution_policy.split('"ProjectRoleAdministration"', 1)[1].split(
        '"V3LakeFormationAdministration"', 1
    )[0]
    state_key_use = execution_policy.split('"TerraformStateKey"', 1)[1].split(
        '"ProjectKmsPolicyAdministration"', 1
    )[0]
    backend_role_use = STATE_BACKEND.split(
        "for role_index, role_arn in var.terraform_role_arns", 1
    )[1]

    assert 'role/insurance-${var.environment}-*' not in role_admin
    assert 'role/insurance-${var.environment}-operator-role' not in role_admin
    assert 'role/insurance-${var.environment}-terraform-execution-role' not in role_admin
    for action in [
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:AttachUserPolicy",
        "iam:PutUserPolicy",
        "iam:UpdateLoginProfile",
        "iam:CreateAccessKey",
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
    ]:
        assert action not in execution_policy
    assert "kms:PutKeyPolicy" not in state_key_use
    assert "kms:PutKeyPolicy" not in backend_role_use
    assert '["kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey"]' in state_key_use
    assert '${var.state_bucket_arn}/*' not in execution_policy
    assert '${var.state_bucket_arn}/bootstrap/terraform.tfstate' not in execution_policy
    assert '${var.state_bucket_arn}/foundation/terraform.tfstate"' in execution_policy
    assert '${var.state_bucket_arn}/foundation/terraform.tfstate.tflock"' in execution_policy


def test_persona_roles_and_no_admin_wildcards():
    for role in ["data_engineer", "analyst", "ml_engineer", "rag_application"]:
        assert f'resource "aws_iam_role" "{role}"' in SECURITY
    assert 'Action = "*"' not in SECURITY
    assert 'Action = ["*"]' not in SECURITY
    for wildcard in ["iam:*", "kms:*", "s3:*", "secretsmanager:*"]:
        assert wildcard not in SECURITY
        assert wildcard not in BOOTSTRAP


def test_lakehouse_data_is_not_read_directly_by_restricted_personas():
    analyst = SECURITY.split('resource "aws_iam_role_policy" "analyst"', 1)[1].split(
        'resource "aws_iam_role" "ml_engineer"', 1
    )[0]
    ml = SECURITY.split('resource "aws_iam_role_policy" "ml_engineer"', 1)[1].split(
        'resource "aws_iam_role" "rag_application"', 1
    )[0]
    rag = SECURITY.split('resource "aws_iam_role_policy" "rag_application"', 1)[1].split(
        'resource "aws_iam_role" "lakeformation_registration"', 1
    )[0]
    assert 'Sid = "ReadGoldObjects"' not in analyst
    assert 'Sid = "ReadMLGold"' not in ml
    assert 'ReadApprovedDocuments' not in rag
    assert 'ReadApprovedVectors' not in rag


def test_lake_formation_explicit_grants_and_hybrid_opt_in_exist():
    for resource in [
        "data_engineer_tables",
        "analyst_gold_tables",
        "ml_gold_tables",
        "data_location",
    ]:
        assert f'aws_lakeformation_permissions" "{resource}' in LF
    assert 'aws_lakeformation_opt_in" "analyst_gold_tables' in LF
    assert 'aws_lakeformation_opt_in" "ml_gold_tables' in LF
    assert "for_each = local.data_location_principals" in LF
    assert 'pipeline_role_arns = {' in DEV
    assert "policy_performance" not in DEV.split("analyst_gold_tables", 1)[1].split("ml_gold_tables", 1)[0]


def test_sensitive_service_access_is_resource_scoped():
    assert 'Resource = var.rds_secret_arn' in SECURITY
    assert 'Resource = var.platform_kms_key_arn' in SECURITY
    assert 'Sid = "DenySecrets"' in SECURITY
    assert 'iam:PassRole", Resource = var.sagemaker_execution_role_arn' in SECURITY


def test_dev_root_kms_visibility_is_read_only_and_explicit():
    assert DEV.count('allow_account_root_read_only') == 2
    assert 'variable "allow_account_root_read_only"' in PLATFORM_KMS_VARIABLES
    assert 'variable "allow_account_root_read_only"' in MONITORING_VARIABLES
    for policy in [PLATFORM_KMS, MONITORING]:
        root_read = policy.split('Sid       = "AllowAccountRootReadOnlyMetadata"', 1)[1].split(
            '] : [],', 1
        )[0]
        for action in [
            "kms:DescribeKey",
            "kms:GetKeyPolicy",
            "kms:GetKeyRotationStatus",
            "kms:ListGrants",
            "kms:ListKeyPolicies",
            "kms:ListResourceTags",
        ]:
            assert action in root_read
        for forbidden in [
            "kms:Decrypt",
            "kms:Encrypt",
            "kms:GenerateDataKey",
            "kms:PutKeyPolicy",
            "kms:ScheduleKeyDeletion",
            "kms:DisableKey",
        ]:
            assert forbidden not in root_read


def test_root_script_decrypt_is_s3_and_control_bucket_scoped():
    assert 'account_root_s3_decrypt_bucket_arns = [' in DEV
    assert '"arn:aws:s3:::${local.bucket_names["control"]}"' in DEV
    assert 'variable "account_root_s3_decrypt_bucket_arns"' in PLATFORM_KMS_VARIABLES
    root_decrypt = PLATFORM_KMS.split(
        'Sid       = "AllowAccountRootDecryptControlObjectsViaS3"', 1
    )[1].split('] : [],', 1)[0]
    assert 'Action    = ["kms:Decrypt", "kms:DescribeKey"]' in root_decrypt
    assert '"kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"' in root_decrypt
    assert '"kms:EncryptionContext:aws:s3:arn"' in root_decrypt
    assert 'var.account_root_s3_decrypt_bucket_arns' in root_decrypt
    for forbidden in [
        '"kms:Encrypt",',
        '"kms:GenerateDataKey",',
        '"kms:PutKeyPolicy",',
        '"kms:ScheduleKeyDeletion",',
        '"kms:DisableKey",',
    ]:
        assert forbidden not in root_decrypt
