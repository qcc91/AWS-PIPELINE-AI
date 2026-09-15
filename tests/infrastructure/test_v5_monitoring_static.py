from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MONITORING = (ROOT / "terraform/modules/monitoring/main.tf").read_text(encoding="utf-8")
MONITORING_VARS = (ROOT / "terraform/modules/monitoring/variables.tf").read_text(
    encoding="utf-8"
)
DEV = (ROOT / "terraform/environments/dev/main.tf").read_text(encoding="utf-8")
PROD = (ROOT / "terraform/environments/prod/main.tf").read_text(encoding="utf-8")
BOOTSTRAP = (ROOT / "terraform/bootstrap/modules/dev-operator/main.tf").read_text(
    encoding="utf-8"
)
BOOTSTRAP_DEV = (ROOT / "terraform/bootstrap/environments/dev/main.tf").read_text(
    encoding="utf-8"
)
BOOTSTRAP_DEV_VARS = (
    ROOT / "terraform/bootstrap/environments/dev/variables.tf"
).read_text(encoding="utf-8")


def test_v5_alerting_is_dev_only_and_uses_existing_topic():
    assert "enable_operational_alerting     = true" in DEV
    assert "enable_operational_alerting" not in PROD
    assert 'resource "aws_sns_topic" "alerts"' in MONITORING
    assert 'resource "aws_sns_topic_policy" "operational_alerts"' in MONITORING
    assert 'resource "aws_sns_topic_subscription"' not in MONITORING
    assert 'default     = false' in MONITORING_VARS


def test_step_functions_and_cicd_alarms_are_small_and_missing_data_safe():
    assert 'resource "aws_cloudwatch_metric_alarm" "workflow_failures"' in MONITORING
    assert 'resource "aws_cloudwatch_metric_alarm" "codepipeline_failures"' in MONITORING
    assert 'resource "aws_cloudwatch_metric_alarm" "codebuild_failures"' in MONITORING
    for metric in (
        "ExecutionsFailed",
        "ExecutionsTimedOut",
        "ExecutionsAborted",
        "FailedPipelineExecutions",
        "FailedBuilds",
    ):
        assert f'"{metric}"' in MONITORING
    assert MONITORING.count('treat_missing_data  = "notBreaching"') == 3
    assert "FILL(failed, 0) + FILL(timedout, 0) + FILL(aborted, 0)" in MONITORING
    assert 'for id in sort(keys(var.codebuild_project_names)) : "FILL(${id}, 0)"' in MONITORING


def test_glue_and_dms_failure_routes_are_exactly_scoped():
    assert 'resource "aws_cloudwatch_event_rule" "glue_job_failures"' in MONITORING
    assert '["FAILED", "STOPPED", "TIMEOUT"]' in MONITORING
    assert "sort(tolist(var.glue_job_names))" in MONITORING
    assert 'resource "aws_dms_event_subscription" "task_failures"' in MONITORING
    assert 'source_ids       = [var.dms_replication_task_id]' in MONITORING
    assert 'event_categories = ["failure"]' in MONITORING
    assert 'resource "aws_lambda_' not in MONITORING


def test_encrypted_sns_publishers_and_topic_policy_are_constrained():
    for service in (
        "cloudwatch.amazonaws.com",
        "events.amazonaws.com",
        "dms.amazonaws.com",
    ):
        assert service in MONITORING
    assert '"kms:EncryptionContext:aws:sns:topicArn" = local.topic_arn' in MONITORING
    assert '"aws:SourceAccount" = var.account_id' in MONITORING
    assert 'alarm:${local.operational_alarm_prefix}-*' in MONITORING
    assert "local.glue_failure_rule_name" in MONITORING
    assert 'Sid    = "AllowAccountOwner"' in MONITORING
    assert '"AWS:SourceOwner" = var.account_id' in MONITORING
    assert 'arn:aws:dms:ap-southeast-2:${var.account_id}:es:${local.dms_failure_subscription}' in MONITORING
    glue_publish = MONITORING.split('Sid       = "AllowGlueFailureRulePublish"', 1)[1].split(
        'Sid       = "AllowDmsFailurePublish"', 1
    )[0]
    assert "Condition" not in glue_publish
    assert 'Principal = { Service = "events.amazonaws.com" }' in glue_publish


def test_v5_terraform_permissions_do_not_grant_data_or_identity_access():
    v5_policy = BOOTSTRAP.split('Sid    = "V5OperationalMonitoringRead"', 1)[1].split(
        'resource "aws_iam_policy" "terraform_execution_v4b_identity"', 1
    )[0]
    assert 'arn:aws:cloudwatch:ap-southeast-2:${var.account_id}:alarm:insurance-${var.environment}-*' in v5_policy
    assert 'rule/insurance-${var.environment}-glue-job-failures' in v5_policy
    assert 'insurance-${var.environment}-critical-alerts' in v5_policy
    assert '"aws:RequestTag/Project" = "aws-insurance-data-ai"' in v5_policy
    assert '"aws:ResourceTag/Project" = "aws-insurance-data-ai"' in v5_policy
    for forbidden in (
        "s3:GetObject",
        "secretsmanager:GetSecretValue",
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "sns:Subscribe",
        "sns:Publish",
    ):
        assert forbidden not in v5_policy


def test_existing_retention_contract_is_preserved():
    s3_module = (ROOT / "terraform/modules/s3/main.tf").read_text(encoding="utf-8")
    control = (ROOT / "terraform/cicd-control/main.tf").read_text(encoding="utf-8")
    assert 'current_retention_days    = each.key == "quarantine" ? 90 : null' in DEV
    assert "days = var.audit_retention_days" in MONITORING
    assert "days = 90" in control
    assert "noncurrent_version_expiration" in s3_module


def test_bootstrap_uses_explicit_application_kms_arns_without_alias_reads():
    assert 'data "aws_kms_alias"' not in BOOTSTRAP_DEV
    assert "var.platform_kms_key_arn" in BOOTSTRAP_DEV
    assert "var.audit_kms_key_arn" in BOOTSTRAP_DEV
    assert 'variable "platform_kms_key_arn"' in BOOTSTRAP_DEV_VARS
    assert 'variable "audit_kms_key_arn"' in BOOTSTRAP_DEV_VARS
    assert "arn:aws:kms:${var.aws_region}:${var.account_id}:key/" in BOOTSTRAP_DEV_VARS
