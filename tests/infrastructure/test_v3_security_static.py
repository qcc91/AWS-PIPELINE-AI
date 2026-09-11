from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SECURITY = (ROOT / "terraform/modules/security-governance/main.tf").read_text(encoding="utf-8")
DEV = (ROOT / "terraform/environments/dev/main.tf").read_text(encoding="utf-8")
LF = (ROOT / "terraform/modules/lakeformation/main.tf").read_text(encoding="utf-8")


def test_v3_is_disabled_without_a_real_non_root_trust_principal():
    assert 'count  = length(var.v3_operator_trusted_principal_arns) > 0 ? 1 : 0' in DEV
    assert 'Principal = { AWS = var.operator_trusted_principal_arns }' in SECURITY
    assert 'Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }' not in SECURITY


def test_persona_roles_and_no_admin_wildcards():
    for role in ["data_engineer", "analyst", "ml_engineer", "rag_application"]:
        assert f'resource "aws_iam_role" "{role}"' in SECURITY
    assert 'Action = "*"' not in SECURITY
    assert 'Action = ["*"]' not in SECURITY
    for wildcard in ["iam:*", "kms:*", "s3:*", "secretsmanager:*"]:
        assert wildcard not in SECURITY


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


def test_sensitive_service_access_is_resource_scoped():
    assert 'Resource = var.rds_secret_arn' in SECURITY
    assert 'Resource = var.platform_kms_key_arn' in SECURITY
    assert 'Sid = "DenySecrets"' in SECURITY
    assert 'iam:PassRole", Resource = var.sagemaker_execution_role_arn' in SECURITY
