# V1 DEV infrastructure deployment result

Date: 2026-09-09

Status: deployed and verified. PROD was not touched.

## Final state

| Root | Terraform state resources | Post-apply drift |
|---|---:|---|
| DEV bootstrap | 9 | none (`-detailed-exitcode` = 0) |
| DEV foundation | 62 | none (`-detailed-exitcode` = 0) |

The deployed resources match the approved net topology: 71 Terraform resource
instances, with no replacement, deletion, duplicate KMS key, or extra bucket.

## Verified AWS controls

- VPC `10.20.0.0/16` is available with private subnets `10.20.1.0/24` in
  `ap-southeast-2a` and `10.20.2.0/24` in `ap-southeast-2b`; public IP mapping
  is disabled.
- The S3 Gateway endpoint is available in the DEV VPC.
- All seven DEV buckets have versioning enabled, SSE-KMS default encryption,
  and all four public-access-block controls enabled.
- Terraform-state, platform-data, and audit KMS aliases resolve to three
  enabled keys with rotation enabled.
- Bronze, Silver, Gold, and Control Glue databases exist.
- The regional management-events CloudTrail is logging; its encrypted
  CloudWatch log group has 30-day retention and its encrypted SNS topic exists.
- The CloudTrail delivery IAM role and inline delivery policy exist.
- No project-named PROD S3 bucket, Glue database, or KMS alias exists.

## Apply deviation and recovery

The first bootstrap apply created part of the approved topology, then failed
while the AWS provider read KMS rotation state. The explicit V1 root key policy
did not yet include all Terraform lifecycle actions. A second attempt exposed
the same issue for alias creation.

The recovery expanded the DEV-only root statement with explicit key-policy,
rotation, tag, and alias lifecycle operations. It did not add `kms:*`, change
PROD, create an access key, persist credentials, replace a KMS key, or destroy
anything. Terraform updated the existing key policy in place and completed the
remaining approved resources. The same correction was applied to platform and
audit KMS modules before foundation deployment.

## State and security

Both roots currently use local V1 state; state and plan artifacts are ignored
by Git and contain no committed credential material. Remote-state migration
remains V4 work. Temporary root execution remains a Human-approved V1-only
shortcut and must be replaced by least-privilege role separation in V3.
