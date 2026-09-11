# Infrastructure Worker Status

- Current package: V2 reliability infrastructure — implementation complete, Manager integration validation in progress.
- Terraform apply result: 8 create, 12 update, 14 destroy, 0 replacement.
- Creates: four additional stage log groups and four Silver/Gold Glue jobs across Batch and CDC.
- Updates: existing Batch/CDC Bronze jobs, scripts, Step Functions and required scoped policies, plus ML script artifacts.
- Destroys: exactly 14 Streaming-only resources (state machine, EventBridge rule/target, Glue job/script object, log group, four roles/policies, and obsolete lakehouse EventBridge notification).
- No Kinesis stream or Firehose existed in state. Shared Batch, CDC, BI, ML, RAG, S3, KMS and catalog resources were preserved.
- Batch and CDC now run Bronze -> Silver -> Gold as separately observable Glue jobs with stage-specific bounded transient retry, Catch, encrypted failure audit and terminal failure.
- Post-apply Terraform plan: no changes. No PROD resource changed.
- New fixed recurring V2 cost: USD 0. Removed Streaming scaffolding and any future Kinesis/Firehose cost exposure.
- TFLint and Checkov remain unavailable; Terraform fmt/validate, focused tests and state/plan checks pass.

Last updated: 2026-09-11.
# V3 infrastructure security — identity decision required (2026-09-12)

- Read-only V2 inventory completed in account `199476069493`, region
  `ap-southeast-2`: root is current operator; IAM users and IAM Identity Center
  instances are absent; LF uses IAM-compatible defaults and has no registered
  locations; CloudTrail is logging but log validation is off.
- Prepared conditional Terraform for Operator/TerraformExecution and four
  persona roles, explicit Lake Formation grants/hybrid opt-ins, platform/audit
  KMS role transition, state-backend transition, and CloudTrail validation.
- V3 resources are intentionally disabled while no real non-root trusted
  principal exists. Root is rejected as operator trust. No AWS changes applied.
- Human decision required: approve a console-only, MFA-protected IAM user with
  no access key and only AssumeOperator, or enable IAM Identity Center.
- `terraform fmt` and `terraform validate` pass. Real V3 plan/apply, assumed-role
  ALLOW/DENY tests, regression, and zero-drift proof remain blocked on identity.
- Real DEV baseline plan with V3 disabled reports `0 add / 1 change / 0 destroy`;
  the sole in-place change enables CloudTrail log-file validation. It was not
  applied, and no identity-enabled plan was generated with a fabricated ARN.
