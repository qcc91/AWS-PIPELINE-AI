# DEV state bootstrap

TASK-INF-002 defines the DEV state bucket/KMS bootstrap here. It plans one KMS
key and alias plus one S3 bucket with versioning, ownership, public-access,
default SSE-KMS, lifecycle, and bucket-policy resources. Both the key and bucket
have deletion protection. `create_resources=true` is explicit for plan review.

Required inputs have no invented defaults: organization/account suffixes,
12-digit account ID, at least one explicit same-account DEV role ARN, and the
approved noncurrent retention period. IAM role paths are supported; wildcard
and cross-account ARNs are rejected.

The partial backend example uses `bootstrap/terraform.tfstate`, Sydney, native
S3 locking, an actual-key-ARN placeholder, and a DEV-specific role placeholder.
Populate a non-committed copy only after an approved bootstrap apply supplies
the actual KMS ARN. The root also exposes the future
`foundation/terraform.tfstate` key contract.

This configuration remains unapplied pending P1-CP1 Human approval. Do not run
`terraform apply` or migrate state before that approval.
