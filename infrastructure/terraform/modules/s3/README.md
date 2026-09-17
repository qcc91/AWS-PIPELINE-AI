# S3 data bucket module

Creates one private, versioned, BucketOwnerEnforced S3 bucket with all public
access blocks, default SSE-KMS using an actual Sydney key ARN, a bucket key,
TLS-only access, and deletion protection. Current objects are not expired.
Noncurrent versions expire only after the required Human-approved retention
period; the lifecycle configuration explicitly depends on versioning and uses
an empty `filter {}` to cover the whole bucket.

The policy denies an explicitly requested algorithm other than `aws:kms` and
an explicitly supplied KMS key other than `kms_key_arn`. Missing encryption
headers are intentionally allowed so the bucket's default SSE-KMS configuration
can apply.

Bucket names reject obvious invalid forms including adjacent periods,
dot-hyphen pairs, IP-address style names, and AWS-reserved prefixes/suffixes.
The approved, non-empty purpose is written to the `Purpose` tag. The complete
project tag contract has no defaults and requires non-empty values, approved
environment/classification values, and `ManagedBy=terraform`.
