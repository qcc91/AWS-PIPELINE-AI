# Terraform state bootstrap

TASK-INF-002 defines one environment-specific, versioned S3 state bucket and
one customer-managed symmetric KMS key/alias for DEV. The S3 controls are Block
Public Access, BucketOwnerEnforced ownership, default SSE-KMS using the created
key ARN, `force_destroy=false`, TLS-only access, and `prevent_destroy` on both
the bucket and key. The lifecycle resource explicitly depends on versioning.
Current versions have no expiration rule. Noncurrent retention is a required,
validated input (7–3650 days) that must be approved before the first apply; no
retention value is invented here.

DEV and PROD have separate bucket names, KMS aliases, backend files, backend
role placeholders, and state roots. PROD explicitly sets
`create_resources=false` and is design-only. No Terraform workspace is used as
an environment boundary. The backend uses S3 native locking
(`use_lockfile=true`) and never uses DynamoDB.

The backend examples contain no credentials. Before migration, replace the KMS
placeholder with the actual `state_kms_key_arn` output from the reviewed and
approved bootstrap apply; do not use an alias or an invented ARN. Replace the
backend `role_arn` with the approved environment-specific, same-account role.
DEV and PROD roles must be different. Authentication remains short-lived and
external to Terraform files.

## One-time sequence (P1-CP1 required for apply)

V1 keeps the active DEV backend local so a bootstrap plan can exist before its
own S3 bucket exists. The S3 partial backend template remains the approved V4
migration target; no credential is stored in either configuration.

1. Use the approved organization short name `aip`, account suffix `dev01`,
   account ID `199476069493`, and approved retention inputs. V1 uses the
   Human-approved root shortcut and does not require a fabricated execution-role
   ARN. Role-path validation remains for the V3 migration.
2. Keep initial bootstrap state local. Run `terraform init -backend=false`,
   then review a DEV plan. The exact plan must be reviewed by Manager and
   Human Owner at P1-CP1 before any apply command is permitted.
3. After explicit P1-CP1 approval, apply the reviewed bootstrap configuration
   with the DEV variable file. Verify versioning, SSE-KMS, public blocks,
   ownership, TLS deny, key policy, and that PROD remains disabled.
4. Populate a non-committed copy of `backend.hcl.example` with the actual bucket
   name, actual KMS key ARN, and approved backend role. Reconfigure and migrate
   local state to `bootstrap/terraform.tfstate`. Confirm remote reads and S3
   lock-object behavior before removing local state.
5. Foundation later uses the separate `foundation/terraform.tfstate` key.

The apply examples above are intentionally procedural and are not automated by
this repository. Never put credentials in tfvars or backend files. Lock
contention must fail safely and be investigated; do not force-unlock without
confirming the owning run has ended. S3 versioning enables recovery: identify
the prior state version, preserve audit evidence, and restore only under a
reviewed recovery operation. Current state has no lifecycle expiration;
noncurrent versions expire only after the Human-approved retention period, so
recovery must occur before that boundary.

## Encryption-header behavior

Bucket default encryption applies SSE-KMS with the created key when a client
omits encryption headers. The bucket policy therefore does not deny a missing
header. It does deny a client that explicitly requests an algorithm other than
`aws:kms`, and separately denies an explicitly supplied KMS key ARN that is not
the created state key. This preserves safe Terraform/S3 default-encryption
behavior while preventing explicit downgrade or wrong-key requests.

## Cost and security

Expected Phase 1 DEV bootstrap cost is approximately USD 1–2/month for one KMS
key and low-volume S3 storage/requests, subject to an official pricing review.
PROD creates zero resources and has zero TASK-INF-002 runtime cost.

KMS rotation, a 30-day deletion window, and deletion protection guard the key.
V1 DEV explicitly permits the exact same-account root principal with a bounded
set of KMS actions and no `kms:*`; PROD keeps the shortcut disabled. This is a
Human-approved temporary exception. V3 must replace it with explicit
same-account non-root execution and KMS administrator roles.

Terraform 1.16.1 with AWS provider 6.63.0 passes formatting and validation. The
real DEV bootstrap plan contains exactly 9 creates, zero changes, and zero
destroys. No apply has run.
