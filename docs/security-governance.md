# V3 Security and Governance — Infrastructure Status

## Current V2 security inventory (2026-09-12)

Read-only discovery in `ap-southeast-2` confirmed account `199476069493` is
currently operated from an authenticated root session. No IAM users and no IAM
Identity Center instance exist. The only existing IAM roles are AWS service
execution roles for Batch, CDC, Glue, SageMaker, Bedrock, and CloudTrail; the
existing `AmazonSageMakerAdminIAMExecutionRole` is service-trusted and is not a
human federation path.

Seven project S3 buckets exist (state, landing, lakehouse, control, quarantine,
documents, and audit). Terraform declares bucket-owner-enforced ownership,
versioning, KMS default encryption, TLS-only access, and all four public-access
blocks. Three project KMS keys exist for Terraform state, platform data, and
audit data. One KMS-encrypted RDS secret exists; the DMS and Glue access policies
already reference that exact secret rather than all account secrets.

Lake Formation has no registered S3 locations. Its database/table creation
defaults use `IAM_ALLOWED_PRINCIPALS=ALL`, and existing grants include broad
IAM-compatible access (for example Silver). Therefore V2 does not yet provide
effective Lake Formation persona isolation.

CloudTrail `insurance-dev-management-trail` is actively delivering regional
management events to the KMS-encrypted audit bucket and CloudWatch Logs. Log
file validation is currently disabled; the prepared V3 Terraform enables it.

## Prepared V3 control model

The Terraform module `security-governance` defines short-session roles for
Operator, TerraformExecution, DataEngineer, Analyst, MLEngineer,
RAGApplication, and LakeFormationRegistration. It contains no `Action="*"`,
`iam:*`, `kms:*`, `s3:*`, or `secretsmanager:*` allow. Secrets access is scoped
to the RDS secret. `iam:PassRole` for MLEngineer is scoped to the current
SageMaker execution role and service.

Analyst and MLEngineer do not receive direct reads from the lakehouse bucket.
Athena uses `lakeformation:GetDataAccess`, and the prepared Lake Formation
hybrid opt-ins make explicit table grants authoritative for those principals.
Analyst receives SELECT only on the approved non-PII analytical tables;
MLEngineer receives SELECT only on `claim_risk_features` and `claim_risk`.
RAGApplication uses the Bedrock runtime API; the existing Bedrock service role,
not the application caller, reads documents and vectors.

Lake Formation registration and hybrid opt-in are migration-sensitive. Existing
V2 Glue roles retain IAM-compatible behavior and receive data-location access so
the change does not intentionally interrupt Batch/CDC/ML. The prepared RAG role
assumes that Bedrock Knowledge Base remains the service boundary; it does not
permit direct S3 document, vector, or lakehouse access.

## Identity decision required before plan/apply

The module deliberately remains disabled while
`v3_operator_trusted_principal_arns=[]`. A root principal is rejected as an
operator trust input. Consequently, current formatting/validation can run, but
no trustworthy V3 plan, apply, or positive/negative assumed-role test can be
completed until an actual non-root human entry principal exists.

The real DEV baseline plan with that input empty reports `0 add / 1 change /
0 destroy`: the only in-place change enables CloudTrail log-file validation.
It creates no V3 roles or Lake Formation grants and has not been applied. Exact
identity-enabled V3 counts cannot be produced without fabricating the missing
trusted principal ARN, which this project explicitly forbids.

Minimum single-account option requiring Human approval: create one console-only
IAM user with no access key, require MFA and `aws login` temporary credentials,
and grant only `sts:AssumeRole` on `insurance-dev-operator-role`. This is the
smallest change but leaves an IAM user to govern. The stronger alternative is
to enable IAM Identity Center and trust its permission-set role; that is an
account-wide identity architecture change. No user, access key, or Identity
Center instance has been created.

## Cost and scope

IAM roles/policies, Lake Formation permissions/opt-ins, and CloudTrail log-file
validation add no fixed monthly charge. Validation would use only small
Athena/Bedrock requests. No paid security service, PROD, V4, or V5 resource is
included.
