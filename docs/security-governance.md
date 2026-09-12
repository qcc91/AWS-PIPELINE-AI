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

Bootstrap Terraform defines the console-only local user plus short-session
Operator and TerraformExecution roles. Foundation module `security-governance`
accepts those existing role ARNs and defines DataEngineer, Analyst, MLEngineer,
RAGApplication, and LakeFormationRegistration without duplicating bootstrap
ownership. It contains no `Action="*"`,
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

## Human enrollment checkpoint

Option A is Human-approved. Bootstrap creates `insurance-dev-local-operator`
without a login profile, console password, MFA device, or access key, attaches
AWS-managed `SignInLocalDevelopmentAccess`, and permits only MFA-qualified
AssumeRole into `insurance-dev-operator-role`. The operator can assume only the
TerraformExecution and four persona roles. TerraformExecution is bootstrap-owned
so the first foundation apply can run through the non-root chain.

The Human Owner must now create the initial console password and enroll MFA.
Those secrets are intentionally not Terraform-managed. Foundation V3 remains
disabled until the non-root session and role chain are proven. Identity Center
remains a stronger future option, but it is outside the approved V3 approach.

The reviewed bootstrap plan is `7 add / 0 change / 0 destroy`: one IAM user,
two IAM roles, two inline role policies, one inline user policy, and one
AWS-managed sign-in policy attachment. It contains no login profile, access key,
AdministratorAccess attachment, replacement, or deletion. Terraform applied the
reviewed plan on 2026-09-12 with exactly `7 added / 0 changed / 0 destroyed`.
Read-only verification confirmed no access keys, no login profile, no managed
role policies, the exact user principal in Operator trust, and MFA-required
AssumeRole. IAM policy simulation returned `implicitDeny` without MFA and
`allowed` with MFA; a real session test follows Human enrollment.

## Cost and scope

IAM roles/policies, Lake Formation permissions/opt-ins, and CloudTrail log-file
validation add no fixed monthly charge. Validation would use only small
Athena/Bedrock requests. No paid security service, PROD, V4, or V5 resource is
included.
