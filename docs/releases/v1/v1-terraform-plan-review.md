# V1 DEV Terraform Plan Review

Date: 2026-09-09

Status: ready for P1-CP1 / Gate 2 Human approval. No apply has run.

## Verified execution context

- Region: `ap-southeast-2`
- Account: `199476069493`
- Caller: account root, temporarily approved by the Human Owner for V1 only
- Existing VPC: default `172.31.0.0/16`; no overlap with `10.20.0.0/16`
- Planned AZs: `ap-southeast-2a`, `ap-southeast-2b`
- Existing project-name collisions: none found for S3, KMS aliases, or Glue databases
- Existing non-shadow CloudTrail trails: none

## Exact plan actions

| Plan | Create | Change | Destroy |
|---|---:|---:|---:|
| DEV bootstrap | 9 | 0 | 0 |
| DEV foundation | 62 | 0 | 0 |
| Combined | 71 | 0 | 0 |

Bootstrap creates one KMS key/alias, one state bucket, and six separate S3
control resources. Foundation creates the private VPC/subnets/route/S3 gateway
endpoint, two KMS keys/aliases, six buckets and their controls, four Glue
databases, one CloudTrail delivery role/policy, one regional management-event
trail, one log group, and one SNS topic.

## Security and governance

All buckets use public-access blocking, BucketOwnerEnforced ownership,
versioning, SSE-KMS, TLS-only policies, and deletion protection. KMS rotation
is enabled. V1 permits the exact account-root principal only through an
explicit DEV-only switch and enumerated KMS actions; PROD disables the switch.
Credentials, state, tfvars, and plan artifacts are excluded from Git.

IAM persona roles and Lake Formation grants are intentionally deferred to V3.
Therefore V1 does not yet demonstrate least-privilege operator/persona or PII
separation. V3 must remove root execution, disable the shortcut, and activate
the retained IAM/Lake Formation design with negative access tests.

## Cost

Expected idle/low-volume DEV cost remains USD 4–12/month. The principal fixed
component is three customer-managed KMS keys at approximately USD 3/month;
small S3 storage/requests, CloudWatch Logs ingestion/storage, CloudTrail
delivery, and SNS requests make up the variable balance. There is no NAT
Gateway, interface endpoint, RDS, DMS, Kinesis, Glue compute, SageMaker,
QuickSight, or Bedrock resource in these plans. PROD cost is USD 0 because it
is not planned or deployed.

## Validation and limitations

Terraform 1.16.1, AWS provider 6.63.0, recursive formatting, both DEV
validations, PowerShell static tests, exact foundation plan-manifest validation,
and Git whitespace checks pass. TFLint, Checkov, and Bash are unavailable and
are recorded as not run.

V1 uses local Terraform state to solve the bootstrap ordering problem. The
reviewed S3 backend design is retained for V4 migration. Local state and plan
files are sensitive and Git-ignored. Rollback before downstream dependencies
is a reviewed destroy plan; protected buckets/keys require an explicit Human
decision before removing deletion protection. S3 versioning supports later
state recovery after remote-state migration.
